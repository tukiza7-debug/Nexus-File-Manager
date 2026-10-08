/// Multi-tab strip. Each tab keeps its own history, selection, sort and view
/// state — the full TabState model, not just a path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/path_utils.dart' as pu;
import '../../../state/app_state.dart';

class TabsBar extends ConsumerWidget {
  const TabsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              scrollDirection: Axis.horizontal,
              onReorder: (oldI, newI) =>
                  ref.read(tabsProvider.notifier).reorder(oldI, newI),
              proxyDecorator: (child, index, animation) => ScaleTransition(
                scale: animation.drive(Tween(begin: 1.0, end: 1.05)),
                child: Material(elevation: 4, child: child),
              ),
              itemCount: tabs.tabs.length,
              itemBuilder: (context, i) {
                final t = tabs.tabs[i];
                final active = t.id == tabs.activeId;
                return ReorderableDragStartListener(
                  key: ValueKey(t.id),
                  index: i,
                  child: _TabChip(
                    label: pu.basename(t.path),
                    active: active,
                    dark: dark,
                    onTap: () => ref.read(tabsProvider.notifier).activate(t.id),
                    onClose: () => ref.read(tabsProvider.notifier).closeTab(t.id),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New tab (Ctrl D reopens current path)',
            icon: const Icon(Icons.add_rounded, size: 17),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                ref.read(tabsProvider.notifier).openTab(tabs.active.path),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.dark,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dim = widget.dark ? NexusColors.textDimDark : NexusColors.textDimLight;
    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTap: widget.onClose,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(right: 6, top: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          constraints: const BoxConstraints(maxWidth: 190, minWidth: 90),
          decoration: BoxDecoration(
            color: widget.active
                ? Theme.of(context).colorScheme.surface
                : (widget.dark
                    ? NexusColors.surface2Dark
                    : NexusColors.surface2Light),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            border: Border.all(
              color: widget.active ? accent.withOpacity( 0.55) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.tab_rounded,
                  size: 13, color: widget.active ? accent : dim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                    color: widget.active
                        ? Theme.of(context).colorScheme.onSurface
                        : dim,
                  ),
                ),
              ),
              if (_hover || widget.active)
                InkWell(
                  onTap: widget.onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
