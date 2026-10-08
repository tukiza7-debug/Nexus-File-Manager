import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/path_utils.dart' as pu;

/// Central directory-watch manager. Explorer, mirrors, watchdogs and
/// auto-versioning all subscribe here so each folder is watched exactly once.
///
/// Audit items 13 / T10 / T11 / R10 / S26:
///  * events are queued per *path* and flushed per listener, so a burst
///    (copy 50 files) is not collapsed into the last event;
///  * each directory supports multiple independent listeners and
///    unwatch(dir, listener) removes only that listener;
///  * FileSystemEvent.type is a bitmask and is decoded with bitwise ops;
///  * periodic polling fallback for filesystems where Directory.watch is
///    unreliable (Android FUSE shared storage);
///  * recursive watching is emulated by watching known subfolders on demand.
class WatcherService {
  final _subs = <String, StreamSubscription<FileSystemEvent>>{};
  final _listeners = <String, List<WatcherListener>>{};
  final _pending = <String, Map<String, _QueuedEvent>>{}; // dir → path → event
  final _flushTimers = <String, Timer>{};
  final _pollTimers = <String, Timer>{};
  final _snapshots = <String, Map<String, DateTime>>{};
  final _childWatches = <String, Set<String>>{}; // dir → subfolders watched

  static const _debounceMs = Duration(milliseconds: 350);

  /// Directories watched here are polled in addition to native events when
  /// [polling] is enabled (default: on mobile platforms).
  final bool polling;

  WatcherService({bool? enablePolling}) : polling = enablePolling ?? _defaultPolling();

