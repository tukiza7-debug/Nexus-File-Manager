/// Application-wide state: service container, settings, tabs, directory
/// listings and every persisted collection. Built on Riverpod 2 with plain
/// [StateNotifier]s — no codegen, fully inspectable.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as pp;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/db/nexus_database.dart';
import '../core/services/clipboard_service.dart';
import '../core/services/diff_engine.dart';
import '../core/services/freeze_service.dart';
import '../core/services/fs_service.dart';
import '../core/services/incoming_share.dart';
import '../core/services/journal.dart';
import '../core/services/macro_service.dart';
import '../core/services/merge_service.dart';
import '../core/services/metadata_service.dart';
import '../core/services/mirror_service.dart';
import '../core/services/ops_service.dart';
import '../core/services/pipeline_service.dart';
import '../core/services/progress.dart';
import '../core/services/rule_engine.dart';
import '../core/services/scheduler_service.dart';
import '../core/services/session_service.dart';
import '../core/services/smart_paste.dart';
import '../core/services/split_service.dart';
import '../core/services/teleport_service.dart';
import '../core/services/template_service.dart';
import '../core/services/versioning_service.dart';
import '../core/services/watchdog_service.dart';
import '../core/services/watcher_service.dart';
import '../core/utils/path_utils.dart' as pu;
import '../domain/enums.dart';
import '../domain/models.dart';

// ── Service container ────────────────────────────────────────────────────────

/// Owns every singleton service. Created once in `main()` and injected via
/// [servicesProvider] so the whole tree can depend on it synchronously.
class AppServices {
  AppServices(this.db, this.prefs);

  final DbService db;
  final SharedPreferences prefs;

  late final watchers = WatcherService();
  late final journal = OperationJournal(db);
  late final freeze = FreezeService(db);
  late final cancels = CancelRegistry();
  late final ops = FileOpsService(journal, cancels, freeze.frozenRoots);
  late final fs = const FileSystemService();
  late final clipboard = ClipboardStackService(db);
  late final smartPaste = const SmartPasteResolver();
  late final split = const SplitService();
  late final merge = const MergeService();
  late final diff = const DiffEngine();
  late final ruleEngine = const RuleEngine();
  late final metadata = const MetadataService();
  late final templates = TemplateService(db);
  late final pipelines = PipelineService(db, ops);
  late final macros = MacroService(db);
  late final sessions = SessionService(db, templates);
  late final versioning = VersioningService(db, watchers);
  late final watchdogs = WatchdogService(db, ops, watchers, pipelines, versioning, journal);
  late final mirrors = MirrorService(db, ops, watchers, journal);
  late final scheduler = SchedulerService(db, ops, pipelines, mirrors);
  late final teleport = TeleportService(ops);
  late final incoming = IncomingShareService();

  final watchdogFeed = <WatchdogEvent>[];
  final _feedCtrl = StreamController<void>.broadcast();
  Stream<void> get feedChanges => _feedCtrl.stream;
  void _pushFeed(WatchdogEvent e) {
    watchdogFeed.insert(0, e);
    if (watchdogFeed.length > 200) watchdogFeed.removeLast();
    _feedCtrl.add(null);
  }

  Future<void> init() async {
    // Auto versioning configuration comes from settings.
    versioning.configure(
      enabled: prefs.getBool('versioning.enabled') ?? true,
      keep: prefs.getInt('versioning.keep') ?? 20,
    );

    clipboard.load();
    await mirrors.startAll();
    for (final w in db.watchdogs().where((w) => w.enabled)) {
      watchdogs.start(w);
    }
    // (watchdog.start returns void; keep the loop await-free by design)
    watchdogs.events.listen(_pushFeed);
    scheduler.start();

    // Teleport — best effort; networking can be unavailable on some devices.
    unawaited(() async {
      try {
        final dir = prefs.getString('teleport.dir') ??
            pp.join((await getApplicationDocumentsDirectory()).path, 'Teleport Inbox');
        await Directory(dir).create(recursive: true);
        final name = prefs.getString('teleport.name') ?? Platform.localHostname;
        await teleport.start(name: name, downloadTo: dir);
      } catch (_) {}
    }());
  }

  void dispose() {
    scheduler.dispose();
    watchdogs.dispose();
    mirrors.dispose();
    teleport.dispose();
    watchers.disposeAll();
    clipboard.dispose();
    ops.dispose();
    db.close();
  }
}

final servicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

