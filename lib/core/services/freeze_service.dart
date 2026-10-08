import 'dart:io';

import '../../domain/models.dart';

import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;

/// Secure Freeze: OS-level read-only (best effort per platform) + app-level
/// guard. Every mutating op routes through FileOpsService which refuses to
/// touch frozen roots.
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
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return;
    try {
      if (Platform.isWindows) {
        await Process.run('attrib', [readOnly ? '+R' : '-R', path]);
      } else {
        await Process.run('chmod', ['a-w', path]);
      }
      if (type == FileSystemEntityType.directory) {
        for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
          try {
            if (Platform.isWindows) {
              await Process.run('attrib', [readOnly ? '+R' : '-R', e.path]);
            } else {
              await Process.run('chmod', ['a-w', e.path]);
            }
          } on ProcessException {
            break;
          }
        }
      }
    } on ProcessException {
      // OS-level enforcement unavailable — the app-level guard still applies.
    }
  }

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
