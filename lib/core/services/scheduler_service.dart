import 'dart:async';
import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'fs_service.dart';
import 'mirror_service.dart';
import 'ops_service.dart';
import 'pipeline_service.dart';

/// Scheduled Actions: runs copy/move/delete/compress/pipeline jobs either
/// once at a specific time or on an interval while the app is open.
class SchedulerService {
  SchedulerService(this._db, this._ops, this._pipelines, this._mirrors);

  final DbService _db;
  final FileOpsService _ops;
  final PipelineService _pipelines;
  final MirrorService _mirrors;

  Timer? _timer;
  final _events = StreamController<ScheduleEvent>.broadcast();
  Stream<ScheduleEvent> get events => _events.stream;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => tick());
    tick();
  }

  void stop() => _timer?.cancel();

  Future<void> tick() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final job in _db.schedules()) {
      if (!job.enabled) continue;
      final due = job.intervalMin != null
          ? (job.lastRunMs == null ||
              now - job.lastRunMs! >= job.intervalMin! * 60 * 1000)
          : job.runAtMs != null && job.runAtMs! <= now;
      if (!due) continue;
      await run(job.id!);
    }
  }

  Future<void> run(int id) async {
    final jobs = _db.schedules();
    final j = jobs.firstWhere((x) => x.id == id);
    final batchId = _journalBatch(j.name);
    try {
      await _execute(j, batchId);
      final next = j.intervalMin != null
          ? DateTime.now().add(Duration(minutes: j.intervalMin!)).millisecondsSinceEpoch
          : null;
      _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch,
          status: 'ok', nextRunAt: next);
      _events.add(ScheduleEvent(jobName: j.name, ok: true, message: 'completed'));
    } on FileSystemException catch (e) {
      _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch, status: 'error: ${e.message}');
      _events.add(ScheduleEvent(jobName: j.name, ok: false, message: e.message));
    } on CancelledException {
      _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch, status: 'cancelled');
    }
  }

  String _journalBatch(String label) =>
      'sched-${DateTime.now().millisecondsSinceEpoch}-$label';

  Future<void> _execute(ScheduleJob j, String batchId) async {
    final srcs = ((j.targets['sources'] as List?) ?? const []).cast<String>();
    final dest = j.targets['dest'] as String? ?? '';
    switch (j.kind) {
      case 'copy':
        Directory(dest).createSync(recursive: true);
        await _ops.copyPaths(srcs, dest, batchId: batchId);
      case 'move':
        Directory(dest).createSync(recursive: true);
        await _ops.movePaths(srcs, dest, batchId: batchId);
      case 'trash':
        await _ops.deletePaths(srcs, batchId: batchId);
      case 'compress':
        final name = j.arg.isEmpty ? 'archive-${DateTime.now().millisecondsSinceEpoch}.zip' : j.arg;
        final zipPath = pu.join(dest.isEmpty ? pu.dirname(srcs.first) : dest, name);
        // Scheduled jobs never overwrite silently: land on a unique name.
        final uniqueZip = FileOpsService.uniqueCopyName(zipPath);
        await _ops.compressToZip(srcs, uniqueZip, batchId: batchId);
      case 'pipeline':
        final p = _pipelines.byId(int.tryParse(j.arg) ?? -1);
        if (p != null) await _pipelines.run(p, srcs, batchId: batchId);
      case 'mirror':
        for (final m in _db.mirrors()) {
          if (m.enabled) await _mirrors.fullSync(m);
        }
    }
  }

  void dispose() => _timer?.cancel();
}

class ScheduleEvent {
  const ScheduleEvent({required this.jobName, required this.ok, required this.message});
  final String jobName;
  final bool ok;
  final String message;
}
