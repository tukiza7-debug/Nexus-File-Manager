import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart' as ar;
import 'package:flutter/foundation.dart' show compute;

import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;
import '../utils/result.dart';
import 'fs_service.dart';
import 'journal.dart';
import 'progress.dart';

/// Central choke point for every mutating file operation:
/// freeze enforcement → conflict handling → execution → journal record →
/// progress broadcast. The UI and every automation feature call into this.
class FileOpsService {
  FileOpsService(this._journal, this._cancels, this._frozenRoots);

  final OperationJournal _journal;
  final CancelRegistry _cancels;
  final List<String> Function() _frozenRoots;
  final _progressCtrl = StreamController<OpProgress>.broadcast();

  Stream<OpProgress> get progress => _progressCtrl.stream;

  void report(OpProgress p) => _progressCtrl.add(p);

  void cancel(String batchId) => _cancels.cancel(batchId);

  bool cancelled(String batchId) => _cancels.isCancelled(batchId);

  void finish(String batchId) => _cancels.clear(batchId);

  // ── freeze enforcement ────────────────────────────────────────────────────
  void _checkFreeze(List<String> paths) {
    final frozen = _frozenRoots();
    for (final p in paths) {
      for (final root in frozen) {
        if (pu.isUnder(p, root)) throw FrozenException(p);
      }
    }
  }

  void checkFreeze(List<String> paths) => _checkFreeze(paths);

  // ── copy / move ───────────────────────────────────────────────────────────
  Future<void> copyPaths(
    List<String> sources,
    String destDir, {
    required String batchId,
    Map<String, String> renamePlan = const {}, // src → final destination path
    void Function(OpProgress)? onProgress,
  }) async {
    _checkFreeze(sources);
    final jobs = sources.map((s) => renamePlan[s] ?? pu.join(destDir, pu.basename(s))).toList();
    final bytesTotal = _totalBytes(sources);
    var bytesDone = 0;
    for (var i = 0; i < sources.length; i++) {
      if (cancelled(batchId)) {
        report(OpProgress(batchId: batchId, title: 'Copy', done: i, total: sources.length, phase: OpPhase.cancelled));
        throw const CancelledException();
      }
      final src = sources[i], dst = jobs[i];
      report(OpProgress(
          batchId: batchId, title: 'Copying ${pu.basename(src)}',
          done: i, total: sources.length, bytesDone: bytesDone, bytesTotal: bytesTotal));
      await _copyRecursive(src, dst, batchId, (n) {
        bytesDone += n;
      });
      _journal.record(batchId: batchId, op: JournalOp.copy, fromPath: src, toPath: dst, meta: 'copy');
    }
    report(OpProgress(batchId: batchId, title: 'Copy', done: sources.length, total: sources.length,
        bytesDone: bytesTotal, bytesTotal: bytesTotal, phase: OpPhase.done));
  }

  Future<void> movePaths(
    List<String> sources,
    String destDir, {
    required String batchId,
    Map<String, String> renamePlan = const {},
  }) async {
    _checkFreeze(sources);
    final jobs = sources.map((s) => renamePlan[s] ?? pu.join(destDir, pu.basename(s))).toList();
    var i = 0;
    for (final src in sources) {
      if (cancelled(batchId)) {
        report(OpProgress(batchId: batchId, title: 'Move', done: i, total: sources.length, phase: OpPhase.cancelled));
        throw const CancelledException();
      }
      final dst = jobs[i];
      report(OpProgress(batchId: batchId, title: 'Moving ${pu.basename(src)}', done: i, total: sources.length));
      Directory(pu.dirname(dst)).createSync(recursive: true);
      try {
        FileSystemEntity.typeSync(src) == FileSystemEntityType.directory
            ? Directory(src).renameSync(dst)
            : File(src).renameSync(dst);
      } on FileSystemException {
        // Cross-device rename → copy + delete fallback.
        await _copyRecursive(src, dst, batchId, (_) {});
        FileSystemEntity.typeSync(src) == FileSystemEntityType.directory
            ? Directory(src).deleteSync(recursive: true)
            : File(src).deleteSync();
      }
      _journal.record(batchId: batchId, op: JournalOp.move, fromPath: src, toPath: dst);
      i++;
    }
    report(OpProgress(batchId: batchId, title: 'Move', done: sources.length, total: sources.length, phase: OpPhase.done));
  }

  Future<void> rename(String oldPath, String newPath, {required String batchId}) async {
    _checkFreeze([oldPath]);
    if (oldPath == newPath) return;
    FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory
        ? Directory(oldPath).renameSync(newPath)
        : File(oldPath).renameSync(newPath);
    _journal.record(batchId: batchId, op: JournalOp.rename, fromPath: oldPath, toPath: newPath);
  }

  Future<void> mkdir(String path, {required String batchId}) async {
    _checkFreeze([pu.dirname(path)]);
    Directory(path).createSync(recursive: true);
    _journal.record(batchId: batchId, op: JournalOp.mkdir, fromPath: path, toPath: path);
  }

  /// Deletes to the journal trash (restorable via Deep Undo).
  Future<void> deletePaths(List<String> paths, {required String batchId}) async {
    _checkFreeze(paths);
    var i = 0;
    for (final p in paths) {
      if (cancelled(batchId)) throw const CancelledException();
      report(OpProgress(batchId: batchId, title: 'Deleting ${pu.basename(p)}', done: i, total: paths.length));
      await _journal.deleteWithBackup(p, batchId);
      i++;
    }
    report(OpProgress(batchId: batchId, title: 'Delete', done: paths.length, total: paths.length, phase: OpPhase.done));
  }

