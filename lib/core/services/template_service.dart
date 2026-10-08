import 'dart:convert';
import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'fs_service.dart';

/// Template Drop: register reusable files/folders/text templates and stamp
/// them into any folder with token substitution and smart naming.
class TemplateService {
  TemplateService(this._db);

  final DbService _db;

  List<TemplateFile> all() => _db.templates();

  int save(TemplateFile t) => _db.saveTemplate(t);

  void delete(int id) => _db.deleteTemplate(id);

  /// Stamps [template] into [destDir] with [name]; returns the created path.
  Future<String> instantiate(TemplateFile template, String destDir, String name) async {
    Directory(destDir).createSync(recursive: true);
    final unique = _uniquePath(destDir, name);
    switch (template.kind) {
      case 'text':
        final content = applyTokens(template.content ?? '', name);
        File(unique).writeAsStringSync(content, flush: true);
      case 'file':
        final src = File(template.sourcePath);
        if (src.existsSync()) {
          final bytes = src.readAsBytesSync();
          // Substitute tokens in text templates only; copy binary as-is.
          if (FileSystemService.isTextLike(template.sourcePath)) {
            File(unique).writeAsStringSync(applyTokens(utf8ish(bytes), name), flush: true);
          } else {
            File(unique).writeAsBytesSync(bytes, flush: true);
          }
        } else {
          File(unique).writeAsStringSync('', flush: true);
        }
      case 'dir':
        await _copyDir(Directory(template.sourcePath), unique, name);
    }
    return unique;
  }

  Future<void> _copyDir(Directory src, String dest, String name) async {
    Directory(dest).createSync(recursive: true);
    for (final e in src.listSync(followLinks: false)) {
      final target = pu.join(dest, pu.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, target, name);
      } else if (e is File) {
        if (FileSystemService.isTextLike(e.path)) {
          File(target).writeAsStringSync(applyTokens(utf8ish(e.readAsBytesSync()), name), flush: true);
        } else {
          await e.copy(target);
        }
      }
    }
  }

  /// Replaces {{name}}, {{date}}, {{time}}, {{year}} tokens.
  String applyTokens(String content, String name) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return content
        .replaceAll('{{name}}', name)
        .replaceAll('{{date}}', '${now.year}-${two(now.month)}-${two(now.day)}')
        .replaceAll('{{time}}', '${two(now.hour)}:${two(now.minute)}')
        .replaceAll('{{year}}', '${now.year}');
  }

  /// Audit item 47: decode template bytes as UTF-8 with malformed-sequence
  /// tolerance. `String.fromCharCodes` (the old behaviour) silently mangles
  /// every multi-byte character (é, 中, emoji…) in user templates.
  static String utf8ish(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static String _uniquePath(String dir, String name) {
    var candidate = pu.join(dir, name);
    if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.notFound) return candidate;
    final stem = pu.stem(name);
    final ext = pu.ext(name);
    var n = 2;
    while (true) {
      candidate = pu.join(dir, ext.isEmpty ? '$stem-$n' : '$stem-$n.$ext');
      if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.notFound) return candidate;
      n++;
    }
  }
}
