/// Automation Studio part 2 — Scheduler, Template Drop, Batch Rule Engine
/// and the Batch Metadata Editor tabs.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/rule_engine.dart';
import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/utils/result.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show metaEditTargetProvider;

// ── Scheduler ───────────────────────────────────────────────────────────────

class SchedulerTab extends ConsumerWidget {
  const SchedulerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(schedulesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Scheduled Actions run while Nexus is open: one-shot or repeating jobs on folders and pipelines.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _addJob(context, ref),
              icon: const Icon(Icons.add_alarm_rounded, size: 17),
              label: const Text('New job'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (jobs.isEmpty)
          const EmptyState(
            icon: Icons.schedule_rounded,
            title: 'No scheduled actions',
            message:
                'Examples: empty your downloads every morning, mirror a folder hourly, or run a cleanup pipeline nightly.',
          ),
        for (final j in jobs)
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(_kindIcon(j.kind),
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${j.kind} · ${j.scheduleLabel}'
                        '${j.lastRunMs == null ? '' : ' · last ${f.formatRelative(DateTime.fromMillisecondsSinceEpoch(j.lastRunMs!))}'}'
                        '${j.lastStatus.isEmpty ? '' : ' · ${j.lastStatus}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: j.enabled,
                  onChanged: (v) {
                    ref.read(servicesProvider).db.saveSchedule(j.copyWith(enabled: v));
                    _bump(ref);
                  },
                ),
                IconButton(
                  tooltip: 'Run now',
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  onPressed: () async {
                    await ref.read(servicesProvider).scheduler.run(j.id!);
                    _bump(ref);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  onPressed: () {
                    ref.read(servicesProvider).db.deleteSchedule(j.id!);
                    _bump(ref);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'copy' => Icons.content_copy_rounded,
        'move' => Icons.drive_file_move_rounded,
        'trash' => Icons.delete_outline_rounded,
        'compress' => Icons.folder_zip_rounded,
        'pipeline' => Icons.account_tree_rounded,
        'mirror' => Icons.sync_rounded,
        _ => Icons.schedule_rounded,
      };

  Future<void> _addJob(BuildContext context, WidgetRef ref) async {
    final name = await promptDialog(context,
        title: 'Job name', initial: 'Nightly cleanup');
    if (name == null) return;
    if (!context.mounted) return;
    final kind = await _pick(context, 'Action', const [
      ('copy', 'Copy folder A → B'),
      ('move', 'Move folder A → B'),
      ('trash', 'Move folder A to backup trash'),
      ('compress', 'Zip folder A'),
      ('pipeline', 'Run pipeline on folder A'),
    ]);
    if (kind == null || !context.mounted) return;
    final source = await promptDialog(context,
        title: 'Target folder (A)', initial: ref.read(tabsProvider).active.path);
    if (source == null) return;
    String? dest;
    if (kind == 'copy' || kind == 'move') {
      if (!context.mounted) return;
      dest = await promptDialog(context, title: 'Destination (B)', hint: '/path');
      if (dest == null) return;
    }
    if (!context.mounted) return;
    final every = await promptDialog(context,
        title: 'Repeat every N minutes (60 = hourly, 1440 = daily)',
        initial: '1440');
    if (every == null) return;
    final minutes = int.tryParse(every) ?? 1440;

    final svc = ref.read(servicesProvider);
    svc.db.saveSchedule(ScheduleJob(
      name: name,
      kind: kind,
      targets: {'source': source, if (dest != null) 'dest': dest},
      arg: '',
      intervalMin: minutes,
      enabled: true,
    ));
    _bump(ref);
    toast(ref, 'Job “$name” scheduled');
  }

  Future<String?> _pick(
      BuildContext context, String title, List<(String, String)> options) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (v, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Text(label),
            ),
        ],
      ),
    );
  }
}

// ── Template drop ───────────────────────────────────────────────────────────

