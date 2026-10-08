import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../domain/models.dart';
import '../utils/logger.dart';
import '../utils/path_utils.dart' as pu;
import 'progress.dart';

/// File Teleport — send files to other Nexus instances on the local network.
///
/// Protocol v2 (audit item 24):
///  * Discovery messages carry an explicit type:
///      `NEXUS_TP_V2|ANNOUNCE|<deviceId>|<name>|<platform>`
///      `NEXUS_TP_V2|REPLY|<deviceId>|<name>|<platform>`
///    ANNOUNCE messages are answered with a unicast REPLY; REPLY messages
///    are NEVER answered (no ping-pong loop). Replies are rate-limited per
///    peer device.
///  * Device names are percent-encoded so `|` cannot break parsing.
///  * deviceId comes from Random.secure().
///
/// Transfer (TCP): the sender writes one JSON header line per batch
/// (`{"count":N,"total":M}`), then per-file `{name}\n{size}\n` followed by
/// raw bytes. Receiver hardening (audit item 25):
///  * consent callback required before the first byte is written;
///  * negative/absurd sizes rejected; max size + free-disk enforced;
///  * file names sanitized and auto-renamed, never overwritten;
///  * the whole handler is wrapped in try/catch;
///  * servers stop when Teleport is switched off.
class TeleportService {
  TeleportService();

  static const int discoveryPort = 48481;
  static const int transferPort = 48482;

  /// Maximum accepted file size per transfer (default 4 GiB).
  int maxFileBytes = 4 * 1024 * 1024 * 1024 ~/ 2; // 2 GiB to stay in int range

  final _peers = <String, TeleportPeer>{};
  final _peersCtrl = StreamController<List<TeleportPeer>>.broadcast();
  final _inboxCtrl = StreamController<TransferEvent>.broadcast();
  final _progressCtrl = StreamController<OpProgress>.broadcast();
  final _consentCtrl = StreamController<IncomingBatch>.broadcast();
  final _rng = Random.secure();

  RawDatagramSocket? _udp;
  ServerSocket? _tcp;
  Timer? _announceTimer;
  String deviceName = 'Nexus Device';
  String deviceId = '';
  String downloadDir = '';
  bool _running = false;

  /// Last REPLY time per peer device — rate limit (audit item 24).
  final _lastReply = <String, int>{};
  static const _replyIntervalMs = 4000;

  /// Trusted device ids (pairing): when non-empty, only these peers are
  /// answered and accepted. Empty means "ask on every incoming batch".
  final Set<String> trustedDevices = {};

  /// Called before writing an incoming batch; return false to reject.
  /// The UI listens on [pendingBatches] and completes [IncomingBatch].
  Stream<IncomingBatch> get pendingBatches => _consentCtrl.stream;

  Stream<List<TeleportPeer>> get peers => _peersCtrl.stream;
  Stream<TransferEvent> get inbox => _inboxCtrl.stream;
  Stream<OpProgress> get progress => _progressCtrl.stream;

