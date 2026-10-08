import 'dart:async';
import 'dart:io';

import '../utils/path_utils.dart' as pu;

/// Central directory-watch manager. Explorer, mirrors, watchdogs and
/// auto-versioning all subscribe here so each folder is watched exactly once.
class WatcherService {
  final _subs = <String, StreamSubscription<FileSystemEvent>>{};
  final _listeners = <String, List<void Function(String eventKind, String path)>>{};
  final _debounce = <String, Timer>{};

  static const _debounceMs = Duration(milliseconds: 350);

  bool isWatched(String dir) => _subs.containsKey(dir);

  /// Registers a listener for a directory; starts a native watcher on demand.
  void watch(String dir, void Function(String kind, String path) onChange) {
    _listeners.putIfAbsent(dir, () => []).add(onChange);
    if (_subs.containsKey(dir)) return;
    final d = Directory(dir);
    if (!d.existsSync()) return;
    try {
      _subs[dir] = d.watch().listen((event) {
        _debounce[dir]?.cancel();
        _debounce[dir] = Timer(_debounceMs, () {
          final kind = switch (event.type) {
            FileSystemEvent.create => 'added',
            FileSystemEvent.delete => 'removed',
            FileSystemEvent.move => 'moved',
            _ => 'modified',
          };
          final target = event.path;
          for (final l in _listeners[dir] ?? const []) {
            // ignore: avoid_dynamic_calls
            l(kind, target);
          }
        });
      }, onError: (_) {});
    } on FileSystemException {
      // Watchers unsupported (e.g. some Android FS) — listeners must poll.
    }
  }

  void unwatch(String dir, {void Function(String, String)? listener}) {
    final list = _listeners[dir];
    if (list != null && listener != null) {
      list.remove(listener);
      if (list.isNotEmpty) return;
    }
    _listeners.remove(dir);
    _debounce[dir]?.cancel();
    _subs.remove(dir)?.cancel();
  }

  int get activeCount => _subs.length;

  void disposeAll() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _listeners.clear();
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
  }
}

/// Glob-ish pattern match: `*.jpg`, `report*`, `?.txt`, plain substring.
bool matchesPattern(String name, String pattern) {
  if (pattern.isEmpty) return false;
  final regex = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '[^/\\\\]*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false);
  return regex.hasMatch(name) || name.toLowerCase().contains(pattern.toLowerCase());
}

String siblingPath(String dir, String name) => pu.join(dir, name);
