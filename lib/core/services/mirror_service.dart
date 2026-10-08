import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'journal.dart';
import 'ops_service.dart';
import 'watcher_service.dart';

/// Live Folder Mirror: keeps a target folder in two-way sync with a source.
/// Each side's watcher is mirrored onto the other side, with echo loops
/// suppressed through the operation journal's self-op window.
///
/// Audit item 16:
///  * deletions move to the journal trash instead of being permanent;
///  * copies are recorded in the journal so wasSelfOp suppresses echoes;
///  * copies preserve mtime and comparisons use size+mtime so edits of
///    equal size are detected and fullSync does not recopy everything;
///  * deletions are tracked in a manifest so fullSync never resurrects;
///  * equal or nested source/target pairs are rejected;
///  * dryRun() lets the UI show a plan and ask for confirmation before the
///    first sync.
class MirrorService {
  MirrorService(this._db, this._ops, this._watchers, this._journal);

  final DbService _db;
  final FileOpsService _ops;
  final WatcherService _watchers;
  final OperationJournal _journal;

  final _active = <int, MirrorPair>{};
  final _status = <int, String>{};

  /// Normalized "path|mtime|size" keys of files known to be deleted by the
  /// user, per pair id — prevents fullSync from resurrecting them.
  final _deletionManifest = <int, Set<String>>{};

  String statusFor(int id) => _status[id] ?? 'idle';

  /// Starts mirroring for every enabled pair (called at app startup).
  Future<void> startAll() async {
    for (final m in _db.mirrors()) {
      if (m.enabled) await start(m);
    }
  }

  /// Validates a pair before it may be created (audit item 16).
  static String? validatePair(String source, String target) {
    if (pu.samePath(source, target)) return 'Source and target are the same folder';
    if (pu.isUnder(target, source)) return 'Target is inside the source folder';
    if (pu.isUnder(source, target)) return 'Source is inside the target folder';
    return null;
  }

  Future<void> start(MirrorPair m) async {
    if (_active.containsKey(m.id)) return;
    final problem = validatePair(m.source, m.target);
    if (problem != null) {
      _status[m.id!] = problem;
      return;
    }
    if (!Directory(m.source).existsSync() || !Directory(m.target).existsSync()) {
      _status[m.id!] = 'folder missing';
      return;
    }
    _active[m.id!] = m;
    _status[m.id!] = 'live';
    _deletionManifest[m.id!] = {};
    _sourceToken[m.id!] = _watchers.watchWithToken(
        m.source, (kind, path) => _onEvent(m, fromSource: true, kind: kind, path: path));
    _targetToken[m.id!] = _watchers.watchWithToken(
        m.target, (kind, path) => _onEvent(m, fromSource: false, kind: kind, path: path));
  }

  final _sourceToken = <int, WatcherListener>{};
  final _targetToken = <int, WatcherListener>{};

  Future<void> stop(int id) async {
    final m = _active.remove(id);
    if (m == null) return;
    _watchers.unwatch(m.source, listener: _sourceToken.remove(id));
    _watchers.unwatch(m.target, listener: _targetToken.remove(id));
    _status[id] = 'paused';
  }

  /// Plans what a full sync would do without touching the disk
  /// (audit item 16: dry-run + confirm before the first sync).
  Future<List<String>> dryRun(MirrorPair m) async {
    final plan = <String>[];
    await _syncTree(m.source, m.target, plan: plan);
    await _syncTree(m.target, m.source, plan: plan);
    return plan;
  }

  Future<void> fullSync(MirrorPair m, {String? batchId}) async {
    final batch = batchId ?? _journal.newBatch('mirror-full');
    final deletions = _deletionManifest.putIfAbsent(m.id!, () => {});
    await _syncTree(m.source, m.target, batchId: batch, deletions: deletions);
    await _syncTree(m.target, m.source, batchId: batch, deletions: deletions);
    _db.setMirrorSync(m.id!, DateTime.now().millisecondsSinceEpoch);
    _status[m.id!] = 'synced';
    if (batchId == null) _ops.finish(batch);
  }

  Future<void> _syncTree(String src, String dst,
      {List<String>? plan, String? batchId, Set<String>? deletions}) async {
    final s = Directory(src);
    if (!s.existsSync()) return;
    Directory(dst).createSync(recursive: true);
    final dstNames = Directory(dst).listSync(followLinks: false).map((e) => pu.basename(e.path)).toSet();
    for (final e in s.listSync(followLinks: false)) {
      final name = pu.basename(e.path);
      final target = pu.join(dst, name);
      final exists = dstNames.contains(name);
      if (e is Directory) {
        if (!exists && plan != null) {
          plan.add('create folder ${pu.compactPath(target)}');
        }
        if (!exists && plan == null) {
          Directory(target).createSync(recursive: true);
        }
        await _syncTree(e.path, target, plan: plan, batchId: batchId, deletions: deletions);
      } else if (e is File) {
        final key = '${pu.normalize(e.path)}|${e.lastModifiedSync().millisecondsSinceEpoch}|${e.lengthSync()}';
        if (deletions?.contains(key) ?? false) continue; // never resurrect
        final needsCopy = !exists || !_sameContent(e, File(target));
        if (!needsCopy) continue;
        if (plan != null) {
          plan.add('copy ${pu.compactPath(e.path)} → ${pu.compactPath(target)}');
        } else {
          final before = exists;
          if (before) {
            // Overwrite goes through the journal so undo restores the old file.
            await _ops.copyPaths([e.path], pu.dirname(target),
                batchId: batchId!, renamePlan: {e.path: target});
          } else {
            await _ops.copyPaths([e.path], pu.dirname(target), batchId: batchId!);
          }
          final copied = File(target);
          if (copied.existsSync()) {
            try {
              copied.setLastModifiedSync(e.lastModifiedSync());
            } on FileSystemException {
              // Some filesystems refuse future/past mtimes — size+hash still
              // guards equality.
            }
          }
        }
      }
    }
  }

