import 'dart:io';

import 'package:path/path.dart' as pp;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../domain/models.dart';

/// Application database. Uses sqlite3 directly (via sqlite3_flutter_libs)
/// behind a fully typed data-access layer — zero codegen required, so the
/// project runs with nothing more than `flutter pub get && flutter run`.
class DbService {
  DbService._(this._db);

  final Database _db;

  static Future<DbService> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = pp.join(dir.path, 'nexus.db');
    final db = sqlite3.open(file);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    final svc = DbService._(db);
    svc._migrate();
    return svc;
  }

  void close() => _db.dispose();

  void _migrate() {
    _db.execute('''
    CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS aliases(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, path TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS stacks(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, items TEXT NOT NULL DEFAULT '[]');
    CREATE TABLE IF NOT EXISTS pinned(
      id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT UNIQUE NOT NULL,
      label TEXT NOT NULL, edge TEXT NOT NULL DEFAULT 'left', sort INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS spatial(
      folder TEXT NOT NULL, name TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
      PRIMARY KEY(folder, name));
    CREATE TABLE IF NOT EXISTS sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL,
      updated_at INTEGER NOT NULL, payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS journal(
      id INTEGER PRIMARY KEY AUTOINCREMENT, batch_id TEXT NOT NULL, op TEXT NOT NULL,
      from_path TEXT NOT NULL, to_path TEXT, meta TEXT, created_at INTEGER NOT NULL,
      undone INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS idx_journal_batch ON journal(batch_id);
    CREATE INDEX IF NOT EXISTS idx_journal_time ON journal(created_at DESC);
    CREATE TABLE IF NOT EXISTS rules(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      match TEXT NOT NULL DEFAULT 'all', conditions TEXT NOT NULL DEFAULT '[]',
      actions TEXT NOT NULL DEFAULT '[]');
    CREATE TABLE IF NOT EXISTS pipelines(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, steps TEXT NOT NULL DEFAULT '[]');
    CREATE TABLE IF NOT EXISTS macros(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      steps TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS watchdogs(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, folder TEXT NOT NULL,
      trigger TEXT NOT NULL, pattern TEXT NOT NULL DEFAULT '', action TEXT NOT NULL,
      arg TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1, last_fired INTEGER);
    CREATE TABLE IF NOT EXISTS schedules(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL,
      targets TEXT NOT NULL DEFAULT '{}', arg TEXT NOT NULL DEFAULT '',
      run_at INTEGER, interval_min INTEGER, enabled INTEGER NOT NULL DEFAULT 1,
      last_run INTEGER, last_status TEXT NOT NULL DEFAULT '');
    CREATE TABLE IF NOT EXISTS versions(
      id INTEGER PRIMARY KEY AUTOINCREMENT, original_path TEXT NOT NULL,
      snapshot_path TEXT NOT NULL, size INTEGER NOT NULL, created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_versions_orig ON versions(original_path);
    CREATE TABLE IF NOT EXISTS mirrors(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, source TEXT NOT NULL,
      target TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, last_sync INTEGER);
    CREATE TABLE IF NOT EXISTS freezes(
      id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT UNIQUE NOT NULL,
      created_at INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '');
    CREATE TABLE IF NOT EXISTS templates(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL,
      source_path TEXT NOT NULL DEFAULT '', content TEXT);
    ''');
  }

  // ── settings ──────────────────────────────────────────────────────────────
  String? getSetting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) =>
      _db.execute('INSERT INTO settings(key,value) VALUES(?,?) '
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value', [key, value]);

  // ── aliases ───────────────────────────────────────────────────────────────
  List<PathAlias> aliases() => _db
      .select('SELECT * FROM aliases ORDER BY name COLLATE NOCASE')
      .map((r) => PathAlias(id: r['id'] as int, name: r['name'] as String, path: r['path'] as String))
      .toList();

  void upsertAlias(String name, String path) => _db.execute(
      'INSERT INTO aliases(name,path) VALUES(?,?) '
      'ON CONFLICT(name) DO UPDATE SET path=excluded.path', [name, path]);

  void deleteAlias(int id) => _db.execute('DELETE FROM aliases WHERE id=?', [id]);

  // ── stacks ────────────────────────────────────────────────────────────────
  List<FolderStack> stacks() => _db
      .select('SELECT * FROM stacks ORDER BY name COLLATE NOCASE')
      .map((r) => FolderStack(
            id: r['id'] as int,
            name: r['name'] as String,
            items: _decodeList(r['items'] as String)
                .map((j) => StackItem.fromJson((j as Map).cast<String, dynamic>()))
                .toList(),
          ))
      .toList();

  void saveStack(FolderStack s) {
    if (s.id == null) {
      _db.execute('INSERT INTO stacks(name,items) VALUES(?,?)', [s.name, _encode(s.items)]);
    } else {
      _db.execute('UPDATE stacks SET name=?, items=? WHERE id=?', [s.name, _encode(s.items), s.id]);
    }
  }

  void deleteStack(int id) => _db.execute('DELETE FROM stacks WHERE id=?', [id]);

  // ── pinned / dock ─────────────────────────────────────────────────────────
  List<PinnedItem> pinned() => _db
      .select('SELECT * FROM pinned ORDER BY edge, sort')
      .map((r) => PinnedItem(
            id: r['id'] as int,
            path: r['path'] as String,
            label: r['label'] as String,
            edge: r['edge'] as String,
            sort: r['sort'] as int,
          ))
      .toList();

  void pin(String path, String label, String edge, int sort) => _db.execute(
      'INSERT INTO pinned(path,label,edge,sort) VALUES(?,?,?,?) '
      'ON CONFLICT(path) DO UPDATE SET label=excluded.label, edge=excluded.edge, sort=excluded.sort',
      [path, label, edge, sort]);

  void unpin(String path) => _db.execute('DELETE FROM pinned WHERE path=?', [path]);

  void setPinnedEdge(String path, String edge) =>
      _db.execute('UPDATE pinned SET edge=? WHERE path=?', [edge, path]);

  // ── spatial memory ────────────────────────────────────────────────────────
  Map<String, Offset2D> spatialFor(String folder) {
    final rows = _db.select('SELECT name,x,y FROM spatial WHERE folder=?', [folder]);
    return {for (final r in rows) r['name'] as String: Offset2D(r['x'] as double, r['y'] as double)};
  }

  void putSpatial(String folder, String name, double x, double y) => _db.execute(
      'INSERT INTO spatial(folder,name,x,y) VALUES(?,?,?,?) '
      'ON CONFLICT(folder,name) DO UPDATE SET x=excluded.x, y=excluded.y', [folder, name, x, y]);

  void clearSpatial(String folder) => _db.execute('DELETE FROM spatial WHERE folder=?', [folder]);

  // ── sessions ──────────────────────────────────────────────────────────────
  List<WorkSession> sessions() => _db
      .select('SELECT * FROM sessions ORDER BY updated_at DESC')
      .map((r) => WorkSession(
            id: r['id'] as int,
            name: r['name'] as String,
            updatedAtMs: r['updated_at'] as int,
            payload: _decodeMap(r['payload'] as String),
          ))
      .toList();

  WorkSession? sessionByName(String name) {
    final rows = _db.select('SELECT * FROM sessions WHERE name=?', [name]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return WorkSession(
        id: r['id'] as int,
        name: r['name'] as String,
        updatedAtMs: r['updated_at'] as int,
        payload: _decodeMap(r['payload'] as String));
  }

  void saveSession(String name, Map<String, dynamic> payload) => _db.execute(
      'INSERT INTO sessions(name,updated_at,payload) VALUES(?,?,?) '
      'ON CONFLICT(name) DO UPDATE SET updated_at=excluded.updated_at, payload=excluded.payload',
      [name, DateTime.now().millisecondsSinceEpoch, _encode(payload)]);

  void deleteSession(String name) => _db.execute('DELETE FROM sessions WHERE name=?', [name]);

  // ── journal (undo + paper trail) ──────────────────────────────────────────
  void addJournal(JournalEntry e) => _db.execute(
      'INSERT INTO journal(batch_id,op,from_path,to_path,meta,created_at,undone) VALUES(?,?,?,?,?,?,?)',
      [e.batchId, e.op.name, e.fromPath, e.toPath, e.meta, e.createdAtMs, e.undone ? 1 : 0]);

  List<JournalEntry> journal({String? query, int limit = 2000}) {
    final rows = query == null || query.isEmpty
        ? _db.select('SELECT * FROM journal ORDER BY created_at DESC LIMIT ?', [limit])
        : _db.select(
            'SELECT * FROM journal WHERE from_path LIKE ? OR to_path LIKE ? '
            'ORDER BY created_at DESC LIMIT ?', ['%$query%', '%$query%', limit]);
    return rows.map(_journalFromRow).toList();
  }

  List<JournalEntry> batch(String batchId) => _db
      .select('SELECT * FROM journal WHERE batch_id=? ORDER BY id', [batchId])
      .map(_journalFromRow)
      .toList();

  void setJournalUndone(int id, bool undone) =>
      _db.execute('UPDATE journal SET undone=? WHERE id=?', [undone ? 1 : 0, id]);

  void pruneJournal(int keep) {
    _db.execute('DELETE FROM journal WHERE id NOT IN '
        '(SELECT id FROM journal ORDER BY created_at DESC LIMIT ?)', [keep]);
  }

  JournalEntry _journalFromRow(Row r) => JournalEntry(
        id: r['id'] as int,
        batchId: r['batch_id'] as String,
        op: JournalOp.values.asNameMap()[r['op']] ?? JournalOp.write,
        fromPath: r['from_path'] as String,
        toPath: r['to_path'] as String?,
        meta: r['meta'] as String?,
        createdAtMs: r['created_at'] as int,
        undone: (r['undone'] as int) == 1,
      );

  List<BatchInfo> journalBatches({int limit = 300}) {
    final rows = _db.select(
      'SELECT batch_id, COUNT(*) AS n, MIN(created_at) AS t FROM journal '
      'GROUP BY batch_id ORDER BY t DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) {
      final entries = batch(r['batch_id'] as String);
      return BatchInfo(r['batch_id'] as String, r['n'] as int,
          DateTime.fromMillisecondsSinceEpoch(r['t'] as int), _batchLabel(entries));
    }).toList();
  }

  String _batchLabel(List<JournalEntry> es) {
    if (es.isEmpty) return 'changes';
    final ops = es.map((e) => e.op.name).toSet();
    if (ops.length == 1) return '${es.first.op.name} · ${es.length} item(s)';
    return '${es.length} change(s)';
  }

  // ── rules ─────────────────────────────────────────────────────────────────
  List<NexusRule> rules() => _db
      .select('SELECT * FROM rules ORDER BY name COLLATE NOCASE')
      .map((r) => NexusRule(
            id: r['id'] as int,
            name: r['name'] as String,
            enabled: (r['enabled'] as int) == 1,
            match: r['match'] as String,
            conditions: _decodeList(r['conditions'] as String)
                .map((j) => RuleCondition.fromJson((j as Map).cast<String, dynamic>()))
                .toList(),
            actions: _decodeList(r['actions'] as String)
                .map((j) => RuleAction.fromJson((j as Map).cast<String, dynamic>()))
                .toList(),
          ))
      .toList();

  int saveRule(NexusRule r) {
    if (r.id == null) {
      _db.execute('INSERT INTO rules(name,enabled,match,conditions,actions) VALUES(?,?,?,?,?)',
          [r.name, r.enabled ? 1 : 0, r.match, _encode(r.conditions), _encode(r.actions)]);
      return _db.lastInsertRowId;
    }
    _db.execute('UPDATE rules SET name=?,enabled=?,match=?,conditions=?,actions=? WHERE id=?',
        [r.name, r.enabled ? 1 : 0, r.match, _encode(r.conditions), _encode(r.actions), r.id]);
    return r.id!;
  }

  void deleteRule(int id) => _db.execute('DELETE FROM rules WHERE id=?', [id]);

  // ── pipelines ─────────────────────────────────────────────────────────────
  List<NexusPipeline> pipelines() => _db
      .select('SELECT * FROM pipelines ORDER BY name COLLATE NOCASE')
      .map((r) => NexusPipeline(
            id: r['id'] as int,
            name: r['name'] as String,
            steps: _decodeList(r['steps'] as String)
                .map((j) => PipelineStep.fromJson((j as Map).cast<String, dynamic>()))
                .toList(),
          ))
      .toList();

  int savePipeline(NexusPipeline p) {
    if (p.id == null) {
      _db.execute('INSERT INTO pipelines(name,steps) VALUES(?,?)', [p.name, _encode(p.steps)]);
      return _db.lastInsertRowId;
    }
    _db.execute('UPDATE pipelines SET name=?, steps=? WHERE id=?', [p.name, _encode(p.steps), p.id]);
    return p.id!;
  }

  void deletePipeline(int id) => _db.execute('DELETE FROM pipelines WHERE id=?', [id]);

  // ── macros ────────────────────────────────────────────────────────────────
  List<NexusMacro> macros() => _db
      .select('SELECT * FROM macros ORDER BY created_at DESC')
      .map((r) => NexusMacro(
            id: r['id'] as int,
            name: r['name'] as String,
            steps: _decodeList(r['steps'] as String)
                .map((j) => MacroStep.fromJson((j as Map).cast<String, dynamic>()))
                .toList(),
            createdAtMs: r['created_at'] as int,
          ))
      .toList();

  int saveMacro(NexusMacro m) {
    if (m.id == null) {
      _db.execute('INSERT INTO macros(name,steps,created_at) VALUES(?,?,?)',
          [m.name, _encode(m.steps), m.createdAtMs]);
      return _db.lastInsertRowId;
    }
    _db.execute('UPDATE macros SET name=?, steps=? WHERE id=?', [m.name, _encode(m.steps), m.id]);
    return m.id!;
  }

  void deleteMacro(int id) => _db.execute('DELETE FROM macros WHERE id=?', [id]);

  // ── watchdogs ─────────────────────────────────────────────────────────────
  List<WatchdogRule> watchdogs() => _db
      .select('SELECT * FROM watchdogs ORDER BY name COLLATE NOCASE')
      .map(_watchdogFromRow)
      .toList();

  WatchdogRule _watchdogFromRow(Row r) => WatchdogRule(
        id: r['id'] as int,
        name: r['name'] as String,
        folder: r['folder'] as String,
        trigger: r['trigger'] as String,
        pattern: r['pattern'] as String,
        action: r['action'] as String,
        arg: r['arg'] as String,
        enabled: (r['enabled'] as int) == 1,
        lastFiredMs: r['last_fired'] as int?,
      );

  int saveWatchdog(WatchdogRule w) {
    if (w.id == null) {
      _db.execute(
          'INSERT INTO watchdogs(name,folder,trigger,pattern,action,arg,enabled) VALUES(?,?,?,?,?,?,?)',
          [w.name, w.folder, w.trigger, w.pattern, w.action, w.arg, w.enabled ? 1 : 0]);
      return _db.lastInsertRowId;
    }
    _db.execute(
        'UPDATE watchdogs SET name=?,folder=?,trigger=?,pattern=?,action=?,arg=?,enabled=? WHERE id=?',
        [w.name, w.folder, w.trigger, w.pattern, w.action, w.arg, w.enabled ? 1 : 0, w.id]);
    return w.id!;
  }

  void setWatchdogFired(int id, int ms) =>
      _db.execute('UPDATE watchdogs SET last_fired=? WHERE id=?', [ms, id]);

  void deleteWatchdog(int id) => _db.execute('DELETE FROM watchdogs WHERE id=?', [id]);

  // ── schedules ─────────────────────────────────────────────────────────────
  List<ScheduleJob> schedules() => _db
      .select('SELECT * FROM schedules ORDER BY name COLLATE NOCASE')
      .map(_scheduleFromRow)
      .toList();

  ScheduleJob _scheduleFromRow(Row r) => ScheduleJob(
        id: r['id'] as int,
        name: r['name'] as String,
        kind: r['kind'] as String,
        targets: _decodeMap(r['targets'] as String),
        arg: r['arg'] as String,
        runAtMs: r['run_at'] as int?,
        intervalMin: r['interval_min'] as int?,
        enabled: (r['enabled'] as int) == 1,
        lastRunMs: r['last_run'] as int?,
        lastStatus: r['last_status'] as String,
      );

  int saveSchedule(ScheduleJob j) {
    if (j.id == null) {
      _db.execute(
          'INSERT INTO schedules(name,kind,targets,arg,run_at,interval_min,enabled) VALUES(?,?,?,?,?,?,?)',
          [j.name, j.kind, _encode(j.targets), j.arg, j.runAtMs, j.intervalMin, j.enabled ? 1 : 0]);
      return _db.lastInsertRowId;
    }
    _db.execute(
        'UPDATE schedules SET name=?,kind=?,targets=?,arg=?,run_at=?,interval_min=?,enabled=? WHERE id=?',
        [j.name, j.kind, _encode(j.targets), j.arg, j.runAtMs, j.intervalMin, j.enabled ? 1 : 0, j.id]);
    return j.id!;
  }

  void setScheduleRun(int id, {required int at, required String status, int? nextRunAt}) {
    _db.execute('UPDATE schedules SET last_run=?, last_status=?, run_at=? WHERE id=?',
        [at, status, nextRunAt, id]);
  }

  void deleteSchedule(int id) => _db.execute('DELETE FROM schedules WHERE id=?', [id]);

  // ── versions ──────────────────────────────────────────────────────────────
  void addVersion(VersionSnapshot v) => _db.execute(
      'INSERT INTO versions(original_path,snapshot_path,size,created_at) VALUES(?,?,?,?)',
      [v.originalPath, v.snapshotPath, v.size, v.createdAtMs]);

  List<VersionSnapshot> versionsFor(String originalPath) => _db
      .select('SELECT * FROM versions WHERE original_path=? ORDER BY created_at DESC', [originalPath])
      .map((r) => VersionSnapshot(
            id: r['id'] as int,
            originalPath: r['original_path'] as String,
            snapshotPath: r['snapshot_path'] as String,
            size: r['size'] as int,
            createdAtMs: r['created_at'] as int,
          ))
      .toList();

  List<String> versionedPaths() => _db
      .select('SELECT DISTINCT original_path FROM versions ORDER BY original_path')
      .map((r) => r['original_path'] as String)
      .toList();

  void deleteVersion(int id) => _db.execute('DELETE FROM versions WHERE id=?', [id]);

  // ── mirrors ───────────────────────────────────────────────────────────────
  List<MirrorPair> mirrors() => _db
      .select('SELECT * FROM mirrors ORDER BY name COLLATE NOCASE')
      .map((r) => MirrorPair(
            id: r['id'] as int,
            name: r['name'] as String,
            source: r['source'] as String,
            target: r['target'] as String,
            enabled: (r['enabled'] as int) == 1,
            lastSyncMs: r['last_sync'] as int?,
          ))
      .toList();

  int saveMirror(MirrorPair m) {
    if (m.id == null) {
      _db.execute('INSERT INTO mirrors(name,source,target,enabled) VALUES(?,?,?,?)',
          [m.name, m.source, m.target, m.enabled ? 1 : 0]);
      return _db.lastInsertRowId;
    }
    _db.execute('UPDATE mirrors SET name=?,source=?,target=?,enabled=? WHERE id=?',
        [m.name, m.source, m.target, m.enabled ? 1 : 0, m.id]);
    return m.id!;
  }

  void setMirrorSync(int id, int ms) => _db.execute('UPDATE mirrors SET last_sync=? WHERE id=?', [ms, id]);

  void deleteMirror(int id) => _db.execute('DELETE FROM mirrors WHERE id=?', [id]);

  // ── freezes ───────────────────────────────────────────────────────────────
  List<FrozenPath> freezes() => _db
      .select('SELECT * FROM freezes ORDER BY created_at DESC')
      .map((r) => FrozenPath(
            id: r['id'] as int,
            path: r['path'] as String,
            createdAtMs: r['created_at'] as int,
            note: r['note'] as String,
          ))
      .toList();

  bool isFrozen(String path) {
    final rows = _db.select('SELECT 1 FROM freezes WHERE path=?', [path]);
    return rows.isNotEmpty;
  }

  List<String> frozenRoots() =>
      _db.select('SELECT path FROM freezes').map((r) => r['path'] as String).toList();

  void freeze(String path, String note) =>
      _db.execute('INSERT INTO freezes(path,created_at,note) VALUES(?,?,?) '
          'ON CONFLICT(path) DO NOTHING', [path, DateTime.now().millisecondsSinceEpoch, note]);

  void unfreeze(String path) => _db.execute('DELETE FROM freezes WHERE path=?', [path]);

  // ── templates ─────────────────────────────────────────────────────────────
  List<TemplateFile> templates() => _db
      .select('SELECT * FROM templates ORDER BY name COLLATE NOCASE')
      .map((r) => TemplateFile(
            id: r['id'] as int,
            name: r['name'] as String,
            kind: r['kind'] as String,
            sourcePath: r['source_path'] as String,
            content: r['content'] as String?,
          ))
      .toList();

  int saveTemplate(TemplateFile t) {
    if (t.id == null) {
      _db.execute('INSERT INTO templates(name,kind,source_path,content) VALUES(?,?,?,?)',
          [t.name, t.kind, t.sourcePath, t.content]);
      return _db.lastInsertRowId;
    }
    _db.execute('UPDATE templates SET name=?,kind=?,source_path=?,content=? WHERE id=?',
        [t.name, t.kind, t.sourcePath, t.content, t.id]);
    return t.id!;
  }

  void deleteTemplate(int id) => _db.execute('DELETE FROM templates WHERE id=?', [id]);

  // ── json helpers ──────────────────────────────────────────────────────────
  static List<dynamic> publicDecodeList(String raw) => _decodeList(raw);
  static String publicEncode(Object o) => _encode(o);

  static String _encode(Object o) => __enc(o);

  static String __enc(Object o) {
    final b = StringBuffer();
    _write(o, b);
    return b.toString();
  }

  static void _write(Object? o, StringBuffer b) {
    if (o == null) {
      b.write('null');
    } else if (o is String) {
      b.write('"');
      for (final c in o.codeUnits) {
        switch (c) {
          case 0x22:
            b.write(r'\"');
          case 0x5C:
            b.write(r'\\');
          case 0x0A:
            b.write(r'\n');
          case 0x0D:
            b.write(r'\r');
          case 0x09:
            b.write(r'\t');
          default:
            if (c < 0x20) {
              b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
            } else {
              b.writeCharCode(c);
            }
        }
      }
      b.write('"');
    } else if (o is bool || o is int) {
      b.write(o.toString());
    } else if (o is double) {
      b.write(o.toString());
    } else if (o is List) {
      b.write('[');
      b.writeAll(o.map(_write2), ',');
      b.write(']');
    } else if (o is Map) {
      b.write('{');
      b.writeAll(o.entries.map((e) => '${_write2(e.key.toString())}:${_write2(e.value)}'), ',');
      b.write('}');
    } else {
      b.write('"$o"');
    }
  }

  static String _write2(Object? o) {
    final b = StringBuffer();
    _write(o, b);
    return b.toString();
  }

  static List<dynamic> _decodeList(String s) => _decode(s) as List<dynamic>;

  static Map<String, dynamic> _decodeMap(String s) {
    final v = _decode(s);
    return v is Map<String, dynamic> ? v : (v as Map).cast<String, dynamic>();
  }

  static dynamic _decode(String s) => _JsonMini.parse(s);
}