// ── Look & feel / accessibility ──────────────────────────────────────────────

enum BrightnessPref { dark, light, system }

class LookState {
  const LookState({
    required this.brand,
    required this.bright,
    required this.accent,
    required this.colorblindSafe,
    required this.badge,
    required this.touchMode,
  });

  final ThemeBrand brand;
  final BrightnessPref bright;
  final String accent; // hex like 0xFF2563EB
  final bool colorblindSafe;
  final TileBadge badge;
  final bool touchMode;

  LookState copyWith({
    ThemeBrand? brand,
    BrightnessPref? bright,
    String? accent,
    bool? colorblindSafe,
    TileBadge? badge,
    bool? touchMode,
  }) =>
      LookState(
        brand: brand ?? this.brand,
        bright: bright ?? this.bright,
        accent: accent ?? this.accent,
        colorblindSafe: colorblindSafe ?? this.colorblindSafe,
        badge: badge ?? this.badge,
        touchMode: touchMode ?? this.touchMode,
      );
}

class LookController extends StateNotifier<LookState> {
  LookController(this._prefs)
      : super(LookState(
          brand: ThemeBrand.values.asNameMap()[_prefs.getString('theme.brand')] ??
              ThemeBrand.nexus,
          bright:
              BrightnessPref.values.asNameMap()[_prefs.getString('theme.bright')] ??
                  BrightnessPref.dark,
          accent: _prefs.getString('theme.accent') ?? '0xFF2563EB',
          colorblindSafe: _prefs.getBool('a11y.colorblind') ?? false,
          badge: TileBadge.values.asNameMap()[_prefs.getString('a11y.badge')] ??
              TileBadge.hatched,
          touchMode: _prefs.getBool('ui.touchMode') ?? false,
        ));

  final SharedPreferences _prefs;

  void _set(String key, Object value) {
    if (value is bool) {
      _prefs.setBool(key, value);
    } else if (value is int) {
      _prefs.setInt(key, value);
    } else if (value is double) {
      _prefs.setDouble(key, value);
    } else {
      _prefs.setString(key, '$value');
    }
  }

  void setBrand(ThemeBrand v) {
    state = state.copyWith(brand: v);
    _set('theme.brand', v.name);
  }

  void setBright(BrightnessPref v) {
    state = state.copyWith(bright: v);
    _set('theme.bright', v.name);
  }

  void setAccent(String hex) {
    state = state.copyWith(accent: hex);
    _set('theme.accent', hex);
  }

  void setColorblind(bool v) {
    state = state.copyWith(colorblindSafe: v);
    _set('a11y.colorblind', v);
  }

  void setBadge(TileBadge v) {
    state = state.copyWith(badge: v);
    _set('a11y.badge', v.name);
  }

  void setTouchMode(bool v) {
    state = state.copyWith(touchMode: v);
    _set('ui.touchMode', v);
  }
}

final lookProvider =
    StateNotifierProvider<LookController, LookState>((ref) {
  final prefs = ref.watch(servicesProvider).prefs;
  return LookController(prefs);
});

// ── Transient UI state ───────────────────────────────────────────────────────

class UiState {
  const UiState({
    this.sidebarVisible = true,
    this.zenMode = false,
    this.ghostOpacity = 1.0,
    this.focusTunnelPath,
    this.peekPath,
    this.inspectorPath,
    this.splitTypeView = false,
    this.showHidden = false,
    this.filter = '',
    this.recentsOpen = false,
  });

  final bool sidebarVisible;
  final bool zenMode;
  final double ghostOpacity; // 1 = solid; <1 = ghost mode active
  final String? focusTunnelPath;
  final String? peekPath; // Peek Preview target (Alt+hover)
  final String? inspectorPath; // Floating Inspector target
  final bool splitTypeView;
  final bool showHidden;
  final String filter;
  final bool recentsOpen;

