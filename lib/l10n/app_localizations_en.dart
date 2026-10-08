// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Nexus File Manager';

  @override
  String get tagline => 'Powerful. Precise. Beautiful.';

  @override
  String get commandPalette => 'Command palette';

  @override
  String get ghostMode => 'Ghost mode';

  @override
  String get zenMode => 'Zen mode';

  @override
  String get exitZen => 'Exit Zen';

  @override
  String get menu => 'Menu';

  @override
  String items(int count) {
    return '$count items';
  }

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String inStack(int count) {
    return '$count in stack';
  }

  @override
  String get recordingMacro => 'Recording macro';

  @override
  String get nothingToUndo => 'Nothing to undo';

  @override
  String get nothingToRedo => 'Nothing to redo';

  @override
  String get undone => 'Undone';

  @override
  String get redone => 'Redone';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Save';

  @override
  String get discard => 'Discard';

  @override
  String get retry => 'Retry';

  @override
  String get clearFilter => 'Clear filter';

  @override
  String copiedCount(int count) {
    return 'Copied $count item(s)';
  }

  @override
  String movedCount(int count) {
    return 'Moved $count item(s)';
  }

  @override
  String pastedCount(int count) {
    return 'Pasted $count item(s)';
  }

  @override
  String deletedCount(int count) {
    return 'Deleted $count item(s)';
  }

  @override
  String operationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get places => 'Places';

  @override
  String get aliases => 'Aliases';

  @override
  String get stacks => 'Folder Stacks';

  @override
  String get secureFreeze => 'Secure Freeze';

  @override
  String get clipboardStack => 'Clipboard Stack';

  @override
  String get name => 'Name';

  @override
  String get size => 'Size';

  @override
  String get modified => 'Modified';

  @override
  String get kind => 'Kind';

  @override
  String get storageTitle => 'Nexus needs storage access';

  @override
  String get storageBody =>
      'To browse, organize and manage your files, Nexus needs permission to read and write storage. Without it the app can still work inside its own folders (limited mode). You can change this any time in system settings.';

  @override
  String get grantStorage => 'Grant storage access';

  @override
  String get limitedMode => 'Continue in limited mode';

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String incomingShares(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files shared to Nexus — save them into your Downloads folder?',
      one: '1 file shared to Nexus — save it into your Downloads folder?',
    );
    return '$_temp0';
  }

  @override
  String get saveToDownloads => 'Save to Downloads';

  @override
  String get sessionSaved => 'Session saved';
}
