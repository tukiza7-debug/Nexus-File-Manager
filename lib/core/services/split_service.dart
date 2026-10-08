import 'dart:io';
import 'dart:isolate';

import '../utils/path_utils.dart' as pu;

/// Visual File Splitter: splits any file at a byte marker into 2 parts, or
/// into N equal parts. Parts are named `name.part001…` and rejoinable via
/// Merge (binary mode).
class SplitService {
  const SplitService();

  /// Splits [path] at [marker] (2 parts) when [parts] == 0, otherwise into
  /// [parts] equal chunks. Returns created part paths.
  Future<List<String>> split({
    required String path,
    required String destDir,
    int marker = -1,
    int parts = 0,
    void Function(double fraction, String label)? onProgress,
  }) async {
    final f = File(path);
    if (!f.existsSync()) throw FileSystemException('File not found', path);
    final size = f.lengthSync();
    if (size == 0) throw const FileSystemException('Cannot split an empty file');
    // Audit item 47: validate the part count BEFORE writing anything.
    // A part count larger than the byte size used to produce zero-byte
    // parts; the hard cap keeps accidental 1,000,000-part requests from
    // filling the disk.
    const maxParts = 1024;
    if (parts < 0) parts = 0;
    if (parts == 1 || parts > maxParts) {
      throw FileSystemException(
          'Invalid part count (use 2–$maxParts, or 0 for marker split)', path);
    }
    final points = <int>[];
    if (parts > 1) {
      final chunk = size ~/ parts;
      if (chunk < 1) {
        throw FileSystemException(
            'Cannot split $size bytes into $parts non-empty parts', path);
      }
      for (var i = 1; i < parts; i++) {
        points.add(chunk * i);
      }
    } else if (marker > 0 && marker < size) {
      points.add(marker);
    } else {
      throw const FileSystemException('Invalid split position');
    }
    final name = pu.basename(path);
    final stem = pu.stem(path);
    final ext = pu.ext(path);
    final width = points.length.toString().length;
    final created = <String>[];
    var start = 0;
    try {
      for (var i = 0; i <= points.length; i++) {
        final end = i < points.length ? points[i] : size;
        final idx = (i + 1).toString().padLeft(width, '0');
        final partName = ext.isEmpty ? '$name.part$idx' : '$stem.part$idx.$ext';
        final dest = pu.join(destDir, partName);
        final out = File(dest).openSync(mode: FileMode.write);
        final raf = f.openSync();
        try {
          raf.setPositionSync(start);
          var remaining = end - start;
          final buf = List<int>.filled(512 * 1024, 0);
          var done = 0;
          while (remaining > 0) {
            final take = remaining < buf.length ? remaining : buf.length;
            final n = raf.readIntoSync(buf, 0, take);
            if (n <= 0) break;
            out.writeFromSync(buf, 0, n);
            remaining -= n;
            done += n;
            onProgress?.call((start + done) / size, partName);
            await Future<void>.delayed(Duration.zero);
          }
        } finally {
          out.closeSync();
          raf.closeSync();
        }
        created.add(dest);
        start = end;
      }
      return created;
    } catch (e) {
      // Audit item 47: a failed split must not leave orphan half-written
      // parts behind — clean up everything this call created.
      for (final p in created) {
        try {
          File(p).deleteSync();
        } catch (_) {
          // best effort — original error below is what matters
        }
      }
      rethrow;
    }
  }

  /// Suggests a sensible marker for a preview (e.g. middle).
  static int defaultMarker(int size) => size ~/ 2;

  static Future<int> sizeOf(String path) => Isolate.run(() => File(path).lengthSync());
}
