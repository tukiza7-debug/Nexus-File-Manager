import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'watcher_service.dart';

/// Auto Versioning: snapshots files whenever they change, stores them under
/// the app store, keeps a retention window and exposes browse/restore.
///
/// Audit item 17:
///  * dedupe by size+mtime+hash recorded in the DB (not snapshot mtime);
///  * per-file and total store size caps (configurable);
///  * folder key is a hash of the full path (no truncation collisions);
///  * restore backs up the current file first;
///  * missing folders are handled instead of throwing.
class VersioningService {
  VersioningService(this._db, this._watchers);

  final DbService _db;
  final WatcherService _watchers;

  bool _enabled = true;
  int _keep = 20;
  int _maxFileBytes = 256 * 1024 * 1024; // 256 MiB per file
  int _maxStoreBytes = 4 * 1024 * 1024 * 1024; // 4 GiB total
  final _watchedFolders = <String, WatcherListener>{};
  final _pending = <String, Timer>{};

  bool get enabled => _enabled;
  int get retention => _keep;

  void configure({bool? enabled, int? keep, int? maxFileBytes, int? maxStoreBytes}) {
    if (enabled != null) _enabled = enabled;
    if (keep != null) _keep = keep;
    if (maxFileBytes != null) _maxFileBytes = maxFileBytes;
    if (maxStoreBytes != null) _maxStoreBytes = maxStoreBytes;
    if (!_enabled) stopAll();
  }

  void watchFolder(String folder) {
    if (!_enabled || _watchedFolders.containsKey(folder)) return;
    // Audit item 17: a missing folder must not crash the caller.
    if (FileSystemEntity.typeSync(folder) != FileSystemEntityType.directory) return;
    final token = _watchers.watchWithToken(folder, (kind, path) {
      if (kind == 'removed') return;
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) return;
      _pending[path]?.cancel();
      // Debounce rapid successive writes to one snapshot per quiet period.
      _pending[path] = Timer(const Duration(milliseconds: 1600), () => snapshot(path));
    });
    _watchedFolders[folder] = token;
  }

  void stopAll() {
    for (final entry in _watchedFolders.entries) {
      _watchers.unwatch(entry.key, listener: entry.value);
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
      final size = f.lengthSync();
      if (size > _maxFileBytes) return null; // per-file cap
      final fstat = f.statSync();
      final hash = await _hashOf(path);
      // Dedupe by size+mtime+hash recorded in the DB (audit item 17).
      if (_db.hasVersionSignature(path, size, fstat.modified.millisecondsSinceEpoch, hash)) {
        return null;
      }
      final store = await nexusDataDir();
      final dir = Directory(pu.join(pu.join(store.path, 'versions'), _keyFor(path)));
      dir.createSync(recursive: true);
      final ts = DateTime.now();
      final name =
          '${ts.year}${_two(ts.month)}${_two(ts.day)}-${_two(ts.hour)}${_two(ts.minute)}${_two(ts.second)}-${pu.basename(path)}';
      final dest = pu.join(dir.path, name);
      await f.copy(dest);
      _db.addVersion(VersionSnapshot(
        originalPath: path,
        snapshotPath: dest,
        size: size,
        createdAtMs: ts.millisecondsSinceEpoch,
        mtimeMs: fstat.modified.millisecondsSinceEpoch,
        hash: hash,
      ));
      await _prune(path);
      await _enforceStoreCap();
      return dest;
    } on FileSystemException {
      return null;
    }
  }

  static Future<String> _hashOf(String path) => Isolate.run(() {
        try {
          return crypto.md5.convert(File(path).readAsBytesSync()).toString();
        } on FileSystemException {
          return '';
        }
      });

  /// Folder key: full sha1 of the path — no 80-char truncation collisions
  /// (audit item 17 / S16).
  static String _keyFor(String path) =>
      crypto.sha1.convert(pu.normalize(path).codeUnits).toString();

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

  Future<void> _enforceStoreCap() async {
    final store = await nexusDataDir();
    final root = Directory(pu.join(store.path, 'versions'));
    if (!root.existsSync()) return;
    // Total size across snapshots.
    final all = _db.allVersions();
    var total = 0;
    for (final v in all) {
      total += v.size;
    }
    if (total <= _maxStoreBytes) return;
    // Delete oldest first until under the cap.
    all.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    for (final v in all) {
      if (total <= _maxStoreBytes) break;
      try {
        File(v.snapshotPath).deleteSync();
      } on FileSystemException {
        // already gone
      }
      if (v.id != null) _db.deleteVersion(v.id!);
      total -= v.size;
    }
  }

  /// Restores [v] over its original path — the current file is backed up
  /// through the journal first so the restore itself is undoable
  /// (audit item 17).
  Future<void> restore(VersionSnapshot v, {OperationJournal? journal}) async {
    final f = File(v.snapshotPath);
    if (!f.existsSync()) return;
    if (journal != null && File(v.originalPath).existsSync()) {
      final batch = journal.newBatch('restore');
      await journal.backupCopyForEdit(v.originalPath, batch);
      journal.record(
          batchId: batch,
          op: JournalOp.restore,
          fromPath: v.originalPath,
          toPath: v.snapshotPath,
          meta: 'version-restore');
    }
    Directory(pu.dirname(v.originalPath)).createSync(recursive: true);
    await f.copy(v.originalPath);
  }

  List<String> versionedPaths() => _db.versionedPaths();

  List<VersionSnapshot> versionsFor(String path) => _db.versionsFor(path);

  static String _two(int n) => n.toString().padLeft(2, '0');
}