class Offset2D {
  const Offset2D(this.x, this.y);
  final double x;
  final double y;
}

/// Minimal JSON parser/serializer so the data layer stays dependency-free
/// and behaves identically on every platform.
class _JsonMini {
  static dynamic parse(String input) {
    final p = _P(input);
    final v = p.value();
    return v;
  }
}

class _P {
  _P(this.s);
  final String s;
  int i = 0;

  dynamic value() {
    _ws();
    final c = s[i];
    return switch (c) {
      '{' => obj(),
      '[' => arr(),
      '"' => str(),
      't' => _lit(true),
      'f' => _lit(false),
      'n' => _lit(null),
      _ => num(),
    };
  }

  dynamic _lit(Object? v) {
    i += (v == null ? 4 : v == true ? 4 : 5);
    return v;
  }

  Map<String, dynamic> obj() {
    final m = <String, dynamic>{};
    i++;
    _ws();
    if (s[i] == '}') {
      i++;
      return m;
    }
    while (true) {
      _ws();
      final k = str();
      _ws();
      i++; // :
      m[k] = value();
      _ws();
      final c = s[i++];
      if (c == '}') break;
    }
    return m;
  }

  List<dynamic> arr() {
    final a = <dynamic>[];
    i++;
    _ws();
    if (s[i] == ']') {
      i++;
      return a;
    }
    while (true) {
      a.add(value());
      _ws();
      final c = s[i++];
      if (c == ']') break;
    }
    return a;
  }

