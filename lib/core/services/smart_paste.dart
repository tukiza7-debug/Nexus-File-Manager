import 'dart:async';
import 'dart:io';

import '../../domain/enums.dart';
import '../utils/path_utils.dart' as pu;
import 'ops_service.dart';

/// Smart Paste: plans how each clipboard item lands in the destination —
/// detect conflicts, resolve per-item strategies, build the rename plan.
class SmartPasteResolver {
  const SmartPasteResolver();

  /// Returns per-source decisions. `null` target means "skip".
  Future<PastePlan> plan({
    required List<String> sources,
    required bool isCut,
    required String destDir,
    required ConflictStrategy defaultStrategy,
  }) async {
    final decisions = <PasteDecision>[];
    for (final src in sources) {
      final name = pu.basename(src);
      final target = pu.join(destDir, name);
      final exists = FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound;
      // Audit item 1: detect pasting an item onto itself (same folder paste,
      // or a copy into the folder that contains it).
      final sameFile = exists && FileOpsService.sameEntity(src, target);
      decisions.add(PasteDecision(src, name, target, exists && !sameFile,
          strategy: defaultStrategy, sameFile: sameFile));
    }
    return PastePlan(decisions, isCut: isCut, destDir: destDir);
  }

  /// Executes a resolved plan via [ops].
  Future<void> execute(PastePlan plan, FileOpsService ops, String batchId) async {
    final renamePlan = <String, String>{};
    final skipped = <String>[];
    for (final d in plan.decisions) {
      // Pasting a file onto itself: a move is a no-op, a copy must land
      // under a unique "name (2).ext" (audit item 1).
      if (d.sameFile) {
        if (plan.isCut) {
          skipped.add(d.name);
          continue;
        }
        renamePlan[d.source] = FileOpsService.uniqueCopyName(d.target);
        continue;
      }
      switch (d.resolved) {
        case ConflictStrategy.skip:
          skipped.add(d.name);
        case ConflictStrategy.keepBoth:
          renamePlan[d.source] = FileOpsService.uniqueCopyName(d.target);
        case ConflictStrategy.overwrite:
          renamePlan[d.source] = d.target;
        case ConflictStrategy.compare:
        case ConflictStrategy.ask:
          // Compare/Ask must be resolved by the UI before execute().
          skipped.add(d.name);
      }
    }
    final sources = renamePlan.keys.toList();
    if (sources.isEmpty) return;
    if (plan.isCut) {
      await ops.movePaths(sources, plan.destDir, batchId: batchId, renamePlan: renamePlan);
    } else {
      await ops.copyPaths(sources, plan.destDir, batchId: batchId, renamePlan: renamePlan);
    }
  }
}

class PastePlan {
  const PastePlan(this.decisions, {required this.isCut, required this.destDir});
  final List<PasteDecision> decisions;
  final bool isCut;
  final String destDir;

  bool get hasConflicts => decisions.any((d) => d.conflict);
  List<String> get sources => [for (final d in decisions) d.source];
}

class PasteDecision {
  PasteDecision(this.source, this.name, this.target, this.conflict,
      {required this.strategy, this.sameFile = false});

  final String source;
  final String name;
  final String target;
  final bool conflict;
  final ConflictStrategy strategy;

  /// True when source and target are the same filesystem entity.
  final bool sameFile;

  ConflictStrategy get resolved =>
      conflict ? strategy : ConflictStrategy.overwrite; // no conflict → plain move/copy
}
