import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/models.dart';

import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;

/// Secure Freeze: OS-level read-only (best effort per platform) + app-level
/// guard. Every mutating op routes through FileOpsService which refuses to
/// touch frozen roots.
///
/// Platform notes (audit item 12):
///  * Windows uses `attrib +R /S /D <dir>\*` — one recursive command.
///  * POSIX uses `chmod -R a-w` / `chmod -R u+w` — one recursive command.
///  * Android has no useful chmod for shared storage (FUSE ignores it); the
///    app-level guard in FileOpsService is the effective protection and the
///    UI says so (see freeze_screen strings).
class FreezeService {
  FreezeService(this._db);

  final DbService _db;

  List<FrozenPath> all() => _db.freezes();

  bool isFrozen(String path) => _db.isFrozen(path);

  Future<void> freeze(String path, {String note = ''}) async {
    _db.freeze(path, note);
    await _applyReadOnly(path, true);
  }

  Future<void> unfreeze(String path) async {
    _db.unfreeze(path);
    await _applyReadOnly(path, false);
  }

  List<String> frozenRoots() => _db.frozenRoots();

  Future<void> _applyReadOnly(String path, bool readOnly) async {
    if (kIsWeb) return;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return;
    try {
      if (Platform.isWindows) {
        // One recursive command instead of one process per file.
        if (type == FileSystemEntityType.directory) {
          await Process.run('attrib',
              [readOnly ? '+R' : '-R', '${_winNormalize(path)}\\*', '/S', '/D']);
        }
        await Process.run('attrib', [readOnly ? '+R' : '-R', _winNormalize(path)]);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Shared storage on mobile ignores permission bits — the app-level
        // freeze guard is the real enforcement here.
        return;
      } else {
        // chmod u+w restores the owner's write bit; a-w strips it for all.
        await Process.run('chmod',
            ['-R', readOnly ? 'a-w' : 'u+w', path]);
      }
    } on ProcessException {
      // OS-level enforcement unavailable — the app-level guard still applies.
    } on FileSystemException {
      // The path may live on a filesystem without permission support.
    }
  }

  static String _winNormalize(String p) => p.endsWith('\\') || p.endsWith('/')
      ? p.substring(0, p.length - 1)
      : p;

  /// Collects frozen paths among [paths]; empty list when clear.
  List<String> violations(List<String> paths) {
    final roots = frozenRoots();
    if (roots.isEmpty) return const [];
    return [
      for (final p in paths)
        for (final r in roots)
          if (pu.isUnder(p, r)) p,
    ];
  }
}
