import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as pp;
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/format_utils.dart';
import '../utils/path_utils.dart' as pu;

/// The single source of truth for "what happened": every mutating operation
/// appends journal entries grouped by batch. Powers Deep Undo, Redo and the
/// Paper Trail, and drives echo-suppression for mirrors & versioning.
class OperationJournal {
  OperationJournal(this._db);
  final DbService _db;

  static const selfOpWindowMs = 2500;

  /// In-memory cache of recent self-op paths to avoid hitting SQLite on
  /// every watcher event (audit item 31).
  final Map<String, int> _recentSelfOps = {};

  /// Globally-unique batch id (audit item 10): uuid v4, safe to embed in
  /// trash folder names.
  String newBatch(String label) {
    final id = const Uuid().v4();
    _db.discardRedoable(); // a new action invalidates the redo stack
    return id;
  }

  void record({
    required String batchId,
    required JournalOp op,
    required String fromPath,
    String? toPath,
    String? meta,
  }) {
    _db.addJournal(JournalEntry(
      batchId: batchId,
      op: op,
      fromPath: fromPath,
      toPath: toPath,
      meta: meta,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    final now = DateTime.now().millisecondsSinceEpoch;
    _recentSelfOps[fromPath] = now;
    if (toPath != null) _recentSelfOps[toPath] = now;
    if (_recentSelfOps.length > 512) {
      _recentSelfOps.removeWhere((_, t) => now - t > selfOpWindowMs * 40);
    }
  }

  /// True when [path] was touched by Nexus itself very recently — used to
  /// suppress watcher echo loops (mirrors, auto-versioning).
  bool wasSelfOp(String path) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - selfOpWindowMs;
    final cached = _recentSelfOps[path];
    if (cached != null && cached >= cutoff) return true;
    final rows = _db.journal(query: path, limit: 50);
    for (final e in rows) {
      if (e.createdAtMs >= cutoff &&
          (e.fromPath == path ||
              e.toPath == path ||
              pu.isUnder(path, e.fromPath) ||
              (e.toPath != null && pu.isUnder(path, e.toPath!)))) {
        _recentSelfOps[path] = e.createdAtMs;
        return true;
      }
    }
    return false;
  }

  List<BatchInfo> batches() => _db.journalBatches();

  List<JournalEntry> batchEntries(String batchId) => _db.batch(batchId);

  /// Next undoable batch (most recent, not yet undone).
  String? nextUndoBatch() {
    final rows = _db.journal(limit: 500);
    for (final e in rows) {
      if (e.undone || e.discarded) continue;
      return e.batchId;
    }
    return null;
  }

  /// Next redoable batch (oldest undone, in chronological order).
  String? nextRedoBatch() {
    final rows = _db.journal(limit: 500).reversed.toList();
    for (final e in rows) {
      if (e.undone && !e.discarded) return e.batchId;
    }
    return null;
  }

  /// Executes the inverse of every entry in [batchId]. Every step is guarded
  /// individually; the result reports partial success accurately
  /// (audit item 10).
  Future<String> undoBatch(String batchId, {required Future<void> Function(String msg) onError}) async {
    final entries = _db.batch(batchId).reversed.toList(); // LIFO
    var done = 0;
    var failed = 0;
    for (final e in entries) {
      if (e.undone || e.discarded) continue;
      try {
        await _invert(e);
        _db.setJournalUndone(e.id!, true);
        done++;
      } catch (ex) {
        failed++;
        await onError('Undo step failed (${e.op.name} ${e.fromPath}): $ex');
      }
    }
    if (failed == 0) return 'Undid $done change(s)';
    return 'Undid $done of ${entries.length}, $failed failed';
  }

  /// Re-applies a previously undone batch in original order.
  Future<String> redoBatch(String batchId, {required Future<void> Function(String msg) onError}) async {
    final entries = _db.batch(batchId);
    var done = 0;
    var failed = 0;
    for (final e in entries) {
      if (!e.undone || e.discarded) continue;
      try {
        await _reapply(e);
        _db.setJournalUndone(e.id!, false);
        done++;
      } catch (ex) {
        failed++;
        await onError('Redo step failed (${e.op.name} ${e.fromPath}): $ex');
      }
    }
    if (failed == 0) return 'Redid $done change(s)';
    return 'Redid $done of ${entries.length}, $failed failed';
  }

  Future<void> _invert(JournalEntry e) async {
    switch (e.op) {
      case JournalOp.copy:
      case JournalOp.write:
      case JournalOp.mkdir:
        // Created something → delete it. For zip roots the folder itself is
        // removed only when the extraction created it (audit item 3: undo
        // of extract never deletes a pre-existing destination).
        final t = e.toPath;
        if (t != null) {
          final f = FileSystemEntity.typeSync(t);
          if (f == FileSystemEntityType.directory) {
            Directory(t).deleteSync(recursive: true);
          } else if (f != FileSystemEntityType.notFound) {
            File(t).deleteSync();
          }
        }
      case JournalOp.move:
      case JournalOp.rename:
        // Moved/renamed → move back. The original slot must be free and its
        // parent must exist (audit item 2).
        final t = e.toPath;
        if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
          if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
            throw FileSystemException('Cannot undo: original path already occupied', e.fromPath);
          }
          Directory(pu.dirname(e.fromPath)).createSync(recursive: true);
          await renameSafe(t, e.fromPath);
        }
      case JournalOp.delete:
        // Deleted → restore from backup recorded in meta.
        final backup = e.meta;
        if (backup != null && FileSystemEntity.typeSync(backup) != FileSystemEntityType.notFound) {
          Directory(pu.dirname(e.fromPath)).createSync(recursive: true);
          await renameSafe(backup, e.fromPath);
        }
      case JournalOp.restore:
        final t = e.toPath;
        if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
          if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
            throw FileSystemException('Cannot undo restore: path already occupied', e.fromPath);
          }
          await renameSafe(t, e.fromPath);
        }
      case JournalOp.metadata:
        // Metadata edits keep the original in a backup; undo restores that
        // backup instead of deleting the original (audit items 10 + 11).
        final backup = e.toPath;
        if (backup != null && FileSystemEntity.typeSync(backup) != FileSystemEntityType.notFound) {
          await restoreBackup(backup, e.fromPath);
        }
      case JournalOp.split:
      case JournalOp.merge:
        // Outputs were recorded as write entries with individual paths;
        // the inverse restores inputs from backup rather than deleting them.
        final backup = e.toPath;
        if (backup != null && FileSystemEntity.typeSync(backup) != FileSystemEntityType.notFound) {
          await restoreBackup(backup, e.fromPath);
        } else {
          final t = e.toPath;
          if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
            File(t).deleteSync();
          }
        }
    }
  }

  Future<void> _reapply(JournalEntry e) async {
    switch (e.op) {
      case JournalOp.copy:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          final dest = e.toPath;
          if (dest != null) {
            await Isolate.run(() => _copyRecursive(e.fromPath, dest));
          }
        }
      case JournalOp.move:
      case JournalOp.rename:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          final t = e.toPath;
          if (t != null) {
            Directory(pu.dirname(t)).createSync(recursive: true);
            await renameSafe(e.fromPath, t);
          }
        }
      case JournalOp.delete:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          await deleteWithBackup(e.fromPath, e.batchId);
        }
      case JournalOp.mkdir:
        final t = e.toPath;
        if (t != null) Directory(t).createSync(recursive: true);
      case JournalOp.write:
      case JournalOp.restore:
      case JournalOp.metadata:
      case JournalOp.split:
      case JournalOp.merge:
        break; // Not re-appliable without payloads; skipped intentionally.
    }
  }

  /// Renames a file OR a directory, falling back to copy+delete when the
  /// source and destination live on different filesystems (audit item 2).
  static Future<void> renameSafe(String src, String dst) async {
    final t = FileSystemEntity.typeSync(src);
    if (t == FileSystemEntityType.notFound) {
      throw FileSystemException('Nothing to move', src);
    }
    try {
      if (t == FileSystemEntityType.directory) {
        Directory(src).renameSync(dst);
      } else {
        File(src).renameSync(dst);
      }
      return;
    } on FileSystemException catch (e) {
      if (!FileOpsBridge.isCrossDevice(e)) rethrow;
    }
    // Cross-device: copy with verification, then delete the source.
    await Isolate.run(() => _copyRecursive(src, dst));
    final ok = await FileOpsBridge.verifyCopy(src, dst);
    if (!ok) {
      try {
        final dt = FileSystemEntity.typeSync(dst);
        if (dt == FileSystemEntityType.directory) {
          Directory(dst).deleteSync(recursive: true);
        } else if (dt != FileSystemEntityType.notFound) {
          File(dst).deleteSync();
        }
      } on FileSystemException {
        // best effort cleanup
      }
      throw FileSystemException('Cross-device move failed verification', src);
    }
    if (t == FileSystemEntityType.directory) {
      Directory(src).deleteSync(recursive: true);
    } else {
      File(src).deleteSync();
    }
  }

  /// Copies [backup] over [original] atomically (temp file + rename) so a
  /// crash mid-restore can never corrupt the restored file.
  static Future<void> restoreBackup(String backup, String original) async {
    Directory(pu.dirname(original)).createSync(recursive: true);
    final tmp = pu.join(pu.dirname(original), '.${pu.basename(original)}.nexus-restore-${const Uuid().v4().substring(0, 8)}');
    await Isolate.run(() => _copyRecursive(backup, tmp));
    await renameSafe(tmp, original);
  }

  static Future<void> _copyRecursive(String src, String dst) async {
    final type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.directory) {
      Directory(dst).createSync(recursive: true);
      for (final child in Directory(src).listSync(followLinks: false)) {
        await _copyRecursive(child.path, pu.join(dst, pu.basename(child.path)));
      }
    } else if (type == FileSystemEntityType.file) {
      await File(src).copy(dst);
    }
  }

  static int _countEntries(String p) {
    final t = FileSystemEntity.typeSync(p);
    if (t == FileSystemEntityType.file) return 1;
    if (t != FileSystemEntityType.directory) return 0;
    var n = 0;
    for (final e in Directory(p).listSync(recursive: true, followLinks: false)) {
      if (e is File) n++;
    }
    return n;
  }

  /// Moves [path] into the journal trash and returns the backup location.
  ///
  /// Primary strategy: rename into the app-private store. On Android shared
  /// storage the rename may fail with EXDEV (different filesystem); the
  /// fallback keeps a `.nexus-trash/<batchId>` folder on the SAME volume so
  /// deletes still work (audit item 5).
  Future<String> _deleteToBackup(String path, String batchId) async {
    final store = await nexusDataDir();
    final trashDir = Directory(pu.join(pu.join(store.path, 'trash'), batchId));
    trashDir.createSync(recursive: true);
    final dest = _uniqueTrashName(trashDir.path, pu.basename(path));
    final type = FileSystemEntity.typeSync(path);
    try {
      type == FileSystemEntityType.directory
          ? Directory(path).renameSync(dest)
          : File(path).renameSync(dest);
      return dest;
    } on FileSystemException catch (e) {
      if (!FileOpsBridge.isCrossDevice(e)) rethrow;
    }
    // Same-volume fallback trash.
    final volumeTrash = Directory(pu.join(pu.join(FileOpsBridge.volumeRootOf(path), '.nexus-trash'), batchId));
    volumeTrash.createSync(recursive: true);
    final altDest = _uniqueTrashName(volumeTrash.path, pu.basename(path));
    final before = _countEntries(path);
    await Isolate.run(() => _copyRecursive(path, altDest));
    final after = _countEntries(altDest);
    if (before != after) {
      try {
        final t = FileSystemEntity.typeSync(altDest);
        if (t == FileSystemEntityType.directory) {
          Directory(altDest).deleteSync(recursive: true);
        } else if (t != FileSystemEntityType.notFound) {
          File(altDest).deleteSync();
        }
      } on FileSystemException {
        // best effort
      }
      throw FileSystemException('Trash backup failed verification; original left untouched', path);
    }
    type == FileSystemEntityType.directory
        ? Directory(path).deleteSync(recursive: true)
        : File(path).deleteSync();
    return altDest;
  }

  static String _uniqueTrashName(String dir, String name) {
    var candidate = pu.join(dir, name);
    if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.notFound) return candidate;
    final stem = pu.stem(name);
    final ext = pu.ext(name);
    var n = 2;
    while (true) {
      candidate = pu.join(dir, ext.isEmpty ? '$stem ($n)' : '$stem ($n).$ext');
      if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.notFound) return candidate;
      n++;
    }
  }

  /// Public helper used by the ops service: moves a path into the journal
  /// trash and records the deletion (restorable).
  Future<String> deleteWithBackup(String path, String batchId) async {
    final backup = await _deleteToBackup(path, batchId);
    record(batchId: batchId, op: JournalOp.delete, fromPath: path, toPath: backup, meta: backup);
    return backup;
  }

  /// Copies (never moves) [path] into the journal trash as a pre-edit
  /// backup and records a metadata entry whose undo restores it
  /// (audit item 11).
  Future<String> backupCopyForEdit(String path, String batchId) async {
    final store = await nexusDataDir();
    final backupDir = Directory(pu.join(pu.join(store.path, 'trash'), batchId));
    backupDir.createSync(recursive: true);
    final dest = _uniqueTrashName(backupDir.path, pu.basename(path));
    await Isolate.run(() => _copyRecursive(path, dest));
    record(batchId: batchId, op: JournalOp.metadata, fromPath: path, toPath: dest, meta: 'backup');
    return dest;
  }

  // ── trash retention (audit item 5) ────────────────────────────────────────
  static const defaultTrashRetentionDays = 30;

  /// Removes trash batches older than [days]. Called opportunistically.
  Future<int> purgeOldTrash({int days = defaultTrashRetentionDays}) async {
    final store = await nexusDataDir();
    final trashRoot = Directory(pp.join(store.path, 'trash'));
    if (!trashRoot.existsSync()) return 0;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    var removed = 0;
    for (final e in trashRoot.listSync(followLinks: false)) {
      final stat = e.statSync();
      if (stat.modified.isBefore(cutoff)) {
        try {
          e is Directory ? e.deleteSync(recursive: true) : e.deleteSync();
          removed++;
        } on FileSystemException {
          // in use or already gone
        }
      }
    }
    // Same-volume fallback trashes live under <volume>/.nexus-trash.
    for (final vol in FileOpsBridge.knownVolumes(_db)) {
      final vt = Directory(pu.join(vol, '.nexus-trash'));
      if (!vt.existsSync()) continue;
      for (final e in vt.listSync(followLinks: false)) {
        final stat = e.statSync();
        if (stat.modified.isBefore(cutoff)) {
          try {
            e is Directory ? e.deleteSync(recursive: true) : e.deleteSync();
            removed++;
          } on FileSystemException {
            // in use
          }
        }
      }
    }
    return removed;
  }

  /// Empties every trash folder immediately ("Empty trash" action).
  Future<int> emptyTrash() async => purgeOldTrash(days: 0);

  static String describe(String batchId, List<JournalEntry> entries) {
    if (entries.isEmpty) return 'nothing';
    final ops = entries.map((e) => e.op.name).toSet();
    final when = formatDateTime(DateTime.fromMillisecondsSinceEpoch(entries.first.createdAtMs));
    return '${ops.join('/')} · ${entries.length} · $when';
  }
}