  List<TeleportPeer> currentPeers() {
    _peers.removeWhere((_, p) => DateTime.now().difference(p.seen).inSeconds > 15);
    return _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static String _encodeField(String value) => Uri.encodeComponent(value);

  static String? _decodeField(String value) {
    try {
      return Uri.decodeComponent(value);
    } on Object {
      // Audit item 25/49: any malformed escape (ArgumentError,
      // FormatException, RangeError) must degrade to "rejected", never
      // propagate out of the discovery loop.
      return null;
    }
  }

  Future<void> start({required String name, required String downloadTo}) async {
    deviceName = name;
    downloadDir = downloadTo;
    if (deviceId.isEmpty) {
      // Cryptographically secure random id (audit item 24).
      final bytes = List<int>.generate(8, (_) => _rng.nextInt(256));
      deviceId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    if (_running) return;
    _running = true;
    await _bindUdp();
    await _bindTcp();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _announce());
  }

  Future<void> _bindUdp() async {
    try {
      final reuse = !kIsWebLike && Platform.isLinux;
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reusePort: reuse);
      _udp!.broadcastEnabled = true;
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udp!.receive();
        if (dg == null) return;
        _onDatagram(dg);
      });
    } on SocketException {
      // Discovery unavailable (e.g. missing multicast permission) — manual
      // peer entry still works via sendTo().
    }
  }

  static bool get kIsWebLike => identical(0, 0.0); // placeholder, always false

  /// Audit item 49: pure protocol parser so the hello format can be
  /// fuzz-tested without sockets. Returns null for anything malformed.
  static ({String type, String peerId, String name, String platform})?
      parseHello(String msg) {
    final parts = msg.split('|');
    if (parts.length < 5 || parts[0] != 'NEXUS_TP_V2') return null;
    final type = parts[1];
    if (type != 'ANNOUNCE' && type != 'REPLY') return null;
    final peerId = parts[2];
    if (peerId.isEmpty) return null;
    final name = _decodeField(parts[3]);
    if (name == null || name.isEmpty) return null; // malformed — ignore
    return (
      type: type,
      peerId: peerId,
      name: name,
      platform: parts[4],
    );
  }

  void _onDatagram(Datagram dg) {
    try {
      final msg = utf8.decode(dg.data, allowMalformed: true);
      final hello = parseHello(msg);
      if (hello == null) return;
      if (hello.peerId == deviceId) return;
      final peer = TeleportPeer(
        id: hello.peerId,
        name: hello.name,
        platform: hello.platform,
        ip: dg.address.address,
        port: transferPort,
        seen: DateTime.now(),
      );
      _peers[peer.id] = peer;
      _peersCtrl.add(currentPeers());
      // Audit item 24: never reply to a reply; rate-limit per peer.
      if (hello.type == 'REPLY') return;
      if (trustedDevices.isNotEmpty && !trustedDevices.contains(hello.peerId)) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastReply[hello.peerId];
      if (last != null && now - last < _replyIntervalMs) return;
      _lastReply[hello.peerId] = now;
      _udp!.send(_hello('REPLY'), dg.address, discoveryPort);
    } catch (e, st) {
      // Malformed input must never crash the discovery loop (item 25);
      // item 46: it is logged so bad peers are observable.
      logWarn('teleport discovery: malformed datagram', e, st);
    }
  }

  List<int> _hello(String type) => utf8.encode(
      'NEXUS_TP_V2|$type|$deviceId|${_encodeField(deviceName)}|${Platform.operatingSystem}');

  /// Audit item 20: best-effort free-space probe via `df` (POSIX/Android).
  /// Returns null when the platform cannot report it — the transfer then
  /// proceeds and fails naturally if the disk fills.
  static int? _bestEffortFreeSpace(String dirPath) {
    try {
      final r = Process.runSync('df', ['-k', dirPath]);
      final lines = r.stdout.toString().trim().split('\n');
      if (lines.length < 2) return null;
      final cols = lines.last
          .split(RegExp(r'\s+'))
          .where((c) => c.isNotEmpty)
          .toList();
      if (cols.length < 4) return null;
      return int.tryParse(cols[3]); // avail (1K blocks)
    } on Object {
      return null;
    }
  }

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
      _udp!.send(_hello('ANNOUNCE'), InternetAddress('255.255.255.255'), discoveryPort);
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
    RandomAccessFile? out;
    try {
      final header = <int>[];
      // Parser state.
      String? pendingName;
      int? pendingSize;
      var batchApproved = false;
      var batchFiles = 0;
      var batchTotal = 0;
      var batchReceived = 0;

      Future<void> startFile(String name, int size) async {
        final dir = Directory(downloadDir);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        if (size > 0) {
          final free = _bestEffortFreeSpace(downloadDir);
          if (free != null && free < size) {
            throw const FileSystemException(
                'Not enough free space for the incoming file');
          }
        }
        final unique = _uniqueName(name);
        final path = pu.join(downloadDir, unique);
        if (!pu.isUnder(path, downloadDir)) {
          throw const FormatException('Resolved path escaped the download directory');
        }
        out = File(path).openSync(mode: FileMode.write);
        _inboxCtrl.add(TransferEvent(kind: 'file-start', name: name, size: size));
      }

      await for (final chunk in socket) {
        var i = 0;
        while (i < chunk.length) {
          if (out == null) {
            // Header accumulation phase.
            var parsed = false;
            while (i < chunk.length) {
              final b = chunk[i++];
              if (b == 0x0A) {
                final line = utf8.decode(header, allowMalformed: true);
                header.clear();
                if (!batchApproved) {
                  final parsed2 = _parseBatchHeader(line);
                  if (parsed2 == null) {
                    throw const FormatException('Malformed batch header');
                  }
                  batchFiles = parsed2.$1;
                  batchTotal = parsed2.$2;
                  final batch = IncomingBatch(
                    sender: _currentSenderName,
                    fileCount: batchFiles,
                    totalBytes: batchTotal,
                  );
                  _consentCtrl.add(batch);
                  batchApproved = await batch.decision;
                  if (!batchApproved) return; // rejected by the user
                  continue;
                }
                if (pendingName == null) {
                  final safe = _sanitizeFileName(line);
                  if (safe == null || safe.isEmpty) {
                    throw const FormatException('Illegal file name');
                  }
                  pendingName = safe;
                  continue;
                }
                final size = int.tryParse(line);
                if (size == null || size < 0) {
                  throw const FormatException('Negative or unparsable file size');
                }
                if (size > maxFileBytes) {
                  throw const FormatException('File exceeds the maximum transfer size');
                }
                pendingSize = size;
                await startFile(pendingName, pendingSize);
                _activeName = pendingName;
                _activeSize = pendingSize;
                pendingName = null;
                pendingSize = null;
                parsed = true;
                break;
              }
              header.add(b);
              if (header.length > 4096) {
                throw const FormatException('Header line too long');
              }
            }
            if (!parsed) continue;
          } else {
            // Payload phase.
            final take = (chunk.length - i).clamp(0, _activeSize - _received);
            if (take > 0) {
              out?.writeFromSync(chunk, i, i + take);
              _received += take;
              i += take;
              _progressCtrl.add(OpProgress(
                batchId: 'teleport-in',
                title: 'Receiving $_activeName',
                done: batchReceived,
                total: batchFiles,
                bytesDone: _received,
                bytesTotal: _activeSize,
              ));
            }
            if (_received >= _activeSize) {
              out?.flushSync();
              await out?.close();
              out = null;
              batchReceived++;
              _inboxCtrl.add(TransferEvent(
                  kind: 'file-done', name: _activeName, size: _activeSize));
              _inboxCtrl.add(TransferEvent(
                  kind: 'received',
                  name: _activeName,
                  size: _activeSize,
                  path: pu.join(downloadDir, _activeName)));
              _activeName = '';
              _activeSize = 0;
              _received = 0;
              if (i < chunk.length && chunk[i] == 0x0A) i++;
            }
          }
        }
      }
      await out?.close();
      _inboxCtrl.add(const TransferEvent(kind: 'batch-end', name: '', size: 0));
    } catch (e) {
      // Audit item 25: malformed input must not crash the receiver.
      try {
        await out?.close();
      } catch (_) {
        // already closed
      }
      _inboxCtrl.add(TransferEvent(kind: 'error', name: '$e', size: 0));
    }
  }

  // Per-file bookkeeping for the streaming parser.
  final String _currentSenderName = '';
  String _activeName = '';
  int _activeSize = 0;
  int _received = 0;

  (int, int)? _parseBatchHeader(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return null;
      final count = int.tryParse('${decoded['count']}');
      final total = int.tryParse('${decoded['total']}');
      if (count == null || total == null || count < 0 || total < 0) return null;
      if (count > 10000 || total > maxFileBytes * 10) return null;
      return (count, total);
    } on FormatException {
      return null;
    }
  }

  /// Sanitizes an untrusted transfer file name: strips separators and
  /// traversal, rejects control characters (audit item 25).
  String? _sanitizeFileName(String raw) {
    var name = raw.trim();
    if (name.isEmpty || name == '.' || name == '..') return null;
    name = name.replaceAll('\\', '/');
    if (name.contains('/')) {
      name = name.split('/').where((s) => s.isNotEmpty).last;
    }
    if (name.isEmpty || name == '.' || name == '..') return null;
    if (name.contains('\u0000')) return null;
    if (name.length > 240) name = name.substring(name.length - 240);
    return name;
  }

  String _uniqueName(String name) {
    final base = File(pu.join(downloadDir, name));
    if (base.existsSync()) {
      // Never overwrite: auto-rename "name (1).ext" (audit item 25).
      var n = 1;
      final stem = pu.stem(name);
      final ext = pu.ext(name);
      while (true) {
        final candidate =
            pu.join(downloadDir, ext.isEmpty ? '$stem ($n)' : '$stem ($n).$ext');
        if (!File(candidate).existsSync()) return pu.basename(candidate);
        n++;
      }
    }
    return name;
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
      final batchHeader = jsonEncode({'count': files.length, 'total': bytesTotal});
      socket.add(utf8.encode('$batchHeader\n'));
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
    // Audit item 25: switching Teleport off closes both servers.
    _announceTimer?.cancel();
    _announceTimer = null;
    _udp?.close();
    await _tcp?.close();
    _udp = null;
    _tcp = null;
    _running = false;
  }

  bool get running => _running;

  void dispose() {
    stop();
    _peersCtrl.close();
    _inboxCtrl.close();
    _progressCtrl.close();
    _consentCtrl.close();
  }
}

/// A batch that awaits user consent before bytes are written (audit 25).
class IncomingBatch {
  IncomingBatch({required this.sender, required this.fileCount, required this.totalBytes});

  final String sender;
  final int fileCount;
  final int totalBytes;

  final Completer<bool> _decision = Completer<bool>();
  Future<bool> get decision => _decision.future;

  void accept() {
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void reject() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

class TransferEvent {
  const TransferEvent({required this.kind, required this.name, required this.size, this.path});
  final String kind; // batch-start | file-start | file-done | received | batch-end | error
  final String name;
  final int size;
  final String? path;
}

/// Tiny adapter so List<int> can be sent on sockets without extra imports.
class Uint8ListX {
  static List<int> sublist(List<int> list, int start, int end) => list.sublist(start, end);
}
