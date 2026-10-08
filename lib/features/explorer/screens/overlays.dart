/// Interactive overlays: entry/directory context menus, the Smart Paste
/// conflict dialog, command palette (Ctrl K) and the quick session switcher.
library;


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/smart_paste.dart';
import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/format_utils.dart' as f;
import '../../../core/utils/fuzzy.dart';
import '../../../core/utils/path_utils.dart' as pu;
import '../../../core/widgets/widgets.dart';
import '../../../domain/enums.dart';
import '../../../domain/models.dart';
import '../../../state/app_state.dart';

class Overlays {
  const Overlays._();

  // ── Selection helpers ─────────────────────────────────────────────────────

  static List<String> _selection(WidgetRef ref) =>
      ref.read(tabsProvider).active.selection.toList();

  static void copySelection(BuildContext context, WidgetRef ref) =>
      _stack(ref, ClipOp.copy);

  static void cutSelection(BuildContext context, WidgetRef ref) =>
      _stack(ref, ClipOp.cut);

  static void _stack(WidgetRef ref, ClipOp op) {
    final sel = _selection(ref);
    if (sel.isEmpty) return;
    final svc = ref.read(servicesProvider);
    for (final p in sel) {
      svc.clipboard.push(op, p);
    }
    ref.read(tabsProvider.notifier).refresh();
    toast(ref,
        '${sel.length} item(s) ${op == ClipOp.copy ? 'copied' : 'cut'} — stacked');
  }

  static void selectAllVisible(BuildContext context, WidgetRef ref) {
    final entries = ref.read(dirProvider).entries;
    ref.read(tabsProvider.notifier).selectAll(entries.map((e) => e.path).toList());
  }

  // ── Smart paste ───────────────────────────────────────────────────────────

  static Future<void> showSmartPasteDialog(
    BuildContext context,
    WidgetRef ref, {
    required String destDir,
  }) async {
    final svc = ref.read(servicesProvider);
    final stack = svc.clipboard.items;
    final sources = [for (final e in stack) e.path];
    if (sources.isEmpty) {
      toast(ref, 'Clipboard stack is empty');
      return;
    }
    final isCut = stack.isNotEmpty && stack.every((e) => e.op == ClipOp.cut);

    final plan = await svc.smartPaste.plan(
      sources: sources,
      isCut: isCut,
      destDir: destDir,
      defaultStrategy: ConflictStrategy.ask,
    );

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SmartPasteDialog(plan: plan),
    );
    if (ok != true) return;

