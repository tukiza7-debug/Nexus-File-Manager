/// Explorer shell — persistent chrome around every route: custom title bar
/// with tabs, ghost mode, keyboard-first shortcuts, pinned docks, the
/// status bar, and every overlay (palette, peek, inspector, tunnel, toasts).
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/services/progress.dart' show OpPhase;
import '../../core/theme/legacy_themes.dart';
import '../../core/theme/nexus_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/enums.dart';
import '../../state/app_state.dart';
import 'screens/chrome.dart';
import 'screens/overlays.dart';
import 'screens/sidebar.dart';
import 'screens/tabs_bar.dart';

class ExplorerShell extends ConsumerStatefulWidget {
  const ExplorerShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ExplorerShell> createState() => _ExplorerShellState();
}

class _ExplorerShellState extends ConsumerState<ExplorerShell>
    implements WindowListener {
  final _filterFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    _filterFocus.dispose();
    super.dispose();
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _undo() async {
    final svc = ref.read(servicesProvider);
    final batch = svc.journal.nextUndoBatch();
    if (batch == null) {
      toast(ref, 'Nothing to undo');
      return;
    }
    try {
      final desc = await svc.journal
          .undoBatch(batch, onError: (msg) async => toast(ref, msg, error: true));
      toast(ref, 'Undone · $desc');
      ref.read(journalProvider.notifier).reload();
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }

  Future<void> _redo() async {
    final svc = ref.read(servicesProvider);
    final batch = svc.journal.nextRedoBatch();
    if (batch == null) {
      toast(ref, 'Nothing to redo');
      return;
    }
    try {
      final desc = await svc.journal
          .redoBatch(batch, onError: (msg) async => toast(ref, msg, error: true));
      toast(ref, 'Redone · $desc');
      ref.read(journalProvider.notifier).reload();
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }

  void _toggleGhost() {
    final notifier = ref.read(uiProvider.notifier);
    if (ref.read(uiProvider).ghostOpacity >= 1.0) {
      notifier.solidGhost();
    } else {
      notifier.restoreGhost();
    }
  }

  Future<void> _pasteIntoCurrent() async {
    await Overlays.showSmartPasteDialog(context, ref,
        destDir: ref.read(tabsProvider).active.path);
  }

  Future<void> _deleteSelection() async {
    final tab = ref.read(tabsProvider).active;
    if (tab.selection.isEmpty) return;
    await Overlays.deletePaths(context, ref, tab.selection.toList(),
        currentPath: tab.path);
  }

  Future<void> _renameSelection() async {
    final tab = ref.read(tabsProvider).active;
    if (tab.selection.length != 1) return;
    await Overlays.renameSingle(context, ref, tab.selection.single);
  }

  Future<void> _saveSessionPrompt() async {
    final name = await promptDialog(context,
        title: 'Save work session',
        hint: 'Session name',
        icon: Icons.bookmark_add_outlined);
    if (name == null) return;
    final svc = ref.read(servicesProvider);
    svc.sessions.save(name, ref.read(tabsProvider.notifier).payload());
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ref.read(dbTickProvider.notifier).state++;
    toast(ref, 'Session “$name” saved');
  }

  void _openSessionSwitcher() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const SessionSwitcherDialog(),
    );
  }

  void _openPalette() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => const CommandPaletteDialog(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiProvider);
    final look = ref.watch(lookProvider);
    final decor = LegacyThemes.decorFor(look.brand,
        Theme.of(context).brightness);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openPalette,
      const SingleActivator(LogicalKeyboardKey.keyP, control: true,
          shift: true): _openPalette,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true,
          shift: true): _redo,
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          () => Overlays.copySelection(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true):
          () => Overlays.cutSelection(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteIntoCurrent,
      const SingleActivator(LogicalKeyboardKey.keyA, control: true):
          () => Overlays.selectAllVisible(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _filterFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
      const SingleActivator(LogicalKeyboardKey.f2): _renameSelection,
      const SingleActivator(LogicalKeyboardKey.f1): () => ref.read(uiProvider.notifier).toggleZen(),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        final u = ref.read(uiProvider);
        if (u.zenMode) ref.read(uiProvider.notifier).toggleZen();
        if (u.focusTunnelPath != null) ref.read(uiProvider.notifier).setFocusTunnel(null);
      },
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): _toggleGhost,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          () => ref.read(uiProvider.notifier).toggleSidebar(),
      const SingleActivator(LogicalKeyboardKey.f5): () {
        ref.read(dirProvider.notifier).reload();
        ref.read(tabsProvider.notifier).refresh();
      },
      const SingleActivator(LogicalKeyboardKey.keyS, control: true,
          shift: true): _openSessionSwitcher,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveSessionPrompt,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
        final t = ref.read(tabsProvider).active;
        ref.read(tabsProvider.notifier).openTab(t.path);
      },
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
        ref.read(tabsProvider.notifier).closeTab(ref.read(tabsProvider).activeId);
      },
      const SingleActivator(LogicalKeyboardKey.keyH, control: true):
          () => ref.read(uiProvider.notifier).toggleHidden(),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
        final sel = ref.read(tabsProvider).active.selection;
        if (sel.isNotEmpty) {
          ref.read(uiProvider.notifier).toggleInspector(sel.first);
        }
      },
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: _GhostWrap(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                _TitleBar(decor: decor, onPalette: _openPalette),
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ui.sidebarVisible && !ui.zenMode)
                            const Sidebar(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(decor.squared ? 0 : 14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(
                                        decor.squared ? 0 : 14),
                                    border: Border.all(
                                        color: decor.borderColor
                                            .withOpacity( 0.7)),
                                  ),
                                  child: widget.child,
                                ),
                              ),
                            ),
                          ),
                          if (ref.watch(uiProvider
                              .select((s) => s.inspectorPath)) !=
                              null)
                            const FloatingInspector(),
                        ],
                      ),
                      // Pinned edge docks + drag action zones.
                      const EdgeDock(edge: Edge.left),
                      const EdgeDock(edge: Edge.right),
                      const EdgeDock(edge: Edge.top),
                      const EdgeDock(edge: Edge.bottom),
                      const DragActionZone(),
                      if (ui.focusTunnelPath != null)
                        const FocusTunnelLayer(),
                      if (ui.zenMode) const ZenOverlay(),
                    ],
                  ),
                ),
                const _StatusBar(),
              ],
            ),
            floatingActionButton: const _MacroFab(),
          ),
        ),
      ),
    );
  }

  @override
  void onWindowClose() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowEvent(String eventName) {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowDocked() {}

  @override
  void onWindowUndocked() {}
}

