import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;
import 'progress.dart';

/// Pure-Dart FS listing + classification. All operations funnel through here
/// so behavior is identical across desktop and mobile.
class FileSystemService {
  const FileSystemService();

  /// Lists a directory inside an isolate (fast even with 100k entries).
  Future<List<NexusEntry>> listDir(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    final entries = await compute(_listSync, path);
    return entries;
  }

  static List<NexusEntry> _listSync(String path) {
    final dir = Directory(path);
    final out = <NexusEntry>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        try {
          if (e is Link) continue;
          final stat = e.statSync();
          final name = pu.basename(e.path);
          if (name.isEmpty) continue;
          out.add(NexusEntry(
            path: e.path,
            name: name,
            isDir: stat.type == FileSystemEntityType.directory,
            size: stat.type == FileSystemEntityType.directory ? 0 : stat.size,
            modified: stat.modified,
            accessed: stat.accessed,
            category: stat.type == FileSystemEntityType.directory
                ? FileCategory.folder
                : categorize(name),
          ));
        } on FileSystemException {
          // Unreadable entry — skip silently (permission denied etc).
        }
      }
    } on FileSystemException {
      // Directory unreadable.
    }
    return out;
  }

  static FileCategory categorize(String name) {
    switch (pu.ext(name)) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'heic':
      case 'svg':
      case 'ico':
      case 'tiff':
      case 'avif':
        return FileCategory.image;
      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
      case 'webm':
      case 'wmv':
      case 'flv':
      case 'm4v':
        return FileCategory.video;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'm4a':
      case 'aac':
      case 'opus':
      case 'wma':
        return FileCategory.audio;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
      case 'odt':
      case 'ods':
      case 'odp':
      case 'rtf':
      case 'epub':
      case 'mobi':
      case 'pages':
        return FileCategory.document;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
      case '7z':
      case 'rar':
      case 'tgz':
      case 'zst':
        return FileCategory.archive;
      case 'dart':
      case 'js':
      case 'ts':
      case 'tsx':
      case 'jsx':
      case 'py':
      case 'rs':
      case 'go':
      case 'java':
      case 'kt':
      case 'c':
      case 'h':
      case 'cpp':
      case 'hpp':
      case 'cs':
      case 'swift':
      case 'rb':
      case 'php':
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'toml':
      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
      case 'html':
      case 'css':
      case 'scss':
      case 'sql':
      case 'gradle':
      case 'lock':
      case 'cmake':
        return FileCategory.code;
      case 'ttf':
      case 'otf':
      case 'woff':
      case 'woff2':
        return FileCategory.font;
      case 'exe':
      case 'msi':
      case 'appimage':
      case 'deb':
      case 'rpm':
      case 'dmg':
      case 'apk':
      case 'bat':
      case 'cmd':
        return FileCategory.executable;
      default:
        return FileCategory.other;
    }
  }

  static bool isTextLike(String name) {
    final e = pu.ext(name);
    if (FileSystemService.categorize(name) == FileCategory.code) return true;
    return const ['txt', 'md', 'markdown', 'log', 'csv', 'tsv', 'ini', 'cfg', 'conf', 'env',
          'gitignore', 'properties', 'plist', 'srt', 'vtt', 'tex', 'rst']
        .contains(e);
  }

  static int dirSizeSync(String path) {
    var total = 0;
    try {
      final list = Directory(path).listSync(recursive: true, followLinks: false);
      for (final e in list) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } on FileSystemException {
            // ignore
          }
        }
      }
    } on FileSystemException {
      // ignore
    }
    return total;
  }

  static int dirItemCountSync(String path) {
    try {
      return Directory(path).listSync(followLinks: false).length;
    } on FileSystemException {
      return 0;
    }
  }

  String homeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) return env['USERPROFILE'] ?? 'C:\\';
    return env['HOME'] ?? '/';
  }

  /// Sensible starting places per platform.
  List<PlaceEntry> places() {
    final home = homeDir();
    final sep = Platform.isWindows ? r'\' : '/';
    PlaceEntry? maybe(String label, String sub, FileCategory c) {
      final p = '$home$sep$sub';
      return Directory(p).existsSync() ? PlaceEntry(label, p, c) : null;
    }

    final out = <PlaceEntry>[
      PlaceEntry('Home', home, FileCategory.folder),
    ];
    void add(String label, String sub, FileCategory c) {
      final e = maybe(label, sub, c);
      if (e != null) out.add(e);
    }

    add('Documents', 'Documents', FileCategory.document);
    add('Downloads', 'Downloads', FileCategory.archive);
    add('Pictures', 'Pictures', FileCategory.image);
    add('Music', 'Music', FileCategory.audio);
    add('Videos', 'Videos', FileCategory.video);
    if (Platform.isAndroid || Platform.isIOS) {
      out.add(PlaceEntry('App files', home, FileCategory.folder));
    }
    return out;
  }

  /// Opens a file with the platform default handler.
  Future<void> openWithSystem(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else {
      // Mobile handled by the UI layer via share sheet.
      throw UnsupportedError('openWithSystem unsupported on ${Platform.operatingSystem}');
    }
  }

  /// Reveals a path in the platform file browser (desktop only).
  Future<void> revealInSystem(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [pu.dirname(path)]);
    }
  }

  static String? readHead(String path, {int bytes = 64 * 1024}) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final raf = f.openSync();
      try {
        final len = raf.lengthSync();
        final data = raf.readSync(len < bytes ? len : bytes);
        return utf8.decode(data, allowMalformed: true);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  static String hexHead(String path, {int offset = 0, int bytes = 256}) {
    try {
      final raf = File(path).openSync();
      try {
        final len = raf.lengthSync();
        final start = offset.clamp(0, len);
        final end = (start + bytes).clamp(0, len);
        raf.setPositionSync(start);
        final data = raf.readSync(end - start);
        final b = StringBuffer();
        for (var i = 0; i < data.length; i += 16) {
          b.write((start + i).toString().padLeft(8, '0'));
          b.write('  ');
          for (var j = 0; j < 16; j++) {
            if (i + j < data.length) {
              b.write(data[i + j].toRadixString(16).padLeft(2, '0'));
            } else {
              b.write('  ');
            }
            b.write(j == 7 ? '  ' : ' ');
          }
          b.write(' |');
          for (var j = 0; j < 16 && i + j < data.length; j++) {
            final c = data[i + j];
            b.write(c >= 0x20 && c < 0x7f ? String.fromCharCode(c) : '·');
          }
          b.writeln('|');
        }
        return b.toString();
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return '';
    }
  }

  /// Runs [fn] with a progress callback in batches, reporting to [onProgress].
  static Future<void> forEachWithProgress<T>(
    Iterable<T> items,
    Future<void> Function(T item, void Function(int bytes) report) fn,
    void Function(OpProgress p) onProgress, {
    required String batchId,
    required String title,
    required bool Function() cancelled,
  }) async {
    final list = items.toList();
    for (var i = 0; i < list.length; i++) {
      if (cancelled()) {
        onProgress(OpProgress(batchId: batchId, title: title, done: i, total: list.length, phase: OpPhase.cancelled));
        throw const CancelledException();
      }
      onProgress(OpProgress(batchId: batchId, title: title, done: i, total: list.length));
      await fn(list[i], (_) {});
      await yieldUi();
    }
    onProgress(OpProgress(batchId: batchId, title: title, done: list.length, total: list.length, phase: OpPhase.done));
  }
}

class PlaceEntry {
  const PlaceEntry(this.label, this.path, this.category);
  final String label;
  final String path;
  final FileCategory category;
}

class CancelledException implements Exception {
  const CancelledException();
}
