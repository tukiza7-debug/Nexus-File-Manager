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
///
/// Audit item 15:
///  * every job runs inside a catch-all — any error records status 'error'
///    and one-shot jobs are disabled so they stop re-firing every tick;
///  * a per-job running lock prevents overlapping ticks from starting the
///    same job twice;
///  * the 'mirror' job runs only the mirror selected in the job's targets
///    (falls back to none);
///  * schedules only run while the app is open — the UI surfaces this.
class SchedulerService {
  SchedulerService(this._db, this._ops, this._pipelines, this._mirrors);

  final DbService _db;
  final FileOpsService _ops;
  final PipelineService _pipelines;
  final MirrorService _mirrors;

  Timer? _timer;
  final _running = <int, bool>{};
  final _events = StreamController<ScheduleEvent>.broadcast();
  Stream<ScheduleEvent> get events => _events.stream;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => tick());
    tick();
  }

  void stop() => _timer?.cancel();

  bool isRunning(int jobId) => _running[jobId] ?? false;

  Future<void> tick() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final job in _db.schedules()) {
      if (!job.enabled) continue;
      if (_running[job.id!] ?? false) continue; // per-job re-entrancy lock
      final due = job.intervalMin != null
          ? (job.lastRunMs == null ||
              now - job.lastRunMs! >= job.intervalMin! * 60 * 1000)
          : job.runAtMs != null && job.runAtMs! <= now;
      if (!due) continue;
      // Fire-and-forget so one slow job cannot starve the others, but the
      // lock above keeps it single-instance.
      unawaited(run(job.id!));
    }
  }

  Future<void> run(int id) async {
    if (_running[id] ?? false) return;
    _running[id] = true;
    try {
      final jobs = _db.schedules();
      final ScheduleJob j;
      try {
        j = jobs.firstWhere((x) => x.id == id);
      } on StateError {
        return; // job deleted while running
      }
      final batchId = _journalBatch();
      try {
        await _execute(j, batchId);
        final next = j.intervalMin != null
            ? DateTime.now().add(Duration(minutes: j.intervalMin!)).millisecondsSinceEpoch
            : null;
        // One-shot jobs disable themselves after a successful run.
        var enabled = j.enabled;
        if (j.intervalMin == null && j.runAtMs != null) enabled = false;
        _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch,
            status: 'ok', nextRunAt: next);
        if (!enabled) _db.saveSchedule(ScheduleJob(
            id: j.id, name: j.name, kind: j.kind, targets: j.targets,
            arg: j.arg, runAtMs: j.runAtMs, intervalMin: j.intervalMin,
            enabled: false, lastRunMs: j.lastRunMs, lastStatus: 'ok'));
        _events.add(ScheduleEvent(jobName: j.name, ok: true, message: 'completed'));
      } on CancelledException {
        _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch, status: 'cancelled');
        _events.add(ScheduleEvent(jobName: j.name, ok: false, message: 'cancelled'));
      } catch (e) {
        // Catch-all: StateError/ArgumentError/cast failures must not leave
        // the job silently re-running every 20 s (audit item 15).
        final msg = _short(e.toString());
        _db.setScheduleRun(id, at: DateTime.now().millisecondsSinceEpoch, status: 'error: $msg');
        _events.add(ScheduleEvent(jobName: j.name, ok: false, message: msg));
        if (j.intervalMin == null && j.runAtMs != null) {
          _db.saveSchedule(ScheduleJob(
              id: j.id, name: j.name, kind: j.kind, targets: j.targets,
              arg: j.arg, runAtMs: j.runAtMs, intervalMin: j.intervalMin,
              enabled: false, lastRunMs: j.lastRunMs, lastStatus: 'error'));
        }
      }
    } finally {
      _running[id] = false;
    }
  }

  static String _short(String s) => s.length > 140 ? '${s.substring(0, 140)}…' : s;

  String _journalBatch() => DateTime.now().microsecondsSinceEpoch.toString();

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
        // Run only the mirror selected for this job (audit item 15 / S14).
        final selectedId = int.tryParse('${j.targets['mirrorId'] ?? ''}');
        if (selectedId == null) {
          throw const FileSystemException(
              'Mirror job has no mirror selected. Edit the job and pick one.');
        }
        final m = _db.mirrors().where((m) => m.id == selectedId).firstOrNull;
        if (m == null) {
          throw FileSystemException('Selected mirror (id $selectedId) no longer exists');
        }
        if (m.enabled) await _mirrors.fullSync(m, batchId: batchId);
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
