import 'dart:io';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'fs_service.dart';
import 'ops_service.dart';

/// File Transform Pipeline: an ordered chain of steps (rename → case →
/// extension → move/copy → compress → trash) applied to a selection, with a
/// dry-run planner and saveable definitions.
class PipelineService {
  PipelineService(this._db, this._ops);

  final DbService _db;
  final FileOpsService _ops;

  List<NexusPipeline> all() => _db.pipelines();

  NexusPipeline? byId(int id) => _db.pipelines().where((p) => p.id == id).firstOrNull;

  int save(NexusPipeline p) => _db.savePipeline(p);

  void delete(int id) => _db.deletePipeline(id);

  /// Dry run: returns the planned final path for every input.
  List<(String, String)> plan(NexusPipeline p, List<NexusEntry> entries) {
    final names = [for (final e in entries) e.name];
    final paths = [for (final e in entries) e.path];
    for (final step in p.steps) {
      if (!step.enabled) continue;
      names.setAll(0, _transformNames(step, names));
    }
    return [for (var i = 0; i < entries.length; i++) (paths[i], names[i])];
  }

  List<String> _transformNames(PipelineStep step, List<String> names) {
    final out = <String>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final stem = pu.stem(name);
      final ext = pu.ext(name);
      out.add(switch (step.kind) {
        'renamePattern' => _apply(step.args['pattern'] ?? '{name}', name, stem, ext, i + 1),
        'case' => _applyCase(step.args['mode'] ?? 'lower', name, ext),
        'ext' => () {
          // Audit item 19: an empty target extension must not produce a
          // trailing dot.
          final target = step.args['ext'] ?? '';
          if (target.isEmpty) return name;
          return ext.isEmpty ? '$name.$target' : '$stem.$target';
        }(),
        _ => name,
      });
    }
    return out;
  }

  String _apply(String pattern, String name, String stem, String ext, int n) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    var out = pattern
        .replaceAll('{n}', n.toString())
        .replaceAll('{name}', stem)
        .replaceAll('{date}', '${now.year}-${two(now.month)}-${two(now.day)}')
        .replaceAll('{time}', '${two(now.hour)}${two(now.minute)}')
        .replaceAll('{size}', '');
    if (ext.isNotEmpty) out = '$out.$ext';
    return out;
  }

  String _applyCase(String mode, String name, String ext) {
    final stem = pu.stem(name);
    final cased = switch (mode) {
      'lower' => stem.toLowerCase(),
      'upper' => stem.toUpperCase(),
      'title' => stem.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' '),
      'kebab' => stem.replaceAll(RegExp(r'[\s_]+'), '-').toLowerCase(),
      'snake' => stem.replaceAll(RegExp(r'[\s-]+'), '_').toLowerCase(),
      'camel' => _camel(stem),
      _ => stem,
    };
    return ext.isEmpty ? cased : '$cased.$ext';
  }

  String _camel(String s) {
    final parts = s.split(RegExp(r'[\s_-]+'));
    if (parts.isEmpty) return s;
    return parts.first.toLowerCase() +
        parts.skip(1).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join();
  }

  /// Executes the pipeline against concrete paths. Dry-run parity
  /// (audit item 19): names chain through steps exactly like plan(), and
  /// the path list stays aligned with the entry list (missing paths are
  /// skipped in BOTH).
  Future<void> run(NexusPipeline p, List<String> paths, {required String batchId}) async {
    final entries = <NexusEntry>[];
    for (final path in paths) {
      final t = FileSystemEntity.typeSync(path);
      if (t == FileSystemEntityType.notFound) continue;
      final stat = FileSystemEntity.typeSync(path);
      entries.add(NexusEntry(
        path: path,
        name: pu.basename(path),
        isDir: stat == FileSystemEntityType.directory,
        size: stat == FileSystemEntityType.file ? File(path).lengthSync() : 0,
        modified: stat == FileSystemEntityType.file ? File(path).lastModifiedSync() : DateTime.now(),
        category: stat == FileSystemEntityType.directory
            ? FileCategory.folder
            : FileSystemService.categorize(pu.basename(path)),
      ));
    }
    // Aligned: currentPaths[i] ↔ entries[i] for the whole run.
    var currentPaths = [for (final e in entries) e.path];
    var currentNames = [for (final e in entries) e.name];

    for (final step in p.steps) {
      if (!step.enabled) continue;
      switch (step.kind) {
        case 'renamePattern':
        case 'case':
        case 'ext':
          final plannedNames = _transformNames(step, currentNames);
          final renamed = <String>[];
          for (var i = 0; i < currentPaths.length; i++) {
            final dir = pu.dirname(currentPaths[i]);
            final newName = plannedNames[i];
            final newPath = pu.join(dir, newName);
            if (newPath != currentPaths[i]) {
              // Validate the produced name before touching the disk.
              pu.checkName(newName);
              if (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) {
                // Never clobber: suffix a counter.
                final candidate = FileOpsService.uniqueCopyName(newPath);
                await _ops.rename(currentPaths[i], candidate, batchId: batchId);
                renamed.add(candidate);
              } else {
                await _ops.rename(currentPaths[i], newPath, batchId: batchId);
                renamed.add(newPath);
              }
            } else {
              renamed.add(currentPaths[i]);
            }
          }
          currentPaths = renamed;
          currentNames = [for (final p2 in currentPaths) pu.basename(p2)];
        case 'move':
          final dest = step.args['dest'] ?? '';
          if (dest.isNotEmpty && currentPaths.isNotEmpty) {
            Directory(dest).createSync(recursive: true);
            await _ops.movePaths(currentPaths, dest, batchId: batchId);
            currentPaths = [for (final src in currentPaths) pu.join(dest, pu.basename(src))];
            currentNames = [for (final p2 in currentPaths) pu.basename(p2)];
          }
        case 'copy':
          final dest = step.args['dest'] ?? '';
          if (dest.isNotEmpty && currentPaths.isNotEmpty) {
            Directory(dest).createSync(recursive: true);
            await _ops.copyPaths(currentPaths, dest, batchId: batchId);
          }
        case 'compress':
          if (currentPaths.isEmpty) break; // guard empty lists (item 19)
          final zipName = step.args['name'] ?? 'archive.zip';
          final dest = step.args['dest'] ?? pu.dirname(currentPaths.first);
          Directory(dest).createSync(recursive: true);
          final uniqueZip = FileOpsService.uniqueCopyName(pu.join(dest, zipName));
          await _ops.compressToZip(currentPaths, uniqueZip, batchId: batchId);
        case 'trash':
          if (currentPaths.isNotEmpty) {
            await _ops.deletePaths(currentPaths, batchId: batchId);
            currentPaths = const [];
            currentNames = const [];
          }
      }
    }
  }
}
