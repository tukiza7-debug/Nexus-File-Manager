/// Live Folder Mirror — continuous two-way sync pairs. Status per pair,
/// manual full sync, and instant propagation via filesystem watchers.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';

class MirrorScreen extends ConsumerWidget {
  const MirrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = ref.watch(mirrorsProvider);
    final svc = ref.read(servicesProvider);

    return ToolScaffold(
      title: 'Live Folder Mirror',
      subtitle:
          'Two-way pairs that stay identical while you work — changes propagate instantly.',
      icon: Icons.sync_rounded,
      actions: [
        FilledButton.icon(
          onPressed: () => _addPair(context, ref),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('New pair'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pairs.isEmpty)
            const EmptyState(
              icon: Icons.sync_rounded,
              title: 'No mirror pairs yet',
              message:
                  'Pick two folders and Nexus keeps them in lockstep: edits on either side copy across, deletions propagate, and every action lands in the Paper Trail. Perfect for a working folder and its twin on another drive.',
            ),
          for (final m in pairs)
            NexusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        size: 17,
                        color: svc.mirrors.statusFor(m.id!) == 'syncing'
                            ? NexusColors.info
                            : NexusColors.ok,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(m.name,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      _StatusChip(status: svc.mirrors.statusFor(m.id!)),
                      const SizedBox(width: 8),
                      Switch(
                        value: m.enabled,
                        onChanged: (v) {
                          svc.db.saveMirror(m.copyWith(enabled: v));
                          if (v) {
                            svc.mirrors.start(m);
                          } else {
                            svc.mirrors.stop(m.id!);
                          }
                          _bump(ref);
                        },
                      ),
                      IconButton(
                        tooltip: 'Full sync now',
                        icon: const Icon(Icons.double_arrow_rounded, size: 18),
                        onPressed: () async {
                          toast(ref, 'Full sync running…');
                          await svc.mirrors.fullSync(m);
                          toast(ref, 'Full sync complete');
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove pair',
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        onPressed: () async {
                          if (!await confirmDialog(context,
                              title: 'Remove mirror pair?',
                              message:
                                  'Files stay untouched — the automatic sync just stops.',
                              danger: true)) {
                            return;
                          }
                          await svc.mirrors.stop(m.id!);
                          svc.db.deleteMirror(m.id!);
                          _bump(ref);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _PathCard(path: m.source, tag: 'SOURCE'),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.swap_horiz_rounded, size: 18,
                            color: NexusColors.blueSoft),
                      ),
                      Expanded(
                        child: _PathCard(path: m.target, tag: 'TARGET'),
                      ),
                    ],
                  ),
                  if (m.lastSyncMs != null) ...[
                    const SizedBox(height: 8),
                    Text('Last sync ${f.formatRelative(
                        DateTime.fromMillisecondsSinceEpoch(m.lastSyncMs!))}',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addPair(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(servicesProvider);
    final current = ref.read(tabsProvider).active.path;
    final name = await promptDialog(context,
        title: 'Mirror pair name', initial: 'My twin folders');
    if (name == null || !context.mounted) return;
    final source = await promptDialog(context,
        title: 'Source folder', initial: current);
    if (source == null || !context.mounted) return;
    final target = await promptDialog(context,
        title: 'Target folder', hint: '/path/to/twin');
    if (target == null) return;

    await Directory(source).create(recursive: true);
    await Directory(target).create(recursive: true);
    final pair = MirrorPair(name: name, source: source, target: target, enabled: true);
    svc.db.saveMirror(pair);
    _bump(ref);
    await svc.mirrors.start(MirrorPair(
        id: svc.db.mirrors().last.id,
        name: name,
        source: source,
        target: target,
        enabled: true));
    toast(ref, 'Mirror “$name” live');
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'syncing' => (NexusColors.info, 'syncing'),
      'error' => (NexusColors.danger, 'error'),
      'live' => (NexusColors.ok, 'live'),
      _ => (Colors.grey, 'idle'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha:  0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({required this.path, required this.tag});

  final String path;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: dark ? NexusColors.surface2Dark : NexusColors.surface2Light,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tag, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(path,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