  UiState copyWith({
    bool? sidebarVisible,
    bool? zenMode,
    double? ghostOpacity,
    String? focusTunnelPath,
    bool clearFocusTunnel = false,
    String? peekPath,
    bool clearPeek = false,
    String? inspectorPath,
    bool clearInspector = false,
    bool? splitTypeView,
    bool? showHidden,
    String? filter,
    bool? recentsOpen,
  }) =>
      UiState(
        sidebarVisible: sidebarVisible ?? this.sidebarVisible,
        zenMode: zenMode ?? this.zenMode,
        ghostOpacity: ghostOpacity ?? this.ghostOpacity,
        focusTunnelPath:
            clearFocusTunnel ? null : (focusTunnelPath ?? this.focusTunnelPath),
        peekPath: clearPeek ? null : (peekPath ?? this.peekPath),
        inspectorPath:
            clearInspector ? null : (inspectorPath ?? this.inspectorPath),
        splitTypeView: splitTypeView ?? this.splitTypeView,
        showHidden: showHidden ?? this.showHidden,
        filter: filter ?? this.filter,
        recentsOpen: recentsOpen ?? this.recentsOpen,
      );
}

class UiController extends StateNotifier<UiState> {
  UiController(this.ref) : super(const UiState());

  final Ref ref;

  void toggleSidebar() => state = state.copyWith(sidebarVisible: !state.sidebarVisible);
  void toggleZen() => state = state.copyWith(zenMode: !state.zenMode);
  void toggleHidden() => state = state.copyWith(showHidden: !state.showHidden);
  void toggleSplitType() => state = state.copyWith(splitTypeView: !state.splitTypeView);
  void setFilter(String q) => state = state.copyWith(filter: q);

  void setGhost(double opacity) {
    state = state.copyWith(ghostOpacity: opacity);
    ref.read(servicesProvider).prefs.setDouble('ui.ghost', opacity);
  }

  void restoreGhost() {
    final v = ref.read(servicesProvider).prefs.getDouble('ui.ghost') ?? 0.45;
    setGhost(v);
  }

  void solidGhost() {
    state = state.copyWith(ghostOpacity: 1.0);
  }

  void setFocusTunnel(String? path) =>
      state = state.copyWith(focusTunnelPath: path, clearFocusTunnel: path == null);
  void setPeek(String? path) => state = state.copyWith(peekPath: path, clearPeek: path == null);
  void setInspector(String? path) =>
      state = state.copyWith(inspectorPath: path, clearInspector: path == null);
  void toggleInspector(String path) => state = state.copyWith(
        inspectorPath: state.inspectorPath == path ? '' : path,
        clearInspector: state.inspectorPath == path,
      );
}

final uiProvider = StateNotifierProvider<UiController, UiState>(UiController.new);

// ── Tabs & directory listing ─────────────────────────────────────────────────

class TabsState {
  const TabsState({required this.tabs, required this.activeId});

  final List<TabState> tabs;
  final String activeId;

  TabState get active => tabs.firstWhere((t) => t.id == activeId, orElse: () => tabs.first);

  TabsState copyWith({List<TabState>? tabs, String? activeId}) =>
      TabsState(tabs: tabs ?? this.tabs, activeId: activeId ?? this.activeId);
}

class TabsController extends StateNotifier<TabsState> {
  TabsController(Ref ref)
      : _svc = ref.read(servicesProvider),
        super(_initial(ref.read(servicesProvider)));

  final AppServices _svc;
  static int _seq = 0;

