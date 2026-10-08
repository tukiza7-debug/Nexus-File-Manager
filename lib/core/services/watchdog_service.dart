import 'dart:async';
import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'journal.dart';
import 'ops_service.dart';
import 'pipeline_service.dart';
import 'versioning_service.dart';
import 'watcher_service.dart';

/// Folder Watchdog: watches folders and fires automated actions when
/// trigger conditions are met (any change / file added / file removed /
/// name matches pattern).
///
/// Audit item 14:
///  * echo suppression — paths written by the ops layer are registered here
///    and ignored for ~3 s so pipeline/move actions cannot re-trigger;
///  * loop guard — a rule firing more than [maxFiringsPerMinute] times in
///    60 s is disabled and reported instead of looping forever;
///  * moveTo guards identicalSync with existsSync, resolves name conflicts
///    with unique names and routes through FileOpsService;
///  * every exception is caught in _fire (not just FileSystemException);
///  * rule cycles are detected when rules are saved.
class WatchdogService {
  WatchdogService(this._db, this._ops, this._watchers, this._pipelines, this._versioning, this._journal);

  final DbService _db;
  final FileOpsService _ops;
  final WatcherService _watchers;
  final PipelineService _pipelines;
  final VersioningService _versioning;
  final OperationJournal _journal;

  final _events = StreamController<WatchdogEvent>.broadcast();
  Stream<WatchdogEvent> get events => _events.stream;

  final _subs = <int, _Sub>{};

  /// Paths (normalized) recently written through the ops layer — echo
  /// suppression window of ~3 s.
  final _recentWrites = <String, int>{};
  static const echoWindowMs = 3000;

  /// Loop guard: rule id → firing timestamps inside the last minute.
  final _firings = <int, List<int>>{};
  static const maxFiringsPerMinute = 10;

  void startAll() {
    for (final w in _db.watchdogs()) {
      if (w.enabled) start(w);
    }
  }

  void start(WatchdogRule w) {
    final id = w.id;
    if (id == null || _subs.containsKey(id)) return;
    stop(id);
    final listener = _watchers.watchWithToken(
        w.folder, (kind, path) => _onEvent(w, kind, path));
    _subs[id] = _Sub(listener);
  }

  void stop(int id) {
    final sub = _subs.remove(id);
    if (sub == null) return;
    final w = _db.watchdogs().where((x) => x.id == id).firstOrNull;
    if (w != null) _watchers.unwatch(w.folder, listener: sub.listener);
  }

  /// Registers a path the ops layer is about to write so the watchdog
  /// ignores the resulting event burst. Called by FileOpsService consumers
  /// via [noteWrite]; the journal window is the general fallback.
  void noteWrite(String path) {
    final key = pu.normalize(path);
    _recentWrites[key] = DateTime.now().millisecondsSinceEpoch;
    _recentWrites[pu.dirname(key)] = DateTime.now().millisecondsSinceEpoch;
    if (_recentWrites.length > 512) {
      final cutoff = DateTime.now().millisecondsSinceEpoch - echoWindowMs * 10;
      _recentWrites.removeWhere((_, t) => t < cutoff);
    }
  }

  bool _isEcho(String path) {
    final key = pu.normalize(path);
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = _recentWrites[key];
    if (t != null && now - t <= echoWindowMs) return true;
    return _journal.wasSelfOp(path);
  }

  void _onEvent(WatchdogRule w, String kind, String path) {
    final id = w.id;
    if (id == null) return;
    if (_isEcho(path)) return;
    if (_loopGuardTripped(id, w.name)) return;
    final name = pu.basename(path);
    final triggered = switch (w.trigger) {
      'any' => true,
      'added' => kind == 'added' || kind == 'moved',
      'removed' => kind == 'removed',
      'pattern' => (kind == 'added' || kind == 'modified') && matchesPattern(name, w.pattern),
      _ => false,
    };
    if (!triggered) return;
    _fire(w, path);
  }

