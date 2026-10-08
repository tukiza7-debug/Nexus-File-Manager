import 'dart:async';
import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'watcher_service.dart';

/// Auto Versioning: snapshots files whenever they change, stores them under
/// the app store, keeps a retention window and exposes browse/restore.
class VersioningService {
  VersioningService(this._db, this._watchers);

  final DbService _db;
  final WatcherService _watchers;

  bool _enabled = true;
  int _keep = 20;
  final _watchedFolders = <String>{};
  final _pending = <String, Timer>{};

  bool get enabled => _enabled;
  int get retention => _keep;

  void configure({bool? enabled, int? keep}) {
    if (enabled != null) _enabled = enabled;
    if (keep != null) _keep = keep;
    if (!_enabled) stopAll();
  }

  void watchFolder(String folder) {
    if (!_enabled || _watchedFolders.contains(folder)) return;
    Directory(folder).listSync(followLinks: false); // probe
    _watchedFolders.add(folder);
    _watchers.watch(folder, (kind, path) {
      if (kind == 'removed') return;
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) return;
      _pending[path]?.cancel();
      // Debounce rapid successive writes to one snapshot per quiet period.
      _pending[path] = Timer(const Duration(milliseconds: 1600), () => snapshot(path));
    });
  }

  void stopAll() {
    for (final f in _watchedFolders) {
      _watchers.unwatch(f);
    }
    _watchedFolders.clear();
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
  }

  Future<String?> snapshot(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final store = await nexusDataDir();
      final dir = Directory(pu.join(pu.join(store.path, 'versions'), _safeKey(path)));
      dir.createSync(recursive: true);
      final ts = DateTime.now();
      final name =
          '${ts.year}${_two(ts.month)}${_two(ts.day)}-${_two(ts.hour)}${_two(ts.minute)}${_two(ts.second)}-${pu.basename(path)}';
      final dest = pu.join(dir.path, name);
      final existing = dir.listSync().whereType<File>().toList();
      // Skip if the newest snapshot already matches size+mtime.
      if (existing.isNotEmpty) {
        existing.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        final last = existing.first;
        if (last.lengthSync() == f.lengthSync() &&
            last.lastModifiedSync().isAtSameMomentAs(f.lastModifiedSync())) {
          return null;
        }
      }
      await f.copy(dest);
      _db.addVersion(VersionSnapshot(
        originalPath: path,
        snapshotPath: dest,
        size: f.lengthSync(),
        createdAtMs: ts.millisecondsSinceEpoch,
      ));
      await _prune(path);
      return dest;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _prune(String path) async {
    final snaps = _db.versionsFor(path);
    if (snaps.length <= _keep) return;
    for (final s in snaps.skip(_keep)) {
      try {
        File(s.snapshotPath).deleteSync();
      } on FileSystemException {
        // already gone
      }
      if (s.id != null) _db.deleteVersion(s.id!);
    }
  }

  Future<void> restore(VersionSnapshot v) async {
    final f = File(v.snapshotPath);
    if (!f.existsSync()) return;
    Directory(pu.dirname(v.originalPath)).createSync(recursive: true);
    await f.copy(v.originalPath);
  }

  List<String> versionedPaths() => _db.versionedPaths();

  List<VersionSnapshot> versionsFor(String path) => _db.versionsFor(path);

  static String _safeKey(String path) =>
      path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').substring(
          (path.length > 80 ? path.length - 80 : 0).clamp(0, path.length));

  static String _two(int n) => n.toString().padLeft(2, '0');
}