class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Templates are files, folders or text snippets you drop into any folder instantly. Tokens like {name}, {date}, {time} are substituted.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _addTemplate(context, ref),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New template'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (templates.isEmpty)
          const EmptyState(
            icon: Icons.dashboard_customize_rounded,
            title: 'No templates yet',
            message:
                'Turn a project skeleton folder, an invoice file or a meeting-notes snippet into a template — then instantiate it anywhere in two taps.',
          ),
        for (final t in templates)
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  switch (t.kind) {
                    'dir' => Icons.folder_copy_rounded,
                    'text' => Icons.notes_rounded,
                    _ => Icons.file_copy_rounded,
                  },
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${t.kind} · ${t.sourcePath.isEmpty && t.content != null ? 'inline content' : pu.compactPath(t.sourcePath)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _instantiate(context, ref, t),
                  icon: const Icon(Icons.launch_rounded, size: 15),
                  label: const Text('Drop here'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  onPressed: () {
                    ref.read(servicesProvider).templates.delete(t.id!);
                    _bump(ref);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addTemplate(BuildContext context, WidgetRef ref) async {
    final name = await promptDialog(context,
        title: 'Template name', initial: 'Meeting notes');
    if (name == null || !context.mounted) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Template type'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'text'),
            child: const Text('Text snippet'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const Text('From a file in this folder'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'dir'),
            child: const Text('From a folder (skeleton)'),
          ),
        ],
      ),
    );
    if (kind == null) return;

    final svc = ref.read(servicesProvider);
    var sourcePath = '';
    String? content;
    if (kind == 'text') {
      if (!context.mounted) return;
      content = await promptDialog(context,
          title: 'Template content', hint: 'Supports {name} {date} {time}');
      if (content == null) return;
    } else {
      if (!context.mounted) return;
      final entries = ref.read(dirProvider).entries;
      final pick = await showDialog<NexusEntry>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Pick the source'),
          children: [
            for (final e in entries.where((e) =>
                kind == 'dir' ? e.isDir : !e.isDir).take(30))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e),
                child: Text(e.name),
              ),
          ],
        ),
      );
      if (pick == null) return;
      sourcePath = pick.path;
    }
    svc.templates.save(TemplateFile(
        name: name, kind: kind, sourcePath: sourcePath, content: content));
    _bump(ref);
    toast(ref, 'Template “$name” saved');
  }

  Future<void> _instantiate(
      BuildContext context, WidgetRef ref, TemplateFile t) async {
    final destDir = ref.read(tabsProvider).active.path;
    final name = await promptDialog(context,
        title: 'Instance name', hint: 'Tokens {name} {date} apply');
    if (name == null) return;
    try {
      final path = await ref
          .read(servicesProvider)
          .templates
          .instantiate(t, destDir, name);
      toast(ref, 'Created ${pu.basename(path)}');
      ref.read(tabsProvider.notifier).refresh();
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }
}

// ── Batch rule engine ───────────────────────────────────────────────────────

class RulesTab extends ConsumerStatefulWidget {
  const RulesTab({super.key});

