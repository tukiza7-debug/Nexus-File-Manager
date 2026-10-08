/// Audit item 49: service-layer tests for the OperationJournal — undo,
/// redo, batch invalidation and per-step error handling — running against
/// a real in-memory SQLite database and real temp files.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nexus_file_manager/core/db/nexus_database.dart';
import 'package:nexus_file_manager/core/services/journal.dart';
import 'package:nexus_file_manager/domain/models.dart';
import 'helpers.dart';

void main() {
  late DbService db;
  late OperationJournal journal;
  late Directory tmp;

  setUpAll(() => mockPathProvider(Directory.systemTemp));

  setUp(() async {
    db = DbService.openInMemory();
    journal = OperationJournal(db);
    tmp = await Directory.systemTemp.createTemp('nexus_journal_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  String file(String name, [String content = 'hello']) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return f.path;
  }

  group('journal undo/redo', () {
    test('undo restores a renamed file to its original name', () async {
      final a = file('a.txt');
      final b = '${tmp.path}/b.txt';
      File(a).renameSync(b);
      journal.record(
          batchId: 't1', op: JournalOp.rename, fromPath: a, toPath: b);

      final batch = journal.nextUndoBatch();
      expect(batch, 't1');
      final desc = await journal.undoBatch(batch!,
          onError: (msg) async => fail('undo should not error: $msg'));
      expect(desc, contains('1'));
      expect(File(a).existsSync(), isTrue);
      expect(File(b).existsSync(), isFalse);
      // It is now redoable.
      expect(journal.nextRedoBatch(), 't1');
      expect(journal.nextUndoBatch(), isNull);
    });

    test('redo re-applies the undone rename', () async {
      final a = file('a.txt');
      final b = '${tmp.path}/b.txt';
      File(a).renameSync(b);
      journal.record(
          batchId: 't1', op: JournalOp.rename, fromPath: a, toPath: b);
      await journal.undoBatch('t1',
          onError: (msg) async => fail('undo should not error: $msg'));

      await journal.redoBatch('t1',
          onError: (msg) async => fail('redo should not error: $msg'));
      expect(File(a).existsSync(), isFalse);
      expect(File(b).existsSync(), isTrue);
      // Redoing makes it undoable again.
      expect(journal.nextUndoBatch(), 't1');
      expect(journal.nextRedoBatch(), isNull);
    });

    test('undoing a copy deletes the copy but keeps the source', () async {
      final a = file('a.txt');
      final b = '${tmp.path}/a copy.txt';
      await File(a).copy(b);
      journal.record(
          batchId: 't2', op: JournalOp.copy, fromPath: a, toPath: b);

      await journal.undoBatch('t2',
          onError: (msg) async => fail('undo should not error: $msg'));
      expect(File(a).existsSync(), isTrue);
      expect(File(b).existsSync(), isFalse);
    });

    test('a new batch invalidates the redo stack', () async {
      final a = file('a.txt');
      final b = '${tmp.path}/b.txt';
      File(a).renameSync(b);
      journal.record(
          batchId: 't1', op: JournalOp.rename, fromPath: a, toPath: b);
      await journal.undoBatch('t1',
          onError: (msg) async => fail('undo should not error: $msg'));
      expect(journal.nextRedoBatch(), 't1');

      // Recording a fresh batch discards every redoable entry.
      journal.newBatch('fresh-work');
      expect(journal.nextRedoBatch(), isNull);
    });

    test('undo reports per-step failures without throwing the whole batch',
        () async {
      final a = file('a.txt');
      final b = '${tmp.path}/b.txt';
      File(a).renameSync(b);
      journal.record(
          batchId: 't3', op: JournalOp.rename, fromPath: a, toPath: b);
      // Sabotage: occupy the original slot behind the journal's back so the
      // move-back cannot proceed — the journal must report it via onError
      // instead of throwing or failing silently.
      File(a).writeAsStringSync('blocker');

      final errors = <String>[];
      await journal.undoBatch('t3', onError: (msg) async => errors.add(msg));
      expect(errors, isNotEmpty);
    });
  });

  group('journal persistence', () {
    test('batches survive across journal instances on the same db', () async {
      final a = file('a.txt');
      journal.record(
          batchId: 'p1', op: JournalOp.delete, fromPath: a, meta: 'trash');
      final again = OperationJournal(db);
      expect(again.nextUndoBatch(), 'p1');
    });
  });
}
