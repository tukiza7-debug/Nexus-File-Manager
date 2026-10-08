import 'dart:io';

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

  String newBatch(String label) => '${DateTime.now().millisecondsSinceEpoch}-${label.hashCode.abs()}';

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
  }

  /// True when [path] was touched by Nexus itself very recently — used to
  /// suppress watcher echo loops (mirrors, auto-versioning).
  bool wasSelfOp(String path) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - selfOpWindowMs;
    final rows = _db.journal(query: path, limit: 50);
    for (final e in rows) {
      if (e.createdAtMs >= cutoff &&
          (e.fromPath == path ||
              e.toPath == path ||
              pu.isUnder(path, e.fromPath) ||
              (e.toPath != null && pu.isUnder(path, e.toPath!)))) {
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
      if (e.undone) continue;
      return e.batchId;
    }
    return null;
  }

  /// Next redoable batch (oldest undone, in chronological order).
  String? nextRedoBatch() {
    final rows = _db.journal(limit: 500).reversed.toList();
    for (final e in rows) {
      if (e.undone) return e.batchId;
    }
    return null;
  }

  /// Executes the inverse of every entry in [batchId]. Returns a human label.
  Future<String> undoBatch(String batchId, {required Future<void> Function(String msg) onError}) async {
    final entries = _db.batch(batchId).reversed.toList(); // LIFO
    var done = 0;
    for (final e in entries) {
      if (e.undone) continue;
      try {
        await _invert(e);
        _db.setJournalUndone(e.id!, true);
        done++;
      } on FileSystemException catch (ex) {
        await onError('Undo step failed: ${ex.message}');
      }
    }
    return 'Undid $done change(s)';
  }

  /// Re-applies a previously undone batch in original order.
  Future<String> redoBatch(String batchId, {required Future<void> Function(String msg) onError}) async {
    final entries = _db.batch(batchId);
    var done = 0;
    for (final e in entries) {
      if (!e.undone) continue;
      try {
        await _reapply(e);
        _db.setJournalUndone(e.id!, false);
        done++;
      } on FileSystemException catch (ex) {
        await onError('Redo step failed: ${ex.message}');
      }
    }
    return 'Redid $done change(s)';
  }

  Future<void> _invert(JournalEntry e) async {
    switch (e.op) {
      case JournalOp.copy:
      case JournalOp.write:
      case JournalOp.mkdir:
        // Created something → delete it.
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
        // Moved/renamed → move back.
        final t = e.toPath;
        if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
          File(t).renameSync(e.fromPath);
        }
      case JournalOp.delete:
        // Deleted → restore from backup recorded in meta.
        final backup = e.meta;
        if (backup != null && FileSystemEntity.typeSync(backup) != FileSystemEntityType.notFound) {
          Directory(pu.dirname(e.fromPath)).createSync(recursive: true);
          File(backup).renameSync(e.fromPath);
        }
      case JournalOp.restore:
        final t = e.toPath;
        if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
          File(t).renameSync(e.fromPath);
        }
      case JournalOp.metadata:
      case JournalOp.split:
      case JournalOp.merge:
        // Outputs were recorded as write entries with individual paths.
        final t = e.toPath;
        if (t != null && FileSystemEntity.typeSync(t) != FileSystemEntityType.notFound) {
          File(t).deleteSync();
        }
    }
  }

  Future<void> _reapply(JournalEntry e) async {
    switch (e.op) {
      case JournalOp.copy:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          final dest = e.toPath;
          if (dest != null) {
            await _copyRecursive(e.fromPath, dest);
          }
        }
      case JournalOp.move:
      case JournalOp.rename:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          final t = e.toPath;
          if (t != null) File(e.fromPath).renameSync(t);
        }
      case JournalOp.delete:
        if (FileSystemEntity.typeSync(e.fromPath) != FileSystemEntityType.notFound) {
          await _deleteToBackup(e.fromPath, e.batchId);
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

  static Future<String> _deleteToBackup(String path, String batchId) async {
    final store = await nexusDataDir();
    final trashDir = Directory(pu.join(pu.join(store.path, 'trash'), batchId));
    trashDir.createSync(recursive: true);
    final dest = pu.join(trashDir.path, pu.basename(path));
    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
        ? Directory(path).renameSync(dest)
        : File(path).renameSync(dest);
    return dest;
  }

  /// Public helper used by the ops service: moves a path into the journal
  /// trash and records the deletion (restorable).
  Future<String> deleteWithBackup(String path, String batchId) async {
    final backup = await _deleteToBackup(path, batchId);
    record(batchId: batchId, op: JournalOp.delete, fromPath: path, toPath: backup, meta: backup);
    return backup;
  }

  static String describe(String batchId, List<JournalEntry> entries) {
    if (entries.isEmpty) return 'nothing';
    final ops = entries.map((e) => e.op.name).toSet();
    final when = formatDateTime(DateTime.fromMillisecondsSinceEpoch(entries.first.createdAtMs));
    return '${ops.join('/')} · ${entries.length} · $when';
  }
}