  /// Permanent delete (Shift+Del). Guarded by freeze; NOT undoable.
  Future<void> deletePermanent(List<String> paths, {required String batchId}) async {
    _checkFreeze(paths);
    var i = 0;
    for (final p in paths) {
      if (cancelled(batchId)) throw const CancelledException();
      report(OpProgress(batchId: batchId, title: 'Permanently deleting ${pu.basename(p)}', done: i, total: paths.length));
      final t = FileSystemEntity.typeSync(p);
      if (t == FileSystemEntityType.directory) {
        Directory(p).deleteSync(recursive: true);
      } else if (t != FileSystemEntityType.notFound) {
        File(p).deleteSync();
      }
      _journal.record(batchId: batchId, op: JournalOp.delete, fromPath: p, meta: 'permanent');
      i++;
    }
  }

  Future<void> writeBytes(String path, List<int> bytes, {required String batchId}) async {
    _checkFreeze([path]);
    Directory(pu.dirname(path)).createSync(recursive: true);
    final f = File(path);
    var existing = false;
    if (f.existsSync()) {
      existing = true;
      await _journal.deleteWithBackup(path, batchId); // keep a restorable copy
    }
    final raf = f.openSync(mode: FileMode.write);
    var written = 0;
    for (var off = 0; off < bytes.length; off += chunkSize) {
      if (cancelled(batchId)) {
        raf.closeSync();
        throw const CancelledException();
      }
      final end = (off + chunkSize).clamp(0, bytes.length);
      raf.writeFromSync(bytes, off, end);
      written = end;
      report(OpProgress(
          batchId: batchId, title: 'Writing ${pu.basename(path)}',
          done: written, total: bytes.length, bytesDone: written, bytesTotal: bytes.length));
      await yieldUi();
    }
    raf.flushSync();
    raf.closeSync();
    _journal.record(batchId: batchId, op: JournalOp.write, fromPath: path, toPath: path,
        meta: existing ? 'overwrite' : '${bytes.length}');
  }

  Future<void> writeText(String path, String text, {required String batchId}) =>
      writeBytes(path, const Utf8Encoder().convert(text), batchId: batchId);

  // ── compress ──────────────────────────────────────────────────────────────
  Future<String> compressToZip(List<String> sources, String zipPath, {required String batchId}) async {
    final encoder = ar.ZipFileEncoder();
    encoder.create(zipPath);
    var i = 0;
    for (final s in sources) {
      if (cancelled(batchId)) {
        await encoder.close();
        throw const CancelledException();
      }
      report(OpProgress(batchId: batchId, title: 'Compressing ${pu.basename(s)}', done: i, total: sources.length));
      final t = FileSystemEntity.typeSync(s);
      if (t == FileSystemEntityType.directory) {
        await encoder.addDirectory(Directory(s));
      } else if (t == FileSystemEntityType.file) {
        await encoder.addFile(File(s));
      }
      i++;
    }
    await encoder.close();
    _journal.record(batchId: batchId, op: JournalOp.write, fromPath: zipPath, toPath: zipPath);
    return zipPath;
  }

  Future<void> extractZip(String zipPath, String destDir, {required String batchId}) async {
    report(OpProgress(batchId: batchId, title: 'Extracting ${pu.basename(zipPath)}', done: 0, total: 1));
    await compute(_extractSync, (zipPath, destDir));
    _journal.record(batchId: batchId, op: JournalOp.write, fromPath: destDir, toPath: destDir);
    report(OpProgress(batchId: batchId, title: 'Extract', done: 1, total: 1, phase: OpPhase.done));
  }

  static void _extractSync((String, String) args) {
    final (zipPath, destDir) = args;
    final input = ar.InputFileStream(zipPath);
    final archive = ar.ZipDecoder().decodeBuffer(input);
    ar.extractArchiveToDisk(archive, destDir);
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  int _totalBytes(List<String> paths) {
    var total = 0;
    for (final p in paths) {
      final t = FileSystemEntity.typeSync(p);
      if (t == FileSystemEntityType.file) {
        total += File(p).lengthSync();
      } else if (t == FileSystemEntityType.directory) {
        total += FileSystemService.dirSizeSync(p);
      }
    }
    return total;
  }

  Future<void> _copyRecursive(String src, String dst, String batchId, void Function(int) onBytes) async {
    final t = FileSystemEntity.typeSync(src);
    if (t == FileSystemEntityType.directory) {
      Directory(dst).createSync(recursive: true);
      final children = Directory(src).listSync(followLinks: false);
      for (final c in children) {
        if (cancelled(batchId)) throw const CancelledException();
        await _copyRecursive(c.path, pu.join(dst, pu.basename(c.path)), batchId, onBytes);
      }
    } else if (t == FileSystemEntityType.file) {
      Directory(pu.dirname(dst)).createSync(recursive: true);
      final inRaf = File(src).openSync();
      final outRaf = File(dst).openSync(mode: FileMode.write);
      try {
        await copyFileChunked(inRaf, outRaf, onBytes, () => cancelled(batchId));
      } finally {
        inRaf.closeSync();
        outRaf.closeSync();
      }
    }
  }

  void dispose() => _progressCtrl.close();
}