    final batch = svc.journal.newBatch(isCut ? 'smart-move' : 'smart-copy');
    try {
      await svc.smartPaste.execute(plan, svc.ops, batch);
      if (isCut) {
        // Paste consumes the stack on move semantics.
        svc.clipboard.clear();
      }
      svc.ops.finish(batch);
      toast(ref, 'Pasted ${plan.decisions.where((d) => d.resolved != ConflictStrategy.skip).length} item(s)');
    } catch (e) {
      toast(ref, '$e', error: true);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  // ── Delete / rename ───────────────────────────────────────────────────────

  static Future<void> deletePaths(
    BuildContext context,
    WidgetRef ref,
    List<String> paths, {
    required String currentPath,
    bool permanent = false,
  }) async {
    if (paths.isEmpty) return;
    final svc = ref.read(servicesProvider);
    final violations = svc.freeze.violations(paths);
    if (violations.isNotEmpty) {
      toast(ref,
          'Blocked: ${pu.basename(violations.first)} is frozen (Secure Freeze)');
      return;
    }
    final label = paths.length == 1
        ? '“${pu.basename(paths.first)}”'
        : '${paths.length} items';
    if (!await confirmDialog(
      context,
      title: permanent ? 'Delete permanently?' : 'Delete $label?',
      message: permanent
          ? 'Files are removed for good — this cannot be undone.'
          : 'You can undo this from the Paper Trail (Ctrl Z).',
      confirmLabel: permanent ? 'Delete forever' : 'Move to backup & delete',
      danger: true,
    )) {
      return;
    }
    final batch = svc.journal.newBatch('delete');
    try {
      await svc.ops.deletePaths(paths, batchId: batch);
      svc.ops.finish(batch);
      _macro(ref, 'delete', {'paths': paths});
      ref.read(tabsProvider.notifier).clearSelection();
      toast(ref, 'Deleted $label');
    } catch (e) {
      toast(ref, '$e', error: true);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  static Future<void> renameSingle(
      BuildContext context, WidgetRef ref, String path) async {
    final svc = ref.read(servicesProvider);
    if (svc.freeze.isFrozen(path)) {
      toast(ref, 'Blocked: item is frozen', error: true);
      return;
    }
    final newName = await promptDialog(context,
        title: 'Rename',
        initial: pu.basename(path),
        icon: Icons.drive_file_rename_outline_rounded);
    if (newName == null || newName == pu.basename(path)) return;
    final batch = svc.journal.newBatch('rename');
    try {
      await svc.ops.rename(path, pu.join(pu.dirname(path), newName), batchId: batch);
      svc.ops.finish(batch);
      _macro(ref, 'rename', {'from': path, 'to': pu.join(pu.dirname(path), newName)});
      toast(ref, 'Renamed to $newName');
    } catch (e) {
      toast(ref, '$e', error: true);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  // ── Action zone dispatcher ────────────────────────────────────────────────

  static Future<void> runAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return;
    final svc = ref.read(servicesProvider);
    final dest = ref.read(tabsProvider).active.path;
    switch (action) {
      case 'copy':
        final batch = svc.journal.newBatch('copy');
        await svc.ops.copyPaths(paths, dest, batchId: batch);
        svc.ops.finish(batch);
        _macro(ref, 'copy', {'sources': paths, 'dest': dest});
        toast(ref, 'Copied ${paths.length} item(s)');
      case 'move':
        final batch = svc.journal.newBatch('move');
        await svc.ops.movePaths(paths, dest, batchId: batch);
        svc.ops.finish(batch);
        _macro(ref, 'move', {'sources': paths, 'dest': dest});
        toast(ref, 'Moved ${paths.length} item(s)');
      case 'zip':
        final name = await promptDialog(context,
            title: 'Compress selection', initial: 'archive.zip');
        if (name == null) return;
        final batch = svc.journal.newBatch('compress');
        final zipPath = await svc.ops.compressToZip(
            paths, pu.join(dest, name),
            batchId: batch);
        svc.ops.finish(batch);
        toast(ref, 'Created ${pu.basename(zipPath)}');
      case 'freeze':
        for (final p in paths) {
          await svc.freeze.freeze(p, note: 'From action zone');
        }
        _bump(ref);
        toast(ref, 'Frozen ${paths.length} item(s)');
      case 'teleport':
        ref.read(teleportPendingProvider.notifier).state = paths;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose a peer to send to')));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (context.mounted) _go(context, '/tools/teleport');
      case 'pipeline':
        ref.read(pipelinePendingProvider.notifier).state = paths;
        if (context.mounted) _go(context, '/tools/pipeline');
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  static void _go(BuildContext context, String loc) {
    context.go(loc);
  }

  /// Macro recorder hook — no-ops unless a recording is in progress.
  static void _macro(WidgetRef ref, String action, Map<String, dynamic> args) {
    final macros = ref.read(servicesProvider).macros;
    if (macros.recording) macros.record(action, args);
  }

  // ── Entry context menu ────────────────────────────────────────────────────

  static Future<void> showEntryMenu(
    BuildContext context,
    WidgetRef ref,
    NexusEntry entry,
    Offset position,
  ) async {
    final svc = ref.read(servicesProvider);
    final frozen = svc.freeze.isFrozen(entry.path);
    final isZip = entry.ext == 'zip';

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 8, 8),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        const PopupMenuItem(
            value: 'peek',
            child: Text('Peek preview',
                style: TextStyle(fontSize: 13))),
        const PopupMenuItem(value: 'inspector', child: Text('Floating inspector')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy', child: Text('Copy')),
        const PopupMenuItem(value: 'cut', child: Text('Cut')),
        if (entry.isDir)
          const PopupMenuItem(value: 'paste', child: Text('Paste into folder')),
        const PopupMenuItem(value: 'rename', child: Text('Rename  (F2)')),
        const PopupMenuItem(value: 'delete', child: Text('Delete  (Del)')),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'freeze',
            child: Text(frozen ? 'Unfreeze (Secure Freeze)' : 'Freeze (Secure Freeze)')),
        const PopupMenuItem(value: 'version', child: Text('Snapshot version')),
        const PopupMenuItem(value: 'meta', child: Text('Edit metadata')),
        const PopupMenuItem(value: 'diff', child: Text('Compare (Diff)…')),
        const PopupMenuItem(value: 'zip', child: Text('Compress to ZIP')),
        if (isZip) const PopupMenuItem(value: 'unzip', child: Text('Extract here')),
        const PopupMenuItem(value: 'teleport', child: Text('Send via Teleport')),
        const PopupMenuItem(value: 'pipeline', child: Text('Run pipeline…')),
        const PopupMenuItem(value: 'tunnel', child: Text('Focus on this')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'pin', child: Text('Pin to edge dock')),
        if (entry.isDir) const PopupMenuItem(value: 'alias', child: Text('Alias this folder')),
        const PopupMenuItem(value: 'trail', child: Text('Paper trail')),
        const PopupMenuItem(value: 'sysopen', child: Text('Open with system')),
      ],
    );
    if (action == null || !context.mounted) return;
    await _dispatchEntry(context, ref, action, entry);
  }

  static Future<void> _dispatchEntry(
    BuildContext context,
    WidgetRef ref,
    String action,
    NexusEntry entry,
  ) async {
    final svc = ref.read(servicesProvider);
    final ui = ref.read(uiProvider.notifier);
    switch (action) {
      case 'open':
        _openEntry(context, ref, entry);
      case 'peek':
        ui.setPeek(entry.path);
      case 'inspector':
        ui.setInspector(entry.path);
      case 'copy':
        svc.clipboard.push(ClipOp.copy, entry.path);
        toast(ref, 'Copied ${entry.name}');
      case 'cut':
        svc.clipboard.push(ClipOp.cut, entry.path);
        toast(ref, 'Cut ${entry.name}');
      case 'paste':
        await showSmartPasteDialog(context, ref, destDir: entry.path);
      case 'rename':
        await renameSingle(context, ref, entry.path);
      case 'delete':
        await deletePaths(context, ref, [entry.path], currentPath: entry.parent);
      case 'freeze':
        if (svc.freeze.isFrozen(entry.path)) {
          await svc.freeze.unfreeze(entry.path);
          toast(ref, 'Unfrozen ${entry.name}');
        } else {
          await svc.freeze.freeze(entry.path);
          toast(ref, 'Frozen ${entry.name}');
        }
        _bump(ref);
      case 'version':
        final snap = await svc.versioning.snapshot(entry.path);
        toast(ref, snap == null ? 'Nothing to snapshot' : 'Version saved');
      case 'meta':
        ref.read(metaEditTargetProvider.notifier).state = entry.path;
        _go(context, '/tools/automation');
      case 'diff':
        ref.read(diffLeftProvider.notifier).state = entry.path;
        _go(context, '/tools/diff');
      case 'zip':
        final batch = svc.journal.newBatch('compress');
        await svc.ops.compressToZip([entry.path],
            pu.join(entry.parent, '${entry.name}.zip'),
            batchId: batch);
        svc.ops.finish(batch);
        toast(ref, 'Created ${entry.name}.zip');
      case 'unzip':
        final batch = svc.journal.newBatch('extract');
        await svc.ops.extractZip(entry.path, entry.parent, batchId: batch);
        svc.ops.finish(batch);
        toast(ref, 'Extracted ${entry.name}');
      case 'teleport':
        ref.read(teleportPendingProvider.notifier).state = [entry.path];
        _go(context, '/tools/teleport');
      case 'pipeline':
        ref.read(pipelinePendingProvider.notifier).state = [entry.path];
        _go(context, '/tools/pipeline');
      case 'tunnel':
        ui.setFocusTunnel(entry.path);
      case 'pin':
        final prefs = svc.prefs;
        final edge = prefs.getString('dock.edge') ?? 'left';
        svc.db.pin(entry.path, entry.name, edge, DateTime.now().millisecond);
        _bump(ref);
        toast(ref, 'Pinned to $edge dock');
      case 'alias':
        final name = await promptDialog(context,
            title: 'Alias this folder',
            initial: entry.name,
            icon: Icons.label_outline_rounded);
        if (name != null) {
          svc.db.upsertAlias(name, entry.path);
          _bump(ref);
        }
      case 'trail':
        ref.read(journalFocusPathProvider.notifier).state = entry.path;
        _go(context, '/papertrail');
      case 'sysopen':
        await svc.fs.openWithSystem(entry.path);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  static void _openEntry(BuildContext context, WidgetRef ref, NexusEntry entry) {
    if (entry.isDir) {
      ref.read(tabsProvider.notifier).navigate(entry.path);
    } else {
      ref.read(servicesProvider).fs.openWithSystem(entry.path);
    }
  }

  // ── Directory background menu ─────────────────────────────────────────────

  static Future<void> showDirMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final tab = ref.read(tabsProvider).active;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 8, 8),
      items: [
        const PopupMenuItem(value: 'paste', child: Text('Paste stack here')),
        const PopupMenuItem(value: 'newfolder', child: Text('New folder')),
        const PopupMenuItem(value: 'newtext', child: Text('New text file')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'sortname', child: Text('Sort · Name')),
        const PopupMenuItem(value: 'sortsize', child: Text('Sort · Size')),
        const PopupMenuItem(value: 'sortmod', child: Text('Sort · Modified')),
        const PopupMenuItem(value: 'sorttype', child: Text('Sort · Type')),
        const PopupMenuItem(value: 'viewgrid', child: Text('View · Grid')),
        const PopupMenuItem(value: 'viewlist', child: Text('View · List')),
        const PopupMenuItem(value: 'spatial', child: Text('Spatial memory view')),
        const PopupMenuItem(value: 'split', child: Text('Split by type')),
        const PopupMenuItem(value: 'hidden', child: Text('Toggle hidden files')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'selectall', child: Text('Select all')),
        const PopupMenuItem(value: 'freezeinfo', child: Text('Freeze this folder')),
      ],
    );
    if (action == null || !context.mounted) return;
    final svc = ref.read(servicesProvider);
    final notifier = ref.read(tabsProvider.notifier);
    switch (action) {
      case 'paste':
        await showSmartPasteDialog(context, ref, destDir: tab.path);
      case 'newfolder':
        final name = await promptDialog(context,
            title: 'New folder', initial: 'New Folder');
        if (name != null) {
          final batch = svc.journal.newBatch('mkdir');
          await svc.ops.mkdir(pu.join(tab.path, name), batchId: batch);
          svc.ops.finish(batch);
          Overlays._macro(ref, 'mkdir', {'path': pu.join(tab.path, name)});
        }
      case 'newtext':
        final name = await promptDialog(context,
            title: 'New text file', initial: 'untitled.txt');
        if (name != null) {
          final batch = svc.journal.newBatch('write');
          await svc.ops.writeText(pu.join(tab.path, name), '', batchId: batch);
          svc.ops.finish(batch);
        }
      case 'sortname':
        notifier.setSort(SortBy.name, SortDir.asc);
      case 'sortsize':
        notifier.setSort(SortBy.size, SortDir.desc);
      case 'sortmod':
        notifier.setSort(SortBy.modified, SortDir.desc);
      case 'sorttype':
        notifier.setSort(SortBy.type, SortDir.asc);
      case 'viewgrid':
        notifier.setViewMode(ViewMode.grid);
      case 'viewlist':
        notifier.setViewMode(ViewMode.list);
      case 'spatial':
        notifier.setSpatial(!tab.spatialMode);
      case 'split':
        ref.read(uiProvider.notifier).toggleSplitType();
      case 'hidden':
        ref.read(uiProvider.notifier).toggleHidden();
      case 'selectall':
        selectAllVisible(context, ref);
      case 'freezeinfo':
        await svc.freeze.freeze(tab.path, note: 'Folder frozen');
        _bump(ref);
        toast(ref, 'Folder frozen');
    }
    ref.read(tabsProvider.notifier).refresh();
  }
}

// Pending-target providers shared between explorer actions and tool screens.
final teleportPendingProvider = StateProvider<List<String>>((ref) => const []);
final pipelinePendingProvider = StateProvider<List<String>>((ref) => const []);
final metaEditTargetProvider = StateProvider<String>((ref) => '');
final diffLeftProvider = StateProvider<String>((ref) => '');
final journalFocusPathProvider = StateProvider<String>((ref) => '');

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}

// ── Smart paste dialog ──────────────────────────────────────────────────────

class _SmartPasteDialog extends StatefulWidget {
  const _SmartPasteDialog({required this.plan});

