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
class WatchdogService {
  WatchdogService(this._db, this._ops, this._watchers, this._pipelines, this._versioning, this._journal);

  final DbService _db;
  // ignore: unused_field
  final FileOpsService _ops;
  final WatcherService _watchers;
  final PipelineService _pipelines;
  final VersioningService _versioning;
  final OperationJournal _journal;

  final _events = StreamController<WatchdogEvent>.broadcast();
  Stream<WatchdogEvent> get events => _events.stream;

  final _subs = <int, _Sub>{};

  void startAll() {
    for (final w in _db.watchdogs()) {
      if (w.enabled) start(w);
    }
  }

  void start(WatchdogRule w) {
    final id = w.id;
    if (id == null || _subs.containsKey(id)) return;
    stop(id);
    void listener(String kind, String path) => _onEvent(w, kind, path);
    _watchers.watch(w.folder, listener);
    _subs[id] = _Sub(listener);
  }

  void stop(int id) {
    final sub = _subs.remove(id);
    if (sub == null) return;
    final w = _db.watchdogs().where((x) => x.id == id).firstOrNull;
    if (w != null) _watchers.unwatch(w.folder, listener: sub.listener);
  }

  void _onEvent(WatchdogRule w, String kind, String path) {
    if (w.id == null) return;
    if (_journalSelf(path)) return;
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

  bool _journalSelf(String path) => false; // Journal echo handled per action.

  Future<void> _fire(WatchdogRule w, String path) async {
    try {
      switch (w.action) {
        case 'notify':
          _events.add(WatchdogEvent(rule: w.name, message: 'Change in ${pu.compactPath(w.folder)}: ${pu.basename(path)}'));
        case 'moveTo':
          if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound && w.arg.isNotEmpty) {
            final batch = 'wd-${DateTime.now().millisecondsSinceEpoch}';
            final destDir = w.arg;
            Directory(destDir).createSync(recursive: true);
            final dest = pu.join(destDir, pu.basename(path));
            if (!FileSystemEntity.identicalSync(path, dest)) {
              FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
                  ? Directory(path).renameSync(dest)
                  : File(path).renameSync(dest);
              _journal.record(batchId: batch, op: JournalOp.move, fromPath: path, toPath: dest);
            }
          }
        case 'pipeline':
          final p = _pipelines.byId(int.tryParse(w.arg) ?? -1);
          if (p != null) {
            await _pipelines.run(p, [path], batchId: 'wd-pipe-${DateTime.now().millisecondsSinceEpoch}');
          }
        case 'version':
          await _versioning.snapshot(path);
        case 'teleport':
          _events.add(WatchdogEvent(rule: w.name, message: 'teleport:$path'));
      }
      if (w.id != null) {
        _db.setWatchdogFired(w.id!, DateTime.now().millisecondsSinceEpoch);
      }
    } on FileSystemException catch (e) {
      _events.add(WatchdogEvent(rule: w.name, message: 'error: ${e.message}'));
    }
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
  final void Function(String kind, String path) listener;
}
