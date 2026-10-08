import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../utils/path_utils.dart' as pu;
import 'fs_service.dart';

enum MergeMode { text, csv, imageVertical, imageHorizontal, binary, pdf }

/// Merge Files — combines multiple files of the same family into one:
/// text (with separators), CSV rows, images (vertical/horizontal
/// composition), best-effort PDF object merge, or raw binary concat.
class MergeService {
  const MergeService();

  static MergeMode detect(List<String> paths) {
    final exts = paths.map(pu.ext).toSet();
    if (paths.every((p) => pu.ext(p) == 'pdf')) return MergeMode.pdf;
    if (paths.every((p) => ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'].contains(pu.ext(p)))) {
      return MergeMode.imageVertical;
    }
    if (paths.every((p) => pu.ext(p) == 'csv' || pu.ext(p) == 'tsv')) return MergeMode.csv;
    if (paths.every(FileSystemService.isTextLike)) return MergeMode.text;
    if (exts.length == 1 && paths.any((p) => RegExp(r'\.part\d+$').hasMatch(p))) {
      return MergeMode.binary;
    }
    return MergeMode.binary;
  }

  Future<String> merge({
    required List<String> paths,
    required MergeMode mode,
    required String outputPath,
    String textSeparator = '\n',
    int imageGap = 0,
    int imageBackground = 0xFFFFFFFF,
  }) async {
    switch (mode) {
      case MergeMode.text:
      case MergeMode.csv:
        final b = StringBuffer();
        for (var i = 0; i < paths.length; i++) {
          final content = File(paths[i]).readAsStringSync();
          if (i > 0) b.write(textSeparator);
          b.write(content.endsWith('\n') || content.isEmpty ? content : '$content\n');
        }
        File(outputPath).writeAsStringSync(b.toString(), flush: true);
      case MergeMode.imageVertical:
      case MergeMode.imageHorizontal:
        final vertical = mode == MergeMode.imageVertical;
        final images = <img.Image>[];
        for (final p in paths) {
          final decoded = img.decodeImage(File(p).readAsBytesSync());
          if (decoded != null) images.add(decoded);
        }
        if (images.isEmpty) throw const FileSystemException('No decodable images');
        if (vertical) {
          final w = images.map((e) => e.width).reduce((a, b) => a > b ? a : b);
          final h = images.fold(0, (s, e) => s + e.height) + imageGap * (images.length - 1);
          final canvas = img.Image(width: w, height: h);
          img.fill(canvas, color: img.ColorRgb8((imageBackground >> 16) & 0xff,
              (imageBackground >> 8) & 0xff, imageBackground & 0xff));
          var y = 0;
          for (final im in images) {
            img.compositeImage(canvas, im, dstX: 0, dstY: y);
            y += im.height + imageGap;
          }
          File(outputPath).writeAsBytesSync(img.encodePng(canvas));
        } else {
          final h = images.map((e) => e.height).reduce((a, b) => a > b ? a : b);
          final w = images.fold(0, (s, e) => s + e.width) + imageGap * (images.length - 1);
          final canvas = img.Image(width: w, height: h);
          img.fill(canvas, color: img.ColorRgb8((imageBackground >> 16) & 0xff,
              (imageBackground >> 8) & 0xff, imageBackground & 0xff));
          var x = 0;
          for (final im in images) {
            img.compositeImage(canvas, im, dstX: x, dstY: 0);
            x += im.width + imageGap;
          }
          File(outputPath).writeAsBytesSync(img.encodePng(canvas));
        }
      case MergeMode.binary:
        final out = File(outputPath).openSync(mode: FileMode.write);
        try {
          for (final p in paths) {
            final raf = File(p).openSync();
            try {
              final buf = List<int>.filled(512 * 1024, 0);
              while (true) {
                final n = raf.readIntoSync(buf, 0, buf.length);
                if (n <= 0) break;
                out.writeFromSync(buf, 0, n);
              }
            } finally {
              raf.closeSync();
            }
          }
          out.flushSync();
        } finally {
          out.closeSync();
        }
      case MergeMode.pdf:
        final merged = await compute(_mergePdfSync, paths);
        File(outputPath).writeAsBytesSync(merged, flush: true);
    }
    return outputPath;
  }

  /// Best-effort PDF merge: renumbers indirect objects from every source and
  /// concatenates page trees under a new /Root. Works for the vast majority
  /// of non-encrypted, directly-addressable PDFs.
  static List<int> _mergePdfSync(List<String> paths) => PdfMerger.merge(paths);
}

/// Object-level PDF concatenation (best effort, no external binaries).
class PdfMerger {
  static List<int> merge(List<String> paths) {
    final docs = [for (final p in paths) _SourceDoc.parse(File(p).readAsBytesSync())];
    final b = BytesBuilder();
    b.add([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A]); // %PDF-1.7\n
    b.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]); // binary comment line

    // Reserve object numbers.
    final map = <int, int>{}; // (srcIndex << 24) | origNum → newNum
    var nextNum = 1;
    for (var si = 0; si < docs.length; si++) {
      for (final n in docs[si].objects.keys) {
        map[(si << 24) | n] = nextNum++;
      }
    }
    final pagesObj = nextNum++;
    final catalogObj = nextNum++;

