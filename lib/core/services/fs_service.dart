import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:share_plus/share_plus.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;
import 'progress.dart';

/// Pure-Dart FS listing + classification. All operations funnel through here
/// so behavior is identical across desktop and mobile.
class FileSystemService {
  const FileSystemService();

  /// Last listing per path — shown immediately while a refresh runs
  /// (audit item 29).
  final Map<String, List<NexusEntry>> _listingCache = {};

  /// Returns the cached listing for [path] (or null).
  List<NexusEntry>? cachedListing(String path) => _listingCache[path];

  /// Lists a directory. Small folders (< [_isolateThreshold] entries) read
  /// with async Directory.list() on the UI isolate; large ones run inside
  /// an isolate. Avoids spawning one isolate per reload (audit item 29).
  Future<List<NexusEntry>> listDir(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    final quick = <NexusEntry>[];
    var count = 0;
    var overflow = false;
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is Link) continue;
        count++;
        if (count > _isolateThreshold) {
          overflow = true;
          break;
        }
        try {
          final stat = e.statSync();
          final name = pu.basename(e.path);
          if (name.isEmpty) continue;
          quick.add(NexusEntry(
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
          // Unreadable entry — skip.
        }
      }
    } on FileSystemException {
      // Directory unreadable.
    }
    if (overflow) {
      final entries = await compute(_listSync, path);
      _listingCache[path] = entries;
      return entries;
    }
    _listingCache[path] = quick;
    return quick;
  }

  static const int _isolateThreshold = 2000;

  /// Applies [filter] to entries in memory without re-listing the disk
  /// (audit item 29).
  static List<NexusEntry> filterEntries(
      List<NexusEntry> entries, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => e.name.toLowerCase().contains(q))
        .toList(growable: false);
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

  /// Best starting directory for the current platform.
  ///
  /// On Android we open the shared primary volume (`/storage/emulated/0`)
  /// so the explorer behaves like a real file manager once
  /// MANAGE_EXTERNAL_STORAGE (or legacy storage) is granted.
  /// Falling back to `$HOME` or `/` left users on an empty path
  /// (mobile screenshot audit, Oct 2026).
  String homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    if (Platform.isAndroid) {
      const candidates = <String>[
        '/storage/emulated/0',
        '/sdcard',
        '/storage/sdcard0',
      ];
      for (final p in candidates) {
        try {
          if (Directory(p).existsSync()) return p;
        } on FileSystemException {
          // keep looking
        }
      }
      final ext = Platform.environment['EXTERNAL_STORAGE'];
      if (ext != null && ext.isNotEmpty) {
        try {
          if (Directory(ext).existsSync()) return ext;
        } on FileSystemException {/* ignore */}
      }
    }
    return Platform.environment['HOME'] ?? '/';
  }

  /// Sensible starting places per platform (sidebar "Places").
  List<PlaceEntry> places() {
    if (Platform.isAndroid) return _androidPlaces();
    if (Platform.isIOS) return _iosPlaces();

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
    return out;
  }

  /// Android Places: Internal Storage + common public folders + secondary
  /// volumes under `/storage` (SD cards, USB OTG).
  List<PlaceEntry> _androidPlaces() {
    final primary = homeDir();
    final out = <PlaceEntry>[
      PlaceEntry('Internal Storage', primary, FileCategory.folder),
    ];

    void addSub(String label, String sub, FileCategory c) {
      final p = '$primary/$sub';
      try {
        if (Directory(p).existsSync()) {
          out.add(PlaceEntry(label, p, c));
        }
      } on FileSystemException {/* skip */}
    }

    addSub('Downloads', 'Download', FileCategory.archive);
    addSub('Downloads', 'Downloads', FileCategory.archive);
    addSub('Documents', 'Documents', FileCategory.document);
    addSub('Pictures', 'Pictures', FileCategory.image);
    addSub('DCIM', 'DCIM', FileCategory.image);
    addSub('Music', 'Music', FileCategory.audio);
    addSub('Movies', 'Movies', FileCategory.video);
    addSub('Videos', 'Videos', FileCategory.video);

    try {
      final storageRoot = Directory('/storage');
      if (storageRoot.existsSync()) {
        for (final e in storageRoot.listSync(followLinks: false)) {
          if (e is! Directory) continue;
          final name = pu.basename(e.path);
          if (name == 'emulated' || name == 'self' || name.startsWith('.')) {
            continue;
          }
          try {
            if (e.path == primary) continue;
            if (Directory(e.path).existsSync()) {
              out.add(PlaceEntry(
                name.length > 12 ? 'SD Card' : 'SD · $name',
                e.path,
                FileCategory.folder,
              ));
            }
          } on FileSystemException {/* skip unreadable */}
        }
      }
    } on FileSystemException {/* no /storage */}

    return out;
  }

  List<PlaceEntry> _iosPlaces() {
    final home = homeDir();
    return [
      PlaceEntry('Files', home, FileCategory.folder),
      PlaceEntry('App files', home, FileCategory.folder),
    ];
  }

  /// Opens a file with the platform default handler.
  ///
  /// Audit item 21: on Android/iOS this routes through the platform
  /// channel — ACTION_VIEW via FileProvider on Android, the share sheet as
  /// a fallback on iOS — instead of throwing UnsupportedError.
  Future<void> openWithSystem(String path) async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('nexus/incoming');
        final ok = await channel.invokeMethod<bool>('openWith', {'path': path});
        if (ok != true) {
          // No handler for this MIME type — fall back to the share sheet so
          // the user can still pick a target app.
          await channel.invokeMethod('shareFrom', {'path': path});
        }
      } on MissingPluginException {
        // Platform side not ready; nothing else we can do on mobile.
      }
      return;
    }
    if (Platform.isIOS) {
      try {
        await Share.shareXFiles([XFile(path)]);
      } catch (_) {
        // User cancelled the share sheet — not an error.
      }
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
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
