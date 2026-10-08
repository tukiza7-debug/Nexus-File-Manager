/// Directory content views: grid, list, spatial-memory free placement and
/// split-by-type. Tiles carry selection, accessibility patterns, drag to the
/// action zone and Alt-hover peek.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/nexus_database.dart' show Offset2D;
import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/format_utils.dart' as f;
import '../../../core/widgets/widgets.dart';
import '../../../domain/enums.dart';
import '../../../domain/models.dart';
import '../../../state/app_state.dart';
import 'chrome.dart' as chrome;
import 'overlays.dart';

class FileViews extends ConsumerWidget {
  const FileViews({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(dirProvider);
    final tab = ref.watch(tabsProvider.select((s) => s.active));
    final ui = ref.watch(uiProvider);
    final look = ref.watch(lookProvider);

    if (dir.loading && dir.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (dir.error != null) {
      return EmptyState(
        icon: Icons.folder_off_rounded,
        title: 'Cannot open this folder',
        message: dir.error!,
        action: FilledButton.tonal(
          onPressed: () => ref.read(dirProvider.notifier).reload(),
          child: const Text('Retry'),
        ),
      );
    }
    if (dir.entries.isEmpty) {
      return EmptyState(
        icon: ui.filter.isEmpty
            ? Icons.folder_open_rounded
            : Icons.search_off_rounded,
        title: ui.filter.isEmpty ? 'Nothing here yet' : 'No matches',
        message: ui.filter.isEmpty
            ? (Platform.isAndroid || Platform.isIOS
                ? 'This folder is empty. Long-press or tap Create to add files.'
                : 'This folder is empty. Right-click to create files, or drop something anywhere on this view.')
            : 'No item matches “${ui.filter}”. Try another search or clear the filter.',
        action: ui.filter.isEmpty
            ? FilledButton.tonal(
                onPressed: () => Overlays.showDirMenu(
                    context, ref, const Offset(200, 200)),
                child: const Text('Create something'))
            : OutlinedButton(
                onPressed: () => ref.read(uiProvider.notifier).setFilter(''),
                child: const Text('Clear filter'),
              ),
      );
    }

    final view = switch (tab.viewMode) {
      ViewMode.grid =>
        tab.spatialMode ? _SpatialView(entries: dir.entries) : _GridView(entries: dir.entries),
      ViewMode.list => _ListView(entries: dir.entries),
    };

    if (ui.splitTypeView && !tab.spatialMode) {
      return _SplitByType(entries: dir.entries, child: view);
    }
    return look.touchMode ? _TouchFrame(child: view) : view;
  }
}

// ── Grid ────────────────────────────────────────────────────────────────────

class _GridView extends ConsumerWidget {
  const _GridView({required this.entries});

  final List<NexusEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(lookProvider);
    final minTile = look.touchMode ? 118.0 : 96.0;

    return LayoutBuilder(builder: (context, box) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: minTile * 1.25,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.92,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) => FileTile(entry: entries[i]),
      );
    });
  }
}

// ── List ────────────────────────────────────────────────────────────────────

class _ListView extends ConsumerWidget {
  const _ListView({required this.entries});

  final List<NexusEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? NexusColors.borderDark
                      : NexusColors.borderLight),
            ),
          ),
          child: Row(
            children: [
              _head(context, 'NAME'),
              const SizedBox(width: 8),
              _head(context, 'SIZE', width: 76),
              _head(context, 'MODIFIED', width: 132),
              _head(context, 'KIND', width: 90),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1, mainAxisExtent: 36),
            itemCount: entries.length,
            itemBuilder: (context, i) => FileTile(
              entry: entries[i],
              listMode: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _head(BuildContext context, String label, {double width = 0}) {
    return width > 0
        ? SizedBox(
            width: width,
            child: Text(label, style: Theme.of(context).textTheme.labelSmall))
        : Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelSmall));
  }
}

// ── Spatial memory view ─────────────────────────────────────────────────────

class _SpatialView extends ConsumerStatefulWidget {
  const _SpatialView({required this.entries});

  final List<NexusEntry> entries;