    final offsets = List<int>.filled(nextNum, 0);
    for (var si = 0; si < docs.length; si++) {
      final doc = docs[si];
      for (final n in doc.objects.keys.toList()..sort()) {
        final newNum = map[(si << 24) | n]!;
        offsets[newNum] = b.length;
        final body = doc.renumber(doc.objects[n]!, map, si);
        b.add('$newNum 0 obj\n'.codeUnits);
        b.add(body);
        b.add('\nendobj\n'.codeUnits);
      }
    }

    final kids = <String>[
      for (var si = 0; si < docs.length; si++)
        for (final n in docs[si].pageObjectNumbers()) '${map[(si << 24) | n]} 0 R',
    ];
    offsets[pagesObj] = b.length;
    b.add('$pagesObj 0 obj\n<< /Type /Pages /Kids [ ${kids.join(' ')} ] '
        '/Count ${kids.length} >>\nendobj\n'.codeUnits);
    offsets[catalogObj] = b.length;
    b.add('$catalogObj 0 obj\n<< /Type /Catalog /Pages $pagesObj 0 R >>\nendobj\n'.codeUnits);

    final xrefPos = b.length;
    b.add('xref\n0 $nextNum\n0000000000 65535 f \n'.codeUnits);
    for (var i = 1; i < nextNum; i++) {
      b.add('${offsets[i].toString().padLeft(10, '0')} 00000 n \n'.codeUnits);
    }
    b.add('trailer\n<< /Size $nextNum /Root $catalogObj 0 R >>\n'
        'startxref\n$xrefPos\n%%EOF\n'.codeUnits);
    return b.toBytes();
  }
}

class _SourceDoc {
  _SourceDoc(this.objects, this.trailer);

  final Map<int, List<int>> objects;
  final String trailer;

  static _SourceDoc parse(List<int> bytes) {
    final s = latin1.decode(bytes, allowInvalid: true);
    final objects = <int, List<int>>{};
    // Find every `N 0 obj ... endobj` while skipping stream contents.
    var i = 0;
    while (true) {
      final objStart = s.indexOf(' obj', i);
      if (objStart < 0) break;
      final declStart = s.lastIndexOf(RegExp(r'\n|\r'), objStart) + 1;
      final decl = s.substring(declStart, objStart).trim();
      final m = RegExp(r'^(\d+)\s+0$').firstMatch(decl);
      if (m == null) {
        i = objStart + 4;
        continue;
      }
      final num = int.parse(m.group(1)!);
      var bodyStart = objStart + 4;
      if (s.startsWith('\r\n', bodyStart)) {
        bodyStart += 2;
      } else if (s.startsWith('\n', bodyStart)) {
        bodyStart += 1;
      }
      // Locate endobj, honoring streams with direct /Length.
      final streamIdx = s.indexOf('stream', bodyStart);
      final endobjIdx = s.indexOf('endobj', bodyStart);
      int bodyEnd;
      if (streamIdx >= 0 && streamIdx < endobjIdx) {
        final dict = s.substring(bodyStart, streamIdx);
        final lenM = RegExp(r'/Length\s+(\d+)(?:\s+0\s+R)?').firstMatch(dict);
        var dataStart = streamIdx + 'stream'.length;
        if (s.startsWith('\r\n', dataStart)) {
          dataStart += 2;
        } else if (s.startsWith('\n', dataStart)) {
          dataStart += 1;
        }
        var dataEnd = dataStart;
        if (lenM != null) {
          dataEnd = dataStart + int.parse(lenM.group(1)!);
        } else {
          dataEnd = s.indexOf('endstream', dataStart);
        }
        bodyEnd = s.indexOf('endobj', dataEnd);
      } else {
        bodyEnd = endobjIdx;
      }
      if (bodyEnd < 0) break;
      var body = s.substring(bodyStart, bodyEnd);
      while (body.endsWith('\n') || body.endsWith('\r')) {
        body = body.substring(0, body.length - 1);
      }
      objects[num] = latin1.encode(body);
      i = bodyEnd;
    }
    final trailerM = RegExp(r'trailer\s*<<(.*?)>>', dotAll: true).firstMatch(s);
    final trailer = trailerM?.group(1) ?? '';
    return _SourceDoc(objects, trailer);
  }

  List<int> pageObjectNumbers() {
    // Pages reference their parent; a page object has /Type /Page.
    return [
      for (final e in objects.entries)
        if (RegExp(r'/Type\s*/Page[^s]')
          .hasMatch(latin1.decode(e.value, allowInvalid: true)))
        e.key,
    ];
  }

  List<int> renumber(List<int> body, Map<int, int> map, int srcIndex) {
    final s = latin1.decode(body, allowInvalid: true);
    final rewritten = s.replaceAllMapped(RegExp(r'(\d+)\s+0\s+R'), (m) {
      final n = int.parse(m.group(1)!);
      final newNum = map[(srcIndex << 24) | n];
      return newNum == null ? m.group(0)! : '$newNum 0 R';
    });
    return latin1.encode(rewritten);
  }
}
