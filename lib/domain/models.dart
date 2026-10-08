import '../core/utils/format_utils.dart' as f;
import '../core/utils/path_utils.dart' as p;
import 'enums.dart';

/// A single file-system entry as surfaced to the UI. Constructed inside
/// isolates for large directories, so it must stay a plain value object.
class NexusEntry {
  const NexusEntry({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
    required this.category,
    this.accessed,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;
  final DateTime? accessed;
  final FileCategory category;

  bool get isHidden => name.startsWith('.');
  String get ext => p.ext(name);
  String get sizeLabel => isDir ? 'Folder' : f.formatSize(size);
  String get parent => p.dirname(path);
}

class TabState {
  const TabState({
    required this.id,
    required this.history,
    required this.histIndex,
    this.selection = const {},
    this.sortBy = SortBy.name,
    this.sortDir = SortDir.asc,
    this.viewMode = ViewMode.grid,
    this.scrollOffset = 0,
    this.visited = const [],
    this.spatialMode = false,
  });

  final String id;
  final List<String> history;
  final int histIndex;
  final Set<String> selection;
  final SortBy sortBy;
  final SortDir sortDir;
  final ViewMode viewMode;
  final double scrollOffset;
  final List<String> visited;
  final bool spatialMode;

  String get path => history[histIndex];
  bool get canBack => histIndex > 0;
  bool get canForward => histIndex < history.length - 1;

  TabState copyWith({
    List<String>? history,
    int? histIndex,
    Set<String>? selection,
    SortBy? sortBy,
    SortDir? sortDir,
    ViewMode? viewMode,
    double? scrollOffset,
    List<String>? visited,
    bool? spatialMode,
  }) =>
      TabState(
        id: id,
        history: history ?? this.history,
        histIndex: histIndex ?? this.histIndex,
        selection: selection ?? this.selection,
        sortBy: sortBy ?? this.sortBy,
        sortDir: sortDir ?? this.sortDir,
        viewMode: viewMode ?? this.viewMode,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        visited: visited ?? this.visited,
        spatialMode: spatialMode ?? this.spatialMode,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'history': history,
        'histIndex': histIndex,
        'sortBy': sortBy.name,
        'sortDir': sortDir.name,
        'viewMode': viewMode.name,
        'scroll': scrollOffset,
        'visited': visited,
        'spatial': spatialMode,
      };

  static TabState fromJson(Map<String, dynamic> j) => TabState(
        id: j['id'] as String,
        history: (j['history'] as List).cast<String>(),
        histIndex: j['histIndex'] as int,
        sortBy: SortBy.values.asNameMap()[j['sortBy']] ?? SortBy.name,
        sortDir: SortDir.values.asNameMap()[j['sortDir']] ?? SortDir.asc,
        viewMode: ViewMode.values.asNameMap()[j['viewMode']] ?? ViewMode.grid,
        scrollOffset: (j['scroll'] as num?)?.toDouble() ?? 0,
        visited: ((j['visited'] as List?) ?? const []).cast<String>(),
        spatialMode: j['spatial'] as bool? ?? false,
      );
}

class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.op,
    required this.path,
    required this.isDir,
    required this.at,
  });

  final String id;
  final ClipOp op;
  final String path;
  final bool isDir;
  final DateTime at;

  String get name => p.basename(path);
  Map<String, dynamic> toJson() =>
      {'id': id, 'op': op.name, 'path': path, 'isDir': isDir, 'at': at.millisecondsSinceEpoch};

  static ClipboardEntry fromJson(Map<String, dynamic> j) => ClipboardEntry(
        id: j['id'] as String,
        op: ClipOp.values.asNameMap()[j['op']] ?? ClipOp.copy,
        path: j['path'] as String,
        isDir: j['isDir'] as bool? ?? false,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

// ── Journal / paper trail / undo ────────────────────────────────────────────

enum JournalOp { copy, move, rename, delete, mkdir, write, restore, metadata, split, merge }

class JournalEntry {
  const JournalEntry({
    this.id,
    required this.batchId,
    required this.op,
    required this.fromPath,
    this.toPath,
    this.meta,
    required this.createdAtMs,
    this.undone = false,
    this.discarded = false,
  });

  final int? id;
  final String batchId;
  final JournalOp op;
  final String fromPath;
  final String? toPath;
  final String? meta;
  final int createdAtMs;
  final bool undone;

  /// True when a newer operation invalidated the redo of this entry.
  final bool discarded;

  String get display => switch (op) {
        JournalOp.copy => 'copied to ${p.basename(toPath ?? '')}',
        JournalOp.move || JournalOp.rename => 'moved to ${p.basename(toPath ?? '')}',
        JournalOp.delete => 'deleted',
        JournalOp.mkdir => 'created',
        JournalOp.write => 'wrote ${f.formatSize(int.tryParse(meta ?? '') ?? 0)}',
        JournalOp.restore => 'restored',
        JournalOp.metadata => 'metadata edited',
        JournalOp.split => 'split into ${meta ?? '?'} parts',
        JournalOp.merge => 'merged',
      };

  JournalEntry copyWith({bool? undone}) => JournalEntry(
        id: id,
        batchId: batchId,
        op: op,
        fromPath: fromPath,
        toPath: toPath,
        meta: meta,
        createdAtMs: createdAtMs,
        undone: undone ?? this.undone,
      );
}

class BatchInfo {
  const BatchInfo(this.batchId, this.count, this.at, this.label);
  final String batchId;
  final int count;
  final DateTime at;
  final String label;
}

// ── Rules, pipelines, macros, automation ────────────────────────────────────

class RuleCondition {
  const RuleCondition({required this.field, required this.match, required this.value});
  final String field; // name | ext | path | size | mtime
  final String match; // contains | equals | glob | gt | lt | within
  final String value;

  Map<String, dynamic> toJson() => {'field': field, 'match': match, 'value': value};
  static RuleCondition fromJson(Map<String, dynamic> j) =>
      RuleCondition(field: j['field'] as String, match: j['match'] as String, value: j['value'] as String);
}

class RuleAction {
  const RuleAction({required this.kind, required this.arg});
  final String kind; // rename | move | trash | freeze | pipeline
  final String arg;

  Map<String, dynamic> toJson() => {'kind': kind, 'arg': arg};
  static RuleAction fromJson(Map<String, dynamic> j) =>
      RuleAction(kind: j['kind'] as String, arg: j['arg'] as String);
}

class NexusRule {
  const NexusRule({
    this.id,
    required this.name,
    required this.enabled,
    required this.match,
    required this.conditions,
    required this.actions,
  });

  final int? id;
  final String name;
  final bool enabled;
  final String match; // all | any
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  NexusRule copyWith({String? name, bool? enabled, String? match, List<RuleCondition>? conditions,
      List<RuleAction>? actions, int? id}) =>
      NexusRule(
        id: id ?? this.id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        match: match ?? this.match,
        conditions: conditions ?? this.conditions,
        actions: actions ?? this.actions,
      );
}

class PipelineStep {
  const PipelineStep({required this.kind, required this.args, this.enabled = true});
  final String kind; // renamePattern | case | ext | move | copy | trash | compress
  final Map<String, String> args;
  final bool enabled;

  String get label => switch (kind) {
        'renamePattern' => 'Rename · ${args['pattern'] ?? ''}',
        'case' => 'Case · ${args['mode'] ?? ''}',
        'ext' => 'Extension · ${args['ext'] ?? ''}',
        'move' => 'Move · ${p.compactPath(args['dest'] ?? '')}',
        'copy' => 'Copy · ${p.compactPath(args['dest'] ?? '')}',
        'trash' => 'Move to trash',
        'compress' => 'Compress · ${args['name'] ?? 'archive.zip'}',
        _ => kind,
      };

  Map<String, dynamic> toJson() => {'kind': kind, 'args': args, 'enabled': enabled};
  static PipelineStep fromJson(Map<String, dynamic> j) => PipelineStep(
        kind: j['kind'] as String,
        args: (j['args'] as Map).cast<String, String>(),
        enabled: j['enabled'] as bool? ?? true,
      );

  PipelineStep copyWith({String? kind, Map<String, String>? args, bool? enabled}) =>
      PipelineStep(kind: kind ?? this.kind, args: args ?? this.args, enabled: enabled ?? this.enabled);
}

class NexusPipeline {
  const NexusPipeline({this.id, required this.name, required this.steps});
  final int? id;
  final String name;
  final List<PipelineStep> steps;

  NexusPipeline copyWith({String? name, List<PipelineStep>? steps}) =>
      NexusPipeline(id: id, name: name ?? this.name, steps: steps ?? this.steps);
}

class MacroStep {
  const MacroStep({required this.action, required this.args, required this.atMs});
  final String action;
  final Map<String, dynamic> args;
  final int atMs;

  Map<String, dynamic> toJson() => {'action': action, 'args': args, 'at': atMs};
  static MacroStep fromJson(Map<String, dynamic> j) => MacroStep(
        action: j['action'] as String,
        args: (j['args'] as Map).cast<String, dynamic>(),
        atMs: j['at'] as int,
      );
}

class NexusMacro {
  const NexusMacro({this.id, required this.name, required this.steps, required this.createdAtMs});
  final int? id;
  final String name;
  final List<MacroStep> steps;
  final int createdAtMs;

  NexusMacro copyWith({String? name, List<MacroStep>? steps}) =>
      NexusMacro(id: id, name: name ?? this.name, steps: steps ?? this.steps, createdAtMs: createdAtMs);
}

class WatchdogRule {
  const WatchdogRule({
    this.id,
    required this.name,
    required this.folder,
    required this.trigger,
    required this.pattern,
    required this.action,
    required this.arg,
    required this.enabled,
    this.lastFiredMs,
  });

  final int? id;
  final String name;
  final String folder;
  final String trigger; // any | added | removed | pattern
  final String pattern;
  final String action; // notify | moveTo | pipeline | version | teleport
  final String arg;
  final bool enabled;
  final int? lastFiredMs;

  WatchdogRule copyWith({bool? enabled, int? lastFiredMs, String? name, String? action, String? arg}) =>
      WatchdogRule(
        id: id,
        name: name ?? this.name,
        folder: folder,
        trigger: trigger,
        pattern: pattern,
        action: action ?? this.action,
        arg: arg ?? this.arg,
        enabled: enabled ?? this.enabled,
        lastFiredMs: lastFiredMs ?? this.lastFiredMs,
      );
}

class ScheduleJob {
  const ScheduleJob({
    this.id,
    required this.name,
    required this.kind,
    required this.targets,
    required this.arg,
    this.runAtMs,
    this.intervalMin,
    required this.enabled,
    this.lastRunMs,
    this.lastStatus = '',
  });

  final int? id;
  final String name;
  final String kind; // copy | move | trash | compress | pipeline | mirror
  final Map<String, dynamic> targets;
  final String arg;
  final int? runAtMs;
  final int? intervalMin;
  final bool enabled;
  final int? lastRunMs;
  final String lastStatus;

  String get scheduleLabel {
    if (intervalMin != null) {
      if (intervalMin! % 1440 == 0) return 'Every ${intervalMin! ~/ 1440} day(s)';
      if (intervalMin! % 60 == 0) return 'Every ${intervalMin! ~/ 60} hour(s)';
      return 'Every $intervalMin min';
    }
    return runAtMs == null ? 'Manual' : f.formatDateTime(DateTime.fromMillisecondsSinceEpoch(runAtMs!));
  }

  ScheduleJob copyWith({bool? enabled, int? lastRunMs, String? lastStatus, int? runAtMs}) => ScheduleJob(
        id: id,
        name: name,
        kind: kind,
        targets: targets,
        arg: arg,
        runAtMs: runAtMs ?? this.runAtMs,
        intervalMin: intervalMin,
        enabled: enabled ?? this.enabled,
        lastRunMs: lastRunMs ?? this.lastRunMs,
        lastStatus: lastStatus ?? this.lastStatus,
      );
}

// ── Organization & extras ───────────────────────────────────────────────────

class VersionSnapshot {
  const VersionSnapshot({
    this.id,
    required this.originalPath,
    required this.snapshotPath,
    required this.size,
    required this.createdAtMs,
  });
  final int? id;
  final String originalPath;
  final String snapshotPath;
  final int size;
  final int createdAtMs;
}

class MirrorPair {
  const MirrorPair({
    this.id,
    required this.name,
    required this.source,
    required this.target,
    required this.enabled,
    this.lastSyncMs,
  });
  final int? id;
  final String name;
  final String source;
  final String target;
  final bool enabled;
  final int? lastSyncMs;

  MirrorPair copyWith({bool? enabled, int? lastSyncMs}) => MirrorPair(
      id: id, name: name, source: source, target: target,
      enabled: enabled ?? this.enabled, lastSyncMs: lastSyncMs ?? this.lastSyncMs);
}

class PathAlias {
  const PathAlias({this.id, required this.name, required this.path});
  final int? id;
  final String name;
  final String path;
}

class StackItem {
  const StackItem({required this.path, required this.label});
  final String path;
  final String label;

  Map<String, dynamic> toJson() => {'path': path, 'label': label};
  static StackItem fromJson(Map<String, dynamic> j) =>
      StackItem(path: j['path'] as String, label: j['label'] as String);
}

class FolderStack {
  const FolderStack({this.id, required this.name, required this.items});
  final int? id;
  final String name;
  final List<StackItem> items;

  FolderStack copyWith({String? name, List<StackItem>? items}) =>
      FolderStack(id: id, name: name ?? this.name, items: items ?? this.items);
}

class PinnedItem {
  const PinnedItem({this.id, required this.path, required this.label, required this.edge, required this.sort});
  final int? id;
  final String path;
  final String label;
  final String edge; // left | right | top | bottom
  final int sort;
}

class FrozenPath {
  const FrozenPath({this.id, required this.path, required this.createdAtMs, required this.note});
  final int? id;
  final String path;
  final int createdAtMs;
  final String note;
}

class TemplateFile {
  const TemplateFile({this.id, required this.name, required this.kind, required this.sourcePath, this.content});
  final int? id;
  final String name;
  final String kind; // file | dir | text
  final String sourcePath;
  final String? content;
}

class WorkSession {
  const WorkSession({this.id, required this.name, required this.updatedAtMs, required this.payload});
  final int? id;
  final String name;
  final int updatedAtMs;
  final Map<String, dynamic> payload;

  WorkSession copyWith({String? name, int? updatedAtMs, Map<String, dynamic>? payload}) => WorkSession(
      id: id, name: name ?? this.name, updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      payload: payload ?? this.payload);
}

class TeleportPeer {
  const TeleportPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.port,
    required this.seen,
  });
  final String id;
  final String name;
  final String platform;
  final String ip;
  final int port;
  final DateTime seen;

  TeleportPeer touches() => TeleportPeer(
      id: id, name: name, platform: platform, ip: ip, port: port, seen: DateTime.now());
}

