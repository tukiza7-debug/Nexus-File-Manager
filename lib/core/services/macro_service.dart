import 'dart:async';

import '../../domain/models.dart';
import '../db/nexus_database.dart';

/// Macro Recorder: captures user actions dispatched through the app's
/// ActionDispatcher (see state layer), stores them and replays them with
/// realistic pacing.
class MacroService {
  MacroService(this._db);

  final DbService _db;

  final _steps = <MacroStep>[];
  int _startedAt = 0;

  /// Behavior-subject-style signal: every new listener immediately receives
  /// the current value, then all changes. Audit item 18 — the recording FAB
  /// never appeared because the old stub terminated after one value.
  final ValueSignalBool _signal = ValueSignalBool(false);
  Stream<bool> get recordingStream => _signal.stream;
  bool get recording => _signal.value;

  List<MacroStep> get liveSteps => List.unmodifiable(_steps);

  void startRecording() {
    _steps.clear();
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _signal.add(true);
  }

  void record(String action, Map<String, dynamic> args) {
    if (!_signal.value) return;
    _steps.add(MacroStep(action: action, args: args, atMs: DateTime.now().millisecondsSinceEpoch - _startedAt));
  }

  List<MacroStep> stopRecording() {
    _signal.add(false);
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

  void dispose() => _signal.close();
}

/// Behavior-subject-style boolean stream: new listeners immediately receive
/// the current value, then every subsequent change.
class ValueSignalBool {
  ValueSignalBool(bool initial) : _value = initial;

  bool _value;
  final _ctrl = StreamController<bool>.broadcast();

  Stream<bool> get stream async* {
    yield _value;
    yield* _ctrl.stream;
  }

  bool get value => _value;

  void add(bool v) {
    _value = v;
    _ctrl.add(v);
  }

  void close() => _ctrl.close();
}
