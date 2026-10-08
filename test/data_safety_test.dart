/// Audit item 49: FileOpsService data-safety behaviour — same-folder copy
/// guard (item 1), overwrite backup + undo (item 4), zip extract undo scope
/// (item 3), move-onto-itself no-op and name validation (item 7).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nexus_file_manager/core/db/nexus_database.dart';
import 'package:nexus_file_manager/core/services/journal.dart';
import 'package:nexus_file_manager/core/services/ops_service.dart';
import 'package:nexus_file_manager/core/services/progress.dart';
import 'package:nexus_file_manager/core/utils/path_utils.dart' as pu;
import 'helpers.dart';

void main() {
  late DbService db;
  late OperationJournal journal;
  late FileOpsService ops;
  late Directory tmp;

  setUpAll(() => mockPathProvider(Directory.systemTemp));

  setUp(() async {
    db = DbService.openInMemory();
    journal = OperationJournal(db);
    ops = FileOpsService(journal, CancelRegistry(), () => const []);
    tmp = await Directory.systemTemp.createTemp('nexus_ops_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('copying a file onto itself lands a unique "(2)" copy instead', () async {
    final a = File('${tmp.path}/same.txt')..writeAsStringSync('original');
    final batch = journal.newBatch('copy');
    await ops.copyPaths([a.path], tmp.path, batchId: batch);

    final copies = tmp
        .listSync()
        .whereType<File>()
        .map((f) => pu.basename(f.path))
        .toList();
    expect(copies, containsAll(['same.txt', 'same (2).txt']));
    // The source must be untouched — never opened for writing.
    expect(File(a.path).readAsStringSync(), 'original');
    // The journal recorded exactly one copy entry.
    expect(journal.batchEntries(batch).length, 1);
  });

  test('moving a file onto itself is a no-op', () async {
    final a = File('${tmp.path}/self.txt')..writeAsStringSync('data');
    final batch = journal.newBatch('move');
    await ops.movePaths([a.path], tmp.path, batchId: batch);

    expect(a.existsSync(), isTrue);
    expect(a.readAsStringSync(), 'data');
    expect(tmp.listSync().whereType<File>().length, 1);
  });

  test('overwriting via rename plan preserves the old file in the journal',
      () async {
    final src = File('${tmp.path}/new.txt')..writeAsStringSync('NEW');
    final victim = File('${tmp.path}/existing.txt')
      ..writeAsStringSync('OLD');
    final batch = journal.newBatch('copy');

    await ops.copyPaths([src.path], tmp.path,
        batchId: batch, renamePlan: {src.path: victim.path});

    // The overwrite went through: content is replaced.
    expect(victim.readAsStringSync(), 'NEW');
    // And the previous file is restorable through Deep Undo.
    await journal.undoBatch(batch, onError: (msg) async => fail(msg));
    expect(victim.existsSync(), isTrue);
    expect(victim.readAsStringSync(), 'OLD');
    expect(src.existsSync(), isTrue);
  });

  test('zip extraction is undoable — only recorded entries are removed',
      () async {
    // Build a source zip with two entries at its root.
    final dir = Directory('${tmp.path}/payload')..createSync();
    File('${dir.path}/one.txt').writeAsStringSync('1');
    File('${dir.path}/two.txt').writeAsStringSync('2');
    final zipPath = '${tmp.path}/payload.zip';
    final zipBatch = journal.newBatch('compress');
    await ops.compressToZip([dir.path], zipPath, batchId: zipBatch);
    expect(File(zipPath).existsSync(), isTrue);

    // Extract into a clean destination (extractZip creates it).
    final destPath = '${tmp.path}/out';
    final batch = journal.newBatch('extract');
    await ops.extractZip(zipPath, destPath, batchId: batch);

    expect(File('$destPath/one.txt').existsSync(), isTrue);
    expect(File('$destPath/two.txt').existsSync(), isTrue);

    // Undo removes exactly what extraction created.
    await journal.undoBatch(batch, onError: (msg) async => fail(msg));
    expect(File('$destPath/one.txt').existsSync(), isFalse);
    expect(File('$destPath/two.txt').existsSync(), isFalse);
    // Source zip survives (the extraction journal entry was separate).
    expect(File(zipPath).existsSync(), isTrue);
  });

  test('moving a folder into its own descendant is rejected', () async {
    final parent = Directory('${tmp.path}/parent')..createSync();
    final child = Directory('${parent.path}/child')..createSync();
    final batch = journal.newBatch('move');
    expect(
      () => ops.movePaths([parent.path], child.path, batchId: batch),
      throwsA(isA<FileSystemException>()),
    );
    // Nothing moved.
    expect(parent.existsSync(), isTrue);
    expect(child.existsSync(), isTrue);
  });

  group('name validation (item 7)', () {
    test('rejects traversal and reserved names', () {
      expect(pu.validateName('ok.txt'), isNull);
      expect(pu.validateName(''), isNotNull);
      expect(pu.validateName('..'), isNotNull);
      expect(pu.validateName('a/b.txt'), isNotNull);
      expect(pu.validateName(r'a\b.txt'), isNotNull);
      expect(pu.validateName('CON'), isNotNull);
      expect(pu.validateName('com1.zip'), isNotNull);
      expect(pu.validateName('trailing.'), isNotNull);
      expect(pu.validateName('trailing '), isNotNull);
      expect(pu.validateName('nul\x00.txt'), isNotNull);
      expect(pu.validateName('a' * 300), isNotNull);
    });
  });
}
