import 'dart:async';
import 'dart:io';

import '../../domain/models.dart';
import '../db/nexus_database.dart';
import '../utils/path_utils.dart' as pu;
import 'template_service.dart';

/// Work Sessions: complete save/restore of tabs, paths, layout and UI state.
class SessionService {
  SessionService(this._db, this._templates);

  final DbService _db;
  // Template tokens may be referenced by stored sessions in future releases.
  // ignore: unused_field
  final TemplateService _templates;
  Timer? _autosave;

  static const autosaveName = '__autosave__';

  List<WorkSession> all() =>
      _db.sessions().where((s) => s.name != autosaveName).toList();

  WorkSession? byName(String name) => _db.sessionByName(name);

  Map<String, dynamic>? autosave() => _db.sessionByName(autosaveName)?.payload;

  void save(String name, Map<String, dynamic> payload) => _db.saveSession(name, payload);

  void delete(String name) => _db.deleteSession(name);

  void startAutosave(Map<String, dynamic> Function() capture) {
    _autosave?.cancel();
    _autosave = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _db.saveSession(autosaveName, capture());
      } on FileSystemException {
        // DB busy — next tick retries.
      }
    });
  }

  void flushAutosave(Map<String, dynamic> payload) => _db.saveSession(autosaveName, payload);

  void stopAutosave() => _autosave?.cancel();
}

/// Default home for new tabs when a session was empty.
String defaultHome() {
  final env = Platform.environment;
  if (Platform.isWindows) return env['USERPROFILE'] ?? 'C:\\';
  return env['HOME'] ?? '/';
}

/// Restores tabs defensively (paths may have vanished since saving).
List<String> sanitizeTabHistory(List<String> history) =>
    history.where((p) => p.isNotEmpty).map(pu.normalize).toList();
