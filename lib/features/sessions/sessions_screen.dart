/// Work Sessions — full-state save/restore: open tabs, paths, selections,
/// sort and view modes. Plus autosave recovery on startup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format_utils.dart' as f;
import '../../core/widgets/widgets.dart';
import '../../state/app_state.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final svc = ref.read(servicesProvider);
    final named = sessions.where((s) => !s.name.startsWith('__')).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    final autosave = svc.sessions.autosave();

    return ToolScaffold(
      title: 'Work Sessions',
      subtitle:
          'Snapshot the entire workspace — every tab, folder, selection and view state.',
      icon: Icons.bookmark_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sessions restore exactly where you were: which folders were open, what was selected, how it was sorted. The autosave recovers your last workspace even after a crash.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _save(context, ref),
                icon: const Icon(Icons.save_rounded, size: 17),
                label: const Text('Save current session'),
              ),
            ],
          ),
          if (autosave != null && ((autosave['tabs'] as List?)?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 14),
            NexusPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 17, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Autosave from your last session — ${(autosave['tabs'] as List).length} tab(s), recovered automatically at startup.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(tabsProvider.notifier).restore(autosave);
                      toast(ref, 'Last session restored');
                    },
                    child: const Text('Restore again'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (named.isEmpty)
            const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No named sessions',
              message:
                  'Create one per context: “Client A work”, “Photo triage”, “Weekend cleanup”. Switch with Ctrl Shift S from anywhere — or from the command palette.',
            ),
          for (final s in named)
            NexusPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.bookmark_rounded,
                      size: 17, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          '${((s.payload['tabs'] as List?) ?? const []).length} tab(s) · saved ${f.formatDateTime(
                              DateTime.fromMillisecondsSinceEpoch(s.updatedAtMs))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.read(tabsProvider.notifier).restore(s.payload);
                      toast(ref, 'Session “${s.name}” restored');
                    },
                    icon: const Icon(Icons.restore_rounded, size: 15),
                    label: const Text('Restore'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Overwrite with current workspace',
                    icon: const Icon(Icons.sync_rounded, size: 17),
                    onPressed: () {
                      svc.sessions.save(
                          s.name, ref.read(tabsProvider.notifier).payload());
                      _bump(ref);
                      toast(ref, '“${s.name}” updated');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    onPressed: () {
                      svc.sessions.delete(s.name);
                      _bump(ref);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final name = await promptDialog(context,
        title: 'Save work session',
        hint: 'Session name',
        icon: Icons.bookmark_add_outlined);
    if (name == null) return;
    ref
        .read(servicesProvider)
        .sessions
        .save(name, ref.read(tabsProvider.notifier).payload());
    _bump(ref);
    toast(ref, 'Session “$name” saved');
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
