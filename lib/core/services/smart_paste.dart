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
      final sameFile = exists && _identical(src, target);
      decisions.add(PasteDecision(src, name, target, exists && !sameFile, strategy: defaultStrategy));
    }
    return PastePlan(decisions, isCut: isCut, destDir: destDir);
  }

  static bool _identical(String a, String b) {
    try {
      return FileSystemEntity.identicalSync(a, b);
    } on FileSystemException {
      return false;
    }
  }

  /// Executes a resolved plan via [ops].
  Future<void> execute(PastePlan plan, FileOpsService ops, String batchId) async {
    final renamePlan = <String, String>{};
    final skipped = <String>[];
    for (final d in plan.decisions) {
      switch (d.resolved) {
        case ConflictStrategy.skip:
          skipped.add(d.name);
        case ConflictStrategy.keepBoth:
          var n = 2;
          var candidate = pu.withCounter(d.target, n);
          while (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
            n++;
            candidate = pu.withCounter(d.target, n);
          }
          renamePlan[d.source] = candidate;
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
  PasteDecision(this.source, this.name, this.target, this.conflict, {required this.strategy});

  final String source;
  final String name;
  final String target;
  final bool conflict;
  final ConflictStrategy strategy;

  ConflictStrategy get resolved =>
      conflict ? strategy : ConflictStrategy.overwrite; // no conflict → plain move/copy
}
