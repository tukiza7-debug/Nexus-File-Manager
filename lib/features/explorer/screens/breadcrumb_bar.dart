/// Breadcrumb bar with the visited-timeline dropdown, filter box, sort and
/// view controls. The timeline is the horizontal memory of this tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/path_utils.dart' as pu;
import '../../../domain/enums.dart';
import '../../../domain/models.dart';
import '../../../state/app_state.dart';

class BreadcrumbBar extends ConsumerWidget {
  const BreadcrumbBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabsProvider.select((s) => s.active));
    final ui = ref.watch(uiProvider.select((s) => s.filter));
    final segments = _segments(tab.path);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          _NavBtn(Icons.arrow_back_rounded, tab.canBack,
              () => ref.read(tabsProvider.notifier).back()),
          _NavBtn(Icons.arrow_forward_rounded, tab.canForward,
              () => ref.read(tabsProvider.notifier).forward()),
          _NavBtn(Icons.arrow_upward_rounded, true,
              () => ref.read(tabsProvider.notifier).up()),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0)
                      const Icon(Icons.chevron_right_rounded,
                          size: 14, color: NexusColors.textDimDark),
                    _Crumb(
                        label: segments[i].$1,
                        path: segments[i].$2,
                        first: i == 0,
                        onTap: i < segments.length - 1
                            ? () => ref.read(tabsProvider.notifier).navigate(segments[i].$2)
                            : null),
                  ],
                  // Breadcrumb timeline: everything this tab has visited.
                  Tooltip(
                    message: 'Breadcrumb timeline — everywhere this tab has been',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showTimeline(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.history_rounded,
                            size: 15, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            height: 30,
            child: TextField(
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Filter…',
                prefixIcon: const Icon(Icons.search_rounded, size: 15),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10),
                suffixIcon: ui.isEmpty
                    ? null
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 13),
                        onPressed: () =>
                            ref.read(uiProvider.notifier).setFilter(''),
                      ),
              ),
              onChanged: (v) => ref.read(uiProvider.notifier).setFilter(v),
            ),
          ),
          const SizedBox(width: 6),
          _SortMenu(tab: tab),
          _ViewToggle(tab: tab),
          Tooltip(
            message: 'Spatial memory view — arrange icons freely',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(tabsProvider.notifier).setSpatial(!tab.spatialMode),
              icon: Icon(Icons.hub_outlined,
                  size: 18,
                  color: tab.spatialMode ? Theme.of(context).colorScheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _segments(String path) {
    final out = <(String, String)>[];
    var acc = '';
    final parts = path.replaceAll(r'\', '/').split('/').where((s) => s.isNotEmpty);
    final isWin = path.contains(r':');
    for (final part in parts) {
      if (isWin && acc.isEmpty) {
        acc = '$part/';
      } else {
        acc = acc.endsWith('/') ? '$acc$part' : '$acc/$part';
      }
      out.add((part, acc));
    }
    if (out.isEmpty) out.add(('/', '/'));
    return out;
  }

  void _showTimeline(BuildContext context, WidgetRef ref) {
    final tab = ref.read(tabsProvider).active;
    final visited = tab.visited.reversed.take(40).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('TIMELINE — ${visited.length} stops',
                    style: Theme.of(ctx).textTheme.labelSmall),
              ),
              Flexible(
                child: visited.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Move around — your path is remembered here.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: visited.length,
                        itemBuilder: (context, i) {
                          final p = visited[i];
                          final idx = tab.visited.indexOf(p);
                          return ListTile(
                            dense: true,
                            leading: Text('#${visited.length - i}',
                                style: Theme.of(ctx).textTheme.labelSmall),
                            title: Text(pu.basename(p),
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(p,
                                style: Theme.of(ctx).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: idx >= 0 && idx < tab.history.length
                                ? Text(
                                    'step ${idx + 1}/${tab.history.length}',
                                    style: Theme.of(ctx).textTheme.labelSmall)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              ref.read(tabsProvider.notifier).navigate(p);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn(this.icon, this.enabled, this.onTap);

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.path,
    required this.first,
    this.onTap,
  });

  final String label;
  final String path;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first)
              Icon(Icons.folder_special_rounded,
                  size: 13, color: Theme.of(context).colorScheme.primary),
            if (first) const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: dark ? NexusColors.textDark : NexusColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.tab});

  final TabState tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuAnchor(
      menuChildren: [
        for (final b in SortBy.values)
          MenuItemButton(
            leadingIcon: tab.sortBy == b
                ? const Icon(Icons.check_rounded, size: 15)
                : const SizedBox(width: 15),
            onPressed: () => ref
                .read(tabsProvider.notifier)
                .setSort(b, tab.sortDir),
            child: Text(b.label),
          ),
        const Divider(height: 9, thickness: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.swap_vert_rounded, size: 15),
          onPressed: () => ref.read(tabsProvider.notifier).setSort(
              tab.sortBy,
              tab.sortDir == SortDir.asc ? SortDir.desc : SortDir.asc),
          child: Text(tab.sortDir == SortDir.asc ? 'Descending' : 'Ascending'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Sort',
        child: IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.open(),
          icon: const Icon(Icons.sort_rounded, size: 18),
        ),
      ),
    );
  }
}

class _ViewToggle extends ConsumerWidget {
  const _ViewToggle({required this.tab});

  final TabState tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Grid / list',
      onPressed: () => ref.read(tabsProvider.notifier).setViewMode(
          tab.viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid),
      icon: Icon(
        tab.viewMode == ViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
        size: 18,
      ),
    );
  }
}