  final PastePlan plan;

  @override
  State<_SmartPasteDialog> createState() => _SmartPasteDialogState();
}

class _SmartPasteDialogState extends State<_SmartPasteDialog> {
  late ConflictStrategy _default = ConflictStrategy.keepBoth;
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.plan.decisions.where((d) => d.conflict).length;
    return AlertDialog(
      icon: const Icon(Icons.content_paste_go_rounded),
      title: Text(widget.plan.isCut ? 'Smart Paste — Move' : 'Smart Paste — Copy'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.plan.decisions.length} item(s) → ${pu.compactPath(widget.plan.destDir)}'
              '${conflicts > 0 ? '  ·  $conflicts conflict(s)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (conflicts > 0) ...[
              Row(
                children: [
                  Text('Resolve conflicts', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  for (final s in const [
                    ConflictStrategy.overwrite,
                    ConflictStrategy.keepBoth,
                    ConflictStrategy.skip,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(switch (s) {
                          ConflictStrategy.overwrite => 'Overwrite',
                          ConflictStrategy.keepBoth => 'Keep both',
                          ConflictStrategy.skip => 'Skip',
                          _ => s.name,
                        }),
                        selected: _default == s,
                        onSelected: (_) => setState(() {
                          _default = s;
                          _touched = true;
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final d in widget.plan.decisions)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          d.conflict
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 17,
                          color: d.conflict ? NexusColors.warn : NexusColors.ok,
                        ),
                        title: Text(d.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          d.conflict
                              ? 'conflict → ${switch (_resolve(d)) {
                                  ConflictStrategy.overwrite => 'overwrite existing',
                                  ConflictStrategy.keepBoth => 'save as copy (2)',
                                  ConflictStrategy.skip => 'skip',
                                  _ => 'resolve',
                                }}'
                              : pu.compactPath(d.target),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(_touched || conflicts == 0
              ? 'Paste ${widget.plan.decisions.where((d) => _resolve(d) != ConflictStrategy.skip).length}'
              : 'Choose a strategy'),
        ),
      ],
    );
  }

  ConflictStrategy _resolve(PasteDecision d) =>
      d.conflict ? _default : ConflictStrategy.overwrite;
}

// ── Command palette ─────────────────────────────────────────────────────────

class _PaletteItem {
  const _PaletteItem(this.title, this.subtitle, this.run, {this.icon});
  final String title;
  final String subtitle;
  final IconData? icon;
  final void Function(BuildContext, WidgetRef) run;
}

class CommandPaletteDialog extends ConsumerStatefulWidget {
  const CommandPaletteDialog({super.key});

  @override
  ConsumerState<CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<CommandPaletteDialog> {
  String _q = '';
  int _selected = 0;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<_PaletteItem> _buildItems() {
    final ref = this.ref;
    final items = <_PaletteItem>[
      _PaletteItem('Go home', 'Navigate', (_, r) => r.read(tabsProvider.notifier).home(),
          icon: Icons.home_rounded),
      _PaletteItem('Go up one level', 'Navigate',
          (_, r) => r.read(tabsProvider.notifier).up(),
          icon: Icons.arrow_upward_rounded),
      _PaletteItem('Toggle zen mode', 'View · F1',
          (c, r) => r.read(uiProvider.notifier).toggleZen(),
          icon: Icons.self_improvement_rounded),
      _PaletteItem('Toggle ghost mode', 'View · Ctrl G',
          (c, r) {
            final n = r.read(uiProvider.notifier);
            if (r.read(uiProvider).ghostOpacity >= 1.0) {
              n.restoreGhost();
            } else {
              n.solidGhost();
            }
          },
          icon: Icons.visibility_off_rounded),
      _PaletteItem('Toggle sidebar', 'View · Ctrl B',
          (c, r) => r.read(uiProvider.notifier).toggleSidebar(),
          icon: Icons.view_sidebar_rounded),
      _PaletteItem('Toggle hidden files', 'View · Ctrl H',
          (c, r) => r.read(uiProvider.notifier).toggleHidden(),
          icon: Icons.hide_source_rounded),
      _PaletteItem('Toggle split by type', 'View',
          (c, r) => r.read(uiProvider.notifier).toggleSplitType(),
          icon: Icons.view_agenda_rounded),
      _PaletteItem('Spatial memory view', 'View',
          (c, r) {
            final t = r.read(tabsProvider).active;
            r.read(tabsProvider.notifier).setSpatial(!t.spatialMode);
          },
          icon: Icons.hub_outlined),
      _PaletteItem('New folder', 'Create', (c, r) async {
        final tab = r.read(tabsProvider).active;
        final name = await promptDialog(c, title: 'New folder', initial: 'New Folder');
        if (name != null) {
          final svc = r.read(servicesProvider);
          final batch = svc.journal.newBatch('mkdir');
          await svc.ops.mkdir(pu.join(tab.path, name), batchId: batch);
          svc.ops.finish(batch);
          r.read(tabsProvider.notifier).refresh();
        }
      }, icon: Icons.create_new_folder_rounded),
      _PaletteItem('Paste stack here', 'Clipboard · Ctrl V',
          (c, r) => Overlays.showSmartPasteDialog(c, r,
              destDir: r.read(tabsProvider).active.path),
          icon: Icons.content_paste_go_rounded),
      _PaletteItem('Undo last batch', 'History · Ctrl Z', (c, r) async {
        final svc = r.read(servicesProvider);
        final batch = svc.journal.nextUndoBatch();
        if (batch == null) return;
        final desc = await svc.journal.undoBatch(batch,
            onError: (m) async => toast(r, m, error: true));
        toast(r, 'Undone · $desc');
        r.read(journalProvider.notifier).reload();
        r.read(tabsProvider.notifier).refresh();
      }, icon: Icons.undo_rounded),
      _PaletteItem('Start recording macro', 'Automation',
          (c, r) {
            r.read(servicesProvider).macros.startRecording();
            toast(r, 'Recording macro — perform actions, then stop in Automation');
          },
          icon: Icons.fiber_manual_record_rounded),
      _PaletteItem('Stop & save macro', 'Automation', (c, r) async {
        final svc = r.read(servicesProvider);
        final steps = svc.macros.stopRecording();
        if (steps.isEmpty) {
          toast(r, 'Macro is empty');
          return;
        }
        final name = await promptDialog(c, title: 'Save macro', hint: 'Macro name');
        if (name != null) {
          svc.macros.save(name, steps);
          _bump(r);
          toast(r, 'Macro “$name” saved');
        }
      }, icon: Icons.stop_circle_outlined),
      _PaletteItem('Open File Teleport', 'Tools', (c, r) => c.go('/tools/teleport'),
          icon: Icons.send_rounded),
      _PaletteItem('Open Transform Pipeline', 'Tools', (c, r) => c.go('/tools/pipeline'),
          icon: Icons.account_tree_rounded),
      _PaletteItem('Open Merge Files', 'Tools', (c, r) => c.go('/tools'),
          icon: Icons.merge_rounded),
      _PaletteItem('Open Content-Aware Rename', 'Tools',
          (c, r) => c.go('/tools/rename'),
          icon: Icons.auto_fix_high_rounded),
      _PaletteItem('Open Live Folder Mirror', 'Tools', (c, r) => c.go('/tools/mirror'),
          icon: Icons.sync_rounded),
      _PaletteItem('Open Paper Trail', 'History · every file op',
          (c, r) => c.go('/papertrail'),
          icon: Icons.history_rounded),
      _PaletteItem('Open Work Sessions', 'Save & restore everything',
          (c, r) => c.go('/sessions'),
          icon: Icons.bookmark_rounded),
      _PaletteItem('Open Settings', 'Appearance & behaviour',
          (c, r) => c.go('/settings'),
          icon: Icons.settings_rounded),
    ];

    // Aliases.
    for (final a in ref.read(aliasesProvider)) {
      items.add(_PaletteItem('Alias: ${a.name}', a.path,
          (c, r) => r.read(tabsProvider.notifier).navigate(a.path),
          icon: Icons.label_outline_rounded));
    }
    // Sessions (quick session switcher inside palette too).
    for (final s in ref.read(sessionsProvider).where((s) => !s.name.startsWith('__'))) {
      items.add(_PaletteItem('Session: ${s.name}', 'Restore work session',
          (c, r) {
            r.read(tabsProvider.notifier).restore(s.payload);
            toast(r, 'Session “${s.name}” restored');
          },
          icon: Icons.bookmark_added_rounded));
    }
    // Files in current folder.
    for (final e in ref.read(dirProvider).entries.take(40)) {
      items.add(_PaletteItem(e.name, e.isDir ? 'Open folder' : 'Peek file',
          (c, r) {
            if (e.isDir) {
              r.read(tabsProvider.notifier).navigate(e.path);
            } else {
              r.read(uiProvider.notifier).setPeek(e.path);
            }
          },
          icon: e.isDir ? Icons.folder_rounded : Icons.description_outlined));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final all = _buildItems();
    final matches = _q.isEmpty
        ? all.take(12).toList()
        : (all
            .map((it) => (it, fuzzyBest(_q, [it.title, it.subtitle])))
            .where((e) => e.$2 > 0)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2)))
            .map((e) => e.$1)
            .take(12)
            .toList();
    if (_selected >= matches.length) _selected = 0;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: TextField(
                autofocus: true,
                focusNode: _focus,
                decoration: const InputDecoration(
                  hintText: 'Type a command, folder alias, session or file…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() {
                  _q = v;
                  _selected = 0;
                }),
                onSubmitted: (_) => _run(matches),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final it = matches[i];
                  return ListTile(
                    dense: true,
                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity( 0.10),
                    selected: i == _selected,
                    leading: Icon(it.icon ?? Icons.chevron_right_rounded, size: 18),
                    title: Text(it.title,
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(it.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => _run(matches),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Kbd('↑↓'),
                  SizedBox(width: 4),
                  Kbd('Enter'),
                  SizedBox(width: 4),
                  Text('to run', style: TextStyle(fontSize: 11)),
                  Spacer(),
                  Kbd('Esc'),
                  SizedBox(width: 4),
                  Text('to close', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _run(List<_PaletteItem> matches) {
    if (matches.isEmpty) return;
    Navigator.of(context).pop();
    matches[_selected].run(context, ref);
  }
}

// ── Quick session switcher ──────────────────────────────────────────────────

class SessionSwitcherDialog extends ConsumerStatefulWidget {
  const SessionSwitcherDialog({super.key});

  @override
  ConsumerState<SessionSwitcherDialog> createState() =>
      _SessionSwitcherDialogState();
}

class _SessionSwitcherDialogState extends ConsumerState<SessionSwitcherDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sessions = ref
        .watch(sessionsProvider)
        .where((s) => !s.name.startsWith('__'))
        .where((s) => fuzzyBest(_q, [s.name]) > 0 || _q.isEmpty)
        .toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Quick Session Switcher · Ctrl Shift S',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Save current tabs as session',
                    icon: const Icon(Icons.save_rounded, size: 18),
                    onPressed: () async {
                      final name = await promptDialog(context,
                          title: 'Save work session',
                          hint: 'Session name',
                          icon: Icons.bookmark_add_outlined);
                      if (name == null) return;
                      ref.read(servicesProvider).sessions.save(
                          name, ref.read(tabsProvider.notifier).payload());
                      _bump(ref);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Filter sessions…'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: sessions.isEmpty
                  ? const EmptyState(
                      icon: Icons.bookmark_border_rounded,
                      title: 'No sessions yet',
                      message:
                          'Press Ctrl S to snapshot your open tabs, selections and view state — restore it here or from any machine.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        final tabs =
                            ((s.payload['tabs'] as List?) ?? const []).length;
                        return ListTile(
                          leading: const Icon(Icons.bookmark_rounded, size: 18),
                          title: Text(s.name),
                          subtitle: Text(
                            '$tabs tab(s) · saved ${f.formatRelative(
                                DateTime.fromMillisecondsSinceEpoch(s.updatedAtMs))}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            onPressed: () {
                              ref.read(servicesProvider).sessions.delete(s.name);
                              _bump(ref);
                            },
                          ),
                          onTap: () {
                            ref.read(tabsProvider.notifier).restore(s.payload);
                            Navigator.of(context).pop();
                            toast(ref, 'Session “${s.name}” restored');
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

