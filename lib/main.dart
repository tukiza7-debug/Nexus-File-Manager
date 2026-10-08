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
import 'core/utils/logger.dart';
import 'features/onboarding/permission_gate.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface unexpected framework errors instead of a blank native window.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  LicenseRegistry.addLicense(() async* {
    // Full Inter OFL license text (audit item 48) — the bundled font is
    // licensed under the SIL Open Font License 1.1.
    yield const LicenseEntryWithLineBreaks(['Inter'], _interOfl);
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
    } catch (e, st) {
      // Non-fatal: the app runs with default window chrome.
      logError('window_manager init failed', e, st);
    }
  }

  // Audit item 22: storage permissions are NOT requested here anymore.
  // The PermissionGate shows an explanation screen after the first frame
  // and requests MANAGE_EXTERNAL_STORAGE (Android 11+), the legacy storage
  // prompt (Android 10−) or READ_MEDIA_* equivalents, with a limited mode
  // for users who decline.

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
      child: const PermissionGate(child: NexusApp()),
    ),
  );
}

Future<void> _fatal(Object e, StackTrace st) async {
  logError('fatal startup error', e, st);
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

/// The SIL Open Font License, Version 1.1 — full text for the Inter font.
const String _interOfl = '''
Copyright (c) 2016-2023 The Inter Project Authors (https://github.com/rsms/inter)

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://scripts.sil.org/OFL

SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a large and
free font library supporting the use of font software across formats and
across a wide range of devices and systems.

The requirements for binding the license are practical: fonts licensed
under this license may be used, studied, modified and redistributed freely
as long as they are not sold by themselves. The fonts, including any
derivative works, can be bundled, embedded, redistributed and/or sold with
any software provided that the font software is not sold by itself. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivative works may
not be sold by themselves.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may include
source files, build scripts and documentation.

"Reserved Font Name" refers to any software specified font name under this
license by the Copyright Holder(s).

"Standard Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting — in part or in whole — any of the components of the
Standard Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical writer or
other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining a
copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components, in
Standard or Modified Versions, may be sold by itself.

2) Standard or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or in
the appropriate machine-readable metadata fields within text or binary
files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any Modified
Version, either (a) under the Reserved Font Name(s) unless explicit
written permission is granted by the corresponding Copyright Holder, or
(b) under any name that conflicts with the Reserved Font Name(s) unless
explicit written permission is granted.

5) The Font Software, modified or unmodified, in part or in whole, must be
distributed entirely under this license, and must not be distributed under
any other license. The requirement for fonts to remain under this license
does not apply to any document created using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are not
met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
DEALINGS IN THE FONT SOFTWARE.
''';
