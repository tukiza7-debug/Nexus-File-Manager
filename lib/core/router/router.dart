/// App shell + navigation. The explorer shell (title bar, sidebar, dock,
/// status bar, toasts) persists across every route inside [ShellRoute], so
/// tools open inside the same chrome — no jarring full-page swaps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/explorer/explorer_shell.dart';
import '../../features/explorer/screens/explorer_screen.dart';
import '../../features/papertrail/papertrail_screen.dart';
import '../../features/sessions/sessions_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tools/automation_screen.dart';
import '../../features/tools/diff_screen.dart';
import '../../features/tools/mirror_screen.dart';
import '../../features/tools/pipeline_screen.dart';
import '../../features/tools/rename_screen.dart';
import '../../features/tools/teleport_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../../features/tools/versions_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => ExplorerShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _fade(state, const ExplorerScreen()),
          ),
          GoRoute(
            path: '/tools',
            pageBuilder: (context, state) => _fade(state, const ToolsScreen()),
            routes: [
              _tool('/tools/pipeline', const PipelineScreen()),
              _tool('/tools/diff', const DiffScreen()),
              _tool('/tools/rename', const ContentRenameScreen()),
              _tool('/tools/mirror', const MirrorScreen()),
              _tool('/tools/teleport', const TeleportScreen()),
              _tool('/tools/automation', const AutomationScreen()),
              _tool('/tools/versions', const VersionsScreen()),
            ],
          ),
          GoRoute(
            path: '/papertrail',
            pageBuilder: (context, state) => _fade(state, const PaperTrailScreen()),
          ),
          GoRoute(
            path: '/sessions',
            pageBuilder: (context, state) => _fade(state, const SessionsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _fade(state, const SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

GoRoute _tool(String path, Widget screen) =>
    GoRoute(path: path, pageBuilder: (context, state) => _fade(state, screen));

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );
