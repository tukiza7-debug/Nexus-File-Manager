import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_file_manager/core/services/diff_engine.dart';
import 'package:nexus_file_manager/core/services/rule_engine.dart';
import 'package:nexus_file_manager/domain/enums.dart';
import 'package:nexus_file_manager/domain/models.dart';

NexusEntry entry(String name, {bool dir = false, int size = 100}) => NexusEntry(
      path: '/tmp/$name',
      name: name,
      isDir: dir,
      size: size,
      modified: DateTime(2026),
      category: dir ? FileCategory.folder : FileCategory.other,
    );

void main() {
  group('diff engine', () {
    const diff = DiffEngine();

    test('detects additions and removals', () {
      final result = diff.diffLines('a\nb\nc', 'a\nc\nd');
      expect(result.any((l) => l.kind == DiffKind.removed && l.text == 'b'), isTrue);
      expect(result.any((l) => l.kind == DiffKind.added && l.text == 'd'), isTrue);
      expect(result.any((l) => l.kind == DiffKind.same && l.text == 'a'), isTrue);
    });

    test('identical inputs produce only same lines', () {
      final result = diff.diffLines('one\ntwo', 'one\ntwo');
      expect(result.every((l) => l.kind == DiffKind.same), isTrue);
    });

    test('ignoreWhitespace folds spacing differences', () {
      final strict = diff.diffLines('hello  world', 'hello world');
      final loose = diff.diffLines('hello  world', 'hello world', ignoreWhitespace: true);
      expect(strict.any((l) => l.kind != DiffKind.same), isTrue);
      expect(loose.every((l) => l.kind == DiffKind.same), isTrue);
    });
  });

  group('rule engine', () {
    const engine = RuleEngine();

    test('matches extension conditions with glob', () {
      const rule = NexusRule(
        name: 'big logs',
        enabled: true,
        match: 'all',
        conditions: [
          RuleCondition(field: 'ext', match: 'equals', value: 'log'),
          RuleCondition(field: 'size', match: 'gt', value: '1kb'),
        ],
        actions: [RuleAction(kind: 'move', arg: '/archive')],
      );
      expect(engine.matches(rule, entry('app.log', size: 2048)), isTrue);
      expect(engine.matches(rule, entry('app.log', size: 10)), isFalse);
      expect(engine.matches(rule, entry('app.txt', size: 2048)), isFalse);
    });

    test('any-match needs only one condition', () {
      const rule = NexusRule(
        name: 'any',
        enabled: true,
        match: 'any',
        conditions: [
          RuleCondition(field: 'name', match: 'contains', value: 'draft'),
          RuleCondition(field: 'ext', match: 'equals', value: 'tmp'),
        ],
        actions: [RuleAction(kind: 'trash', arg: '')],
      );
      expect(engine.matches(rule, entry('report.tmp')), isTrue);
      expect(engine.matches(rule, entry('draft-notes.txt')), isTrue);
      expect(engine.matches(rule, entry('final.txt')), isFalse);
    });

    test('plan applies rename patterns with counters', () {
      const rule = NexusRule(
        name: 'rename all',
        enabled: true,
        match: 'any',
        conditions: [RuleCondition(field: 'name', match: 'glob', value: '*')],
        actions: [RuleAction(kind: 'rename', arg: '{name}-{n}.{ext}')],
      );
      final plan = engine.plan(rule, [entry('a.txt'), entry('b.txt')]);
      expect(plan.length, 2);
      expect(plan[0].arg, 'a-1.txt');
      expect(plan[1].arg, 'b-2.txt');
    });
  });
}
