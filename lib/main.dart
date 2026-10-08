import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/db/nexus_database.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Inter'], 'OFL');
  });

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Desktop window chrome (no-op guarded on mobile / unsupported platforms).
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          title: 'Nexus File Manager',
          titleBarStyle: TitleBarStyle.hidden,
          minimumSize: Size(980, 620),
          windowButtonVisibility: true,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (_) {}
  }

  late final AppServices services;
  try {
    final prefs = await SharedPreferences.getInstance();
    final db = await DbService.open();
    services = AppServices(db, prefs);
    await services.init();
  } catch (e, st) {
    await _fatal(e, st);
    return;
  }

  runApp(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const NexusApp(),
    ),
  );
}

Future<void> _fatal(Object e, StackTrace st) async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  await File('${dir.path}/nexus-crash.log')
      .writeAsString('$e\n\n$st', flush: true);
  runApp(_FatalApp(message: '$e'));
}

class _FatalApp extends StatelessWidget {
  const _FatalApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nexus could not start',
                    style: TextStyle(
                        color: Color(0xFFE6EAF2),
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  'A crash log was written to your application support folder.\n\n$message',
                  style: const TextStyle(
                      color: Color(0xFF8B94A7), fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
