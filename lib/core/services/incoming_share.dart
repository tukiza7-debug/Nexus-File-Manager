/// Incoming share receiver — the Dart half of Android's ACTION_SEND flow.
///
/// Files shared into Nexus from other apps are copied into the app cache by
/// [MainActivity] and their paths are delivered here over the
/// `nexus/incoming` method channel. The service keeps the pending list,
/// notifies listeners via [changes], and can save everything into the user's
/// Downloads folder (collision-safe) or discard it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// One file received from another app.
class IncomingShare {
  IncomingShare({required this.path, required this.name, required this.size});

  /// Local cache path of the received copy.
  final String path;

  /// Original display name reported by the sending app.
  final String name;

  /// Byte size, from the completed cache copy.
  final int size;
}

/// Receives, lists, saves and clears files shared into Nexus.
class IncomingShareService with WidgetsBindingObserver {
  IncomingShareService() {
    if (kIsWeb || !Platform.isAndroid) return;
    const MethodChannel('nexus/incoming').setMethodCallHandler(_onCall);
    WidgetsBinding.instance.addObserver(this);
    // Cover files delivered before this handler was registered.
    unawaited(pull());
  }

  static const _channel = MethodChannel('nexus/incoming');

  final List<IncomingShare> pending = [];
  final _changes = StreamController<void>.broadcast();

  /// Fires whenever [pending] gains entries or is cleared.
  Stream<void> get changes => _changes.stream;

  /// Ask the platform for files received before Dart started listening.
  Future<void> pull() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final paths =
          await _channel.invokeMethod<List<dynamic>>('pendingSharedFiles');
      _merge((paths ?? const []).cast<String>());
    } on PlatformException {
      // Platform side unavailable — nothing to deliver.
    } on MissingPluginException {
      // Not running on Android.
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onSharedFiles') {
      _merge((call.arguments as List<dynamic>? ?? const []).cast<String>());
    }
    return null;
  }

  void _merge(List<String> paths) {
    var added = false;
    for (final path in paths) {
      if (pending.any((s) => s.path == path)) continue;
      try {
        final stat = FileStat.statSync(path);
        if (stat.type == FileSystemEntityType.notFound) continue;
        pending.add(IncomingShare(
          path: path,
          name: path.split(Platform.pathSeparator).last,
          size: stat.size,
        ));
        added = true;
      } on FileSystemException {
        // The copy vanished — skip it.
      }
    }
    if (added) _changes.add(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(pull());
  }

  /// Save every pending file into [root] (by default a Nexus folder inside
  /// the public Downloads directory, falling back to app documents).
  /// Returns the directory the files were written to.
  Future<String> saveAll([String? root]) async {
    if (pending.isEmpty) return root ?? '';
    final target = root ?? await _defaultTarget();
    await Directory(target).create(recursive: true);
    for (final share in pending) {
      final dest = _uniqueChild(Directory(target), share.name);
      await File(share.path).copy(dest.path);
    }
    await discardAll();
    return target;
  }

  /// Delete the cached copies and clear the platform-side pending list.
  Future<void> discardAll() async {
    for (final share in List<IncomingShare>.of(pending)) {
      try {
        await File(share.path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    pending.clear();
    try {
      await _channel.invokeMethod<void>('clearPendingSharedFiles');
    } on PlatformException {
      // Nothing left to clear anyway.
    } on MissingPluginException {
      // Not running on Android.
    }
    _changes.add(null);
  }

  Future<String> _defaultTarget() async {
    const downloads = '/storage/emulated/0/Download/NexusIncoming';
    try {
      final dir = Directory(downloads);
      await dir.create(recursive: true);
      // Verify we can actually write (safeguard for restricted builds).
      final probe = File('$downloads/.nexus-probe');
      await probe.writeAsString('', flush: true);
      await probe.delete();
      return downloads;
    } on FileSystemException {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}${Platform.pathSeparator}NexusIncoming';
    }
  }

  File _uniqueChild(Directory dir, String name) {
    var candidate = '${dir.path}${Platform.pathSeparator}$name';
    if (!File(candidate).existsSync()) return File(candidate);
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (true) {
      candidate =
          '${dir.path}${Platform.pathSeparator}$base ($i)$ext';
      if (!File(candidate).existsSync()) return File(candidate);
      i++;
    }
  }
}
