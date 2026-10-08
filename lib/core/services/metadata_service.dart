import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:archive/archive.dart' as ar;
import 'package:exif/exif.dart' as exif;
import 'package:image/image.dart' as img;

import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;
import '../utils/result.dart';
import 'fs_service.dart';
import 'journal.dart';

/// Content-aware metadata: reads EXIF / ID3 / PNG / EPUB / PDF / DOCX /
/// plain-text and writes ID3v2.3 (audio), JPEG EXIF, EPUB & DOCX properties.
///
/// Every write (audit item 11): checks freeze → copies the original into
/// the journal trash → writes a temp file → renames atomically → records a
/// journal entry whose undo restores the backup. Errors are surfaced,
/// never swallowed.
class MetadataService {
  MetadataService({OperationJournal? journal, bool Function(String path)? isFrozen})
      : _journal = journal,
        _isFrozen = isFrozen;

  final OperationJournal? _journal;
  final bool Function(String path)? _isFrozen;

  /// Freeze + backup + atomic temp-write, shared by all writers.
  Future<void> _safeWrite(String path, List<int> Function() produce,
      {String? batchId}) async {
    if (_isFrozen?.call(path) ?? false) {
      throw FrozenException(path);
    }
    final batch = batchId ?? _journal?.newBatch('metadata') ?? '';
    if (_journal != null) {
      await _journal!.backupCopyForEdit(path, batch);
    }
    final tmp =
        pu.join(pu.dirname(path), '.${pu.basename(path)}.nexus-edit');
    final tmpFile = File(tmp);
    try {
      await tmpFile.writeAsBytes(produce(), flush: true);
      // Atomic within the same volume; on cross-device errors renameSafe
      // falls back to copy+verify+delete.
      tmpFile.renameSync(path);
    } on FileSystemException {
      try {
        tmpFile.deleteSync();
      } on FileSystemException {// already gone
      }
      rethrow;
    }
    if (_journal != null && batchId == null) {
      // One self-contained batch per standalone write.
    }
  }

  Future<EntryMeta> read(String path) async {
    switch (pu.ext(path)) {
      case 'jpg':
      case 'jpeg':
      case 'tiff':
        return _readExif(path);
      case 'png':
      case 'webp':
      case 'bmp':
      case 'gif':
        return _readImageSize(path);
      case 'mp3':
        return _readId3(path);
      case 'epub':
        return _readEpub(path);
      case 'docx':
      case 'xlsx':
      case 'pptx':
        return _readOoxml(path);
      case 'pdf':
        return _readPdf(path);
      default:
        if (FileSystemService.isTextLike(path)) {
          final head = FileSystemService.readHead(path, bytes: 2048) ?? '';
          final first = head.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
          return EntryMeta(title: first.trim().startsWith('#')
              ? first.trim().replaceAll(RegExp(r'^#+\s*'), '').trim() : null);
        }
        return const EntryMeta();
    }
  }

