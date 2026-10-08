/// Explorer screen — breadcrumb bar, the content views, external file drops,
/// and the Alt-hover peek card. Composes everything the shell provides.
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/fs_service.dart';
import '../../../core/theme/nexus_theme.dart';
import '../../../core/utils/path_utils.dart' as pu;
import '../../../core/widgets/widgets.dart';
import '../../../domain/models.dart';
import '../../../state/app_state.dart';
import 'breadcrumb_bar.dart';
import 'file_views.dart';

class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key});

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dirProvider.notifier).reload();
      ref.read(journalProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(lookProvider);

    return Column(
      children: [
        if (!look.touchMode) const BreadcrumbBar(),
        Expanded(
          child: Stack(
            children: [
              DropTarget(
                onDragEntered: (_) {},
                onDragDone: (details) => _onExternalDrop(details.files
                    .map((x) => x.path)
                    .whereType<String>()
                    .toList()),
                onDragExited: (_) {},
                child: const FileViews(),
              ),
              // Peek preview card (Alt+hover or palette).
              const _PeekCard(),
              Positioned.fill(
                child: Consumer(builder: (context, ref, _) {
                  final tunnel = ref.watch(
                      uiProvider.select((s) => s.focusTunnelPath));
                  if (tunnel == null) return const SizedBox.shrink();
                  return GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onTap: () => ref.read(uiProvider.notifier).setFocusTunnel(null),
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        pu.basename(tunnel),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onExternalDrop(List<String> paths) async {
    if (paths.isEmpty) return;
    final dest = ref.read(tabsProvider).active.path;
    final svc = ref.read(servicesProvider);
    final dirs = paths.where(FileSystemEntity.isDirectorySync).toList();
    final files = paths.where(FileSystemEntity.isFileSync).toList();

    final batch = svc.journal.newBatch('drop-in');
    try {
      if (dirs.isNotEmpty) {
        await svc.ops.copyPaths(dirs, dest, batchId: batch);
      }
      if (files.isNotEmpty) {
        await svc.ops.copyPaths(files, dest, batchId: batch);
      }
      svc.ops.finish(batch);
      toast(ref, 'Dropped ${paths.length} item(s) into ${pu.basename(dest)}');
    } catch (e) {
      toast(ref, '$e', error: true);
    }
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }
}

/// Floating peek card: rich preview of the file under Alt+hover.
class _PeekCard extends ConsumerStatefulWidget {
  const _PeekCard();

  @override
  ConsumerState<_PeekCard> createState() => _PeekCardState();
}

class _PeekCardState extends ConsumerState<_PeekCard> {
  String? _peekFor;
  String? _head;
  EntryMeta? _meta;

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(uiProvider.select((s) => s.peekPath));
    final dir = ref.watch(dirProvider);
    if (path == null) return const SizedBox.shrink();

    final entry = dir.entries.where((e) => e.path == path).firstOrNull;
    if (_peekFor != path) {
      _peekFor = path;
      _loadPreview(path);
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      right: 18,
      bottom: 18,
      child: Material(
        elevation: 20,
        borderRadius: BorderRadius.circular(14),
        color: dark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
        child: Container(
          width: 300,
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
                  FileGlyph(
                      category: entry?.category ??
                          FileSystemService.categorize(pu.basename(path))),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry?.name ?? pu.basename(path),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    onPressed: () => ref.read(uiProvider.notifier).setPeek(null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isImage(path) && File(path).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: Image.file(
                      File(path),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                )
              else if (_head != null && _head!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: dark ? NexusColors.bgDark : NexusColors.surface2Light,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _head!,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        fontFamily: 'monospace',
                        color: dark ? NexusColors.textDimDark : NexusColors.textDimLight),
                  ),
                ),
              if (_meta != null) ...[
                const SizedBox(height: 8),
                Text(_meta!.describe(), style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 12, color: NexusColors.warn),
                  const SizedBox(width: 4),
                  Text('Alt + hover to peek · Ctrl I to pin inspector',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isImage(String path) =>
      const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(pu.ext(path));

  Future<void> _loadPreview(String path) async {
    String? head;
    EntryMeta? meta;
    if (!File(path).existsSync()) {
      if (mounted) setState(() { _head = ''; _meta = null; });
      return;
    }
    if (!_isImage(path)) {
      head = FileSystemService.readHead(path, bytes: 2048);
    }
    try {
      meta = await ref.read(servicesProvider).metadata.read(path);
    } catch (_) {}
    if (mounted) setState(() { _head = head; _meta = meta; });
  }
}
