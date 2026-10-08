import '../../domain/models.dart';
import '../db/nexus_database.dart';

/// Macro Recorder: captures user actions dispatched through the app's
/// ActionDispatcher (see state layer), stores them and replays them with
/// realistic pacing.
class MacroService {
  MacroService(this._db);

  final DbService _db;

  bool _recording = false;
  final _steps = <MacroStep>[];
  int _startedAt = 0;

  final _stateCtrl = StreamControllerMacro();
  Stream<bool> get recordingStream => _stateCtrl.stream;
  bool get recording => _recording;

  List<MacroStep> get liveSteps => List.unmodifiable(_steps);

  void startRecording() {
    _steps.clear();
    _recording = true;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _stateCtrl.add(true);
  }

  void record(String action, Map<String, dynamic> args) {
    if (!_recording) return;
    _steps.add(MacroStep(action: action, args: args, atMs: DateTime.now().millisecondsSinceEpoch - _startedAt));
  }

  List<MacroStep> stopRecording() {
    _recording = false;
    _stateCtrl.add(false);
    return List.of(_steps);
  }

  int save(String name, List<MacroStep> steps) =>
      _db.saveMacro(NexusMacro(name: name, steps: steps, createdAtMs: DateTime.now().millisecondsSinceEpoch));

  List<NexusMacro> all() => _db.macros();

  void delete(int id) => _db.deleteMacro(id);

  void renameMacro(NexusMacro m, String name) => _db.saveMacro(m.copyWith(name: name));

  /// Removes a step by index; used by the macro editor.
  void updateSteps(NexusMacro m, List<MacroStep> steps) => _db.saveMacro(m.copyWith(steps: steps));

  /// Replay pacing: interpolate recorded timings but clamp to 40–600ms.
  static Duration delayFor(List<MacroStep> steps, int index) {
    if (index == 0) return Duration.zero;
    final delta = steps[index].atMs - steps[index - 1].atMs;
    final clamped = delta.clamp(40, 600);
    return Duration(milliseconds: clamped);
  }

  void dispose() => _stateCtrl.close();
}

class StreamControllerMacro {
  final _c = <void Function(bool)>[];
  bool _last = false;

  Stream<bool> get stream async* {
    yield _last;
    await for (final _ in const Stream<void>.empty()) {
      yield _last;
    }
  }

  void add(bool v) {
    _last = v;
    for (final f in _c) {
      f(v);
    }
  }

  void listen(void Function(bool) f) => _c.add(f);

  void close() => _c.clear();
}