  @override
  ConsumerState<_SpatialView> createState() => _SpatialViewState();
}

class _SpatialViewState extends ConsumerState<_SpatialView> {
  Map<String, Offset2D>? _positions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SpatialView old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final folder = ref.read(tabsProvider).active.path;
    _positions = ref.read(servicesProvider).db.spatialFor(folder);
  }

  Offset _defaultPos(int i, Size box) {
    final perRow = (box.width / 110).floor().clamp(1, 20);
    return Offset(16.0 + (i % perRow) * 110, 16.0 + (i ~/ perRow) * 118);
  }

  @override
  Widget build(BuildContext context) {
    final folder = ref.read(tabsProvider).active.path;
    return LayoutBuilder(builder: (context, box) {
      return Stack(
        children: [
          Positioned.fill(
            child: DragTarget<List<String>>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (d) async {
                final dest = folder;
                final svc = ref.read(servicesProvider);
                final batch = svc.journal.newBatch('move');
                await svc.ops.movePaths(d.data, dest, batchId: batch);
                svc.ops.finish(batch);
                toast(ref, 'Moved ${d.data.length} item(s) into spatial view');
                ref.read(tabsProvider.notifier).refresh();
              },
              builder: (_, candidates, __) => candidates.isNotEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                          border: Border.all(color: NexusColors.blueSoft, width: 1.4)))
                  : const SizedBox.shrink(),
            ),
          ),
          for (var i = 0; i < widget.entries.length; i++)
            _spatialTile(context, i, box),
        ],
      );
    });
  }

  Widget _spatialTile(BuildContext context, int i, BoxConstraints box) {
    final e = widget.entries[i];
    final saved = _positions?[e.name];
    final pos = saved != null
        ? Offset(saved.x, saved.y)
        : _defaultPos(i, Size(box.maxWidth, box.maxHeight));
    return Positioned(
      key: ValueKey('sp-${e.path}'),
      left: pos.dx.clamp(0.0, (box.maxWidth - 96).clamp(0.0, double.infinity)),
      top: pos.dy.clamp(0.0, (box.maxHeight - 110).clamp(0.0, double.infinity)),
      child: Draggable<NexusEntry>(
        data: e,
        onDragStarted: () {
          ref.read(chrome.dragActiveProvider.notifier).state = true;
          ref.read(chrome.dragPathsProvider.notifier).state = [e.path];
        },
        onDragEnd: (_) =>
            ref.read(chrome.dragActiveProvider.notifier).state = false,
        feedback: _Feedback(entry: e),
        childWhenDragging: Opacity(opacity: 0.35, child: _SpatialCard(entry: e)),
        child: GestureDetector(
          onPanUpdate: (d) {
            final folder = ref.read(tabsProvider).active.path;
            final next = Offset(
              (pos.dx + d.delta.dx).clamp(0.0, (box.maxWidth - 96).clamp(0.0, double.infinity)),
              (pos.dy + d.delta.dy).clamp(0.0, (box.maxHeight - 110).clamp(0.0, double.infinity)),
            );
            ref.read(servicesProvider).db.putSpatial(folder, e.name, next.dx, next.dy);
            setState(() => _positions?[e.name] = Offset2D(next.dx, next.dy));
          },
          child: _SpatialCard(entry: e),
        ),
      ),
    );
  }
}

class _SpatialCard extends ConsumerWidget {
  const _SpatialCard({required this.entry});

  final NexusEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(tabsProvider.select((s) => s.active.selection.contains(entry.path)));
    return FileTileBody(entry: entry, selected: selected, width: 92);
  }
}

// ── Split by type ───────────────────────────────────────────────────────────

class _SplitByType extends ConsumerWidget {
  const _SplitByType({required this.child, required this.entries});

