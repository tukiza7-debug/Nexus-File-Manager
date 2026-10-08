import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../domain/models.dart';
import '../utils/path_utils.dart' as pu;
import 'ops_service.dart';
import 'progress.dart';

/// File Teleport — send files to other Nexus instances on the local network.
///
/// Protocol:
///  * Discovery: UDP broadcast `NEXUS_TP_V1|<deviceId>|<name>|<platform>` on
///    [discoveryPort]; listeners reply unicast to the sender.
///  * Transfer: TCP to the peer's [transferPort]. The sender writes one JSON
///    header line per batch, then per-file `{name}\n{size}\n` followed by raw
///    bytes. The receiver streams to disk under its configured download dir.
class TeleportService {
  TeleportService(this._ops);

  static const int discoveryPort = 48481;
  static const int transferPort = 48482;

  // ignore: unused_field
  final FileOpsService _ops;
  final _peers = <String, TeleportPeer>{};
  final _peersCtrl = StreamController<List<TeleportPeer>>.broadcast();
  final _inboxCtrl = StreamController<TransferEvent>.broadcast();
  final _progressCtrl = StreamController<OpProgress>.broadcast();

  RawDatagramSocket? _udp;
  ServerSocket? _tcp;
  Timer? _announceTimer;
  String deviceName = 'Nexus Device';
  String deviceId = '';
  String downloadDir = '';
  bool _running = false;

  Stream<List<TeleportPeer>> get peers => _peersCtrl.stream;
  Stream<TransferEvent> get inbox => _inboxCtrl.stream;
  Stream<OpProgress> get progress => _progressCtrl.stream;

  List<TeleportPeer> currentPeers() {
    _peers.removeWhere((_, p) => DateTime.now().difference(p.seen).inSeconds > 15);
    return _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> start({required String name, required String downloadTo}) async {
    deviceName = name;
    downloadDir = downloadTo;
    deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(99999).toString();
    if (_running) return;
    _running = true;
    await _bindUdp();
    await _bindTcp();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _announce());
  }