  bool _loopGuardTripped(int id, String name) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _firings.putIfAbsent(id, () => []);
    list.removeWhere((t) => now - t > 60000);
    if (list.length >= maxFiringsPerMinute) {
      // Disable the runaway rule instead of looping forever.
      final w = _db.watchdogs().where((x) => x.id == id).firstOrNull;
      if (w != null) {
        _db.saveWatchdog(WatchdogRule(
          id: w.id,
          name: w.name,
          folder: w.folder,
          trigger: w.trigger,
          pattern: w.pattern,
          action: w.action,
          arg: w.arg,
          enabled: false,
          lastFiredMs: w.lastFiredMs,
        ));
      }
      _events.add(WatchdogEvent(
          rule: name,
          message: 'Rule disabled: it fired more than $maxFiringsPerMinute times per minute (possible loop)'));
      _firings.remove(id);
      return true;
    }
    return false;
  }

  Future<void> _fire(WatchdogRule w, String path) async {
    try {
      switch (w.action) {
        case 'notify':
          _events.add(WatchdogEvent(rule: w.name, message: 'Change in ${pu.compactPath(w.folder)}: ${pu.basename(path)}'));
        case 'moveTo':
          if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound && w.arg.isNotEmpty) {
            noteWrite(path); // suppress our own move echo
            final batch = _journal.newBatch('watchdog-move');
            final destDir = w.arg;
            Directory(destDir).createSync(recursive: true);
            final dest = FileOpsService.uniqueCopyName(pu.join(destDir, pu.basename(path)));
            // identicalSync throws when the destination does not exist —
            // only compare when both sides exist (audit item 14).
            if (!FileOpsService.sameEntity(path, dest)) {
              await _ops.movePaths([path], destDir, batchId: batch,
                  renamePlan: {path: dest});
              _ops.finish(batch);
            }
          }
        case 'pipeline':
          final p = _pipelines.byId(int.tryParse(w.arg) ?? -1);
          if (p != null) {
            noteWrite(path);
            await _pipelines.run(p, [path], batchId: _journal.newBatch('watchdog-pipeline'));
          }
        case 'version':
          await _versioning.snapshot(path);
        case 'teleport':
          _events.add(WatchdogEvent(rule: w.name, message: 'teleport:$path'));
      }
      final id = w.id;
      if (id != null) {
        _db.setWatchdogFired(id, DateTime.now().millisecondsSinceEpoch);
        _firings.putIfAbsent(id, () => []).add(DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      // Catch-all: a malformed rule must never crash the watchdog loop.
      _events.add(WatchdogEvent(rule: w.name, message: 'error: $e'));
    }
  }

  /// Detects cycles among enabled moveTo rules before a rule is saved
  /// (audit item 14). Returns the cycle description, or null when clear.
  String? detectCycle(WatchdogRule candidate) {
    final edges = <String, String>{};
    for (final w in _db.watchdogs()) {
      if (w.action == 'moveTo' && w.arg.isNotEmpty && w.enabled) {
        edges[pu.normalize(w.folder)] = pu.normalize(w.arg);
      }
    }
    if (candidate.action == 'moveTo' && candidate.arg.isNotEmpty) {
      edges[pu.normalize(candidate.folder)] = pu.normalize(candidate.arg);
    }
    String? hop(String start) {
      var current = start;
      var steps = 0;
      while (edges.containsKey(current)) {
        current = edges[current]!;
        steps++;
        if (steps > edges.length) return current;
        if (current == start) return current;
      }
      return null;
    }

    for (final start in edges.keys) {
      final hit = hop(start);
      if (hit != null) {
        return 'moveTo rules form a cycle through ${pu.compactPath(hit)}';
      }
    }
    return null;
  }

  void dispose() {
    for (final id in _subs.keys.toList()) {
      stop(id);
    }
  }
}

class WatchdogEvent {
  const WatchdogEvent({required this.rule, required this.message});
  final String rule;
  final String message;
}

class _Sub {
  _Sub(this.listener);
  final WatcherListener listener;
}
