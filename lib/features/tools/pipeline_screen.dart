/// Transform Pipeline — a visual chain of file actions: rename patterns,
/// case folding, extension swaps, move/copy/trash and zip. Plan preview is
/// computed live, then the whole chain executes as one undoable batch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show pipelinePendingProvider;

class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});

  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  NexusPipeline? _editing;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(pipelinePendingProvider);
      if (pending.isNotEmpty) {
        toast(ref, '${pending.length} item(s) ready — pick a pipeline and run');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pipelines = ref.watch(pipelinesProvider);
    final entries = ref.watch(dirProvider.select((s) => s.entries));

    if (_editing != null) {
      return _Editor(
        pipeline: _editing!,
        entries: entries,
        onClose: () => setState(() => _editing = null),
        onSave: (p) {
          ref.read(servicesProvider).pipelines.save(p);
          _bump(ref);
          setState(() => _editing = null);
          toast(ref, 'Pipeline “${p.name}” saved');
        },
      );
    }

    return ToolScaffold(
      title: 'Transform Pipeline',
      subtitle: 'Reusable chains of file actions, previewed before anything moves.',
      icon: Icons.account_tree_rounded,
      actions: [
        FilledButton.icon(
          onPressed: () => setState(() => _editing =
              const NexusPipeline(name: 'New pipeline', steps: [])),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('New pipeline'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice != null)
            NexusPanel(
              padding: const EdgeInsets.all(10),
              child: Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
            ),
          if (pipelines.isEmpty)
            const EmptyState(
              icon: Icons.account_tree_rounded,
              title: 'No pipelines yet',
              message:
                  'A pipeline chains steps like “rename by pattern” → “lowercase extension” → “move to folder”. Build one and apply it to any selection — it shows a live preview of every resulting name first.',
            ),
          for (final p in pipelines)
            NexusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_rounded,
                          size: 17, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(p.name,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      IconButton(
                        tooltip: 'Edit steps',
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        onPressed: () => setState(() => _editing = p),
                      ),
                      IconButton(
                        tooltip: 'Delete pipeline',
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        onPressed: () async {
                          if (!await confirmDialog(context,
                              title: 'Delete pipeline?',
                              message: p.name,
                              danger: true)) {
                            return;
                          }
                          ref.read(servicesProvider).pipelines.delete(p.id!);
                          _bump(ref);
                        },
                      ),
                      FilledButton.tonal(
                        onPressed: () => _run(context, ref, p),
                        child: const Text('Run…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in p.steps)
                        Chip(
                          avatar: const Icon(Icons.bolt_rounded, size: 13),
                          label: Text(s.label,
                              style: const TextStyle(fontSize: 11.5)),
                        ),
                      if (p.steps.isEmpty)
                        Text('No steps yet — edit to add actions.',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, NexusPipeline p) async {
    final tab = ref.read(tabsProvider).active;
    final pending = ref.read(pipelinePendingProvider);
    final selection = tab.selection.isNotEmpty
        ? tab.selection.toList()
        : (pending.isNotEmpty ? pending : <String>[]);
    if (selection.isEmpty) {
      toast(ref, 'Select files in the explorer first, then run the pipeline',
          error: true);
      return;
    }
    final svc = ref.read(servicesProvider);
    final all = await svc.fs.listDir(tab.path);
    final chosen = all.where((e) => selection.contains(e.path)).toList();
    if (chosen.isEmpty) {
      toast(ref, 'Selection no longer exists', error: true);
      return;
    }
    if (!context.mounted) return;
    final preview = svc.pipelines.plan(p, chosen);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PreviewDialog(plan: preview),
    );
    if (ok != true) return;
    final batch = svc.journal.newBatch('pipeline');
    try {
      await svc.pipelines.run(p, selection, batchId: batch);
      svc.ops.finish(batch);
      toast(ref, 'Pipeline applied to ${selection.length} item(s)');
    } catch (e) {
      toast(ref, '$e', error: true);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.plan});

  final List<(String, String)> plan;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.preview_rounded),
      title: const Text('Pipeline preview'),
      content: SizedBox(
        width: 430,
        height: 300,
        child: plan.isEmpty
            ? const Center(child: Text('No changes would be applied.'))
            : ListView.builder(
                itemCount: plan.length,
                itemBuilder: (context, i) {
                  final (from, to) = plan[i];
                  final changed = from != to;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          changed ? Icons.arrow_forward_rounded : Icons.remove_rounded,
                          size: 13,
                          color: changed ? Theme.of(context).colorScheme.primary : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(pu.basename(from),
                              style: const TextStyle(fontSize: 12.5),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          child: Text(
                            changed ? pu.basename(to) : '—',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: changed
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).textTheme.bodySmall?.color,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
      ],
    );
  }
}

// ── Editor ──────────────────────────────────────────────────────────────────

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.pipeline,
    required this.entries,
    required this.onClose,
    required this.onSave,
  });

  final NexusPipeline pipeline;
  final List<NexusEntry> entries;
  final VoidCallback onClose;
  final ValueChanged<NexusPipeline> onSave;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late NexusPipeline _p = widget.pipeline;

  static const _kinds = [
    ('renamePattern', 'Rename by pattern', '{name} ({n}).{ext}'),
    ('case', 'Change case', 'lower | UPPER | camel'),
    ('ext', 'Replace extension', 'txt'),
    ('move', 'Move to folder', '/destination'),
    ('copy', 'Copy to folder', '/destination'),
    ('trash', 'Move to backup trash', ''),
    ('compress', 'Compress to ZIP', 'archive name'),
  ];

  List<(String, String)> get _preview {
    final svc = ref.read(servicesProvider);
    return svc.pipelines.plan(_p, widget.entries);
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: 'Edit pipeline',
      subtitle: 'Drag to reorder · toggle steps on/off',
      icon: Icons.account_tree_rounded,
      actions: [
        TextButton.icon(
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => widget.onSave(_p),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Save pipeline'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Pipeline name'),
            controller: TextEditingController(text: _p.name),
            onChanged: (v) => _p = _p.copyWith(name: v),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _p.steps.length,
              onReorder: (a, b) => setState(() {
                if (b > a) b--;
                final steps = [..._p.steps];
                final s = steps.removeAt(a);
                steps.insert(b, s);
                _p = _p.copyWith(steps: steps);
              }),
              proxyDecorator: (child, i, anim) => Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
              itemBuilder: (context, i) {
                final s = _p.steps[i];
                return ListTile(
                  key: ValueKey('step-$i-${s.kind}'),
                  dense: true,
                  leading: const Icon(Icons.drag_indicator_rounded, size: 16),
                  title: Text(s.label, style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.enabled,
                        onChanged: (v) => setState(() {
                          final steps = [..._p.steps];
                          steps[i] = s.copyWith(enabled: v);
                          _p = _p.copyWith(steps: steps);
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        onPressed: () => setState(() {
                          final steps = [..._p.steps]..removeAt(i);
                          _p = _p.copyWith(steps: steps);
                        }),
                      ),
                    ],
                  ),
                  onTap: () => _editStep(i),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (kind, label, hint) in _kinds)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 14),
                  label: Text(label, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _addStep(kind, hint),
                ),
            ],
          ),
          const Divider(height: 30),
          const SectionHeader('Live preview — against the current folder',
              icon: Icons.preview_rounded),
          NexusPanel(
            padding: const EdgeInsets.all(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (from, to) in _preview.take(30))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: pu.basename(from)),
                            if (from != to) ...[
                              const TextSpan(text: '  →  '),
                              TextSpan(
                                text: pu.basename(to),
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ]),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (_preview.isEmpty)
                      Text('Nothing in this folder matches yet.',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addStep(String kind, String hint) async {
    final args = await _promptArgs(kind, hint, {});
    if (args == null) return;
    setState(() {
      _p = _p.copyWith(steps: [..._p.steps, PipelineStep(kind: kind, args: args)]);
    });
  }

  Future<void> _editStep(int i) async {
    final s = _p.steps[i];
    final hint = switch (s.kind) {
      'renamePattern' => '{name} ({n}).{ext}',
      'case' => 'lower | UPPER | camel',
      'ext' => 'txt',
      'move' || 'copy' => '/destination',
      'compress' => 'archive name',
      _ => '',
    };
    final args = await _promptArgs(s.kind, hint, s.args);
    if (args == null) return;
    setState(() {
      final steps = [..._p.steps];
      steps[i] = s.copyWith(args: args);
      _p = _p.copyWith(steps: steps);
    });
  }

  Future<Map<String, String>?> _promptArgs(
      String kind, String hint, Map<String, String> current) async {
    if (kind == 'trash') return const {};
    final keys = switch (kind) {
      'renamePattern' => ['pattern'],
      'case' => ['mode'],
      'ext' => ['ext'],
      'move' || 'copy' => ['dest'],
      'compress' => ['name'],
      _ => <String>['value'],
    };
    final out = <String, String>{};
    for (final k in keys) {
      final v = await promptDialog(context,
          title: '$kind · $k', initial: current[k] ?? (k == 'mode' ? 'lower' : hint));
      if (v == null) return null;
      out[k] = v;
    }
    return out;
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