  final Widget child;
  final List<NexusEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<NexusEntry>>{
      'Folders': entries.where((e) => e.isDir).toList(),
      'Images': entries.where((e) => e.category == FileCategory.image).toList(),
      'Documents': entries
          .where((e) =>
              e.category == FileCategory.document ||
              e.category == FileCategory.archive)
          .toList(),
      'Media': entries
          .where((e) =>
              e.category == FileCategory.audio ||
              e.category == FileCategory.video)
          .toList(),
      'Code': entries.where((e) => e.category == FileCategory.code).toList(),
      'Other': entries
          .where((e) =>
              !e.isDir &&
              e.category != FileCategory.image &&
              e.category != FileCategory.document &&
              e.category != FileCategory.archive &&
              e.category != FileCategory.audio &&
              e.category != FileCategory.video &&
              e.category != FileCategory.code)
          .toList(),
    }..removeWhere((_, v) => v.isEmpty);

    return DefaultTabController(
      length: groups.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final e in groups.entries)
                Tab(
                  height: 34,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.key),
                      const SizedBox(width: 6),
                      Badge(
                        label: Text('${e.value.length}'),
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final e in groups.entries)
                  _GridView(entries: e.value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Touch frame (one-hand mode) ─────────────────────────────────────────────

class _TouchFrame extends ConsumerWidget {
  const _TouchFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(child: child),
        // One-handed bottom action bar — thumb reachable.
        Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? NexusColors.borderDark
                    : NexusColors.borderLight),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha:  0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tbtn(context, Icons.content_copy_rounded, 'Copy',
                  () => Overlays.copySelection(context, ref)),
              _tbtn(context, Icons.content_cut_rounded, 'Cut',
                  () => Overlays.cutSelection(context, ref)),
              _tbtn(context, Icons.content_paste_go_rounded, 'Paste',
                  () => Overlays.showSmartPasteDialog(context, ref,
                      destDir: ref.read(tabsProvider).active.path)),
              _tbtn(context, Icons.drive_file_rename_outline_rounded, 'Rename',
                  () async {
                final sel = ref.read(tabsProvider).active.selection;
                if (sel.length == 1) {
                  await Overlays.renameSingle(context, ref, sel.first);
                }
              }),
              _tbtn(context, Icons.delete_outline_rounded, 'Delete', () async {
                final sel = ref.read(tabsProvider).active.selection;
                await Overlays.deletePaths(context, ref, sel.toList(),
                    currentPath: ref.read(tabsProvider).active.path);
              }),
              _tbtn(context, Icons.more_vert_rounded, 'More',
                  () => Overlays.showDirMenu(context, ref, const Offset(120, 300))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tbtn(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: label,
        child: IconButton(
          iconSize: 24,
          visualDensity: VisualDensity.comfortable,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

// ── The tile itself ─────────────────────────────────────────────────────────

class FileTile extends ConsumerStatefulWidget {
  const FileTile({super.key, required this.entry, this.listMode = false});

  final NexusEntry entry;
  final bool listMode;

  @override
  ConsumerState<FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<FileTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final selected = ref.watch(
        tabsProvider.select((s) => s.active.selection.contains(entry.path)));
    final ui = ref.watch(uiProvider);
    final look = ref.watch(lookProvider);

    final tunnelActive = ui.focusTunnelPath != null;
    final dimmed = tunnelActive && ui.focusTunnelPath != entry.path;

    final tile = FileTileBody(
      entry: entry,
      selected: selected,
      listMode: widget.listMode,
      hover: _hover,
    );

    return GestureDetector(
      onTap: () => _select(selected, entry),
      onDoubleTap: () => _open(entry),
      onSecondaryTapUp: (d) =>
          Overlays.showEntryMenu(context, ref, entry, d.globalPosition),
      onLongPressStart: (d) =>
          Overlays.showEntryMenu(context, ref, entry, d.globalPosition),
      child: Draggable<NexusEntry>(
        data: entry,
        onDragStarted: () {
          ref.read(chrome.dragActiveProvider.notifier).state = true;
          final sel = ref.read(tabsProvider).active.selection;
          ref.read(chrome.dragPathsProvider.notifier).state =
              sel.contains(entry.path) ? sel.toList() : [entry.path];
        },
        onDragEnd: (_) =>
            ref.read(chrome.dragActiveProvider.notifier).state = false,
        feedback: _Feedback(entry: entry),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) {
            setState(() => _hover = false);
            ref.read(uiProvider.notifier).setPeek(null);
          },
          onHover: (_) {
            if (HardwareKeyboard.instance.isAltPressed) {
              ref.read(uiProvider.notifier).setPeek(entry.path);
            }
          },
          child: _SelectionBorder(
            selected: selected,
            colorblindSafe: look.colorblindSafe,
            category: entry.category,
            child: dimmed
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Colors.black54, BlendMode.saturation),
                    child: Opacity(opacity: 0.35, child: tile),
                  )
                : tile,
          ),
        ),
      ),
    );
  }