  String str() {
    final b = StringBuffer();
    i++;
    while (true) {
      final c = s[i++];
      if (c == '"') break;
      if (c == r'\') {
        final e = s[i++];
        switch (e) {
          case 'n':
            b.write('\n');
          case 't':
            b.write('\t');
          case 'r':
            b.write('\r');
          case 'b':
            b.write('\b');
          case 'f':
            b.write('\f');
          case 'u':
            final hex = s.substring(i, i + 4);
            b.writeCharCode(int.parse(hex, radix: 16));
            i += 4;
          default:
            b.write(e);
        }
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  dynamic num() {
    final start = i;
    while (i < s.length && '0123456789+-.eE'.contains(s[i])) {
      i++;
    }
    final t = s.substring(start);
    return int.tryParse(t) ?? double.parse(t);
  }

  void _ws() {
    while (i < s.length && ' \t\n\r'.contains(s[i])) {
      i++;
    }
  }
}

/// Directory used for undo backups and version snapshots.
Future<Directory> nexusDataDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory(pp.join(base.path, 'nexus-store'));
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}


/// Public JSON helpers for services that persist JSON blobs via the DB layer.
class DbJsonAccess {
  DbJsonAccess._();

  static List<Map<String, dynamic>> decodeList(String raw) => [
        for (final e in DbService.publicDecodeList(raw))
          (e as Map).cast<String, dynamic>(),
      ];

  static String encodeList(List<Map<String, dynamic>> items) =>
      DbService.publicEncode(items);
}