class VersionInfo {
  const VersionInfo({required this.name, required this.path, required this.size, required this.at});
  final String name;
  final String path;
  final int size;
  final DateTime at;
}

// ── Diff ────────────────────────────────────────────────────────────────────

enum DiffKind { same, added, removed, changed }

class DiffSpan {
  const DiffSpan(this.start, this.end, this.kind);
  final int start;
  final int end;
  final DiffKind kind;
}

class DiffLine {
  const DiffLine({required this.aNo, required this.bNo, required this.kind, required this.text, this.spans = const []});
  final int? aNo;
  final int? bNo;
  final DiffKind kind;
  final String text;
  final List<DiffSpan> spans;
}

// ── Metadata ────────────────────────────────────────────────────────────────

class EntryMeta {
  const EntryMeta({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.genre,
    this.track,
    this.camera,
    this.taken,
    this.description,
    this.width,
    this.height,
    this.durationMs,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String? genre;
  final String? track;
  final String? camera;
  final DateTime? taken;
  final String? description;
  final int? width;
  final int? height;
  final int? durationMs;

  String? operator [](String key) => switch (key) {
        'title' => title,
        'artist' => artist,
        'album' => album,
        'year' => year,
        'genre' => genre,
        'track' => track,
        'camera' => camera,
        'taken' => taken == null ? null : f.formatDate(taken!),
        'description' => description,
        'dimensions' => width == null ? null : '$width×$height',
        _ => null,
      };

  String describe() {
    final parts = <String>[
      if (title != null) title!,
      if (artist != null) artist!,
      if (album != null) album!,
      if (camera != null) camera!,
      if (taken != null) f.formatDateTime(taken!),
      if (width != null) '$width×$height',
      if (durationMs != null) f.formatDuration(Duration(milliseconds: durationMs!)),
    ];
    return parts.isEmpty ? 'No metadata found' : parts.join(' · ');
  }
}

/// Result row of the content-aware rename scan.
class RenameCandidate {
  const RenameCandidate({required this.entry, required this.meta, required this.suggested, required this.newName});
  final NexusEntry entry;
  final EntryMeta meta;
  final String suggested;
  final String newName;

  RenameCandidate withName(String n) =>
      RenameCandidate(entry: entry, meta: meta, suggested: suggested, newName: n);
}