  static bool _defaultPolling() {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  bool isWatched(String dir) => _subs.containsKey(dir) || _pollTimers.containsKey(dir);

  /// Registers a listener for a directory; starts a native watcher on demand.
  void watch(String dir, void Function(String kind, String path) onChange) {
    final listeners = _listeners.putIfAbsent(dir, () => []);
    listeners.add(WatcherListener(onChange));
    _ensureNative(dir);
  }

  /// Registers a listener and returns the token to pass to [unwatch].
  WatcherListener watchWithToken(String dir, void Function(String kind, String path) onChange) {
    final l = WatcherListener(onChange);
    _listeners.putIfAbsent(dir, () => []).add(l);
    _ensureNative(dir);
    return l;
  }

  void _ensureNative(String dir) {
    if (_subs.containsKey(dir)) return;
    final d = Directory(dir);
    if (!d.existsSync()) return;
    try {
      _subs[dir] = d.watch().listen((event) {
        _enqueue(dir, event);
      }, onError: (_) {});
    } on FileSystemException {
      // Native watchers unsupported — polling below still delivers changes.
    }
    if (polling) {
      _snapshots[dir] = _snapshotOf(dir);
      _pollTimers[dir]?.cancel();
      _pollTimers[dir] = Timer.periodic(const Duration(seconds: 3), (_) {
        final before = _snapshots[dir];
        final now = _snapshotOf(dir);
        _snapshots[dir] = now;
        if (before == null) return;
        final names = <String>{...before.keys, ...now.keys};
        for (final name in names) {
          final was = before[name];
          final isNow = now[name];
          if (was == null && isNow != null) {
            _enqueueRaw(dir, FileSystemEvent.create, pu.join(dir, name));
          } else if (was != null && isNow == null) {
            _enqueueRaw(dir, FileSystemEvent.delete, pu.join(dir, name));
          } else if (was != null && isNow != null && !isNow.isAtSameMomentAs(was)) {
            _enqueueRaw(dir, FileSystemEvent.modify, pu.join(dir, name));
          }
        }
      });
    }
  }

  static Map<String, DateTime> _snapshotOf(String dir) {
    try {
      return {
        for (final e in Directory(dir).listSync(followLinks: false))
          pu.basename(e.path): e.statSync().modified,
      };
    } on FileSystemException {
      return {};
    }
  }

  /// Watches the immediate subfolders of [dir] as well (emulated recursion
  /// for automation features that need whole-tree coverage).
  void watchSubfolders(String dir) {
    try {
      for (final e in Directory(dir).listSync(followLinks: false)) {
        if (e is Directory && !_childWatches[dir]!.contains(e.path)) {
          _childWatches.putIfAbsent(dir, () => {}).add(e.path);
          watch(e.path, (kind, path) => _dispatch(e.path, kind, path));
        }
      }
    } on FileSystemException {
      // unreadable folder — nothing to add
    }
  }

  void _enqueue(String dir, FileSystemEvent event) => _enqueueRaw(dir, event.type, event.path);

  void _enqueueRaw(String dir, int type, String path) {
    // Audit R10: type is a bitmask — decode with bitwise checks.
    final kind = _kindOf(type);
    final queue = _pending.putIfAbsent(dir, () => {});
    final existing = queue[path];
    if (existing != null) {
      existing.kinds.add(kind);
    } else {
      queue[path] = _QueuedEvent(path, [kind]);
    }
    _flushTimers[dir]?.cancel();
    _flushTimers[dir] = Timer(_debounceMs, () => _flush(dir));
  }

  static String _kindOf(int type) {
    var k = '';
    if (type & FileSystemEvent.create != 0) k = 'added';
    if (type & FileSystemEvent.modify != 0) k = k.isEmpty ? 'modified' : k;
    if (type & FileSystemEvent.move != 0) k = k.isEmpty ? 'moved' : 'modified';
    if (type & FileSystemEvent.delete != 0) k = 'removed';
    return k.isEmpty ? 'modified' : k;
  }

  void _flush(String dir) {
    final queue = _pending.remove(dir) ?? {};
    for (final ev in queue.values) {
      // Collapse a burst per path: removed wins, then added, else modified.
      final kinds = ev.kinds.toSet();
      final kind = kinds.contains('removed')
          ? 'removed'
          : kinds.contains('added')
              ? 'added'
              : kinds.contains('moved')
                  ? 'moved'
                  : 'modified';
      _dispatch(dir, kind, ev.path);
    }
  }

  void _dispatch(String dir, String kind, String path) {
    for (final l in List<WatcherListener>.of(_listeners[dir] ?? const [])) {
      l.callback(kind, path);
    }
  }

  /// Removes ONLY the given listener. The directory watcher stays alive
  /// while any listener remains (audit item 13 / T11).
  void unwatch(String dir, {WatcherListener? listener, void Function(String, String)? legacy}) {
    final list = _listeners[dir];
    if (list == null) return;
    if (listener != null) {
      list.remove(listener);
    } else if (legacy != null) {
      list.removeWhere((l) => identical(l.callback, legacy));
    }
    if (list.isNotEmpty) return;
    _teardown(dir);
  }

  void _teardown(String dir) {
    _listeners.remove(dir);
    _flushTimers.remove(dir)?.cancel();
    _pollTimers.remove(dir)?.cancel();
    _snapshots.remove(dir);
    for (final child in _childWatches.remove(dir) ?? const <String>{}) {
      if (_listeners.containsKey(child)) {
        _listeners.remove(child);
        _flushTimers.remove(child)?.cancel();
        _pollTimers.remove(child)?.cancel();
        _subs.remove(child)?.cancel();
      }
    }
    _subs.remove(dir)?.cancel();
  }

  int get activeCount => _subs.length;

  void disposeAll() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _listeners.clear();
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    _flushTimers.clear();
    for (final t in _pollTimers.values) {
      t.cancel();
    }
    _pollTimers.clear();
    _snapshots.clear();
    _childWatches.clear();
    _pending.clear();
  }
}

/// Identifies one listener so unwatch removes exactly that registration.
class WatcherListener {
  WatcherListener(this.callback);
  final void Function(String kind, String path) callback;
}

class _QueuedEvent {
  _QueuedEvent(this.path, this.kinds);
  final String path;
  final List<String> kinds;
}

/// Glob-ish pattern match: `*.jpg`, `report*`, `?.txt`, `[abc].txt`,
/// `[!a-z].txt`, plain substring.
bool matchesPattern(String name, String pattern) {
  if (pattern.isEmpty) return false;
  var re = RegExp.escape(pattern)
      .replaceAll(r'\*', '[^/\\]*')
      .replaceAll(r'\?', '.')
      .replaceAll(r'\[!', '[^');
  // Character classes: [abc] stays a class; RegExp.escape escaped the
  // brackets, so un-escape balanced ones (audit S19).
  re = re.replaceAllMapped(RegExp(r'\\\[([^\]\\]*)\\\]'), (m) => '[${m.group(1)}]');
  final regex = RegExp('^$re\$', caseSensitive: false);
  return regex.hasMatch(name) || name.toLowerCase().contains(pattern.toLowerCase());
}

String siblingPath(String dir, String name) => pu.join(dir, name);