/// Ghost Mode — desktop: real window opacity; mobile: in-app translucency.
class _GhostWrap extends ConsumerStatefulWidget {
  const _GhostWrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_GhostWrap> createState() => _GhostWrapState();
}

class _GhostWrapState extends ConsumerState<_GhostWrap> {
  double? _applied;

  void _apply(double opacity) {
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        windowManager.setOpacity(opacity);
        _applied = opacity;
        return;
      } catch (_) {}
    }
    _applied = opacity;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(uiProvider.select((s) => s.ghostOpacity), (_, next) {
      if (_applied != next) _apply(next);
    });
    final opacity = ref.watch(uiProvider.select((s) => s.ghostOpacity));
    final desktopHandled = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final w = widget.child;
    return desktopHandled
        ? w
        : Opacity(opacity: opacity.clamp(0.25, 1.0), child: w);
  }
}

// ── Title bar ───────────────────────────────────────────────────────────────

class _TitleBar extends ConsumerStatefulWidget {
  const _TitleBar({required this.decor, required this.onPalette});

  final LegacyDecor decor;
  final VoidCallback onPalette;

  @override
  ConsumerState<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends ConsumerState<_TitleBar> {
  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    final ghostOn = ref.watch(uiProvider.select((s) => s.ghostOpacity)) < 1.0;
    final zen = ref.watch(uiProvider.select((s) => s.zenMode));

    final bar = Container(
      height: 46,
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        gradient: widget.decor.titleBarGradient,
        border: Border(
            bottom: BorderSide(color: widget.decor.borderColor)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo/nexus-icon.png',
            width: 22,
            height: 22,
            errorBuilder: (_, __, ___) => const Icon(Icons.hub_rounded,
                size: 20, color: NexusColors.blueSoft),
          ),
          const SizedBox(width: 9),
          if (!zen)
            const Expanded(child: TabsBar())
          else ...[
            Text('Zen',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
          ],
          if (!zen) ...[
            _IconBtn(Icons.search_rounded, 'Command palette  ·  Ctrl K',
                widget.onPalette),
            _IconBtn(ghostOn ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                'Ghost mode  ·  Ctrl G',
                () {
                  final notifier = ref.read(uiProvider.notifier);
                  if (ref.read(uiProvider).ghostOpacity >= 1.0) {
                    notifier.restoreGhost();
                  } else {
                    notifier.solidGhost();
                  }
                }),
          ],
          _IconBtn(
              zen ? Icons.fullscreen_exit_rounded : Icons.self_improvement_rounded,
              zen ? 'Exit Zen  ·  F1' : 'Zen mode  ·  F1',
              () => ref.read(uiProvider.notifier).toggleZen()),
          if (_isDesktop) ...const [
            SizedBox(width: 6),
            _WindowControls(),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );

    if (!_isDesktop) return bar;
    return DragToMoveArea(child: bar);
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.icon, this.tip, this.onTap);

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 19),
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinBtn(Icons.horizontal_rule_rounded, 'Minimize',
            windowManager.minimize),
        _WinBtn(Icons.crop_square_rounded, 'Maximize',
            () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }),
        _WinBtn(Icons.close_rounded, 'Close',
            windowManager.close, danger: true),
      ],
    );
  }
}