/// Platform bridges shared by the journal and the ops service. Kept as a
/// separate class so pure-logic tests can stub the volume logic.
class FileOpsBridge {
  /// True for the errno/OS codes that genuinely mean "different filesystem".
  static bool isCrossDevice(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == 18 || code == 17) return true; // EXDEV / ERROR_NOT_SAME_DEVICE
    final msg = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    return msg.contains('cross-device') ||
        msg.contains('crosses') ||
        msg.contains('different drive') ||
        msg.contains('not same device');
  }

  /// Verifies a copy before its source is deleted: file count and total
  /// byte size must match (audit item 6).
  static Future<bool> verifyCopy(String src, String dst) async {
    return Isolate.run(() {
      int measure(String p, {required bool sizeOnly}) {
        final t = FileSystemEntity.typeSync(p);
        if (t == FileSystemEntityType.file) return sizeOnly ? File(p).lengthSync() : 1;
        if (t != FileSystemEntityType.directory) return 0;
        var total = 0;
        for (final e in Directory(p).listSync(recursive: true, followLinks: false)) {
          if (e is File) total += sizeOnly ? e.lengthSync() : 1;
        }
        return total;
      }

      if (FileSystemEntity.typeSync(src) == FileSystemEntityType.file) {
        return measure(src, sizeOnly: true) == measure(dst, sizeOnly: true);
      }
      return measure(src, sizeOnly: false) == measure(dst, sizeOnly: false) &&
          measure(src, sizeOnly: true) == measure(dst, sizeOnly: true);
    });
  }

  /// The storage root that hosts [path] — used for same-volume trash on
  /// Android (e.g. `/storage/emulated/0`) and drive roots on desktop.
  static String volumeRootOf(String path) {
    final norm = pu.normalize(path);
    if (norm.startsWith('/storage/emulated/')) return '/storage/emulated/0';
    if (norm.startsWith('/sdcard/')) return '/sdcard';
    final segs = norm.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return '/';
    // Heuristic: on Android/Linux the first two segments identify the volume
    // for /storage/... paths; elsewhere the first segment.
    if (segs.first == 'storage') return '/${segs.take(2).join('/')}';
    return '/';
  }

  /// Volumes we have used for fallback trash (recorded in settings).
  static List<String> knownVolumes(DbService db) {
    final raw = db.getSetting('trash.volumes');
    if (raw == null || raw.isEmpty) return const [];
    return raw.split('|').where((s) => s.isNotEmpty).toList();
  }

  static void rememberVolume(DbService db, String path) {
    final root = volumeRootOf(path);
    final vols = knownVolumes(db).toSet();
    if (vols.contains(root)) return;
    vols.add(root);
    db.setSetting('trash.volumes', vols.join('|'));
  }
}
