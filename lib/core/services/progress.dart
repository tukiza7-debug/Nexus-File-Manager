/// Progress reporting + cancellation shared by every long-running operation.
library;

import 'dart:io';

enum OpPhase { running, done, error, cancelled }

class OpProgress {
  const OpProgress({
    required this.batchId,
    required this.title,
    required this.done,
    required this.total,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.detail = '',
    this.phase = OpPhase.running,
  });

  final String batchId;
  final String title;
  final int done;
  final int total;
  final int bytesDone;
  final int bytesTotal;
  final String detail;
  final OpPhase phase;

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  double get byteFraction => bytesTotal == 0 ? 0 : (bytesDone / bytesTotal).clamp(0.0, 1.0);

  OpProgress copyWith({int? done, int? total, int? bytesDone, int? bytesTotal, String? detail, OpPhase? phase}) =>
      OpProgress(
        batchId: batchId,
        title: title,
        done: done ?? this.done,
        total: total ?? this.total,
        bytesDone: bytesDone ?? this.bytesDone,
        bytesTotal: bytesTotal ?? this.bytesTotal,
        detail: detail ?? this.detail,
        phase: phase ?? this.phase,
      );
}

/// Registry of cancellable batches. The UI cancels by batch id; the worker
/// checks the registry between chunks.
class CancelRegistry {
  final _cancelled = <String>{};

  void cancel(String batchId) => _cancelled.add(batchId);
  bool isCancelled(String batchId) => _cancelled.contains(batchId);
  void clear(String batchId) => _cancelled.remove(batchId);
}

const chunkSize = 256 * 1024;

/// Copies bytes in chunks; awaits a microtask each chunk so the UI stays
/// responsive and cancellation is checked.
Future<int> copyFileChunked(
  RandomAccessFile src,
  RandomAccessFile dst,
  void Function(int bytes) onChunk,
  bool Function() cancelled,
) async {
  final buf = List<int>.filled(chunkSize, 0);
  var total = 0;
  while (true) {
    if (cancelled()) throw const _Cancelled();
    final n = src.readIntoSync(buf, 0, chunkSize);
    if (n <= 0) break;
    dst.writeFromSync(buf, 0, n);
    total += n;
    onChunk(n);
    await Future<void>.delayed(Duration.zero);
  }
  return total;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// One chunk of file IO per event-loop turn — keeps animations smooth.
Future<void> yieldUi() async => Future<void>.delayed(Duration.zero);
