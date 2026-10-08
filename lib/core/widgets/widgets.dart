/// Shared UI kit: panels, toasts, dialogs, file icons, empty states and the
/// small primitives every screen composes from. One consistent voice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../state/app_state.dart';
import '../theme/nexus_theme.dart';

// ── Toasts ──────────────────────────────────────────────────────────────────

class Toast {
  const Toast(this.message, {this.error = false});
  final String message;
  final bool error;
}

class ToastController extends StateNotifier<List<Toast>> {
  ToastController()
      : super(const []);

  void show(String message, {bool error = false}) {
    final t = Toast(message, error: error);
    state = [...state, t];
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (mounted) state = state.where((e) => e != t).toList();
    });
  }
}

final toastProvider =
    StateNotifierProvider<ToastController, List<Toast>>((ref) => ToastController());

class ToastHost extends ConsumerWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider);
    if (toasts.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      bottom: 24,
      right: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final t in toasts.take(4))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: dark ? NexusColors.surface3Dark : NexusColors.navy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: t.error
                        ? NexusColors.danger
                        : (dark ? NexusColors.borderDark : Colors.transparent)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity( 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    t.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: t.error ? NexusColors.danger : NexusColors.ok,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(t.message,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 180.ms).moveY(begin: 8, end: 0, duration: 200.ms, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

// ── Panels & chrome ─────────────────────────────────────────────────────────

class NexusPanel extends StatelessWidget {
  const NexusPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 12,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: dark ? NexusColors.borderDark : NexusColors.borderLight),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.icon});

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Standard page scaffold for tool screens: header row + scrollable body.
class ToolScaffold extends StatelessWidget {
  const ToolScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.icon,
    this.maxWidth = 980,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final IconData? icon;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity( 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Empty states ────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity( 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34,
                color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: dim, height: 1.45),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ).animate().fadeIn(duration: 240.ms);
  }
}

// ── File icons ──────────────────────────────────────────────────────────────

class FileGlyph extends ConsumerWidget {
  const FileGlyph({super.key, required this.category, this.size = 20, this.color});

  final FileCategory category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(lookProvider.select((s) => s.colorblindSafe));
    final c = color ?? categoryColor(category, colorblindSafe: a11y);
    return Icon(_iconFor(category), size: size, color: c);
  }

  static IconData _iconFor(FileCategory c) => switch (c) {
        FileCategory.folder => Icons.folder_rounded,
        FileCategory.image => Icons.image_rounded,
        FileCategory.video => Icons.movie_rounded,
        FileCategory.audio => Icons.music_note_rounded,
        FileCategory.document => Icons.description_rounded,
        FileCategory.archive => Icons.folder_zip_rounded,
        FileCategory.code => Icons.code_rounded,
        FileCategory.font => Icons.text_fields_rounded,
        FileCategory.executable => Icons.terminal_rounded,
        FileCategory.other => Icons.insert_drive_file_rounded,
      };
}

// ── Dialog helpers ──────────────────────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: NexusColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = 'OK',
  IconData? icon,
}) async {
  final ctrl = TextEditingController(text: initial);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: Theme.of(ctx).colorScheme.primary),
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(confirmLabel)),
      ],
    ),
  );
  return (res == null || res.trim().isEmpty) ? null : res;
}

// ── Keyboard hint chip ──────────────────────────────────────────────────────

class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: dark ? NexusColors.surface3Dark : NexusColors.surface2Light,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: dark ? NexusColors.borderDark : NexusColors.borderLight),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFamily: NexusTheme.fontFamily,
              color: dark ? NexusColors.textDimDark : NexusColors.textDimLight)),
    );
  }
}

// ── Two-pane helper for editors ─────────────────────────────────────────────

class SideBySide extends StatelessWidget {
  const SideBySide({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final stacked = box.maxWidth < 720;
      if (stacked) {
        return Column(children: [
          left,
          const SizedBox(height: 16),
          right,
        ]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      );
    });
  }
}

void toast(WidgetRef ref, String msg, {bool error = false}) =>
    ref.read(toastProvider.notifier).show(msg, error: error);