  static TabsState _initial(AppServices svc) {
    final saved = svc.sessions.autosave();
    if (saved != null && ((saved['tabs'] as List?)?.isNotEmpty ?? false)) {
      final tabs = (saved['tabs'] as List)
          .map((e) => TabState.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (tabs.isNotEmpty) {
        return TabsState(
          tabs: tabs,
          activeId: (saved['activeId'] as String?) ?? tabs.first.id,
        );
      }
    }
    final home = svc.fs.homeDir();
    final t = TabState(id: _newId(), history: [home], histIndex: 0);
    return TabsState(tabs: [t], activeId: t.id);
  }

  static String _newId() => 'tab-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Payload for Work Session save/restore + autosave.
  Map<String, dynamic> payload() => {
        'activeId': state.activeId,
        'tabs': [for (final t in state.tabs) t.toJson()],
      };

  void restore(Map<String, dynamic> payload) {
    final tabs = (payload['tabs'] as List)
        .map((e) => TabState.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    if (tabs.isEmpty) return;
    state = TabsState(
      tabs: tabs,
      activeId: (payload['activeId'] as String?) ?? tabs.first.id,
    );
    _svc.sessions.flushAutosave(payload);
  }

  void _update(TabState t) {
    state = state.copyWith(tabs: [
      for (final old in state.tabs)
        if (old.id == t.id) t else old,
    ]);
    _svc.sessions.flushAutosave(payload());
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state.tabs];
    var target = newIndex;
    if (target > oldIndex) target--;
    final t = list.removeAt(oldIndex);
    list.insert(target.clamp(0, list.length), t);
    state = TabsState(tabs: list, activeId: state.activeId);
    _svc.sessions.flushAutosave(payload());
  }

  void openTab(String path) {
    final t = TabState(id: _newId(), history: [path], histIndex: 0);
    state = TabsState(tabs: [...state.tabs, t], activeId: t.id);
    _svc.sessions.flushAutosave(payload());
  }

  void closeTab(String id) {
    if (state.tabs.length == 1) return;
    final idx = state.tabs.indexWhere((t) => t.id == id);
    final tabs = state.tabs.where((t) => t.id != id).toList();
    var active = state.activeId;
    if (id == active) active = tabs[(idx - 1).clamp(0, tabs.length - 1)].id;
    state = TabsState(tabs: tabs, activeId: active);
    _svc.sessions.flushAutosave(payload());
  }

  void activate(String id) {
    state = state.copyWith(activeId: id);
    _svc.sessions.flushAutosave(payload());
  }

  void navigate(String path) => _update(state.active.copyWith(
        history: [...state.active.history.sublist(0, state.active.histIndex + 1), path],
        histIndex: state.active.histIndex + 1,
        selection: {},
        visited: state.active.visited.contains(path)
            ? state.active.visited
            : [...state.active.visited, path],
      ));

  void back() {
    if (!state.active.canBack) return;
    _update(state.active.copyWith(histIndex: state.active.histIndex - 1, selection: {}));
  }

  void forward() {
    if (!state.active.canForward) return;
    _update(state.active.copyWith(histIndex: state.active.histIndex + 1, selection: {}));
  }

  void up() {
    final parent = pu.dirname(state.active.path);
    if (parent != state.active.path) navigate(parent);
  }

  void home() => navigate(_svc.fs.homeDir());

  void toggleSelect(String path) {
    final sel = {...state.active.selection};
    sel.contains(path) ? sel.remove(path) : sel.add(path);
    _update(state.active.copyWith(selection: sel));
  }

  void selectOnly(String path) => _update(state.active.copyWith(selection: {path}));
  void selectAll(List<String> paths) => _update(state.active.copyWith(selection: paths.toSet()));
  void clearSelection() => _update(state.active.copyWith(selection: {}));

  void setSort(SortBy by, SortDir dir) =>
      _update(state.active.copyWith(sortBy: by, sortDir: dir));

  void setViewMode(ViewMode m) => _update(state.active.copyWith(viewMode: m));

  void setSpatial(bool v) => _update(state.active.copyWith(spatialMode: v));

  /// Spatial Memory: persist a manually placed tile position.
  void putSpatial(String folder, String name, double x, double y) =>
      _svc.db.putSpatial(folder, name, x, y);

  void refresh() => _update(state.active); // identical state; dir listener reloads on ref.tick
}

final tabsProvider = StateNotifierProvider<TabsController, TabsState>(
  TabsController.new,
);

class DirState {
  const DirState({this.entries = const [], this.loading = false, this.error});
  final List<NexusEntry> entries;
  final bool loading;
  final String? error;
}

/// Loads the active directory. Reloads when path / sort / hidden / filter
/// change, or when the filesystem watcher fires for the current folder.
class DirController extends StateNotifier<DirState> {
  DirController(this.ref) : super(const DirState(loading: true));

  final Ref ref;
  Timer? _reloadDebounce;
  StreamSubscription<void>? _watchSub;
  String? _watchedPath;

  void _watchFolder(String path) {
    if (_watchedPath == path) return;
    if (_watchedPath != null) {
      ref.read(servicesProvider).watchers.unwatch(_watchedPath!);
    }
    _watchedPath = path;
    ref.read(servicesProvider).watchers.watch(path, (_, __) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 350), reload);
    });
  }

  Future<void> reload() async {
    final tab = ref.read(tabsProvider).active;
    final svc = ref.read(servicesProvider);
    _watchFolder(tab.path);
    state = DirState(entries: state.entries, loading: true);
    try {
      final entries = await svc.fs.listDir(tab.path);
      state = DirState(entries: _sort(entries, tab));
    } catch (e) {
      state = DirState(error: e.toString());
    }
  }

  List<NexusEntry> _sort(List<NexusEntry> input, TabState tab) {
    final ui = ref.read(uiProvider);
    final q = ui.filter.trim().toLowerCase();
    final list = input.where((e) {
      if (ui.showHidden || !e.isHidden) {
        return q.isEmpty || pu.basename(e.path).toLowerCase().contains(q);
      }
      return false;
    }).toList();
    int cmp(NexusEntry a, NexusEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return switch (tab.sortBy) {
        SortBy.name => pu.naturalKey(a.name).compareTo(pu.naturalKey(b.name)),
        SortBy.size => a.size.compareTo(b.size),
        SortBy.modified => a.modified.compareTo(b.modified),
        SortBy.type => a.ext.compareTo(b.ext),
      };
    }

    list.sort((a, b) => tab.sortDir == SortDir.asc ? cmp(a, b) : cmp(b, a));
    return list;
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _watchSub?.cancel();
    if (_watchedPath != null) ref.read(servicesProvider).watchers.unwatch(_watchedPath!);
    super.dispose();
  }
}

