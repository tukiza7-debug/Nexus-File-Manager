/// Shared test bootstrap: initializes the Flutter binding and mocks the
/// path_provider channel so journal backups land inside the test temp dir
/// instead of a host application-support directory.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Call from `setUpAll()` in service tests that touch nexusDataDir().
void mockPathProvider(Directory base) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationSupportPath':
      case 'getApplicationDocumentsPath':
      case 'getApplicationDocumentsDirectory':
      case 'getTemporaryPath':
        return base.path;
      default:
        return base.path;
    }
  });
}