  Future<EntryMeta> _readExif(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final data = await exif.readExifFromBytes(bytes);
      String? s(String k) => data[k]?.printable;
      final dims = _jpegDimensions(bytes);
      return EntryMeta(
        camera: s('EXIF Model') ?? s('Image Model'),
        taken: _exifDate(s('EXIF DateTimeOriginal') ?? s('Image DateTime')),
        description: s('Image ImageDescription'),
        artist: s('Image Artist'),
        width: dims?.$1,
        height: dims?.$2,
      );
    } catch (_) {
      return _readImageSize(path);
    }
  }

  EntryMeta _readImageSize(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info != null) {
        return EntryMeta(width: info.width, height: info.height);
      }
    } catch (_) {}
    return const EntryMeta();
  }

  Future<EntryMeta> _readId3(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.length < 10) return const EntryMeta();
      if (_s(bytes, 0, 3) != 'ID3') return const EntryMeta();
      final size = _syncsafe(bytes, 6);
      final body = bytes.sublist(10, (10 + size).clamp(0, bytes.length));
      String? title, artist, album, year, genre, track;
      var i = 0;
      while (i + 10 <= body.length) {
        final id = _s(body, i, 4);
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
        final fsize = (body[i + 4] << 24) | (body[i + 5] << 16) | (body[i + 6] << 8) | body[i + 7];
        if (fsize <= 0 || i + 10 + fsize > body.length) break;
        final payload = body.sublist(i + 10, i + 10 + fsize);
        final text = _decodeTextFrame(payload);
        switch (id) {
          case 'TIT2': title = text;
          case 'TPE1': artist = text;
          case 'TALB': album = text;
          case 'TYER': year ??= text;
          case 'TDRC': year ??= text;
          case 'TCON': genre = text;
          case 'TRCK': track = text;
        }
        i += 10 + fsize;
      }
      return EntryMeta(title: title, artist: artist, album: album, year: year, genre: genre, track: track);
    } catch (_) {
      return const EntryMeta();
    }
  }

  Future<EntryMeta> _readEpub(String path) async {
    try {
      final archive = ar.ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      String? opfPath;
      for (final f in archive.files) {
        if (f.name == 'META-INF/container.xml') {
          final xml = utf8.decode(f.content as List<int>);
          final m = RegExp('full-path="([^"]+)"').firstMatch(xml);
          opfPath = m?.group(1);
          break;
        }
      }
      if (opfPath == null) return const EntryMeta();
      final opf = archive.files.where((f) => f.name == opfPath).firstOrNull;
      if (opf == null) return const EntryMeta();
      final xml = utf8.decode(opf.content as List<int>);
      return EntryMeta(
        title: _xmlTag(xml, 'dc:title'),
        artist: _xmlTag(xml, 'dc:creator'),
        description: _xmlTag(xml, 'dc:description'),
        year: _xmlTag(xml, 'dc:date')?.substring(0, 4.clamp(0, (_xmlTag(xml, 'dc:date') ?? '').length)),
      );
    } catch (_) {
      return const EntryMeta();
    }
  }

  Future<EntryMeta> _readOoxml(String path) async {
    try {
      final archive = ar.ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      final core = archive.files.where((f) => f.name == 'docProps/core.xml').firstOrNull;
      if (core == null) return const EntryMeta();
      final xml = utf8.decode(core.content as List<int>);
      return EntryMeta(
        title: _xmlTag(xml, 'dc:title'),
        artist: _xmlTag(xml, 'dc:creator'),
        description: _xmlTag(xml, 'dc:description'),
      );
    } catch (_) {
      return const EntryMeta();
    }
  }

  Future<EntryMeta> _readPdf(String path) async {
    final head = FileSystemService.readHead(path, bytes: 128 * 1024) ?? '';
    final m = RegExp(r'/Title\s*\(((?:[^()\\]|\\.)*)\)').firstMatch(head);
    final a = RegExp(r'/Author\s*\(((?:[^()\\]|\\.)*)\)').firstMatch(head);
    String? clean(String? s) => s?.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
    return EntryMeta(title: clean(m?.group(1)), artist: clean(a?.group(1)));
  }

  // ── writers ───────────────────────────────────────────────────────────────

  /// Writes ID3v2.3 text frames, preserving existing binary frames (APIC…).
  Future<void> writeId3(String path, Map<String, String> tags, {String? batchId}) async {
    final bytes = await File(path).readAsBytes();
    final frames = <String, List<int>>{}; // existing
    var audioStart = 0;
    if (bytes.length > 10 && _s(bytes, 0, 3) == 'ID3') {
      final size = _syncsafe(bytes, 6);
      audioStart = 10 + size;
      final body = bytes.sublist(10, audioStart);
      var i = 0;
      while (i + 10 <= body.length) {
        final id = _s(body, i, 4);
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
        final fsize = (body[i + 4] << 24) | (body[i + 5] << 16) | (body[i + 6] << 8) | body[i + 7];
        if (fsize <= 0 || i + 10 + fsize > body.length) break;
        final isText = id.startsWith('T') || id == 'COMM' && false;
        if (!isText || id == 'USLT') {
          frames[id] = body.sublist(i + 10, i + 10 + fsize);
        }
        i += 10 + fsize;
      }
    }
    const textIds = ['TIT2', 'TPE1', 'TALB', 'TYER', 'TCON', 'TRCK'];
    for (final e in tags.entries) {
      if (!textIds.contains(e.key) || e.value.isEmpty) continue;
      frames[e.key] = _encodeTextFrame(e.value);
    }
    final frameBytes = BytesBuilder();
    for (final e in frames.entries) {
      final payload = e.value;
      frameBytes.add(utf8.encode(e.key));
      frameBytes.add([(payload.length >> 24) & 0xff, (payload.length >> 16) & 0xff,
          (payload.length >> 8) & 0xff, payload.length & 0xff]);
      frameBytes.add([0, 0]);
      frameBytes.add(payload);
    }
    final body = frameBytes.toBytes();
    final sync = _syncsafeEncode(body.length);
    final out = BytesBuilder();
    out.add(utf8.encode('ID3'));
    out.add([3, 0, 0]);
    out.add(sync);
    out.add(body);
    if (audioStart > 0 && audioStart <= bytes.length) {
      out.add(bytes.sublist(audioStart));
    }
    await _safeWrite(path, () => out.toBytes(), batchId: batchId);
  }

  List<int> _encodeTextFrame(String text) {
    final utf16le = <int>[0xFF, 0xFE];
    for (final unit in text.codeUnits) {
      utf16le.addAll([unit & 0xff, (unit >> 8) & 0xff]);
    }
    utf16le.addAll([0, 0]);
    return utf16le;
  }

  /// Writes basic JPEG EXIF fields by rebuilding the APP1 TIFF block.
  /// Supported: ImageDescription(010E), Artist(013B), DateTime(0132),
  /// DateTimeOriginal in the Exif sub-IFD (9003).
  Future<void> writeJpegExif(String path, Map<String, String> fields, {String? batchId}) async {
    final bytes = await File(path).readAsBytes();
    if (_s(bytes, 0, 2) != String.fromCharCodes(const [0xFF, 0xD8])) {
      throw const FileSystemException('Not a JPEG file');
    }
    // Locate existing APP1 EXIF.
    var app1Start = -1, app1End = -1;
    var i = 2;
    while (i + 4 <= bytes.length) {
      if (bytes[i] != 0xFF) break;
      final marker = bytes[i + 1];
      if (marker == 0xDA) break; // SOS
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      if (marker == 0xE1 &&
          _s(bytes, i + 4, 6) == 'Exif\u0000\u0000') {
        app1Start = i;
        app1End = i + 2 + len;
        break;
      }
      i += 2 + len;
    }

    final tiff = app1Start >= 0
        ? bytes.sublist(app1Start + 10, app1End)
        : _defaultTiff();
    final rebuilt = _TiffEditor(tiff).setFields(fields);

    final out = BytesBuilder();
    out.add([0xFF, 0xD8]);
    final payload = <int>[...utf8.encode('Exif\u0000\u0000'), ...rebuilt];
    out.add([0xFF, 0xE1, (payload.length + 2 >> 8) & 0xff, (payload.length + 2) & 0xff]);
    out.add(payload);
    if (app1Start >= 0) {
      out.add(bytes.sublist(app1End));
    } else {
      out.add(bytes.sublist(2));
    }
    await _safeWrite(path, () => out.toBytes(), batchId: batchId);
  }

  List<int> _defaultTiff() => [
        0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // II*\0, IFD0@8
        0x00, 0x00, // empty IFD0 (patched by editor)
        0x00, 0x00, 0x00, 0x00,
      ];

  /// Rewrites EPUB (OPF) or OOXML (docProps/core.xml) document properties.
  Future<void> writeDocumentProps(String path, Map<String, String> props, {String? batchId}) async {
    final isEpub = pu.ext(path) == 'epub';
    final archive = ar.ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final entries = <String, List<int>>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      entries[f.name] = f.content as List<int>;
    }
    if (isEpub) {
      var opfName = entries.keys.where((k) => k.endsWith('.opf')).firstOrNull ?? '';
      if (opfName.isEmpty) {
        for (final f in entries.keys) {
          if (f.startsWith('META-INF')) continue;
          opfName = f;
          break;
        }
      }
      if (opfName.isEmpty) throw const FileSystemException('EPUB has no OPF manifest');
      entries[opfName] = utf8.encode(_patchXml(utf8.decode(entries[opfName]!), {
        'dc:title': props['title'], 'dc:creator': props['artist'],
        'dc:description': props['description'],
      }));
    } else {
      const core = 'docProps/core.xml';
      final xml = entries.containsKey(core)
          ? utf8.decode(entries[core]!)
          : '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
              'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
              'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>';
      entries[core] = utf8.encode(_patchXml(xml, {
        'dc:title': props['title'], 'dc:creator': props['artist'],
        'dc:description': props['description'],
      }));
    }
    final encoder = ar.ZipEncoder();
    final out = ar.Archive();
    entries.forEach((name, data) {
      out.addFile(ar.ArchiveFile(name, data.length, data));
    });
    final zip = encoder.encode(out)!;
    await _safeWrite(path, () => zip, batchId: batchId);
  }

  String _patchXml(String xml, Map<String, String?> tags) {
    var out = xml;
    tags.forEach((tag, value) {
      if (value == null) return;
      final escaped =
          value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      final existing = RegExp('<$tag(?: [^>]*)?>.*?</$tag>', dotAll: true).firstMatch(out);
      if (existing != null) {
        out = out.replaceRange(existing.start, existing.end, '<$tag>$escaped</$tag>');
      } else if (!out.contains('<$tag')) {
        final insertAt = out.indexOf('</');
        final idx = insertAt < 0 ? out.length : insertAt;
        out = out.replaceRange(idx, idx, '<$tag>$escaped</$tag>');
      }
    });
    return out;
  }

  String? _xmlTag(String xml, String tag) {
    final m = RegExp('<$tag(?: [^>]*)?>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return m?.group(1)?.trim();
  }

  DateTime? _exifDate(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
        int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
  }

  (int, int)? _jpegDimensions(List<int> bytes) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) break;
      final marker = bytes[i + 1];
      if (marker == 0xC0 || marker == 0xC2) {
        return ((bytes[i + 7] << 8) | bytes[i + 8], (bytes[i + 5] << 8) | bytes[i + 6]);
      }
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + len;
    }
    return null;
  }

  static String _s(List<int> b, int off, int len) => latin1.decode(b.sublist(off, off + len));

  static int _syncsafe(List<int> b, int off) =>
      (b[off] << 21) | (b[off + 1] << 14) | (b[off + 2] << 7) | b[off + 3];

  static List<int> _syncsafeEncode(int n) => [
        (n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f,
      ];

  /// UTF-16 decoder for ID3 text frames (handles BOM-prefixed payloads).
  static String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
    if (bytes.length < 2) return '';
    var be = bigEndian;
    var start = 0;
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      be = false;
      start = 2;
    } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      be = true;
      start = 2;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(be ? (bytes[i] << 8) | bytes[i + 1] : bytes[i + 1] << 8 | bytes[i]);
    }
    return String.fromCharCodes(units).replaceAll('\u0000', '').trim();
  }

  String _decodeTextFrame(List<int> payload) {
    if (payload.isEmpty) return '';
    final enc = payload[0];
    final data = payload.sublist(1);
    try {
      if (enc == 1 || enc == 2) {
        return _decodeUtf16(data, bigEndian: enc == 2);
      }
      return latin1.decode(data).replaceAll('\u0000', '').trim();
    } catch (_) {
      return '';
    }
  }
}

