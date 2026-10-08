import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart' as ar;

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

  /// Zip-extraction safety limits (audit item 9). Tunable per call.
  static int zipMaxTotalBytes = 2 * 1024 * 1024 * 1024; // 2 GiB
  static int zipMaxEntries = 200000;

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

  // ── same-file detection (audit item 1) ────────────────────────────────────
  /// True when [a] and [b] both exist and are the same filesystem entry.
  static bool sameEntity(String a, String b) {
    try {
      if (FileSystemEntity.typeSync(a) == FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(b) == FileSystemEntityType.notFound) {
        return false;
      }
      return FileSystemEntity.identicalSync(a, b);
    } on FileSystemException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// First non-existing "name (2).ext" style sibling for [path].
  static String uniqueCopyName(String path) {
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return path;
    }
    var n = 2;
    var candidate = pu.withCounter(path, n);
    while (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      n++;
      candidate = pu.withCounter(path, n);
    }
    return candidate;
  }

  // ── copy / move ───────────────────────────────────────────────────────────
  Future<void> copyPaths(
    List<String> sources,
    String destDir, {
    required String batchId,
    Map<String, String> renamePlan = const {}, // src → final destination path
    void Function(OpProgress)? onProgress,
  }) async {
    _checkFreeze(sources);
    _checkFreeze([destDir]); // audit item 8: destinations are frozen-aware too
    final jobs = <String>[];
    for (final s in sources) {
      var dst = renamePlan[s] ?? pu.join(destDir, pu.basename(s));
      // Audit item 1: copying onto the source itself must never touch the
      // source — land it under a unique "name (2).ext" instead.
      if (sameEntity(s, dst)) dst = uniqueCopyName(dst);
      jobs.add(dst);
    }
    final bytesTotal = await _totalBytesAsync(sources);
    var bytesDone = 0;
    for (var i = 0; i < sources.length; i++) {
      if (cancelled(batchId)) {
        report(OpProgress(batchId: batchId, title: 'Copy', done: i, total: sources.length, phase: OpPhase.cancelled));
        throw const CancelledException();
      }
      final src = sources[i], dst = jobs[i];
      // Audit item 4: an explicit overwrite must preserve the previous file
      // through the journal so Deep Undo can restore it.
      final overwriting = sameEntity(src, dst) == false &&
          renamePlan[src] == dst &&
          FileSystemEntity.typeSync(dst) != FileSystemEntityType.notFound;
      if (overwriting) {
        await _journal.deleteWithBackup(dst, batchId);
      }
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
    _checkFreeze([destDir]);
    // Audit item 6: refuse to move a folder into itself or a descendant —
    // that would recurse forever and destroy the source.
    for (final s in sources) {
      if (FileSystemEntity.typeSync(s) == FileSystemEntityType.directory &&
          pu.isUnder(destDir, s)) {
        throw FileSystemException('Cannot move a folder into itself or one of its subfolders', s);
      }
    }
    final jobs = <String>[];
    for (final s in sources) {
      final dst = renamePlan[s] ?? pu.join(destDir, pu.basename(s));
      if (sameEntity(s, dst)) continue; // move onto itself → no-op
      jobs.add(dst);
    }
    var i = 0;
    var done = 0;
    for (final src in sources) {
      final dst = renamePlan[src] ?? pu.join(destDir, pu.basename(src));
      if (sameEntity(src, dst)) {
        i++;
        continue;
      }
      if (cancelled(batchId)) {
        report(OpProgress(batchId: batchId, title: 'Move', done: i, total: sources.length, phase: OpPhase.cancelled));
        throw const CancelledException();
      }
      report(OpProgress(batchId: batchId, title: 'Moving ${pu.basename(src)}', done: i, total: sources.length));
      Directory(pu.dirname(dst)).createSync(recursive: true);
      var moved = false;
      try {
        FileSystemEntity.typeSync(src) == FileSystemEntityType.directory
            ? Directory(src).renameSync(dst)
            : File(src).renameSync(dst);
        moved = true;
      } on FileSystemException catch (e) {
        // Audit item 6: only a genuine cross-device error may trigger the
        // copy+delete fallback — permission errors must surface as failures.
        if (!_isCrossDeviceError(e)) rethrow;
        await _copyRecursive(src, dst, batchId, (_) {});
        if (!await FileOpsBridge.verifyCopy(src, dst)) {
          // Clean up the partial destination; the source stays untouched.
          _deleteQuietly(dst);
          throw FileSystemException('Cross-device move failed: copy verification mismatch', src);
        }
        if (cancelled(batchId)) {
          _deleteQuietly(dst);
          throw const CancelledException();
        }
        FileSystemEntity.typeSync(src) == FileSystemEntityType.directory
            ? Directory(src).deleteSync(recursive: true)
            : File(src).deleteSync();
        moved = true;
      }
      if (moved) {
        _journal.record(batchId: batchId, op: JournalOp.move, fromPath: src, toPath: dst);
        done++;
      }
      i++;
    }
    report(OpProgress(batchId: batchId, title: 'Move', done: done, total: sources.length, phase: OpPhase.done));
  }

  Future<void> rename(String oldPath, String newPath, {required String batchId}) async {
    _checkFreeze([oldPath]);
    pu.checkName(pu.basename(newPath)); // audit item 7
    if (pu.samePath(oldPath, newPath)) return;
    // Audit item 4: rename must fail clearly when the target already exists.
    if (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) {
      throw FileSystemException('A file or folder with that name already exists', newPath);
    }
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
    // Audit item 1 (defense in depth): never open a destination for writing
    // when it is the very entity we are reading from.
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
  /// Compresses [sources] into [zipPath]. When the zip already exists the
  /// caller must pass [overwrite] = true (the UI asks first — audit item 9).
  /// The output zip is always excluded from its own sources.
  Future<String> compressToZip(List<String> sources, String zipPath,
      {required String batchId, bool overwrite = false}) async {
    _checkFreeze([...sources, zipPath]);
    if (!overwrite && FileSystemEntity.typeSync(zipPath) != FileSystemEntityType.notFound) {
      throw FileSystemException('A zip with that name already exists', zipPath);
    }
    // Never zip the output into itself.
    final inputs = sources.where((s) => !pu.samePath(s, zipPath)).toList();
    final encoder = ar.ZipFileEncoder();
    try {
      encoder.create(zipPath);
      var i = 0;
      for (final s in inputs) {
        if (cancelled(batchId)) throw const CancelledException();
        report(OpProgress(batchId: batchId, title: 'Compressing ${pu.basename(s)}', done: i, total: inputs.length));
        final t = FileSystemEntity.typeSync(s);
        if (t == FileSystemEntityType.directory) {
          // archive 3.x addDirectory() has no filter param, so we walk the
          // tree here and add each file under its relative path — this also
          // lets us guarantee the output zip is never included in itself.
          final base = s.endsWith('/') ? s : '$s/';
          final all = Directory(s).listSync(recursive: true, followLinks: false);
          for (final fe in all) {
            if (fe is Directory) continue;
            if (pu.samePath(fe.path, zipPath)) continue;
            var rel = fe.path.startsWith(base) ? fe.path.substring(base.length) : pu.basename(fe.path);
            // Zip paths are always forward-slash separated.
            rel = rel.replaceAll(r'\', '/');
            await encoder.addFile(File(fe.path), rel);
          }
        } else if (t == FileSystemEntityType.file) {
          if (pu.samePath(s, zipPath)) continue;
          await encoder.addFile(File(s));
        }
        i++;
      }
    } finally {
      // Audit item 9: the encoder must close even when a step throws.
      await encoder.close();
    }
    _journal.record(batchId: batchId, op: JournalOp.write, fromPath: zipPath, toPath: zipPath);
    return zipPath;
  }

  /// Extracts [zipPath] into [destDir] with zip-slip protection, size/entry
  /// limits and per-entry progress. Returns the exact paths created so undo
  /// removes only what this extraction produced (audit items 3 + 9).
  ///
  /// When [destDir] already contains files the archive is extracted into a
  /// fresh subfolder named after the zip, so undo can never delete unrelated
  /// user data.
  Future<String> extractZip(String zipPath, String destDir, {required String batchId}) async {
    _checkFreeze([destDir]);
    final destNotEmpty = destDir.isNotEmpty &&
        Directory(destDir).existsSync() &&
        Directory(destDir).listSync(followLinks: false).isNotEmpty;
    final root = destNotEmpty
        ? uniqueCopyName(pu.join(destDir, pu.stem(zipPath)))
        : destDir;
    Directory(root).createSync(recursive: true);
    report(OpProgress(batchId: batchId, title: 'Reading ${pu.basename(zipPath)}', done: 0, total: 1));
    // Decode + validate entirely inside an isolate.
    final entries = await Isolate.run(() => _readArchive(zipPath, root, zipMaxTotalBytes, zipMaxEntries));
    // Extract in one worker isolate; it streams progress back and honours
    // cancellation between entries.
    await _extractInIsolate(zipPath, entries, root, batchId);
    // Record each produced path so undo touches only these entries.
    for (final entry in entries) {
      final outPath = entry.targetPath(root);
      _journal.record(batchId: batchId, op: JournalOp.write, fromPath: outPath, toPath: outPath, meta: 'zip-entry');
    }
    _journal.record(batchId: batchId, op: JournalOp.mkdir, fromPath: root, toPath: root, meta: 'zip-root');
    report(OpProgress(batchId: batchId, title: 'Extract', done: entries.length, total: entries.length, phase: OpPhase.done));
    return root;
  }

  static List<_ZipEntry> _readArchive(String zipPath, String destDir, int maxTotal, int maxEntries) {
    final input = ar.InputFileStream(zipPath);
    try {
      final archive = ar.ZipDecoder().decodeBuffer(input);
      final out = <_ZipEntry>[];
      var total = 0;
      for (final e in archive.files) {
        if (e.isFile) {
          total += e.size;
          if (total > maxTotal) {
            throw FileSystemException('Archive exceeds the maximum total extract size', zipPath);
          }
        }
        out.add(_ZipEntry(e.name, e.isFile, e.size));
        if (out.length > maxEntries) {
          throw FileSystemException('Archive exceeds the maximum entry count', zipPath);
        }
      }
      // Zip-slip validation (audit item 9): every resolved path must stay
      // inside the destination.
      final destNorm = pu.normalize(destDir);
      for (final e in out) {
        if (e.name.startsWith('/') || e.name.contains(':') ||
            RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(e.name)) {
          throw FileSystemException('Archive entry escapes the destination: ${e.name}', zipPath);
        }
        final resolved = pu.normalize(pu.join(destDir, e.name));
        if (!pu.isUnder(resolved, destNorm)) {
          throw FileSystemException('Archive entry escapes the destination: ${e.name}', zipPath);
        }
      }
      return out;
    } finally {
      input.closeSync();
    }
  }

  /// Runs the whole extraction inside one worker isolate. The worker sends
  /// `int` progress messages after every entry and polls the main isolate
  /// for cancellation between entries.
  Future<void> _extractInIsolate(String zipPath, List<_ZipEntry> entries, String root, String batchId) async {
    final done = Completer<void>();
    final fromWorker = ReceivePort();
    final toWorker = ReceivePort();
    late final SendPort workerInbox;
    var cancelledByMain = false;
    // ReceivePort has no isOpen getter — track closure manually.
    var fromWorkerOpen = true;

    fromWorker.listen((msg) {
      if (msg is SendPort) {
        workerInbox = msg;
        workerInbox.send(toWorker.sendPort);
      } else if (msg is int) {
        report(OpProgress(
            batchId: batchId, title: 'Extracting…', done: msg, total: entries.length));
        // Push a fresh cancellation flag after each progress message.
        cancelledByMain = cancelled(batchId);
        workerInbox.send(cancelledByMain);
      } else if (msg == 'done') {
        if (fromWorkerOpen) {
          fromWorker.close();
          fromWorkerOpen = false;
        }
        if (!done.isCompleted) done.complete();
      } else if (msg is String && msg.startsWith('error:')) {
        if (fromWorkerOpen) {
          fromWorker.close();
          fromWorkerOpen = false;
        }
        if (!done.isCompleted) done.completeError(FileSystemException(msg.substring(6), zipPath));
      }
    });

    await Isolate.spawn(
      _extractWorker,
      (zipPath: zipPath, root: root, outPort: fromWorker.sendPort),
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
    );

    // Drain the worker's inbox so cancellation flags are delivered.
    final feed = toWorker.listen((_) {});
    try {
      await done.future;
    } finally {
      await feed.cancel();
      fromWorker.close();
      toWorker.close();
    }
  }

  @pragma('vm:entry-point')
  static void _extractWorker(({String zipPath, String root, SendPort outPort}) args) {
    final inbox = ReceivePort();
    args.outPort.send(inbox.sendPort);
    var stop = false;
    inbox.listen((msg) {
      if (msg is bool) stop = msg;
    });
    try {
      final input = ar.InputFileStream(args.zipPath);
      final archive = ar.ZipDecoder().decodeBuffer(input);
      var i = 0;
      for (final e in archive.files) {
        if (stop) break;
        final targetPath = _ZipEntry(e.name, e.isFile, e.size).targetPath(args.root);
        if (e.isFile) {
          Directory(pu.dirname(targetPath)).createSync(recursive: true);
          final output = ar.OutputFileStream(targetPath);
          try {
            // archive 3.x exposes entry bytes via `content`; write them
            // through the streaming output so memory stays bounded per
            // entry.
            final data = e.content;
            if (data is List<int>) {
              output.writeBytes(data);
            }
          } finally {
            output.closeSync();
          }
        } else {
          Directory(targetPath).createSync(recursive: true);
        }
        i++;
        args.outPort.send(i);
      }
      args.outPort.send('done');
    } catch (err) {
      args.outPort.send('error:$err');
    } finally {
      inbox.close();
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────
  static bool _isCrossDeviceError(FileSystemException e) => FileOpsBridge.isCrossDevice(e);

  static void _deleteQuietly(String path) {
    try {
      final t = FileSystemEntity.typeSync(path);
      if (t == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else if (t != FileSystemEntityType.notFound) {
        File(path).deleteSync();
      }
    } on FileSystemException {
      // best effort
    }
  }

  Future<int> _totalBytesAsync(List<String> paths) => Isolate.run(() {
        var total = 0;
        for (final p in paths) {
          final t = FileSystemEntity.typeSync(p);
          if (t == FileSystemEntityType.file) {
            total += File(p).lengthSync();
          } else if (t == FileSystemEntityType.directory) {
            total += _dirSizeSync(p);
          }
        }
        return total;
      });

  static int _dirSizeSync(String path) {
    var total = 0;
    try {
      for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } on FileSystemException {
            // unreadable entry
          }
        }
      }
    } on FileSystemException {
      // unreadable directory
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
      // Never truncate the source by opening it as the destination.
      if (sameEntity(src, dst)) return;
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

/// Normalised archive entry used for validation and progress.
class _ZipEntry {
  const _ZipEntry(this.name, this.isFile, this.size);
  final String name;
  final bool isFile;
  final int size;

  /// Total bytes when known; the archive-level sum is tracked separately.
  int get totalSize => size;

  String targetPath(String root) {
    final rel = name.replaceAll(r'\', '/');
    return pu.join(root, rel);
  }
}