final dirProvider = StateNotifierProvider<DirController, DirState>(DirController.new);

// ── Journal (paper trail + undo) ─────────────────────────────────────────────

class JournalController extends StateNotifier<List<JournalEntry>> {
  JournalController(this.ref) : super(const []) {
    reload();
  }

  final Ref ref;
  String query = '';

  void reload() {
    final db = ref.read(servicesProvider).db;
    state = query.isEmpty ? db.journal() : db.journal(query: query);
  }

  void search(String q) {
    query = q;
    reload();
  }

  /// Full history for one path (its own operations plus direct children ops
  /// when [path] is a folder).
  List<JournalEntry> forPath(String path) =>
      ref.read(servicesProvider).db.journal().where((e) {
        return e.fromPath == path ||
            (e.toPath ?? '') == path ||
            pu.dirname(e.fromPath) == path;
      }).toList();
}

final journalProvider =
    StateNotifierProvider<JournalController, List<JournalEntry>>(JournalController.new);

final batchesProvider = Provider<List<BatchInfo>>((ref) {
  ref.watch(journalProvider);
  return ref.read(servicesProvider).journal.batches();
});

// ── Streams from services ────────────────────────────────────────────────────

final clipboardProvider = StreamProvider<void>(
    (ref) => ref.watch(servicesProvider).clipboard.changes);

final progressProvider = StreamProvider<OpProgress>(
    (ref) => ref.watch(servicesProvider).ops.progress);

final watchdogFeedProvider = StreamProvider<void>(
    (ref) => ref.watch(servicesProvider).feedChanges);

final teleportPeersProvider = StreamProvider<List<TeleportPeer>>(
    (ref) => ref.watch(servicesProvider).teleport.peers);

final teleportInboxProvider = StreamProvider<TransferEvent>(
    (ref) => ref.watch(servicesProvider).teleport.inbox);

final teleportProgressProvider = StreamProvider<OpProgress>(
    (ref) => ref.watch(servicesProvider).teleport.progress);

final macroRecordingProvider = StreamProvider<bool>(
    (ref) => ref.watch(servicesProvider).macros.recordingStream);

// ── Persisted collections (reload-after-mutate pattern) ───────────────────
final aliasesProvider = Provider<List<PathAlias>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.aliases();
});

final stacksProvider = Provider<List<FolderStack>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.stacks();
});

final pinnedProvider = Provider<List<PinnedItem>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.pinned();
});

final rulesProvider = Provider<List<NexusRule>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.rules();
});

final pipelinesProvider = Provider<List<NexusPipeline>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.pipelines();
});

final macrosProvider = Provider<List<NexusMacro>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.macros();
});

final watchdogsProvider = Provider<List<WatchdogRule>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.watchdogs();
});

final schedulesProvider = Provider<List<ScheduleJob>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.schedules();
});

final templatesProvider = Provider<List<TemplateFile>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.templates();
});

final mirrorsProvider = Provider<List<MirrorPair>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.mirrors();
});

final freezesProvider = Provider<List<FrozenPath>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.freezes();
});

final sessionsProvider = Provider<List<WorkSession>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.sessions();
});

final versionedPathsProvider = Provider<List<String>>((ref) {
  ref.watch(dbTickProvider);
  return ref.watch(servicesProvider).db.versionedPaths();
});

/// Bump this to force every persisted-collection provider to re-read the DB.
final dbTickProvider = StateProvider<int>((ref) => 0);

void bumpDb(Ref ref) => ref.read(dbTickProvider.notifier).state++;
