import 'dart:async';
import 'dart:io';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/logger.dart';

/// Multi-Clipboard Stack: every copy/cut lands on a visual stack with a
/// selectable active entry. The stack persists across launches.
class ClipboardStackService {
  ClipboardStackService(this._db);

  final DbService _db;

  final _items = <ClipboardEntry>[];
  String? _activeId;

  final _ctrl = StreamController<void>.broadcast();
  Stream<void> get changes => _ctrl.stream;

  static const maxItems = 25;

  List<ClipboardEntry> get items => List.unmodifiable(_items);

  ClipboardEntry? get active {
    if (_items.isEmpty) return null;
    return _items.where((e) => e.id == _activeId).firstOrNull ?? _items.first;
  }

  void load() {
    final raw = _db.getSetting('clipboard_stack');
    if (raw == null) return;
    // Encoded via the DB mini-JSON; parse through DbService helpers.
    final list = _parseList(raw);
    _items
      ..clear()
      ..addAll(list);
    _activeId = _items.isNotEmpty ? _items.first.id : null;
  }

  static List<ClipboardEntry> _parseList(String raw) {
    try {
      final v = DbJsonAccess.decodeList(raw);
      return [for (final e in v) ClipboardEntry.fromJson((e as Map).cast<String, dynamic>())];
    } catch (e, st) {
      // Audit item 46: corrupted persisted stack — report, don't swallow.
      logWarn('clipboard stack decode failed — starting empty', e, st);
      return const [];
    }
  }

  void _persist() {
    final encoded = DbJsonAccess.encodeList([for (final e in _items) e.toJson()]);
    _db.setSetting('clipboard_stack', encoded);
  }

  void push(ClipOp op, String path) {
    _items.removeWhere((e) => e.path == path && e.op == op);
    final entry = ClipboardEntry(
      id: 'cb-${DateTime.now().microsecondsSinceEpoch}',
      op: op,
      path: path,
      isDir: _probeIsDir(path),
      at: DateTime.now(),
    );
    _items.insert(0, entry);
    if (_items.length > maxItems) {
      _items.removeLast();
    }
    _activeId = entry.id;
    _persist();
    _ctrl.add(null);
  }

  void setActive(String id) {
    _activeId = id;
    _ctrl.add(null);
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    if (_activeId == id) {
      _activeId = _items.isNotEmpty ? _items.first.id : null;
    }
    _persist();
    _ctrl.add(null);
  }

  void clear() {
    _items.clear();
    _activeId = null;
    _persist();
    _ctrl.add(null);
  }

  void promoteActive() {
    if (_items.isEmpty || _activeId == null) return;
    final e = _items.where((x) => x.id == _activeId).firstOrNull;
    if (e == null) return;
    _items.remove(e);
    _items.insert(0, e);
    _persist();
    _ctrl.add(null);
  }

  static bool _probeIsDir(String path) {
    try {
      return dirType(path);
    } on Exception {
      return false;
    }
  }

  void dispose() => _ctrl.close();
}

bool dirType(String path) => _DirProbe.isDir(path);

class _DirProbe {
  static bool isDir(String path) {
    // Late import cycle avoidance: implemented via dart:io at call time.
    return _isDirImpl(path);
  }

  static bool _isDirImpl(String path) => ioIsDir(path);
}

// Small indirection so the file compiles without top-level dart:io import
// leaking into other layers via public surface.
bool ioIsDir(String path) => IoDirProbe.isDir(path);

class IoDirProbe {
  static bool isDir(String path) => _ioType(path) == 'dir';
}

String _ioType(String path) => _TypeBridge.typeOf(path);

class _TypeBridge {
  static String typeOf(String path) => IoTypeBridge.typeOf(path);
}

class IoTypeBridge {
  static String typeOf(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
          ? 'dir'
          : 'file';
}
