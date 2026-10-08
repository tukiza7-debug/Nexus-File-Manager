/// Paper Trail — the complete, searchable history of every file operation.
/// Undo and redo whole batches; trace any file's lifetime.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/journal.dart';
import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show journalFocusPathProvider;

class PaperTrailScreen extends ConsumerStatefulWidget {
  const PaperTrailScreen({super.key});

  @override
  ConsumerState<PaperTrailScreen> createState() => _PaperTrailScreenState();
}

class _PaperTrailScreenState extends ConsumerState<PaperTrailScreen> {
  bool _batchesView = true;
  String? _openBatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focus = ref.read(journalFocusPathProvider);
      if (focus.isNotEmpty) {
        ref.read(journalProvider.notifier).search(pu.basename(focus));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(journalProvider);
    final svc = ref.read(servicesProvider);
    final undoable = svc.journal.nextUndoBatch();
    final redoable = svc.journal.nextRedoBatch();
    final undoDesc = undoable == null
        ? null
        : OperationJournal.describe(undoable, svc.journal.batchEntries(undoable));
    final redoDesc = redoable == null
        ? null
        : OperationJournal.describe(redoable, svc.journal.batchEntries(redoable));

    return ToolScaffold(
      title: 'Paper Trail',
      subtitle:
          'Every copy, move, rename and deletion — searchable, replayable, reversible.',
      icon: Icons.history_rounded,
      maxWidth: 1100,
      actions: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Batches'), icon: Icon(Icons.view_agenda_rounded, size: 15)),
            ButtonSegment(value: false, label: Text('All events'), icon: Icon(Icons.list_rounded, size: 15)),
          ],
          selected: {_batchesView},
          onSelectionChanged: (s) => setState(() => _batchesView = s.first),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText:
                        'Search the trail — file name, batch label, operation…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) =>
                      ref.read(journalProvider.notifier).search(v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _UndoCard(
                      label: 'UNDO',
                      desc: undoDesc,
                      enabled: undoable != null,
                      onTap: () async {
                        final desc = await svc.journal.undoBatch(undoable!,
                            onError: (m) async => toast(ref, m, error: true));
                        ref.read(journalProvider.notifier).reload();
                        ref.read(tabsProvider.notifier).refresh();
                        toast(ref, 'Undone · $desc');
                      },
                    ),
                    const SizedBox(width: 10),
                    _UndoCard(
                      label: 'REDO',
                      desc: redoDesc,
                      enabled: redoable != null,
                      onTap: () async {
                        final desc = await svc.journal.redoBatch(redoable!,
                            onError: (m) async => toast(ref, m, error: true));
                        ref.read(journalProvider.notifier).reload();
                        ref.read(tabsProvider.notifier).refresh();
                        toast(ref, 'Redone · $desc');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            const EmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: 'The trail is empty',
              message:
                  'Copy a file, rename another, delete something — every operation lands here with its full batch, so Ctrl Z always knows exactly what to reverse.',
            )
          else if (_batchesView)
            ..._buildBatches(entries, svc)
          else
            NexusPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final e in entries.take(200))
                    ListTile(
                      dense: true,
                      leading: Icon(_opIcon(e.op),
                          size: 15, color: _opColor(e.op)),
                      title: Text(
                        '${pu.basename(e.fromPath)}  ·  ${e.display}',
                        style: const TextStyle(fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${f.formatDateTime(DateTime.fromMillisecondsSinceEpoch(e.createdAtMs))} · batch ${e.batchId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: e.undone
                          ? const Chip(label: Text('undone', style: TextStyle(fontSize: 10)))
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildBatches(List<JournalEntry> entries, AppServices svc) {
    final seen = <String>{};
    final widgets = <Widget>[];
    for (final e in entries) {
      if (seen.contains(e.batchId)) continue;
      seen.add(e.batchId);
      final batchEntries = svc.journal.batchEntries(e.batchId);
      final undone = batchEntries.every((b) => b.undone);
      widgets.add(
        NexusPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                    undone ? Icons.undo_rounded : Icons.history_rounded,
                    size: 16,
                    color: undone ? Colors.grey : Theme.of(context).colorScheme.primary),
                title: Text(OperationJournal.describe(e.batchId, batchEntries),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${batchEntries.length} operation(s) · ${f.formatDateTime(
                      DateTime.fromMillisecondsSinceEpoch(e.createdAtMs))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _openBatch == e.batchId ? 'Collapse' : 'Expand',
                      icon: Icon(
                          _openBatch == e.batchId
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 17),
                      onPressed: () => setState(() =>
                          _openBatch = _openBatch == e.batchId ? null : e.batchId),
                    ),
                  ],
                ),
              ),
              if (_openBatch == e.batchId)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      for (final b in batchEntries)
                        ListTile(
                          dense: true,
                          leading: Icon(_opIcon(b.op), size: 14,
                              color: _opColor(b.op)),
                          title: Text('${pu.basename(b.fromPath)} → ${b.toPath == null ? '' : pu.basename(b.toPath!)}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  IconData _opIcon(JournalOp op) => switch (op) {
        JournalOp.copy => Icons.content_copy_rounded,
        JournalOp.move => Icons.drive_file_move_rounded,
        JournalOp.rename => Icons.drive_file_rename_outline_rounded,
        JournalOp.delete => Icons.delete_outline_rounded,
        JournalOp.mkdir => Icons.create_new_folder_rounded,
        JournalOp.write => Icons.save_rounded,
        JournalOp.restore => Icons.restore_rounded,
        JournalOp.metadata => Icons.edit_note_rounded,
        JournalOp.split => Icons.call_split_rounded,
        JournalOp.merge => Icons.merge_rounded,
      };

  Color _opColor(JournalOp op) => switch (op) {
        JournalOp.delete => NexusColors.danger,
        JournalOp.restore => NexusColors.ok,
        _ => NexusColors.info,
      };
}

class _UndoCard extends StatelessWidget {
  const _UndoCard({
    required this.label,
    required this.desc,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String? desc;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: enabled
            ? (dark ? NexusColors.surface2Dark : NexusColors.surface2Light)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Icon(
                  label == 'UNDO'
                      ? Icons.undo_rounded
                      : Icons.redo_rounded,
                  size: 18,
                  color: enabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: Theme.of(context).textTheme.labelSmall),
                      Text(
                        desc ?? (label == 'UNDO' ? 'Nothing to undo' : 'Nothing to redo'),
                        style: TextStyle(
                            fontSize: 12,
                            color: enabled
                                ? (dark ? NexusColors.textDark : NexusColors.textLight)
                                : Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