  @override
  ConsumerState<RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends ConsumerState<RulesTab> {
  List<RulePlanEntry>? _plan;

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'If-then rules over the current folder: match on name, extension, size or modified time — then rename, move, trash or freeze.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _editRule(context, ref, null),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New rule'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rules.isEmpty)
          const EmptyState(
            icon: Icons.rule_rounded,
            title: 'No rules yet',
            message:
                'Example: “if extension is log and size greater than 10 MB → move to Archive”. Rules run on demand and preview every planned action first.',
          ),
        for (final r in rules)
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.rule_rounded,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'match ${r.match}: ${r.conditions.map((c) => '${c.field} ${c.match} ${c.value}').join(' AND ')}'
                        ' → ${r.actions.map((a) => '${a.kind} ${a.arg}'.trim()).join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: r.enabled,
                  onChanged: (v) {
                    ref.read(servicesProvider).db.saveRule(r.copyWith(enabled: v));
                    _bump(ref);
                  },
                ),
                IconButton(
                  tooltip: 'Test on this folder',
                  icon: const Icon(Icons.science_rounded, size: 17),
                  onPressed: () => _test(context, ref, r),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  onPressed: () => _editRule(context, ref, r),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  onPressed: () {
                    ref.read(servicesProvider).db.deleteRule(r.id!);
                    _bump(ref);
                  },
                ),
              ],
            ),
          ),
        if (_plan != null) ...[
          const SizedBox(height: 12),
          const SectionHeader('Test result — what this rule would do now',
              icon: Icons.science_rounded),
          NexusPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in _plan!)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      p.action == 'noop' ? Icons.remove_rounded : Icons.bolt_rounded,
                      size: 15,
                      color: p.action == 'noop' ? Colors.grey : NexusColors.warn,
                    ),
                    title: Text(p.entry.name, style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(
                      p.action == 'noop' ? 'no action' : '${p.action} ${p.arg}'.trim(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _test(BuildContext context, WidgetRef ref, NexusRule r) async {
    final svc = ref.read(servicesProvider);
    final entries = await svc.fs.listDir(ref.read(tabsProvider).active.path);
    setState(() {
      _plan = svc.ruleEngine.plan(r, entries.where((e) => !e.isHidden).toList());
    });
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, NexusRule? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RuleEditor(rule: existing),
    );
    if (saved ?? false) _bump(ref);
  }
}

class _RuleEditor extends ConsumerStatefulWidget {
  const _RuleEditor({required this.rule});

  final NexusRule? rule;

  @override
  ConsumerState<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<_RuleEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.rule?.name ?? 'New rule');
  late String _match = widget.rule?.match ?? 'all';
  late final List<RuleCondition> _conds = [...?widget.rule?.conditions];
  late final List<RuleAction> _acts = [...?widget.rule?.actions];

  static const _fields = ['name', 'ext', 'path', 'size', 'mtime'];
  static const _matches = ['contains', 'equals', 'glob', 'gt', 'lt', 'within'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit rule'),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Rule name'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Match', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                ChoiceChip(
                  label: const Text('ALL conditions'),
                  selected: _match == 'all',
                  onSelected: (_) => setState(() => _match = 'all'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('ANY'),
                  selected: _match == 'any',
                  onSelected: (_) => setState(() => _match = 'any'),
                ),
              ],
            ),
            for (var i = 0; i < _conds.length; i++) _conditionRow(i),
            TextButton.icon(
              onPressed: () => setState(() => _conds.add(
                  const RuleCondition(field: 'name', match: 'contains', value: ''))),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Add condition'),
            ),
            const Divider(),
            Text('Actions', style: Theme.of(context).textTheme.titleSmall),
            for (final a in _acts)
              ListTile(
                dense: true,
                title: Text('${a.kind} · ${a.arg}'.trim()),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  onPressed: () => setState(() => _acts.remove(a)),
                ),
              ),
            Wrap(
              spacing: 6,
              children: [
                for (final (kind, hint) in const [
                  ('rename', 'pattern with {name} {n}'),
                  ('move', '/destination'),
                  ('trash', ''),
                  ('freeze', ''),
                ])
                  ActionChip(
                    label: Text(kind),
                    onPressed: () async {
                      final arg = hint.isEmpty
                          ? ''
                          : await promptDialog(context, title: kind, hint: hint);
                      if (arg == null && hint.isNotEmpty) return;
                      setState(() =>
                          _acts.add(RuleAction(kind: kind, arg: arg ?? '')));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final svc = ref.read(servicesProvider);
            svc.db.saveRule(NexusRule(
              id: widget.rule?.id,
              name: _name.text,
              enabled: widget.rule?.enabled ?? true,
              match: _match,
              conditions: _conds,
              actions: _acts,
            ));
            Navigator.pop(context, true);
            toast(ref, 'Rule “${_name.text}” saved');
          },
          child: const Text('Save rule'),
        ),
      ],
    );
  }

  Widget _conditionRow(int i) {
    final c = _conds[i];
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: c.field,
            items: [
              for (final f in _fields) DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => _conds[i] =
                RuleCondition(field: v ?? 'name', match: c.match, value: c.value)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: c.match,
            items: [
              for (final m in _matches) DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _conds[i] =
                RuleCondition(field: c.field, match: v ?? 'contains', value: c.value)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(
            controller: TextEditingController(text: c.value),
            decoration: const InputDecoration(hintText: 'value', isDense: true),
            onChanged: (v) =>
                _conds[i] = RuleCondition(field: c.field, match: c.match, value: v),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 14),
          onPressed: () => setState(() => _conds.removeAt(i)),
        ),
      ],
    );
  }
}
class MetadataTab extends ConsumerStatefulWidget {
  const MetadataTab({super.key});

