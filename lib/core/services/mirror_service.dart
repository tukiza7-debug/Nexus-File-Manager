import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'journal.dart';
import 'ops_service.dart';
import 'watcher_service.dart';

/// Live Folder Mirror: keeps a target folder in two-way sync with a source.
/// Each side's watcher is mirrored onto the other side, with echo loops
/// suppressed through the operation journal's self-op window.
class MirrorService {
  MirrorService(this._db, this._ops, this._watchers, this._journal);

  final DbService _db;
  // ignore: unused_field
  final FileOpsService _ops;
  final WatcherService _watchers;
  final OperationJournal _journal;

  final _active = <int, MirrorPair>{};
  final _status = <int, String>{};

  String statusFor(int id) => _status[id] ?? 'idle';

  /// Starts mirroring for every enabled pair (called at app startup).
  Future<void> startAll() async {
    for (final m in _db.mirrors()) {
      if (m.enabled) await start(m);
    }
  }

  Future<void> start(MirrorPair m) async {
    if (_active.containsKey(m.id)) return;
    if (!Directory(m.source).existsSync() || !Directory(m.target).existsSync()) {
      _status[m.id!] = 'folder missing';
      return;
    }
    _active[m.id!] = m;
    _status[m.id!] = 'live';
    _watchers.watch(m.source, (kind, path) => _onEvent(m, fromSource: true, kind: kind, path: path));
    _watchers.watch(m.target, (kind, path) => _onEvent(m, fromSource: false, kind: kind, path: path));
  }

  Future<void> stop(int id) async {
    final m = _active.remove(id);
    if (m == null) return;
    _watchers.unwatch(m.source);
    _watchers.unwatch(m.target);
    _status[id] = 'paused';
  }

  Future<void> fullSync(MirrorPair m) async {
    await _syncTree(m.source, m.target);
    await _syncTree(m.target, m.source);
    _db.setMirrorSync(m.id!, DateTime.now().millisecondsSinceEpoch);
    _status[m.id!] = 'synced';
  }

  Future<void> _syncTree(String src, String dst) async {
    final s = Directory(src);
    if (!s.existsSync()) return;
    Directory(dst).createSync(recursive: true);
    final dstNames = Directory(dst).listSync(followLinks: false).map((e) => pu.basename(e.path)).toSet();
    for (final e in s.listSync(followLinks: false)) {
      final name = pu.basename(e.path);
      final target = pu.join(dst, name);
      final exists = dstNames.contains(name);
      if (e is Directory) {
        if (!exists) Directory(target).createSync(recursive: true);
        await _syncTree(e.path, target);
      } else if (e is File) {
        if (!exists || File(target).lengthSync() != e.lengthSync() ||
            File(target).lastModifiedSync().isBefore(e.lastModifiedSync())) {
          await e.copy(target);
        }
      }
    }
  }

  Future<void> _onEvent(MirrorPair m, {required bool fromSource, required String kind, required String path}) async {
    // Skip our own writes (echo suppression via the journal).
    if (_journal.wasSelfOp(path) || _journal.wasSelfOp(path.endsWith('/') ? path.substring(0, path.length - 1) : path)) {
      return;
    }
    final srcRoot = fromSource ? m.source : m.target;
    final dstRoot = fromSource ? m.target : m.source;
    final rel = path.substring(srcRoot.length).replaceAll(RegExp(r'^[/\\]'), '');
    final dst = pu.join(dstRoot, rel);
    final fileName = pu.basename(path);

    // If the event path is inside a directory that was mirrored (e.g. its
    // parent moved), map through the parent instead.
    try {
      switch (kind) {
        case 'added':
        case 'modified':
        case 'moved':
          final t = FileSystemEntity.typeSync(path);
          if (t == FileSystemEntityType.notFound) return;
          final type = FileSystemEntity.typeSync(dst);
          if (type == FileSystemEntityType.file && File(dst).lengthSync() == _sizeOf(path)) return;
          if (t == FileSystemEntityType.directory) {
            if (type != FileSystemEntityType.directory) {
              if (type != FileSystemEntityType.notFound) {
                File(dst).deleteSync();
              }
              Directory(dst).createSync(recursive: true);
            }
            await _syncTree(path, dst);
          } else if (t == FileSystemEntityType.file) {
            Directory(pu.dirname(dst)).createSync(recursive: true);
            await File(path).copy(dst);
          }
        case 'removed':
          final type = FileSystemEntity.typeSync(dst);
          if (type == FileSystemEntityType.notFound) return;
          type == FileSystemEntityType.directory
              ? Directory(dst).deleteSync(recursive: true)
              : File(dst).deleteSync();
      }
      _db.setMirrorSync(m.id!, DateTime.now().millisecondsSinceEpoch);
      _status[m.id!] = 'live · ${fileName.length > 18 ? '…${fileName.substring(fileName.length - 18)}' : fileName}';
    } on FileSystemException {
      _status[m.id!] = 'sync error';
    }
  }

  static int _sizeOf(String p) {
    final t = FileSystemEntity.typeSync(p);
    return t == FileSystemEntityType.file ? File(p).lengthSync() : 0;
  }

  void dispose() {
    for (final m in _active.values) {
      _watchers.unwatch(m.source);
      _watchers.unwatch(m.target);
    }
    _active.clear();
  }
}
