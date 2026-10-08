/// File Teleport — LAN transfer between Nexus devices. UDP discovery,
/// direct TCP push, inbox with received files and live progress.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/teleport_service.dart' show TransferEvent;
import '../../core/theme/nexus_theme.dart';
import '../../core/utils/format_utils.dart' as f;
import '../../core/utils/path_utils.dart' as pu;
import '../../core/widgets/widgets.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../explorer/screens/overlays.dart' show teleportPendingProvider;

class TeleportScreen extends ConsumerStatefulWidget {
  const TeleportScreen({super.key});

  @override
  ConsumerState<TeleportScreen> createState() => _TeleportScreenState();
}

class _TeleportScreenState extends ConsumerState<TeleportScreen> {
  final _inbox = <TransferEvent>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(teleportPendingProvider);
      if (pending.isNotEmpty) {
        toast(ref, '${pending.length} file(s) ready — choose a peer below');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(servicesProvider);
    final peers = ref.watch(teleportPeersProvider).valueOrNull ?? const <TeleportPeer>[];
    final inbox = ref.watch(teleportInboxProvider);
    final progress = ref.watch(teleportProgressProvider).valueOrNull;

    inbox.whenData((e) {
      if (!_inbox.any((x) => x == e)) {
        _inbox.insert(0, e);
        if (_inbox.length > 100) _inbox.removeLast();
      }
    });

    return ToolScaffold(
      title: 'File Teleport',
      subtitle:
          'Direct device-to-device transfer on your network — no cloud, no accounts.',
      icon: Icons.send_rounded,
      maxWidth: 1100,
      child: SideBySide(
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('THIS DEVICE', icon: Icons.smartphone_rounded),
            NexusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_rounded,
                          size: 18,
                          color: svc.teleport.deviceId.isEmpty
                              ? Colors.grey
                              : NexusColors.ok),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          svc.teleport.deviceName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename device',
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        onPressed: () async {
                          final name = await promptDialog(context,
                              title: 'Device name',
                              initial: svc.teleport.deviceName);
                          if (name != null) {
                            await svc.prefs.setString('teleport.name', name);
                            await svc.teleport.start(
                                name: name,
                                downloadTo: svc.teleport.downloadDir.isEmpty
                                    ? Directory.systemTemp.path
                                    : svc.teleport.downloadDir);
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    svc.teleport.deviceId.isEmpty
                        ? 'Starting network services…'
                        : 'ID ${svc.teleport.deviceId.substring(0, 8)}  ·  inbox ${svc.teleport.downloadDir}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('NEARBY DEVICES', icon: Icons.devices_rounded),
            if (peers.isEmpty)
              const EmptyState(
                icon: Icons.radar_rounded,
                title: 'Listening for peers',
                message:
                    'Open Nexus on another device in the same network — it appears here within seconds. Then drop files on it to send.',
              ),
            for (final p in peers)
              NexusPanel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.devices_other_rounded,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text('${p.ip}:${p.port} · ${p.platform}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _send(context, ref, p),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Send…'),
                    ),
                  ],
                ),
              ),
            if (progress != null && progress.phase.name == 'running') ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.byteFraction),
              const SizedBox(height: 4),
              Text('${progress.title}  ·  ${f.formatSize(progress.bytesDone)} / ${f.formatSize(progress.bytesTotal)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('INBOX', icon: Icons.inbox_rounded),
            if (_inbox.isEmpty)
              const EmptyState(
                icon: Icons.inbox_rounded,
                title: 'Nothing received yet',
                message:
                    'Files sent to this device land in the Teleport inbox folder and appear here in real time.',
              )
            else
              NexusPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final e in _inbox.take(30))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          switch (e.kind) {
                            'received' || 'file-done' => Icons.check_circle_rounded,
                            'file-start' => Icons.download_rounded,
                            'batch-start' => Icons.archive_rounded,
                            'batch-end' => Icons.done_all_rounded,
                            _ => Icons.circle_outlined,
                          },
                          size: 16,
                          color: switch (e.kind) {
                            'received' || 'file-done' => NexusColors.ok,
                            'file-start' => NexusColors.info,
                            _ => Colors.grey,
                          },
                        ),
                        title: Text(e.name,
                            style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${e.kind} · ${f.formatSize(e.size)}${e.path == null ? '' : ' → ${pu.compactPath(e.path!)}'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context, WidgetRef ref, TeleportPeer peer) async {
    final svc = ref.read(servicesProvider);
    final pending = ref.read(teleportPendingProvider);
    var paths = pending;

    // Nothing pending → quick pick from current folder selection.
    if (paths.isEmpty) {
      final sel = ref.read(tabsProvider).active.selection.toList();
      if (sel.isEmpty) {
        toast(ref, 'Select files in the explorer first', error: true);
        return;
      }
      paths = sel;
    }
    try {
      await svc.teleport.send(paths, peer);
      toast(ref, 'Sent ${paths.length} file(s) to ${peer.name}');
      ref.read(teleportPendingProvider.notifier).state = const [];
    } catch (e) {
      toast(ref, '$e', error: true);
    }
  }
}
