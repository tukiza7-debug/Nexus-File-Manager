/// Content-Aware Rename — scans EXIF/ID3/document metadata and proposes
/// names built from what each file actually contains. Editable per-file,
/// then applied as one undoable batch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';

class ContentRenameScreen extends ConsumerStatefulWidget {
  const ContentRenameScreen({super.key});

  @override
  ConsumerState<ContentRenameScreen> createState() => _ContentRenameScreenState();
}

class _ContentRenameScreenState extends ConsumerState<ContentRenameScreen> {
  final _patternCtrl =
      TextEditingController(text: '{date}_{title}.{ext}');
  List<RenameCandidate> _candidates = [];
  bool _scanning = false;
  String _folder = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _folder = ref.read(tabsProvider).active.path));
  }

  Future<void> _scan() async {
    final svc = ref.read(servicesProvider);
    setState(() => _scanning = true);
    try {
      final entries = (await svc.fs.listDir(_folder))
          .where((e) => !e.isDir && !e.isHidden)
          .toList();
      final out = <RenameCandidate>[];
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        try {
          final meta = await svc.metadata.read(e.path);
          out.add(RenameCandidate(
            entry: e,
            meta: meta,
            suggested: _suggest(e, meta, i),
            newName: _suggest(e, meta, i),
          ));
        } catch (_) {
          out.add(RenameCandidate(
              entry: e, meta: const EntryMeta(), suggested: e.name, newName: e.name));
        }
      }
      setState(() => _candidates = out);
    } catch (e) {
      if (mounted) toast(ref, '$e', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _suggest(NexusEntry e, EntryMeta meta, int i) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = meta.taken ?? e.modified;
    final title = (meta.title ?? meta.artist ?? '').isNotEmpty
        ? (meta.title ?? meta.artist ?? '')
            .replaceAll(RegExp(r'[\\/:*?\"<>|]'), '')
            .trim()
        : 'file-${i + 1}';
    final camera = (meta.camera ?? '').replaceAll(RegExp(r'\s+'), '');
    return _patternCtrl.text
        .replaceAll('{date}', '${date.year}-${two(date.month)}-${two(date.day)}')
        .replaceAll('{time}', '${two(date.hour)}${two(date.minute)}')
        .replaceAll('{title}', title)
        .replaceAll('{artist}', meta.artist ?? '')
        .replaceAll('{album}', meta.album ?? '')
        .replaceAll('{camera}', camera)
        .replaceAll('{n}', '${i + 1}')
        .replaceAll('{ext}', e.ext.isEmpty ? pu.ext(e.name) : e.ext)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _reapply() {
    setState(() {
      for (var i = 0; i < _candidates.length; i++) {
        final c = _candidates[i];
        if (c.suggested != c.entry.name) continue; // user edited → keep
        _candidates[i] = c.withName(_suggest(c.entry, c.meta, i));
      }
    });
  }

  Future<void> _apply() async {
    final svc = ref.read(servicesProvider);
    final batch = svc.journal.newBatch('content-rename');
    var n = 0;
    try {
      for (final c in _candidates) {
        final newName = c.newName.trim();
        if (newName.isEmpty || newName == c.entry.name) continue;
        final target = pu.join(c.entry.parent,
            '$newName${c.entry.ext.isEmpty ? '' : '.'}${c.entry.ext.isEmpty ? '' : c.entry.ext}');
        if (c.entry.ext.isNotEmpty && !target.endsWith('.${c.entry.ext}')) {
          await svc.ops.rename(
              c.entry.path, pu.join(c.entry.parent, '$newName.${c.entry.ext}'),
              batchId: batch);
        } else {
          await svc.ops.rename(c.entry.path, target, batchId: batch);
        }
        n++;
      }
      svc.ops.finish(batch);
      toast(ref, 'Renamed $n file(s) from their content');
      ref.read(journalProvider.notifier).reload();
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changes = _candidates
        .where((c) => _finalName(c) != c.entry.name)
        .length;

    return ToolScaffold(
      title: 'Content-Aware Rename',
      subtitle:
          'Files renamed by what they contain — EXIF dates, song titles, document names.',
      icon: Icons.auto_fix_high_rounded,
      actions: [
        if (_candidates.isNotEmpty)
          FilledButton.icon(
            onPressed: changes == 0 ? null : _apply,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('Apply $changes renames'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexusPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PATTERN', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _patternCtrl,
                  onChanged: (_) => _reapply(),
                  decoration: const InputDecoration(
                    hintText: '{date}_{title}.{ext}',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in const [
                      '{date}', '{time}', '{title}', '{artist}', '{album}',
                      '{camera}', '{n}', '{ext}',
                    ])
                      ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          _patternCtrl.text = '${_patternCtrl.text}$t';
                          _reapply();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Folder: $_folder',
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _scanning ? null : _scan,
                      icon: _scanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.radar_rounded, size: 17),
                      label: const Text('Scan folder'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_candidates.isEmpty)
            const EmptyState(
              icon: Icons.radar_rounded,
              title: 'Scan a folder to begin',
              message:
                  'Nexus reads each file: photos give capture date and camera, songs give title/artist/album, PDFs and Office documents give their titles. Names update live as you edit the pattern.',
            )
          else
            NexusPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final c in _candidates)
                    ListTile(
                      dense: true,
                      leading: FileGlyph(category: c.entry.category, size: 18),
                      title: Text(c.entry.name,
                          style: const TextStyle(fontSize: 12.5)),
                      subtitle: c.meta.describe() == 'No metadata found'
                          ? null
                          : Text(c.meta.describe(),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      trailing: SizedBox(
                        width: 240,
                        child: TextField(
                          controller:
                              TextEditingController(text: _finalName(c)),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) =>
                              setState(() => _candidates[_candidates.indexOf(c)] =
                                  c.withName(v)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _finalName(RenameCandidate c) => c.newName;
}
