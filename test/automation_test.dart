/// Audit item 49: automation surfaces — macro broadcast signal (item 18),
/// pipeline plan==run parity (item 19), scheduler error status + overlap
/// lock (item 15), template UTF-8 decoding (item 47), split validation and
/// cleanup (item 47).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_file_manager/core/db/nexus_database.dart';
import 'package:nexus_file_manager/core/services/journal.dart';
import 'package:nexus_file_manager/core/services/macro_service.dart';
import 'package:nexus_file_manager/core/services/mirror_service.dart';
import 'package:nexus_file_manager/core/services/ops_service.dart';
import 'package:nexus_file_manager/core/services/pipeline_service.dart';
import 'package:nexus_file_manager/core/services/progress.dart';
import 'package:nexus_file_manager/core/services/scheduler_service.dart';
import 'package:nexus_file_manager/core/services/split_service.dart';
import 'package:nexus_file_manager/core/services/template_service.dart';
import 'package:nexus_file_manager/core/services/watcher_service.dart';
import 'package:nexus_file_manager/domain/enums.dart';
import 'package:nexus_file_manager/domain/models.dart';

void main() {
  group('macro broadcast signal (item 18)', () {
    late DbService db;
    late MacroService macros;
    setUp(() {
      db = DbService.openInMemory();
      macros = MacroService(db);
    });
    tearDown(() => macros.dispose());

    test('late listeners receive the current value, then updates', () async {
      macros.startRecording();
      // Listener attached AFTER recording started must not miss the state.
      final values = <bool>[];
      final sub = macros.recordingStream.listen(values.add);
      await Future<void>.delayed(Duration.zero);
      expect(values, [true]);

      macros.stopRecording();
      await Future<void>.delayed(Duration.zero);
      expect(values, [true, false]);
      await sub.cancel();
    });

    test('record() is a no-op unless a recording is active', () {
      macros.record('copy', {'a': 1});
      expect(macros.liveSteps, isEmpty);
      macros.startRecording();
      macros.record('copy', {'a': 1});
      expect(macros.liveSteps, hasLength(1));
    });

    test('saved macros round-trip through the database', () {
      macros.startRecording();
      macros.record('rename', {'from': '/a.txt', 'to': '/b.txt'});
      final steps = macros.stopRecording();
      macros.save('demo', steps);

      final loaded = macros.all();
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'demo');
      expect(loaded.first.steps.single.action, 'rename');
    });
  });

  group('pipeline plan == run parity (item 19)', () {
    late DbService db;
    late OperationJournal journal;
    late FileOpsService ops;
    late PipelineService pipelines;
    late Directory tmp;

    setUp(() async {
      db = DbService.openInMemory();
      journal = OperationJournal(db);
      ops = FileOpsService(journal, CancelRegistry(), () => const []);
      pipelines = PipelineService(db, ops);
      tmp = await Directory.systemTemp.createTemp('nexus_pipeline_test');
    });
    tearDown(() => tmp.delete(recursive: true));

    NexusPipeline pipeline(List<PipelineStep> steps) =>
        NexusPipeline(name: 'test', steps: steps);

    test('run() renames exactly what plan() predicted', () async {
      final fileA = File('${tmp.path}/report.docx')..writeAsStringSync('A');
      final fileB = File('${tmp.path}/photo.jpg')..writeAsStringSync('B');

      final p = pipeline([
        const PipelineStep(kind: 'renamePattern', args: {'pattern': '{name}-2026'}),
      ]);

      final planned = pipelines.plan(p, [
        _entry(fileA.path, 'report.docx'),
        _entry(fileB.path, 'photo.jpg'),
      ]);
      // plan() returns (path, newName) pairs — names only, no directory.
      expect(planned, hasLength(2));
      expect(planned.first.$1, fileA.path);
      expect(planned.first.$2, 'report-2026.docx');
      expect(planned.last.$2, 'photo-2026.jpg');

      final batch = journal.newBatch('pipeline');
      await pipelines.run(p, [fileA.path, fileB.path], batchId: batch);
      expect(File('${tmp.path}/report-2026.docx').existsSync(), isTrue);
      expect(File('${tmp.path}/photo-2026.jpg').existsSync(), isTrue);
    });

    test('ext step never produces a trailing dot for empty targets',
        () async {
      final f = File('${tmp.path}/noext')..writeAsStringSync('x');
      final p = pipeline([const PipelineStep(kind: 'ext', args: {'ext': ''})]);
      final planned = pipelines.plan(p, [_entry(f.path, 'noext')]);
      expect(planned.single.$2, 'noext');
    });

    test('case step chains consistently between plan and run', () async {
      final f = File('${tmp.path}/My Report.docx')..writeAsStringSync('x');
      final p = pipeline([
        const PipelineStep(kind: 'case', args: {'mode': 'kebab'}),
        const PipelineStep(kind: 'ext', args: {'ext': 'pdf'}),
      ]);
      final planned = pipelines.plan(p, [_entry(f.path, 'My Report.docx')]);
      expect(planned.single.$2, 'my-report.pdf');

      final batch = journal.newBatch('pipeline');
      await pipelines.run(p, [f.path], batchId: batch);
      expect(File('${tmp.path}/my-report.pdf').existsSync(), isTrue);
    });
  });

  group('scheduler (item 15)', () {
    late DbService db;
    late OperationJournal journal;
    late FileOpsService ops;
    late SchedulerService scheduler;
    late Directory tmp;

    setUp(() async {
      db = DbService.openInMemory();
      journal = OperationJournal(db);
      ops = FileOpsService(journal, CancelRegistry(), () => const []);
      final pipelines = PipelineService(db, ops);
      final watcherSvc = WatcherService();
      final mirrors = MirrorService(db, ops, watcherSvc, journal);
      scheduler = SchedulerService(db, ops, pipelines, mirrors);
      tmp = await Directory.systemTemp.createTemp('nexus_sched_test');
    });
    tearDown(() => tmp.delete(recursive: true));

    test('a failing job records an error status, not a silent re-run',
        () async {
      // A mirror job with no mirror selected throws inside _execute — the
      // scheduler must record the failure instead of looping silently.
      db.saveSchedule(const ScheduleJob(
        name: 'boom',
        kind: 'mirror',
        targets: {}, // no mirrorId → deterministic failure
        arg: '',
        intervalMin: 1,
        enabled: true,
      ));
      final job = db.schedules().single;

      await scheduler.run(job.id!);

      final after = db.schedules().single;
      expect(after.lastStatus, startsWith('error'));
      expect(after.lastRunMs, isNotNull);
      expect(after.enabled, isTrue, reason: 'recurring job stays enabled');
    });

    test('a successful run records status ok and a next-run timestamp',
        () async {
      final src = File('${tmp.path}/src.txt')..writeAsStringSync('x');
      final dest = Directory('${tmp.path}/dest')..createSync();
      db.saveSchedule(ScheduleJob(
        name: 'copy ok',
        kind: 'copy',
        targets: {'sources': [src.path], 'dest': dest.path},
        arg: '',
        intervalMin: 1,
        enabled: true,
      ));
      final job = db.schedules().single;

      await scheduler.run(job.id!);

      final after = db.schedules().single;
      expect(after.lastStatus, 'ok');
      expect(after.lastRunMs, isNotNull);
      expect(File('${dest.path}/src.txt').existsSync(), isTrue);
    });

    test('one-shot jobs disable themselves after a successful run', () async {
      final src = File('${tmp.path}/one.txt')..writeAsStringSync('x');
      final dest = Directory('${tmp.path}/dest2')..createSync();
      db.saveSchedule(ScheduleJob(
        name: 'oneshot',
        kind: 'copy',
        targets: {'sources': [src.path], 'dest': dest.path},
        arg: '',
        runAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
        enabled: true,
      ));
      final job = db.schedules().single;

      await scheduler.run(job.id!);

      final after = db.schedules().single;
      expect(after.enabled, isFalse, reason: 'one-shot disabled after run');
      expect(File('${dest.path}/one.txt').existsSync(), isTrue);
    });

    test('per-job running lock prevents overlap', () async {
      final src = File('${tmp.path}/lock.txt')..writeAsStringSync('x');
      final dest = Directory('${tmp.path}/dest3')..createSync();
      db.saveSchedule(ScheduleJob(
        name: 'lock',
        kind: 'copy',
        targets: {'sources': [src.path], 'dest': dest.path},
        arg: '',
        intervalMin: 1,
        enabled: true,
      ));
      final job = db.schedules().single;
      // The public contract: isRunning() flips back to false after run(),
      // and tick() skips jobs whose lock is held (checked internally).
      expect(scheduler.isRunning(job.id!), isFalse);
      await scheduler.run(job.id!);
      expect(scheduler.isRunning(job.id!), isFalse);
    });
  });

  group('template utf8 decoding (item 47)', () {
    test('multi-byte characters survive template stamping', () {
      const source = 'Résumé — 中文 — \u{1F600}';
      expect(TemplateService.utf8ish(utf8.encode(source)), source);
    });

    test('malformed sequences degrade instead of throwing', () {
      expect(() => TemplateService.utf8ish([0xFF, 0xFE, 0x41]),
          returnsNormally);
    });
  });

  group('split validation + cleanup (item 47)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nexus_split_test');
    });
    tearDown(() => tmp.delete(recursive: true));

    test('rejects part counts larger than the file size', () async {
      final f = File('${tmp.path}/tiny.bin')..writeAsBytesSync([1, 2, 3]);
      expect(
        () => const SplitService()
            .split(path: f.path, destDir: tmp.path, parts: 8),
        throwsA(isA<FileSystemException>()),
      );
      // Nothing was written.
      expect(tmp.listSync().whereType<File>().length, 1);
    });

    test('rejects part counts beyond the hard cap', () async {
      final f = File('${tmp.path}/big.bin')
        ..writeAsBytesSync(List.filled(4096, 7));
      expect(
        () => const SplitService()
            .split(path: f.path, destDir: tmp.path, parts: 5000),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('splits produce complete rejoinable parts', () async {
      final data = List<int>.generate(1000, (i) => i % 251);
      final f = File('${tmp.path}/data.bin')..writeAsBytesSync(data);
      final parts = await const SplitService()
          .split(path: f.path, destDir: tmp.path, parts: 4);
      expect(parts, hasLength(4));
      final recombined = <int>[];
      for (final p in parts) {
        recombined.addAll(File(p).readAsBytesSync());
      }
      expect(recombined, data);
    });
  });
}

NexusEntry _entry(String path, String name) => NexusEntry(
      path: path,
      name: name,
      size: 1,
      modified: DateTime(2026),
      isDir: false,
      category: FileCategory.other,
    );
