/// Shell chrome overlays: pinned edge docks, the drag action zone, focus
/// tunnel vignette, zen-mode veil, and the draggable floating inspector.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/fs_service.dart';
import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/format_utils.dart' as f;
import '../../../core/utils/path_utils.dart' as pu;
import '../../../core/widgets/widgets.dart';
import '../../../domain/enums.dart';
import '../../../domain/models.dart';
import '../../../state/app_state.dart';
import 'overlays.dart';

/// True while an internal file drag is in flight; drives the action zone.
final dragActiveProvider = StateProvider<bool>((ref) => false);

/// Paths attached to the current drag (selection or the dragged tile).
final dragPathsProvider = StateProvider<List<String>>((ref) => const []);

// ── Pinned edge docks (Pin to Edge) ─────────────────────────────────────────

class EdgeDock extends ConsumerWidget {
  const EdgeDock({super.key, required this.edge});

  final Edge edge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref
        .watch(pinnedProvider)
        .where((p) => p.edge == edge.name)
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    if (pinned.isEmpty) return const SizedBox.shrink();

    final dark = Theme.of(context).brightness == Brightness.dark;
    final isVertical = edge == Edge.left || edge == Edge.right;
    final bg = dark ? NexusColors.surface2Dark : NexusColors.surfaceLight;

    Widget dock = AnimatedSlide(
      duration: const Duration(milliseconds: 160),
      offset: const Offset(0, 0),
      child: Material(
        color: bg.withValues(alpha:  0.92),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: dark ? NexusColors.borderDark : NexusColors.borderLight),
          ),
          child: isVertical
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final p in pinned) _PinTile(pinned: p, edge: edge)])
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final p in pinned) _PinTile(pinned: p, edge: edge)]),
        ),
      ),
    );

    // Drag-to-pin target wrapping the whole dock.
    dock = DragTarget<List<String>>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final svc = ref.read(servicesProvider);
        for (var i = 0; i < d.data.length; i++) {
          final path = d.data[i];
          svc.db.pin(path, pu.basename(path), edge.name, i);
        }
        _bump(ref);
        toast(ref, 'Pinned to ${edge.name} dock');
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: hovering ? Border.all(color: NexusColors.blueSoft, width: 1.6) : null,
          ),
          child: dock,
        );
      },
    );

    return Align(
      alignment: switch (edge) {
        Edge.left => Alignment.centerLeft,
        Edge.right => Alignment.centerRight,
        Edge.top => Alignment.topCenter,
        Edge.bottom => Alignment.bottomCenter,
      },
      child: Padding(
        padding: switch (edge) {
          Edge.left => const EdgeInsets.only(left: 6),
          Edge.right => const EdgeInsets.only(right: 6),
          Edge.top => const EdgeInsets.only(top: 6),
          Edge.bottom => const EdgeInsets.only(bottom: 32),
        },
        child: dock,
      ),
    );
  }
}

class _PinTile extends ConsumerWidget {
  const _PinTile({required this.pinned, required this.edge});

  final PinnedItem pinned;
  final Edge edge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDir = FileSystemEntity.typeSync(pinned.path) == FileSystemEntityType.directory;
    return Tooltip(
      message: pinned.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context, ref),
        onLongPress: () => _menu(context, ref),
        onSecondaryTap: () => _menu(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            isDir ? Icons.folder_rounded : Icons.description_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final tab = ref.read(tabsProvider).active;
    if (FileSystemEntity.typeSync(pinned.path) == FileSystemEntityType.directory) {
      ref.read(tabsProvider.notifier).navigate(pinned.path);
    } else {
      ref.read(tabsProvider.notifier).navigate(tab.path);
      ref.read(uiProvider.notifier).setPeek(pinned.path);
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(servicesProvider);
    final v = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(300, 300, 0, 0),
      items: [
        const PopupMenuItem(value: 'unpin', child: Text('Unpin')),
        const PopupMenuItem(value: 'left', child: Text('Move to left dock')),
        const PopupMenuItem(value: 'right', child: Text('Move to right dock')),
        const PopupMenuItem(value: 'top', child: Text('Move to top dock')),
        const PopupMenuItem(value: 'bottom', child: Text('Move to bottom dock')),
      ],
    );
    if (v == 'unpin') {
      svc.db.unpin(pinned.path);
      _bump(ref);
    } else if (v != null) {
      svc.db.setPinnedEdge(pinned.path, v);
      _bump(ref);
    }
  }
}

// ── Drag to Action Zone ─────────────────────────────────────────────────────

class DragActionZone extends ConsumerWidget {
  const DragActionZone({super.key});

