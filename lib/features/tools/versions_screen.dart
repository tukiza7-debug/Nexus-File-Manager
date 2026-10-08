/// Auto Versioning — browse every file with snapshots, inspect versions and
/// restore any of them as a new undoable operation.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../state/app_state.dart';

class VersionsScreen extends ConsumerStatefulWidget {
  const VersionsScreen({super.key});

  @override
  ConsumerState<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends ConsumerState<VersionsScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final paths = ref.watch(versionedPathsProvider);
    final svc = ref.read(servicesProvider);

    return ToolScaffold(
      title: 'Auto Versioning',
      subtitle:
          'Every saved edit keeps a snapshot. Browse, diff mentally, restore in one tap.',
      icon: Icons.history_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Versioning ${svc.versioning.enabled ? 'is on' : 'is off'} — keeping ${svc.versioning.retention} snapshots per file. Configure in Settings.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (paths.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No versioned files yet',
              message:
                  'When a watched file changes, Nexus quietly snapshots the previous copy. Overwrite a document a few times and its whole history appears here — restore any point instantly.',
            ),
          SideBySide(
            left: NexusPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in paths)
                    ListTile(
                      dense: true,
                      selected: _selected == p,
                      leading: Icon(
                          FileSystemEntity.isDirectorySync(p)
                              ? Icons.folder_rounded
                              : Icons.description_outlined,
                          size: 17),
                      title: Text(pu.basename(p),
                          style: const TextStyle(fontSize: 12.5)),
                      subtitle: Text(pu.compactPath(p),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(
                          '${svc.versioning.versionsFor(p).length} versions',
                          style: Theme.of(context).textTheme.labelSmall),
                      onTap: () => setState(() => _selected = p),
                    ),
                ],
              ),
            ),
            right: _selected == null
                ? const EmptyState(
                    icon: Icons.touch_app_rounded,
                    title: 'Pick a file',
                    message: 'Select a versioned file to see its snapshot history.',
                  )
                : _VersionList(path: _selected!),
          ),
        ],
      ),
    );
  }
}

class _VersionList extends ConsumerWidget {
  const _VersionList({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(servicesProvider);
    final versions = svc.versioning.versionsFor(path)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    if (versions.isEmpty) {
      return const EmptyState(
          icon: Icons.hourglass_empty_rounded,
          title: 'No snapshots',
          message: 'This file has no snapshots stored.');
    }

    return NexusPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final v in versions)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history_rounded, size: 16),
              title: Text(
                f.formatDateTime(DateTime.fromMillisecondsSinceEpoch(v.createdAtMs)),
                style: const TextStyle(fontSize: 12.5),
              ),
              subtitle: Text(f.formatSize(v.size),
                  style: Theme.of(context).textTheme.bodySmall),
              trailing: TextButton(
                onPressed: () async {
                  if (!await confirmDialog(context,
                      title: 'Restore this version?',
                      message:
                          'The current file is snapshotted first, so this restore is itself undoable.',
                      confirmLabel: 'Restore')) {
                    return;
                  }
                  await svc.versioning.restore(v);
                  toast(ref, 'Restored ${pu.basename(v.originalPath)}');
                  ref.read(journalProvider.notifier).reload();
                },
                child: const Text('Restore'),
              ),
            ),
        ],
      ),
    );
  }
}
