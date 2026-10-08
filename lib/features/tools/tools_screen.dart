/// Tools hub — every heavy utility one hop away. Splitter and Merger run
/// inline here; the deeper studios navigate to their own routes.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/merge_service.dart';
import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show diffLeftProvider;

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = [
      (Icons.account_tree_rounded, 'Transform Pipeline',
          'Chain rename → case → move → compress actions and run them on any selection.',
          () => context.go('/tools/pipeline')),
      (Icons.call_split_rounded, 'Visual File Splitter',
          'Cut any file into sized or counted parts — with a live size preview.',
          () => _openSplitSheet(context)),
      (Icons.merge_rounded, 'Merge Files',
          'Combine PDFs, images, CSVs, text or binary parts back into one file.',
          () => _openMergeSheet(context, ref)),
      (Icons.auto_fix_high_rounded, 'Content-Aware Rename',
          'Scan EXIF / ID3 / document metadata and rename files by what they contain.',
          () => context.go('/tools/rename')),
      (Icons.difference_rounded, 'File Diff View',
          'Line and word level compare between any two files.', () {
        final sel = ref.read(tabsProvider).active.selection;
        if (sel.isNotEmpty) ref.read(diffLeftProvider.notifier).state = sel.first;
        context.go('/tools/diff');
      }),
      (Icons.sync_rounded, 'Live Folder Mirror',
          'Continuous two-way sync pairs with status and full-sync triggers.',
          () => context.go('/tools/mirror')),
      (Icons.send_rounded, 'File Teleport',
          'Send files across your LAN to other Nexus devices — no cloud.',
          () => context.go('/tools/teleport')),
      (Icons.auto_mode_rounded, 'Automation Studio',
          'Macros, watchdogs, schedules, templates, auto-versioning, rules & metadata.',
          () => context.go('/tools/automation')),
      (Icons.history_rounded, 'Auto Versioning',
          'Browse and restore snapshots kept for versioned files.',
          () => context.go('/tools/versions')),
    ];

    return ToolScaffold(
      title: 'Tools',
      subtitle: 'Heavy machinery — pipelines, transforms, transfers and automation.',
      icon: Icons.home_repair_service_rounded,
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 900 ? 3 : (box.maxWidth > 620 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) {
            final (icon, title, desc, onTap) = cards[i];
            return _ToolCard(
                icon: icon, title: title, desc: desc, onTap: onTap);
          },
        );
      }),
    );
  }

  static void _openSplitSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SplitSheet(),
    );
  }

  static void _openMergeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MergeSheet(),
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover
                  ? Theme.of(context).colorScheme.primary.withOpacity( 0.6)
                  : dark
                      ? NexusColors.borderDark
                      : NexusColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity( 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon,
                    size: 20, color: Theme.of(context).colorScheme.primary),
              ),
              const Spacer(),
              Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(widget.desc,
                  style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Splitter sheet ──────────────────────────────────────────────────────────

class _SplitSheet extends ConsumerStatefulWidget {
  const _SplitSheet();

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  final _pathCtrl = TextEditingController();
  double _mode = 0; // 0 = parts, 1 = custom size marker
  double _parts = 2;
  double _mb = 10;
  String _result = '';
  bool _running = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    final tab = ref.watch(tabsProvider.select((s) => s.active));
    if (_pathCtrl.text.isEmpty && ref.read(dirProvider).entries.isNotEmpty) {
      final sel = tab.selection;
      if (sel.isNotEmpty) _pathCtrl.text = sel.first;
    }

    return Padding(
      padding: EdgeInsets.only(
          left: 22, right: 22, bottom: MediaQuery.viewPaddingOf(context).bottom + 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Visual File Splitter',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Split any file into parts. Reassemble later with Merge Files.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _pathCtrl,
              decoration: const InputDecoration(
                  labelText: 'File path', hintText: '/path/to/file'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Into N parts'),
                  selected: _mode == 0,
                  onSelected: (_) => setState(() => _mode = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('At byte marker'),
                  selected: _mode == 1,
                  onSelected: (_) => setState(() => _mode = 1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_mode == 0)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: 2,
                      max: 24,
                      divisions: 22,
                      value: _parts,
                      label: '${_parts.round()} parts',
                      onChanged: (v) => setState(() => _parts = v),
                    ),
                  ),
                  SizedBox(
                      width: 90,
                      child: Text('${_parts.round()} parts',
                          style: Theme.of(context).textTheme.titleSmall)),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 512,
                      divisions: 511,
                      value: _mb,
                      label: '${_mb.round()} MB',
                      onChanged: (v) => setState(() => _mb = v),
                    ),
                  ),
                  SizedBox(
                      width: 90,
                      child: Text('${_mb.round()} MB',
                          style: Theme.of(context).textTheme.titleSmall)),
                ],
              ),
            if (_running)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(value: _progress),
              ),
            if (_result.isNotEmpty) ...[
              Text(_result, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.call_split_rounded),
              label: const Text('Split file'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() => _result = 'Pick an existing file first.');
      return;
    }
    setState(() {
      _running = true;
      _result = '';
      _progress = 0;
    });
    try {
      final parts = await ref.read(servicesProvider).split.split(
            path: path,
            destDir: pu.dirname(path),
            parts: _mode == 0 ? _parts.round() : 0,
            marker: _mode == 1 ? (_mb * 1024 * 1024).round() : -1,
            onProgress: (frac, _) => setState(() => _progress = frac),
          );
      setState(() {
        _result = 'Created ${parts.length} parts:\n${parts.map(pu.basename).join('\n')}';
      });
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      setState(() => _result = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

// ── Merger sheet ────────────────────────────────────────────────────────────

class _MergeSheet extends ConsumerStatefulWidget {
  const _MergeSheet();

  @override
  ConsumerState<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends ConsumerState<_MergeSheet> {
  final _items = <String>[];
  MergeMode _mode = MergeMode.text;
  bool _running = false;
  String _result = '';

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(dirProvider.select((s) => s.entries));

    return Padding(
      padding: EdgeInsets.only(
          left: 22, right: 22, bottom: MediaQuery.viewPaddingOf(context).bottom + 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Merge Files', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Order matters — pick files from the current folder, then merge.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in entries.where((e) => !e.isDir).take(24))
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 14),
                    label: Text(e.name, style: const TextStyle(fontSize: 11.5)),
                    onPressed: () => setState(() => _items.add(e.path)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Text('Nothing queued yet.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 170),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  onReorder: (a, b) => setState(() {
                    if (b > a) b--;
                    final it = _items.removeAt(a);
                    _items.insert(b, it);
                  }),
                  itemBuilder: (context, i) => ListTile(
                    key: ValueKey(_items[i]),
                    dense: true,
                    leading: const Icon(Icons.drag_indicator_rounded, size: 15),
                    title: Text(pu.basename(_items[i]),
                        style: const TextStyle(fontSize: 12.5)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14),
                      onPressed: () => setState(() => _items.removeAt(i)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<MergeMode>(
              value: _mode,
              items: const [
                DropdownMenuItem(value: MergeMode.text, child: Text('Text — join with newline')),
                DropdownMenuItem(value: MergeMode.csv, child: Text('CSV / TSV — append rows')),
                DropdownMenuItem(value: MergeMode.imageVertical, child: Text('Images — stack vertically')),
                DropdownMenuItem(value: MergeMode.imageHorizontal, child: Text('Images — side by side')),
                DropdownMenuItem(value: MergeMode.pdf, child: Text('PDF — append pages')),
                DropdownMenuItem(value: MergeMode.binary, child: Text('Binary — raw concat (rejoin parts)')),
              ],
              onChanged: (v) => setState(() => _mode = v ?? MergeMode.text),
            ),
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            if (_result.isNotEmpty) ...[
              Text(_result, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _running || _items.isEmpty ? null : _run,
              icon: const Icon(Icons.merge_rounded),
              label: Text(_items.isEmpty ? 'Merge files' : 'Merge ${_items.length} files'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = '';
    });
    try {
      final detected = MergeService.detect(_items);
      final outBase = pu.join(
          pu.dirname(_items.first), 'merged-${DateTime.now().millisecondsSinceEpoch}');
      final outputPath = switch (detected) {
        MergeMode.pdf => '$outBase.pdf',
        MergeMode.imageVertical || MergeMode.imageHorizontal => '$outBase.png',
        MergeMode.csv => '$outBase.csv',
        MergeMode.binary => '$outBase.bin',
        _ => '$outBase.txt',
      };
      await ref.read(servicesProvider).merge.merge(
            paths: _items,
            mode: _mode,
            outputPath: outputPath,
          );
      setState(() =>
          _result = 'Merged into ${pu.basename(outputPath)} (${f.formatSize(File(outputPath).lengthSync())})');
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      setState(() => _result = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