  static const actions = [
    ('move', 'Move here', Icons.drive_file_move_rounded),
    ('copy', 'Copy here', Icons.content_copy_rounded),
    ('zip', 'Compress', Icons.folder_zip_rounded),
    ('freeze', 'Freeze', Icons.ac_unit_rounded),
    ('teleport', 'Teleport', Icons.send_rounded),
    ('pipeline', 'Pipeline', Icons.account_tree_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(dragActiveProvider);
    final paths = ref.watch(dragPathsProvider);
    if (!active || paths.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha:  0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexusColors.blueSoft, width: 1.4),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:  0.3),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ACTION ZONE',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            for (final (id, label, icon) in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DragTarget<List<String>>(
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (_) => _run(context, ref, id),
                  builder: (context, candidates, _) {
                    final hover = candidates.isNotEmpty;
                    return Material(
                      color: hover
                          ? Theme.of(context).colorScheme.primary.withValues(alpha:  0.16)
                          : Theme.of(context).brightness == Brightness.dark
                              ? NexusColors.surface2Dark
                              : NexusColors.surface2Light,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _run(context, ref, id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 17,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(label,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ).animate().moveX(begin: 40, end: 0, duration: 160.ms, curve: Curves.easeOutCubic).fadeIn(duration: 120.ms);
  }

  Future<void> _run(BuildContext context, WidgetRef ref, String action) async {
    final paths = ref.read(dragPathsProvider);
    ref.read(dragActiveProvider.notifier).state = false;
    ref.read(dragPathsProvider.notifier).state = const [];
    await Overlays.runAction(context, ref, action, paths);
  }
}

// ── Focus Tunnel ────────────────────────────────────────────────────────────

class FocusTunnelLayer extends StatelessWidget {
  const FocusTunnelLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: NexusColors.navy.withValues(alpha:  0.92),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.center_focus_strong_rounded, size: 14, color: Colors.white),
              SizedBox(width: 8),
              Text('Focus tunnel — Esc exits',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Zen veil ────────────────────────────────────────────────────────────────

class ZenOverlay extends ConsumerWidget {
  const ZenOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabsProvider.select((s) => s.active));
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final hint = mobile
        ? '${pu.basename(tab.path)}  ·  Tap to exit zen'
        : '${pu.basename(tab.path)}  ·  F1 exits zen';
    // Tappable so Android users can leave without hunting the title-bar icon.
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => ref.read(uiProvider.notifier).setZen(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: NexusColors.navy.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                hint,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Floating Inspector ──────────────────────────────────────────────────────

class FloatingInspector extends ConsumerStatefulWidget {
  const FloatingInspector({super.key});

  @override
  ConsumerState<FloatingInspector> createState() => _FloatingInspectorState();
}

class _FloatingInspectorState extends ConsumerState<FloatingInspector> {
  Offset _offset = const Offset(0, -60);
  EntryMeta? _meta;
  String _metaFor = '';

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(uiProvider.select((s) => s.inspectorPath));
    if (path == null || path.isEmpty) return const SizedBox.shrink();

    if (_metaFor != path) {
      _metaFor = path;
      _loadMeta(path);
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final f2 = File(path);
    final name = pu.basename(path);
    final stat = f2.existsSync() ? f2.statSync() : null;

    return Positioned(
      right: 16 + _offset.dx,
      bottom: 46 - _offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _offset += d.delta),
        child: Material(
          elevation: 18,
          borderRadius: BorderRadius.circular(14),
          color: dark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
          child: Container(
            width: 264,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: dark ? NexusColors.borderDark : NexusColors.borderLight),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.drag_indicator_rounded,
                        size: 14, color: NexusColors.textDimDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('INSPECTOR',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                    InkWell(
                      onTap: () => ref.read(uiProvider.notifier).setInspector(null),
                      child: const Icon(Icons.close_rounded, size: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FileGlyph(
                        category: FileSystemService.categorize(name),
                        size: 22),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _row('Path', pu.compactPath(path, segments: 3)),
                if (stat != null) ...[
                  _row('Size', stat.size >= 0 ? f.formatSize(stat.size) : '—'),
                  _row('Modified', f.formatDateTime(stat.modified)),
                  _row('Accessed', f.formatDateTime(stat.accessed)),
                  _row('Kind', stat.type.toString().split('.').last),
                ],
                if (_meta != null) ...[
                  const Divider(height: 18),
                  Text(_meta!.describe(),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _miniBtn(context, 'Peek', Icons.visibility_outlined,
                        () => ref.read(uiProvider.notifier).setPeek(path)),
                    _miniBtn(context, 'Paper trail', Icons.history_rounded, () {
                      ref.read(journalProvider.notifier).search(name);
                    }),
                    _miniBtn(context, 'Freeze', Icons.ac_unit_rounded, () async {
                      await ref.read(servicesProvider).freeze.freeze(path);
                      _bump(ref);
                      if (context.mounted) {
                        toast(ref, 'Frozen $name');
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 74,
                child: Text(k, style: const TextStyle(fontSize: 11.5, color: Colors.grey))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _miniBtn(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha:  0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadMeta(String path) async {
    try {
      final m = await ref.read(servicesProvider).metadata.read(path);
      if (mounted) setState(() => _meta = m);
    } catch (_) {
      _meta = null;
    }
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