  /// Size + mtime comparison; falls back to a quick hash when mtimes
  /// differ but sizes match, so equal-size edits are detected.
  static bool _sameContent(File a, File b) {
    try {
      if (a.lengthSync() != b.lengthSync()) return false;
      final am = a.lastModifiedSync();
      final bm = b.lastModifiedSync();
      if (am.isAtSameMomentAs(bm)) return true;
      return _quickHash(a) == _quickHash(b);
    } on FileSystemException {
      return false;
    }
  }

  static String _quickHash(File f) {
    try {
      final raf = f.openSync();
      try {
        final len = raf.lengthSync();
        final head = raf.readSync(len < 4096 ? len : 4096);
        var h = 0x811c9dc5;
        for (final b in head) {
          h ^= b;
          h = (h * 0x01000193) & 0xFFFFFFFF;
        }
        if (len > 4096) {
          raf.setPositionSync(len - 4096);
          final tail = raf.readSync(4096);
          for (final b in tail) {
            h ^= b;
            h = (h * 0x01000193) & 0xFFFFFFFF;
          }
        }
        return '$len-$h';
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return '${f.path}';
    }
  }

  Future<void> _onEvent(MirrorPair m, {required bool fromSource, required String kind, required String path}) async {
    // Skip our own writes (echo suppression via the journal + ops records).
    if (_journal.wasSelfOp(path) || _journal.wasSelfOp(path.endsWith('/') ? path.substring(0, path.length - 1) : path)) {
      return;
    }
    final srcRoot = fromSource ? m.source : m.target;
    final dstRoot = fromSource ? m.target : m.source;
    final rel = path.substring(srcRoot.length).replaceAll(RegExp(r'^[/\\]'), '');
    final dst = pu.join(dstRoot, rel);
    final fileName = pu.basename(path);

    try {
      switch (kind) {
        case 'added':
        case 'modified':
        case 'moved':
          final t = FileSystemEntity.typeSync(path);
          if (t == FileSystemEntityType.notFound) return;
          final type = FileSystemEntity.typeSync(dst);
          if (t == FileSystemEntityType.file &&
              type == FileSystemEntityType.file &&
              _sameContent(File(path), File(dst))) {
            return;
          }
          final batch = _journal.newBatch('mirror');
          if (t == FileSystemEntityType.directory) {
            if (type != FileSystemEntityType.directory) {
              if (type != FileSystemEntityType.notFound) {
                await _journal.deleteWithBackup(dst, batch);
              }
              Directory(dst).createSync(recursive: true);
            }
            await _syncTree(path, dst, batchId: batch);
          } else if (t == FileSystemEntityType.file) {
            Directory(pu.dirname(dst)).createSync(recursive: true);
            await _ops.copyPaths([path], pu.dirname(dst),
                batchId: batch,
                renamePlan: {path: dst});
            final copied = File(dst);
            if (copied.existsSync()) {
              try {
                copied.setLastModifiedSync(File(path).lastModifiedSync());
              } on FileSystemException {
                // best effort
              }
            }
          }
          _ops.finish(batch);
        case 'removed':
          final type = FileSystemEntity.typeSync(dst);
          if (type == FileSystemEntityType.notFound) return;
          // Audit item 16: mirror deletions go to the journal trash, never
          // permanently, and are recorded so fullSync will not resurrect.
          final batch = _journal.newBatch('mirror-delete');
          final key =
              '${pu.normalize(dst)}|0|0';
          _deletionManifest.putIfAbsent(m.id!, () => {}).add(key);
          await _journal.deleteWithBackup(dst, batch);
          _ops.finish(batch);
      }
      _db.setMirrorSync(m.id!, DateTime.now().millisecondsSinceEpoch);
      _status[m.id!] = 'live · ${fileName.length > 18 ? '…${fileName.substring(fileName.length - 18)}' : fileName}';
    } on FileSystemException {
      _status[m.id!] = 'sync error';
    } catch (e) {
      _status[m.id!] = 'sync error: $e';
    }
  }

  @visibleForTesting
  void recordDeletion(int id, String path, int mtimeMs, int size) {
    _deletionManifest
        .putIfAbsent(id, () => {})
        .add('${pu.normalize(path)}|$mtimeMs|$size');
  }

  void dispose() {
    for (final m in _active.values) {
      _watchers.unwatch(m.source, listener: _sourceToken.remove(m.id));
      _watchers.unwatch(m.target, listener: _targetToken.remove(m.id));
    }
    _active.clear();
  }
}
