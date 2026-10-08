/// Sidebar — Places, Path Aliases, Folder Stacks, Secure Freeze list and the
/// Multi-Clipboard stack. Everything here is live and persisted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/path_utils.dart' as pu;
import '../../../core/widgets/widgets.dart';
import '../../../domain/enums.dart';
import '../../../domain/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, this.flush = false});

  /// When true the sidebar fills its parent (used inside the phone Drawer)
  /// instead of pinning its usual 244 px column width.
  final bool flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final look = ref.watch(lookProvider);

    return Container(
      width: flush ? double.infinity : 244,
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
      decoration: BoxDecoration(
        color: dark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
        border: Border(
          right: BorderSide(
            color: dark ? NexusColors.borderDark : NexusColors.borderLight,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PlacesSection(),
            const _AliasesSection(),
            const _StacksSection(),
            const _FreezeSection(),
            const _ClipboardSection(),
            if (look.colorblindSafe) const _A11yNotice(),
          ],
        ),
      ),
    );
  }
}

// ── Places ──────────────────────────────────────────────────────────────────

class _PlacesSection extends ConsumerWidget {
  const _PlacesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(servicesProvider).fs.places();
    return _Section(
      title: AppLocalizations.of(context).places,
      children: [
        for (final p in places)
          _Row(
            icon: _placeIcon(p.category),
            label: p.label,
            onTap: () => ref.read(tabsProvider.notifier).navigate(p.path),
          ),
      ],
    );
  }
}

// ── Aliases ─────────────────────────────────────────────────────────────────

class _AliasesSection extends ConsumerWidget {
  const _AliasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(aliasesProvider);
    return _Section(
      title: AppLocalizations.of(context).aliases,
      action: IconButton(
        tooltip: 'Alias current folder (type: in palette too)',
        icon: const Icon(Icons.add_rounded, size: 15),
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final name = await promptDialog(context,
              title: 'New path alias',
              hint: 'e.g. work → any folder',
              icon: Icons.label_outline_rounded);
          if (name == null) return;
          final path = ref.read(tabsProvider).active.path;
          ref.read(servicesProvider).db.upsertAlias(name, path);
          _bump(ref);
        },
      ),
      children: [
        if (aliases.isEmpty)
          const _Hint('Name any folder — tap + to alias it.'),
        for (final a in aliases)
          _Row(
            icon: Icons.label_outline_rounded,
            label: a.name,
            trailing: Icons.close_rounded,
            onTrailing: () {
              ref.read(servicesProvider).db.deleteAlias(a.id!);
              _bump(ref);
            },
            onTap: () => ref.read(tabsProvider.notifier).navigate(a.path),
          ),
      ],
    );
  }
}

// ── Folder stacks ───────────────────────────────────────────────────────────

class _StacksSection extends ConsumerWidget {
  const _StacksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stacks = ref.watch(stacksProvider);
    return _Section(
      title: AppLocalizations.of(context).stacks,
      action: IconButton(
        tooltip: 'Stack current tabs',
        icon: const Icon(Icons.layers_rounded, size: 15),
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final name = await promptDialog(context,
              title: 'Save tabs as stack',
              hint: 'Stack name',
              icon: Icons.layers_rounded);
          if (name == null) return;
          final tabs = ref.read(tabsProvider).tabs;
          final stack = FolderStack(
            name: name,
            items: [
              for (final t in tabs) StackItem(path: t.path, label: pu.basename(t.path)),
            ],
          );
          ref.read(servicesProvider).db.saveStack(stack);
          _bump(ref);
          toast(ref, 'Stack “$name” saved (${tabs.length} folders)');
        },
      ),
      children: [
        if (stacks.isEmpty)
          const _Hint('Snapshot open tabs as one stack and restore anytime.'),
        for (final s in stacks)
          _Row(
            icon: Icons.layers_rounded,
            label: '${s.name}  (${s.items.length})',
            trailing: Icons.delete_outline_rounded,
            onTrailing: () {
              ref.read(servicesProvider).db.deleteStack(s.id!);
              _bump(ref);
            },
            onTap: () {
              final c = ref.read(tabsProvider.notifier);
              c.restore({
                'activeId': s.items.first.label,
                'tabs': [
                  for (final it in s.items)
                    {
                      'id': 'tab-${it.hashCode}',
                      'history': [it.path],
                      'histIndex': 0,
                    }
                ],
              });
              toast(ref, 'Stack “${s.name}” opened');
            },
          ),
      ],
    );
  }
}