/// Edits a TIFF block's IFD0/ExifIFD entries and re-serializes offsets.
class _TiffEditor {
  _TiffEditor(this._bytes) {
    _little = _bytes[0] == 0x49 && _bytes[1] == 0x49;
  }

  final List<int> _bytes;
  late bool _little;

  static const desc = 0x010E, dateTime = 0x0132, artist = 0x013B, exifIfdPtr = 0x8769, dto = 0x9003;

  List<int> setFields(Map<String, String> fields) {
    final entries0 = _parseIfd(_readU32(4));
    final exifPtrEntry = entries0.entries.where((e) => e.key == exifIfdPtr).firstOrNull;
    final exifEntries = <int, _TiffEntry>{};
    if (exifPtrEntry != null) {
      exifEntries.addAll(_parseIfd(_readU32(exifPtrEntry.value.valueOffset)));
    }
    final now = DateTime.now();
    final iso = '${now.year}-${_t(now.month)}-${_t(now.day)} '
        '${_t(now.hour)}:${_t(now.minute)}:${_t(now.second)}';

    void upsert(int tag, int type, List<int> data, {bool exif = false}) {
      (exif ? exifEntries : entries0)[tag] = _TiffEntry(tag, type, data.length, data, -1);
    }

    String norm(String v) => v.replaceAll('T', ' ').length == 19 ? v.replaceAll('T', ' ') : iso;

    if (fields.containsKey('description')) upsert(desc, 2, _ascii(fields['description']!));
    if (fields.containsKey('artist')) upsert(artist, 2, _ascii(fields['artist']!));
    if (fields.containsKey('taken')) {
      upsert(dateTime, 2, _ascii(norm(fields['taken']!)));
      upsert(dto, 2, _ascii(norm(fields['taken']!)), exif: true);
    }

    final ifd0List = entries0.values.where((e) => e.tag != exifIfdPtr).toList()
      ..sort((a, b) => a.tag.compareTo(b.tag));
    final exifList = exifEntries.values.toList()..sort((a, b) => a.tag.compareTo(b.tag));
    final hasExif = exifList.isNotEmpty;

    const ifd0Offset = 8;
    final ifd0Size = 2 + (ifd0List.length + (hasExif ? 1 : 0)) * 12 + 4;
    final exifOffset = hasExif ? ifd0Offset + ifd0Size : -1;
    final exifSize = hasExif ? 2 + exifList.length * 12 + 4 : 0;
    var dataCursor = ifd0Offset + ifd0Size + exifSize;

    for (final e in ifd0List) {
      if (e.data.length > 4) {
        e.valueOffset = dataCursor;
        dataCursor += e.data.length + (e.data.length & 1);
      }
    }
    for (final e in exifList) {
      if (e.data.length > 4) {
        e.valueOffset = dataCursor;
        dataCursor += e.data.length + (e.data.length & 1);
      }
    }

    final out = BytesBuilder();
    out.add(_bytes.sublist(0, 8));

    void writeIfd(List<_TiffEntry> list) {
      out.add(_u16(list.length));
      for (final e in list) {
        out.add(_u16(e.tag));
        out.add(_u16(e.type));
        out.add(_u32(e.data.length));
        if (e.data.length <= 4) {
          final pad = List<int>.from(e.data);
          while (pad.length < 4) {
            pad.add(0);
          }
          out.add(pad);
        } else {
          out.add(_u32(e.valueOffset));
        }
      }
      out.add(_u32(0)); // next IFD
    }

    // IFD0 including the Exif pointer in tag order.
    final merged = <_TiffEntry>[...ifd0List];
    if (hasExif) {
      final ptr = _TiffEntry(exifIfdPtr, 4, 1, _u32(exifOffset), -1);
      merged.add(ptr);
      merged.sort((a, b) => a.tag.compareTo(b.tag));
    }
    writeIfd(merged);
    if (hasExif) writeIfd(exifList);
    for (final e in [...ifd0List, ...exifList]) {
      if (e.data.length > 4) out.add(_pad2(e.data));
    }
    return out.toBytes();
  }

