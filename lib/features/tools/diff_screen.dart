/// File Diff View — two files, line-level Myers diff with intra-line word
/// highlights. Side A defaults to a prior selection; B is picked freely.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/nexus_theme.dart';
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show diffLeftProvider;

class DiffScreen extends ConsumerStatefulWidget {
  const DiffScreen({super.key});

  @override
  ConsumerState<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends ConsumerState<DiffScreen> {
  final _aCtrl = TextEditingController();
  final _bCtrl = TextEditingController();
  List<DiffLine>? _result;
  bool _ignoreWs = false;
  bool _swapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final left = ref.read(diffLeftProvider);
      if (left.isNotEmpty) _aCtrl.text = left;
      final sel = ref.read(tabsProvider).active.selection;
      if (sel.length >= 2) {
        _aCtrl.text = sel.first;
        _bCtrl.text = sel.last;
        _run();
      } else if (sel.length == 1 && left.isEmpty) {
        _aCtrl.text = sel.first;
      }
      if (_aCtrl.text.isNotEmpty && _bCtrl.text.isNotEmpty) _run();
    });
  }

  @override
  void dispose() {
    _aCtrl.dispose();
    _bCtrl.dispose();
    super.dispose();
  }

  void _run() {
    final a = _aCtrl.text.trim();
    final b = _bCtrl.text.trim();
    if (a.isEmpty || b.isEmpty) {
      setState(() => _result = null);
      return;
    }
    try {
      final aText = File(a).readAsStringSync();
      final bText = File(b).readAsStringSync();
      final svc = ref.read(servicesProvider);
      setState(() => _result =
          svc.diff.diffLines(aText, bText, ignoreWhitespace: _ignoreWs));
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entries =
        ref.watch(dirProvider.select((s) => s.entries.where((e) => !e.isDir).toList()));

    return ToolScaffold(
      title: 'File Diff View',
      subtitle: 'Compare two files line-by-line with word-level highlights.',
      icon: Icons.difference_rounded,
      actions: [
        IconButton(
          tooltip: 'Swap sides',
          onPressed: () => setState(() {
            final t = _aCtrl.text;
            _aCtrl.text = _bCtrl.text;
            _bCtrl.text = t;
            _swapped = !_swapped;
            _run();
          }),
          icon: const Icon(Icons.swap_horiz_rounded),
        ),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Compare'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilePicker(
                  label: 'File A',
                  controller: _aCtrl,
                  entries: entries,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilePicker(
                  label: 'File B',
                  controller: _bCtrl,
                  entries: entries,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Switch(
                value: _ignoreWs,
                onChanged: (v) {
                  setState(() => _ignoreWs = v);
                  _run();
                },
              ),
              const Text('Ignore whitespace'),
              const Spacer(),
              if (_result != null) _legend(context),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: 200,
                maxHeight: MediaQuery.sizeOf(context).height - 380),
            child: NexusPanel(
              padding: EdgeInsets.zero,
              child: _result == null
                  ? Center(
                      child: Text('Pick two files and hit Compare.',
                          style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _result!.length,
                      itemBuilder: (context, i) {
                        final line = _result![i];
                        final (bg, marker, markerColor) = switch (line.kind) {
                          DiffKind.added => (
                              NexusColors.ok.withOpacity( 0.13),
                              '+',
                              NexusColors.ok
                            ),
                          DiffKind.removed => (
                              NexusColors.danger.withOpacity( 0.13),
                              '−',
                              NexusColors.danger
                            ),
                          DiffKind.changed => (
                              NexusColors.warn.withOpacity( 0.10),
                              '~',
                              NexusColors.warn
                            ),
                          _ => (Colors.transparent, ' ', Colors.grey),
                        };
                        return Container(
                          color: bg,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 1.5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '${line.aNo ?? ''}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: dark
                                          ? NexusColors.textDimDark
                                          : NexusColors.textDimLight),
                                ),
                              ),
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '${line.bNo ?? ''}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: dark
                                          ? NexusColors.textDimDark
                                          : NexusColors.textDimLight),
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                child: Text(marker,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: markerColor)),
                              ),
                              Expanded(
                                child: _DiffSpansText(line: line),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    return Row(children: [
      _dot(context, NexusColors.ok, 'added'),
      _dot(context, NexusColors.danger, 'removed'),
      _dot(context, NexusColors.warn, 'changed'),
    ]);
  }

  Widget _dot(BuildContext context, Color c, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

class _DiffSpansText extends StatelessWidget {
  const _DiffSpansText({required this.line});

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    if (line.spans.isEmpty) {
      return Text(
        line.text,
        style: TextStyle(
            fontSize: 11.5,
            fontFamily: 'monospace',
            height: 1.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? NexusColors.textDark
                : NexusColors.textLight),
      );
    }
    final spans = [...line.spans]..sort((a, b) => a.start.compareTo(b.start));
    final children = <TextSpan>[];
    var cursor = 0;
    for (final s in spans) {
      if (s.start > cursor) {
        children.add(TextSpan(text: line.text.substring(cursor, s.start)));
      }
      final end = s.end.clamp(0, line.text.length);
      children.add(TextSpan(
        text: line.text.substring(s.start.clamp(0, line.text.length), end),
        style: TextStyle(backgroundColor: switch (s.kind) {
          DiffKind.added => NexusColors.ok.withOpacity( 0.35),
          DiffKind.removed => NexusColors.danger.withOpacity( 0.35),
          DiffKind.changed => NexusColors.warn.withOpacity( 0.35),
          _ => null,
        }),
      ));
      cursor = end;
    }
    if (cursor < line.text.length) {
      children.add(TextSpan(text: line.text.substring(cursor)));
    }
    return RichText(
      text: TextSpan(
        children: children,
        style: TextStyle(
            fontSize: 11.5,
            fontFamily: 'monospace',
            height: 1.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? NexusColors.textDark
                : NexusColors.textLight),
      ),
    );
  }
}

class _FilePicker extends StatelessWidget {
  const _FilePicker({
    required this.label,
    required this.controller,
    required this.entries,
  });

  final String label;
  final TextEditingController controller;
  final List<NexusEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                    isDense: true,
                    hintText: pu.compactPath(controller.text)),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Pick from current folder',
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              onSelected: (v) {
                controller.text = v;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              itemBuilder: (context) => [
                for (final e in entries.take(30))
                  PopupMenuItem(value: e.path, child: Text(e.name,
                      style: const TextStyle(fontSize: 12.5))),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