// ── Secure freeze ───────────────────────────────────────────────────────────

class _FreezeSection extends ConsumerWidget {
  const _FreezeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frozen = ref.watch(freezesProvider);
    return _Section(
      title: AppLocalizations.of(context).secureFreeze,
      children: [
        if (frozen.isEmpty)
          const _Hint('Right-click any file → Freeze to lock it read-only.'),
        for (final f in frozen)
          _Row(
            icon: Icons.ac_unit_rounded,
            label: pu.basename(f.path),
            color: const Color(0xFF4E8AD2),
            trailing: Icons.lock_open_rounded,
            onTrailing: () async {
              await ref.read(servicesProvider).freeze.unfreeze(f.path);
              _bump(ref);
              toast(ref, 'Unfrozen ${pu.basename(f.path)}');
            },
            // Audit item 40: dead onTap removed — the unfreeze button above
            // is the single, discoverable action for this row.
          ),
      ],
    );
  }
}

// ── Clipboard stack ─────────────────────────────────────────────────────────

class _ClipboardSection extends ConsumerWidget {
  const _ClipboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(servicesProvider);
    final items = svc.clipboard.items;
    final activeId = svc.clipboard.active?.id;

    return _Section(
      title: AppLocalizations.of(context).clipboardStack,
      action: IconButton(
        tooltip: 'Clear stack',
        icon: const Icon(Icons.clear_all_rounded, size: 15),
        visualDensity: VisualDensity.compact,
        onPressed: items.isEmpty ? null : () => svc.clipboard.clear(),
      ),
      children: [
        if (items.isEmpty)
          const _Hint('Copy or cut multiple items — they stack instead of replacing.'),
        for (final e in items.take(6))
          _Row(
            icon: e.op == ClipOp.copy
                ? Icons.content_copy_rounded
                : Icons.content_cut_rounded,
            label: e.name,
            highlight: e.id == activeId,
            onTap: () => svc.clipboard.setActive(e.id),
            trailing: Icons.close_rounded,
            onTrailing: () => svc.clipboard.remove(e.id),
          ),
        if (items.length > 6)
          _Hint('+${items.length - 6} more in the stack'),
      ],
    );
  }
}

class _A11yNotice extends ConsumerWidget {
  const _A11yNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 10, right: 10),
      child: Row(
        children: [
          const Icon(Icons.contrast_rounded, size: 13, color: NexusColors.ok),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Colour-blind-safe mode active — categories use patterns.',
                style: Theme.of(context).textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

// ── Primitives ──────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, trailing: action),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.onTrailing,
    this.highlight = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final IconData? trailing;
  final VoidCallback? onTrailing;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: highlight
            ? accent.withValues(alpha:  0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 15, color: color ?? (highlight ? accent : null)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                          color: dark ? NexusColors.textDark : NexusColors.textLight)),
                ),
                if (trailing != null)
                  InkWell(
                    onTap: onTrailing,
                    child: Icon(trailing, size: 13,
                        color: dark ? NexusColors.textDimDark : NexusColors.textDimLight),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}

IconData _placeIcon(FileCategory c) => switch (c) {
      FileCategory.folder => Icons.home_rounded,
      FileCategory.document => Icons.description_rounded,
      FileCategory.archive => Icons.download_rounded,
      FileCategory.image => Icons.image_rounded,
      FileCategory.audio => Icons.music_note_rounded,
      FileCategory.video => Icons.movie_rounded,
      _ => Icons.folder_rounded,
    };