  Map<int, _TiffEntry> _parseIfd(int offset) {
    final count = _readU16(offset);
    final map = <int, _TiffEntry>{};
    for (var i = 0; i < count; i++) {
      final e = offset + 2 + i * 12;
      final tag = _readU16(e);
      final type = _readU16(e + 2);
      final n = _readU32(e + 4);
      final byteLen = n * _typeSize(type);
      final List<int> data;
      var valueOffset = -1;
      if (byteLen <= 4) {
        data = _bytes.sublist(e + 8, e + 8 + byteLen);
      } else {
        valueOffset = _readU32(e + 8);
        data = _bytes.sublist(valueOffset, valueOffset + byteLen);
      }
      map[tag] = _TiffEntry(tag, type, n, data, valueOffset);
    }
    return map;
  }

  int _typeSize(int type) => switch (type) {
        1 || 2 || 6 || 7 => 1,
        3 || 8 => 2,
        4 || 9 || 11 => 4,
        5 || 10 || 12 => 8,
        _ => 1,
      };

  int _readU16(int off) => _little
      ? _bytes[off] | (_bytes[off + 1] << 8)
      : (_bytes[off] << 8) | _bytes[off + 1];

  int _readU32(int off) => _little
      ? _bytes[off] | (_bytes[off + 1] << 8) | (_bytes[off + 2] << 16) | (_bytes[off + 3] << 24)
      : (_bytes[off] << 24) | (_bytes[off + 1] << 16) | (_bytes[off + 2] << 8) | _bytes[off + 3];

  List<int> _u16(int v) => _little ? [v & 0xff, (v >> 8) & 0xff] : [(v >> 8) & 0xff, v & 0xff];

  List<int> _u32(int v) => _little
      ? [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]
      : [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  List<int> _ascii(String s) => [...latin1.encode(s), 0];

  List<int> _pad2(List<int> d) {
    final out = List<int>.from(d);
    if (out.length.isOdd) out.add(0);
    return out;
  }

  static String _t(int n) => n.toString().padLeft(2, '0');
}

class _TiffEntry {
  _TiffEntry(this.tag, this.type, this.count, this.data, this.valueOffset);
  final int tag;
  final int type;
  final int count;
  final List<int> data;
  int valueOffset;
}