  @override
  ConsumerState<MetadataTab> createState() => _MetadataTabState();
}

class _MetadataTabState extends ConsumerState<MetadataTab> {
  final _ctrls = {
    'title': TextEditingController(),
    'artist': TextEditingController(),
    'album': TextEditingController(),
    'year': TextEditingController(),
    'genre': TextEditingController(),
    'description': TextEditingController(),
    'camera': TextEditingController(),
  };
  List<String> _targets = const [];
  EntryMeta? _current;
  String _loadedFor = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = ref.read(metaEditTargetProvider);
      if (target.isNotEmpty) {
        _setTargets([target]);
      } else {
        final sel = ref.read(tabsProvider).active.selection.toList();
        if (sel.isNotEmpty) _setTargets(sel);
      }
    });
  }

  Future<void> _setTargets(List<String> paths) async {
    paths = paths.where(FileSystemEntity.isFileSync).toList();
    setState(() => _targets = paths);
    if (paths.isEmpty) {
      setState(() { _current = null; _loadedFor = ''; });
      return;
    }
    try {
      final meta = await ref.read(servicesProvider).metadata.read(paths.first);
      setState(() {
        _current = meta;
        _loadedFor = paths.first;
        _ctrls['title']!.text = meta.title ?? '';
        _ctrls['artist']!.text = meta.artist ?? '';
        _ctrls['album']!.text = meta.album ?? '';
        _ctrls['year']!.text = meta.year ?? '';
        _ctrls['genre']!.text = meta.genre ?? '';
        _ctrls['description']!.text = meta.description ?? '';
        _ctrls['camera']!.text = meta.camera ?? '';
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(dirProvider.select((s) => s.entries));
    final sel = ref.watch(tabsProvider.select((s) => s.active.selection));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Edit EXIF (photos), ID3 (music) and Office/PDF document properties in batch. Fill a field, pick targets, write.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in entries.where((e) => !e.isDir).take(20))
              FilterChip(
                label: Text(e.name, style: const TextStyle(fontSize: 11)),
                selected: _targets.contains(e.path) || sel.contains(e.path),
                onSelected: (v) => _setTargets(
                    v ? [..._targets, e.path] : _targets.where((p) => p != e.path).toList()),
              ),
            if (sel.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.checklist_rounded, size: 14),
                label: Text('Use selection (${sel.length})',
                    style: const TextStyle(fontSize: 11)),
                onPressed: () => _setTargets(sel.toList()),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_current != null)
          NexusPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _targets.length == 1
                            ? pu.basename(_loadedFor)
                            : '${_targets.length} files — writing to all',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(_current!.describe(),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in _ctrls.entries)
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: e.value,
                          decoration: InputDecoration(
                            labelText: e.key,
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy || _targets.isEmpty ? null : _write,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 17),
                  label: Text('Write metadata to ${_targets.length} file(s)'),
                ),
              ],
            ),
          )
        else
          const EmptyState(
            icon: Icons.edit_note_rounded,
            title: 'Pick files to edit',
            message:
                'Choose audio files to tag titles and albums, photos to set descriptions and artists, or documents to rewrite their properties — all from one form.',
          ),
      ],
    );
  }

  Future<void> _write() async {
    setState(() => _busy = true);
    final svc = ref.read(servicesProvider);
    final fields = {
      for (final e in _ctrls.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    try {
      for (final t in _targets) {
        final ext = pu.ext(t);
        if (const ['mp3', 'flac', 'ogg', 'wav', 'm4a'].contains(ext)) {
          await svc.metadata.writeId3(t, fields);
        } else if (const ['jpg', 'jpeg'].contains(ext)) {
          await svc.metadata.writeJpegExif(t, fields);
        } else if (const ['docx', 'xlsx', 'pptx', 'epub'].contains(ext)) {
          await svc.metadata.writeDocumentProps(t, fields);
        } else {
          throw NexusException('No metadata writer for ${pu.basename(t)}');
        }
      }
      toast(ref, 'Metadata written to ${_targets.length} file(s)');
      ref.read(journalProvider.notifier).reload();
    } catch (e) {
      toast(ref, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
