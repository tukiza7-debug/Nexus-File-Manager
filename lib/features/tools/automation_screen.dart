/// Automation Studio — tabbed shell over Macros (record/play), Watchdog
/// rules with live event feed, Scheduler, Templates, Rules and Metadata.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/macro_service.dart';
import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import 'automation2_screen.dart';

class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const tabs = [
      (Icons.fiber_manual_record_rounded, 'Macros'),
      (Icons.radar_rounded, 'Watchdog'),
      (Icons.schedule_rounded, 'Scheduler'),
      (Icons.dashboard_customize_rounded, 'Templates'),
      (Icons.rule_rounded, 'Rules'),
      (Icons.edit_note_rounded, 'Metadata'),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: ToolScaffold(
        title: 'Automation Studio',
        subtitle:
            'Record repetitive work once — Nexus repeats it forever, verifiably.',
        icon: Icons.auto_mode_rounded,
        maxWidth: 1100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final (icon, label) in tabs)
                  Tab(height: 38, child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 14),
                    const SizedBox(width: 6),
                    Text(label),
                  ])),
              ],
            ),
            const SizedBox(height: 14),
            const Expanded(
              child: TabBarView(
                children: [
                  MacrosTab(),
                  WatchdogTab(),
                  SchedulerTab(),
                  TemplatesTab(),
                  RulesTab(),
                  MetadataTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Macro recorder ──────────────────────────────────────────────────────────

class MacrosTab extends ConsumerStatefulWidget {
  const MacrosTab({super.key});

  @override
  ConsumerState<MacrosTab> createState() => _MacrosTabState();
}

class _MacrosTabState extends ConsumerState<MacrosTab> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final macros = ref.watch(macrosProvider);
    final svc = ref.read(servicesProvider);
    final recording = ref.watch(macroRecordingProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusPanel(
          child: Row(
            children: [
              Icon(
                recording ? Icons.fiber_manual_record_rounded : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: recording ? NexusColors.danger : NexusColors.textDimDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recording ? 'Recording — perform file actions now' : 'Macro recorder',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      recording
                          ? '${svc.macros.liveSteps.length} step(s) captured · stop to save'
                          : 'Start recording, do the work (copy, move, rename…), stop and save as a replayable macro.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (recording)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: NexusColors.danger),
                  onPressed: () => _stopAndSave(context, ref),
                  icon: const Icon(Icons.stop_rounded, size: 17),
                  label: const Text('Stop & save'),
                )
              else
                FilledButton.icon(
                  onPressed: () {
                    svc.macros.startRecording();
                    setState(() {});
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Record'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (macros.isEmpty)
          const EmptyState(
            icon: Icons.smart_toy_rounded,
            title: 'No macros saved',
            message:
                'Anything you do while recording becomes a macro: paste into three folders, rename batches, archive sets. Play it back on any folder later — every step is a real, undoable operation.',
          ),
        for (final m in macros)
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.smart_toy_rounded,
                        size: 17, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(m.name,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Text('${m.steps.length} steps · ${f.formatRelative(
                        DateTime.fromMillisecondsSinceEpoch(m.createdAtMs))}',
                        style: Theme.of(context).textTheme.labelSmall),
                    IconButton(
                      tooltip: _openId == m.id ? 'Hide steps' : 'Show steps',
                      icon: Icon(
                          _openId == m.id
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 17),
                      onPressed: () => setState(() =>
                          _openId = _openId == m.id ? null : m.id),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _play(context, ref, m),
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: const Text('Play here'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      onPressed: () {
                        svc.macros.delete(m.id!);
                        _bump(ref);
                      },
                    ),
                  ],
                ),
                if (_openId == m.id) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < m.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 3),
                      child: Row(
                        children: [
                          Text('#${i + 1}',
                              style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(width: 8),
                          Text(m.steps[i].action,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _describeArgs(m.steps[i].args),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                              '+${MacroService.delayFor(m.steps, i).inMilliseconds} ms',
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _describeArgs(Map<String, dynamic> args) {
    final parts = <String>[];
    args.forEach((k, v) {
      if (v is List) {
        parts.add('$k: ${v.length} item(s)');
      } else {
        parts.add('$k: ${pu.compactPath('$v')}');
      }
    });
    return parts.join(' · ');
  }

  Future<void> _stopAndSave(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(servicesProvider);
    final steps = svc.macros.stopRecording();
    if (steps.isEmpty) {
      toast(ref, 'No actions were captured');
      return;
    }
    final name = await promptDialog(context,
        title: 'Save macro', hint: 'e.g. Weekly photo sort', icon: Icons.smart_toy_rounded);
    if (name == null) return;
    svc.macros.save(name, steps);
    _bump(ref);
    toast(ref, 'Macro “$name” saved with ${steps.length} steps');
  }

  Future<void> _play(BuildContext context, WidgetRef ref, NexusMacro m) async {
    final svc = ref.read(servicesProvider);
    final dest = ref.read(tabsProvider).active.path;
    var executed = 0;
    for (var i = 0; i < m.steps.length; i++) {
      final step = m.steps[i];
      await Future<void>.delayed(MacroService.delayFor(m.steps, i));
      try {
        await _execStep(svc, step, dest);
        executed++;
      } catch (e) {
        toast(ref, 'Step ${i + 1} failed: $e', error: true);
        break;
      }
    }
    toast(ref, 'Macro finished — $executed step(s) applied');
    ref.read(journalProvider.notifier).reload();
    ref.read(tabsProvider.notifier).refresh();
  }

  Future<void> _execStep(dynamic svc, MacroStep step, String dest) async {
    final args = step.args;
    switch (step.action) {
      case 'copy':
        await svc.ops.copyPaths(
            (args['sources'] as List).cast<String>(), dest,
            batchId: svc.journal.newBatch('macro'));
      case 'move':
        await svc.ops.movePaths(
            (args['sources'] as List).cast<String>(),
            (args['dest'] as String?) ?? dest,
            batchId: svc.journal.newBatch('macro'));
      case 'delete':
        await svc.ops.deletePaths((args['paths'] as List).cast<String>(),
            batchId: svc.journal.newBatch('macro'));
      case 'rename':
        await svc.ops.rename(args['from'] as String, args['to'] as String,
            batchId: svc.journal.newBatch('macro'));
      case 'mkdir':
        await svc.ops.mkdir(args['path'] as String,
            batchId: svc.journal.newBatch('macro'));
      case 'compress':
        await svc.ops.compressToZip(
            (args['sources'] as List).cast<String>(),
            (args['zip'] as String?) ?? pu.join(dest, 'macro-archive.zip'),
            batchId: svc.journal.newBatch('macro'));
      case 'paste':
        final resolver = svc.smartPaste;
        final plan = await resolver.plan(
          sources: (args['sources'] as List).cast<String>(),
          isCut: args['isCut'] as bool? ?? false,
          destDir: dest,
          defaultStrategy: ConflictStrategy.keepBoth,
        );
        await resolver.execute(plan, svc.ops, svc.journal.newBatch('macro'));
    }
  }
}

// ── Watchdog ────────────────────────────────────────────────────────────────

class WatchdogTab extends ConsumerWidget {
  const WatchdogTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(watchdogsProvider);
    final feed = ref.watch(watchdogFeedProvider);
    final svc = ref.read(servicesProvider);
    final events = svc.watchdogFeed.take(30).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Watchdogs guard folders: the moment something appears, changes or leaves, an action fires automatically.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _addWatchdog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New watchdog'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rules.isEmpty)
          const EmptyState(
            icon: Icons.radar_rounded,
            title: 'No watchdogs running',
            message:
                'Example: when a .zip lands in Downloads → extract it and move the archive to Storage. Or snapshot any change in a project folder via auto-versioning.',
          ),
        for (final w in rules)
          NexusPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.radar_rounded,
                    size: 18,
                    color: w.enabled ? NexusColors.ok : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${pu.compactPath(w.folder)} · on ${w.trigger}'
                        '${w.pattern.isEmpty ? '' : ' “${w.pattern}”'} → ${w.action}'
                        '${w.arg.isEmpty ? '' : ' ${w.arg}'}'
                        '${w.lastFiredMs == null ? '' : ' · fired ${f.formatRelative(DateTime.fromMillisecondsSinceEpoch(w.lastFiredMs!))}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: w.enabled,
                  onChanged: (v) {
                    final updated = w.copyWith(enabled: v);
                    svc.db.saveWatchdog(updated);
                    if (v) {
                      svc.watchdogs.start(updated);
                    } else {
                      svc.watchdogs.stop(w.id!);
                    }
                    _bump(ref);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  onPressed: () {
                    svc.watchdogs.stop(w.id!);
                    svc.db.deleteWatchdog(w.id!);
                    _bump(ref);
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        const SectionHeader('Live event feed', icon: Icons.bolt_rounded),
        if (feed.hasValue && events.isEmpty)
          Text('Watching… events appear here the moment rules fire.',
              style: Theme.of(context).textTheme.bodySmall),
        for (final e in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 6, color: NexusColors.blueSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.message,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addWatchdog(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(servicesProvider);
    final name = await promptDialog(context,
        title: 'Watchdog name', initial: 'Downloads auto-extract');
    if (name == null || !context.mounted) return;
    final folder = await promptDialog(context,
        title: 'Folder to watch',
        initial: ref.read(tabsProvider).active.path);
    if (folder == null || !context.mounted) return;
    final trigger = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Trigger on'),
        children: [
          for (final (v, l) in const [
            ('any', 'Any change'),
            ('added', 'File added'),
            ('removed', 'File removed'),
            ('pattern', 'File matching pattern'),
          ])
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, v), child: Text(l)),
        ],
      ),
    );
    if (trigger == null || !context.mounted) return;
    var pattern = '';
    if (trigger == 'pattern') {
      final p = await promptDialog(context,
          title: 'Filename pattern', hint: '*.zip');
      if (p == null) return;
      pattern = p;
    }
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Then…'),
        children: [
          for (final (v, l) in const [
            ('notify', 'Notify me'),
            ('version', 'Snapshot (auto-version)'),
            ('moveTo', 'Move to folder…'),
            ('pipeline', 'Run a pipeline…'),
            ('teleport', 'Teleport to device…'),
          ])
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, v), child: Text(l)),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    var arg = '';
    if (action == 'moveTo') {
      final d = await promptDialog(context, title: 'Move to folder', hint: '/path');
      if (d == null) return;
      arg = d;
    } else if (action == 'pipeline') {
      arg = 'pipeline'; // first saved pipeline is used
    } else if (action == 'teleport') {
      arg = 'teleport'; // first available peer is used
    }

    svc.db.saveWatchdog(WatchdogRule(
      name: name,
      folder: folder,
      trigger: trigger,
      pattern: pattern,
      action: action,
      arg: arg,
      enabled: true,
    ));
    _bump(ref);
    // Restart this rule live.
    final saved = svc.db.watchdogs().last;
    svc.watchdogs.start(saved);
    toast(ref, 'Watchdog “$name” armed');
  }
}

void _bump(WidgetRef ref) {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ref.read(dbTickProvider.notifier).state++;
}