  void _select(bool selected, NexusEntry entry) {
    final c = ref.read(tabsProvider.notifier);
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      c.toggleSelect(entry.path);
    } else if (HardwareKeyboard.instance.isShiftPressed) {
      c.selectOnly(entry.path);
    } else {
      selected ? c.clearSelection() : c.selectOnly(entry.path);
    }
  }

  void _open(NexusEntry entry) {
    if (entry.isDir) {
      ref.read(tabsProvider.notifier).navigate(entry.path);
    } else {
      ref.read(servicesProvider).fs.openWithSystem(entry.path);
    }
  }
}

/// Selection ring with optional colour-blind-safe pattern overlay.
class _SelectionBorder extends StatelessWidget {
  const _SelectionBorder({
    required this.selected,
    required this.colorblindSafe,
    required this.category,
    required this.child,
  });

  final bool selected;
  final bool colorblindSafe;
  final FileCategory category;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    final accent = Theme.of(context).colorScheme.primary;
    return CustomPaint(
      foregroundPainter: colorblindSafe
          ? PatternPainter(patternFor(category),
              accent, strokeWidth: 1)
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 1.6),
        ),
        padding: const EdgeInsets.all(2),
        child: child,
      ),
    );
  }
}

class FileTileBody extends ConsumerWidget {
  const FileTileBody({
    super.key,
    required this.entry,
    required this.selected,
    this.listMode = false,
    this.hover = false,
    this.width,
  });

  final NexusEntry entry;
  final bool selected;
  final bool listMode;
  final bool hover;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final touchMode = ref.watch(lookProvider.select((s) => s.touchMode));
    if (listMode) return _listBody(context, touchMode);
    return _gridBody(context, touchMode);
  }

  Widget _gridBody(BuildContext context, bool touchMode) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = dark ? NexusColors.surface2Dark : NexusColors.surface2Light;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha:  0.10)
            : hover
                ? hoverBg
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FileGlyph(category: entry.category, size: touchMode ? 40 : 34),
          const SizedBox(height: 7),
          Text(
            entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: touchMode ? 13 : 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: dark ? NexusColors.textDark : NexusColors.textLight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.isDir ? 'Folder' : entry.sizeLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _listBody(BuildContext context, bool touchMode) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = dark ? NexusColors.surface2Dark : NexusColors.surface2Light;
    return Container(
      height: touchMode ? 52 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha:  0.10)
            : hover
                ? hoverBg
                : Colors.transparent,
      ),
      child: Row(
        children: [
          FileGlyph(category: entry.category, size: touchMode ? 26 : 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: dark ? NexusColors.textDark : NexusColors.textLight,
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(entry.isDir ? 'Folder' : entry.sizeLabel,
                style: Theme.of(context).textTheme.labelSmall),
          ),
          SizedBox(
            width: 132,
            child: Text(f.formatDateTime(entry.modified),
                style: Theme.of(context).textTheme.labelSmall),
          ),
          SizedBox(
            width: 90,
            child: Text(
              entry.isDir ? '—' : (entry.ext.isEmpty ? 'file' : entry.ext),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feedback extends ConsumerWidget {
  const _Feedback({required this.entry});

  final NexusEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileGlyph(category: entry.category, size: 18),
            const SizedBox(width: 8),
            Text(entry.name, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// GridView delegate alias to keep the import list short.
typedef SlGridDelegateWithMaxCrossAxisExtent = SliverGridDelegateWithMaxCrossAxisExtent;
typedef SlGridDelegateWithFixedCrossAxisCount = SliverGridDelegateWithFixedCrossAxisCount;