  Future<void> _bindUdp() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reusePort: Platform.isLinux);
      _udp!.broadcastEnabled = true;
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udp!.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        final parts = msg.split('|');
        if (parts.length < 4 || parts[0] != 'NEXUS_TP_V1' || parts[1] == deviceId) return;
        final peer = TeleportPeer(
          id: parts[1],
          name: parts[2],
          platform: parts[3],
          ip: dg.address.address,
          port: transferPort,
          seen: DateTime.now(),
        );
        _peers[peer.id] = peer;
        _peersCtrl.add(currentPeers());
        // Reply so the sender sees us too.
        _udp!.send(_hello(), dg.address, discoveryPort);
      });
    } on SocketException {
      // Discovery unavailable (e.g. missing multicast permission) — manual
      // peer entry still works via sendTo().
    }
  }

  List<int> _hello() => utf8
      .encode('NEXUS_TP_V1|$deviceId|$deviceName|${Platform.operatingSystem}');

  Future<void> _bindTcp() async {
    try {
      _tcp = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort);
      _tcp!.listen(_handleClient, onError: (_) {});
    } on SocketException {
      // Transfer server unavailable; sending still possible to peers that listen.
    }
  }

  Future<void> _announce() async {
    try {
      final addresses = await _localAddresses();
      if (addresses.isEmpty || _udp == null) return;
      _udp!.send(_hello(), InternetAddress('255.255.255.255'), discoveryPort);
      _peersCtrl.add(currentPeers());
    } on SocketException {
      // ignore
    }
  }

  Future<List<InternetAddress>> _localAddresses() async =>
      (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((i) => i.addresses)
          .toList();

  Future<void> _handleClient(Socket socket) async {
    final buffer = <int>[];
    String? mode, fileName;
    int? fileSize;
    // ignore: unused_local_variable
    int? fileCount;
    var read = 0;
    RandomAccessFile? out;
    final sink = socket;

    await for (final chunk in sink) {
      var i = 0;
      while (i < chunk.length) {
        if (mode == null || fileName == null || fileSize == null) {
          // Accumulate header bytes.
          while (i < chunk.length) {
            final b = chunk[i++];
            if (b == 0x0A) {
              final line = utf8.decode(buffer);
              buffer.clear();
              if (mode == null) {
                mode = line;
                fileCount = int.tryParse(line);
                _inboxCtrl.add(const TransferEvent(kind: 'batch-start', name: '', size: 0));
                continue;
              }
              if (fileName == null) {
                fileName = line;
                continue;
              }
              fileSize = int.tryParse(line);
              break;
            } else {
              buffer.add(b);
            }
          }
          if (fileName != null && fileSize != null) {
            read = 0;
            final safe = fileName.replaceAll(RegExp(r'[/\\\\]'), '_');
            final path = pu.join(downloadDir, safe);
            Directory(downloadDir).createSync(recursive: true);
            out = File(path).openSync(mode: FileMode.write);
            _inboxCtrl.add(TransferEvent(kind: 'file-start', name: fileName, size: fileSize));
          }
        } else {
          final take = (chunk.length - i).clamp(0, fileSize - read);
          if (take > 0) {
            out?.writeFromSync(chunk, i, i + take);
            read += take;
            i += take;
            _progressCtrl.add(OpProgress(
              batchId: 'teleport-in',
              title: 'Receiving $fileName',
              done: read,
              total: fileSize,
              bytesDone: read,
              bytesTotal: fileSize,
            ));
          }
          if (read >= fileSize) {
            out?.flushSync();
            out?.closeSync();
            _inboxCtrl.add(TransferEvent(kind: 'file-done', name: fileName, size: fileSize));
            _inboxCtrl.add(TransferEvent(kind: 'received', name: fileName, size: fileSize,
                path: pu.join(downloadDir, fileName.replaceAll(RegExp(r'[/\\\\]'), '_'))));
            mode = null;
            fileName = null;
            fileSize = null;
            out = null;
            if (i < chunk.length && chunk[i] == 0x0A) i++;
          }
        }
      }
    }
    out?.closeSync();
    _inboxCtrl.add(const TransferEvent(kind: 'batch-end', name: '', size: 0));
  }

  /// Sends [paths] to [peer]; reports through [progress].
  Future<void> send(List<String> paths, TeleportPeer peer) async {
    final files = <String>[];
    for (final p in paths) {
      final t = FileSystemEntity.typeSync(p);
      if (t == FileSystemEntityType.file) {
        files.add(p);
      } else if (t == FileSystemEntityType.directory) {
        files.addAll(Directory(p).listSync(recursive: true, followLinks: false)
            .whereType<File>().map((f) => f.path));
      }
    }
    if (files.isEmpty) return;
    final bytesTotal = files.fold<int>(0, (s, f) => s + File(f).lengthSync());
    Socket? socket;
    try {
      socket = await Socket.connect(peer.ip, peer.port, timeout: const Duration(seconds: 4));
      final header = '${files.length}\n';
      socket.add(utf8.encode(header));
      var bytesDone = 0;
      for (var i = 0; i < files.length; i++) {
        final f = File(files[i]);
        final name = pu.basename(files[i]);
        final size = f.lengthSync();
        socket.add(utf8.encode('$name\n$size\n'));
        final raf = f.openSync();
        try {
          final buf = List<int>.filled(128 * 1024, 0);
          while (true) {
            final n = raf.readIntoSync(buf, 0, buf.length);
            if (n <= 0) break;
            socket.add(buf.sublist(0, n));
            bytesDone += n;
            _progressCtrl.add(OpProgress(
              batchId: 'teleport-out',
              title: 'Sending to ${peer.name}',
              done: i + 1,
              total: files.length,
              bytesDone: bytesDone,
              bytesTotal: bytesTotal,
            ));
          }
        } finally {
          raf.closeSync();
        }
        await socket.flush();
      }
      await socket.flush();
      _progressCtrl.add(const OpProgress(
          batchId: 'teleport-out', title: 'Sent', done: 1, total: 1, phase: OpPhase.done));
    } on SocketException catch (e) {
      _progressCtrl.add(OpProgress(
          batchId: 'teleport-out', title: 'Send failed', done: 0, total: 1,
          detail: e.message, phase: OpPhase.error));
      rethrow;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _udp?.close();
    await _tcp?.close();
    _udp = null;
    _tcp = null;
    _running = false;
  }

  void dispose() {
    stop();
    _peersCtrl.close();
    _inboxCtrl.close();
    _progressCtrl.close();
  }
}

class TransferEvent {
  const TransferEvent({required this.kind, required this.name, required this.size, this.path});
  final String kind; // batch-start | file-start | file-done | received | batch-end
  final String name;
  final int size;
  final String? path;
}

/// Tiny adapter so List<int> can be sent on sockets without extra imports.
class Uint8ListX {
  static List<int> sublist(List<int> list, int start, int end) => list.sublist(start, end);
}