class _WinBtn extends StatelessWidget {
  const _WinBtn(this.icon, this.tip, this.onTap, {this.danger = false});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        hoverColor: danger
            ? NexusColors.danger
            : Theme.of(context).colorScheme.onSurface.withOpacity( 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Icon(icon, size: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.75)),
        ),
      ),
    );
  }
}

class DragToMoveArea extends StatelessWidget {
  const DragToMoveArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        if (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
          windowManager.startDragging();
        }
      },
      child: child,
    );
  }
}

// ── Macro FAB ───────────────────────────────────────────────────────────────

class _MacroFab extends ConsumerWidget {
  const _MacroFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording =
        ref.watch(macroRecordingProvider).valueOrNull ?? false;
    if (!recording) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      backgroundColor: NexusColors.danger,
      foregroundColor: Colors.white,
      onPressed: () => context.go('/tools/automation'),
      icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
      label: const Text('Recording macro'),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn().shake();
  }
}

// ── Status bar ──────────────────────────────────────────────────────────────

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tab = ref.watch(tabsProvider.select((s) => s.active));
    final dir = ref.watch(dirProvider);
    ref.watch(clipboardProvider);
    final clipCount = ref.read(servicesProvider).clipboard.items.length;
    final selCount = tab.selection.length;
    final progress = ref.watch(progressProvider).valueOrNull;
    final look = ref.watch(lookProvider);

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: dark ? NexusColors.bgDark : NexusColors.bgLight,
        border: Border(top: BorderSide(color: decorBorder(look, dark))),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${dir.entries.length} items'
              '${selCount > 0 ? '  ·  $selCount selected' : ''}',
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (clipCount > 0) ...[
            const SizedBox(width: 12),
            const Icon(Icons.content_copy_rounded, size: 11, color: NexusColors.blueSoft),
            const SizedBox(width: 4),
            Text('$clipCount in stack',
                style: Theme.of(context).textTheme.labelSmall),
          ],
          const Spacer(),
          if (progress != null && progress.phase == OpPhase.running) ...[
            SizedBox(
              width: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${progress.title} · ${progress.done}/${progress.total}',
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }

  Color decorBorder(LookState look, bool dark) {
    final decor = LegacyThemes.decorFor(look.brand, dark ? Brightness.dark : Brightness.light);
    return decor.borderColor;
  }
}


