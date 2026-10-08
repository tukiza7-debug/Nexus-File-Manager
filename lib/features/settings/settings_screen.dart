/// Settings — appearance (Nexus / legacy brands, brightness, accent),
/// accessibility (colour-blind-safe patterns), touch mode, ghost mode,
/// Teleport identity, auto-versioning retention and data controls.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/nexus_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/enums.dart';
import '../../state/app_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _accents = [
    ('0xFF2563EB', 'Nexus Blue'),
    ('0xFF7C3AED', 'Violet'),
    ('0xFF0D9488', 'Teal'),
    ('0xFFD2564E', 'Crimson'),
    ('0xFFB45309', 'Amber'),
    ('0xFF4F7942', 'Fern'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(lookProvider);
    final svc = ref.read(servicesProvider);
    final ghost = ref.watch(uiProvider.select((s) => s.ghostOpacity));

    return ToolScaffold(
      title: 'Settings',
      subtitle: 'Make Nexus yours — appearance, accessibility and behaviour.',
      icon: Icons.settings_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          _Group(
            title: 'Appearance',
            icon: Icons.palette_rounded,
            children: [
              Row(
                children: [
                  Text('Theme brand', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  SegmentedButton<ThemeBrand>(
                    segments: [
                      for (final b in ThemeBrand.values)
                        ButtonSegment(value: b, label: Text(b.label)),
                    ],
                    selected: {look.brand},
                    onSelectionChanged: (s) =>
                        ref.read(lookProvider.notifier).setBrand(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Brightness', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  SegmentedButton<BrightnessPref>(
                    segments: const [
                      ButtonSegment(value: BrightnessPref.dark, label: Text('Dark')),
                      ButtonSegment(value: BrightnessPref.light, label: Text('Light')),
                      ButtonSegment(value: BrightnessPref.system, label: Text('System')),
                    ],
                    selected: {look.bright},
                    onSelectionChanged: (s) =>
                        ref.read(lookProvider.notifier).setBright(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Accent', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  for (final (hex, name) in _accents)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: name,
                        child: InkWell(
                          onTap: () =>
                              ref.read(lookProvider.notifier).setAccent(hex),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(int.parse(hex)),
                              shape: BoxShape.circle,
                              border: look.accent == hex
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      width: 2)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Accessibility ────────────────────────────────────────────────
          _Group(
            title: 'Accessibility',
            icon: Icons.accessibility_new_rounded,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Colour-blind-safe mode'),
                subtitle: const Text(
                    'Categories gain pattern textures (hatch, dots, rings) — never colour alone.',
                    style: TextStyle(fontSize: 12)),
                value: look.colorblindSafe,
                onChanged: (v) => ref.read(lookProvider.notifier).setColorblind(v),
              ),
              if (look.colorblindSafe)
                Row(
                  children: [
                    Text('Badge style', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    SegmentedButton<TileBadge>(
                      segments: const [
                        ButtonSegment(value: TileBadge.hatched, label: Text('Hatched')),
                        ButtonSegment(value: TileBadge.dot, label: Text('Dots')),
                        ButtonSegment(value: TileBadge.glyph, label: Text('Glyphs')),
                      ],
                      selected: {look.badge},
                      onSelectionChanged: (s) =>
                          ref.read(lookProvider.notifier).setBadge(s.first),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('One-hand / touch mode'),
                subtitle: const Text(
                    'Larger tiles, bigger hit targets and a thumb-reachable action bar.',
                    style: TextStyle(fontSize: 12)),
                value: look.touchMode,
                onChanged: (v) => ref.read(lookProvider.notifier).setTouchMode(v),
              ),
            ],
          ),

          // ── Ghost mode ───────────────────────────────────────────────────
          _Group(
            title: 'Ghost mode',
            icon: Icons.visibility_off_rounded,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Window transparency while ghosted (Ctrl G toggles).'),
                        Slider(
                          min: 0.2,
                          max: 0.9,
                          value: ghost >= 1.0
                              ? (svc.prefs.getDouble('ui.ghost') ?? 0.45)
                              : ghost,
                          label: '${((ghost >= 1.0
                                  ? (svc.prefs.getDouble('ui.ghost') ?? 0.45)
                                  : ghost) * 100).round()}%',
                          onChanged: (v) =>
                              ref.read(uiProvider.notifier).setGhost(v),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => ref.read(uiProvider.notifier).restoreGhost(),
                    child: const Text('Preview'),
                  ),
                ],
              ),
            ],
          ),

          // ── Teleport ─────────────────────────────────────────────────────
          _Group(
            title: 'File Teleport',
            icon: Icons.send_rounded,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Device name'),
                subtitle: Text(svc.teleport.deviceName),
                trailing: const Icon(Icons.edit_rounded, size: 16),
                onTap: () async {
                  final name = await showNameDialog(context, svc.teleport.deviceName);
                  if (name != null) {
                    await svc.prefs.setString('teleport.name', name);
                    try {
                      await svc.teleport.start(
                          name: name,
                          downloadTo: svc.teleport.downloadDir.isEmpty
                              ? Directory.systemTemp.path
                              : svc.teleport.downloadDir);
                    } catch (_) {}
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Inbox folder'),
                subtitle: Text(svc.teleport.downloadDir.isEmpty
                    ? 'Default documents folder'
                    : svc.teleport.downloadDir),
              ),
            ],
          ),

          // ── Auto versioning ──────────────────────────────────────────────
          _Group(
            title: 'Auto versioning',
            icon: Icons.history_rounded,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep snapshots on every save'),
                subtitle: const Text('Watched files snapshot before each overwrite.',
                    style: TextStyle(fontSize: 12)),
                value: svc.versioning.enabled,
                onChanged: (v) {
                  svc.versioning.configure(enabled: v);
                  svc.prefs.setBool('versioning.enabled', v);
                  _bumpCollections(ref);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Snapshots kept per file'),
                subtitle: Slider(
                  min: 5,
                  max: 100,
                  divisions: 19,
                  label: '${svc.versioning.retention}',
                  value: svc.versioning.retention.toDouble(),
                  onChanged: (v) {
                    svc.versioning.configure(keep: v.round());
                    svc.prefs.setInt('versioning.keep', v.round());
                  },
                ),
              ),
            ],
          ),

          // ── Data ─────────────────────────────────────────────────────────
          _Group(
            title: 'Data',
            icon: Icons.storage_rounded,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Clear operation history'),
                subtitle: const Text(
                    'Removes the Paper Trail entries (files are untouched). Undo history resets.',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.delete_sweep_rounded),
                onTap: () async {
                  final ok = await showConfirm(
                      context, 'Clear the paper trail?',
                      'This cannot be undone and wipes all undo/redo information.');
                  if (ok) {
                    svc.db.pruneJournal(0);
                    ref.read(journalProvider.notifier).reload();
                    toast(ref, 'Paper trail cleared');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _bumpCollections(WidgetRef ref) {
    // Versioning toggles are read live from the service; bump collections so
    // any visible lists refresh.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ref.read(dbTickProvider.notifier).state++;
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: NexusPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

Future<String?> showNameDialog(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: initial);
        return AlertDialog(
          title: const Text('Device name'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
          ],
        );
      },
    );

Future<bool> showConfirm(BuildContext context, String title, String message) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: NexusColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    ).then((v) => v ?? false);
