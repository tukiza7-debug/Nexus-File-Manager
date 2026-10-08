import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ms.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('id'), Locale('ms')];

  /// Application name shown in chrome and stores
  ///
  /// In en, this message translates to:
  /// **'Nexus File Manager'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Powerful. Precise. Beautiful.'**
  String get tagline;

  /// No description provided for @commandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get commandPalette;

  /// No description provided for @ghostMode.
  ///
  /// In en, this message translates to:
  /// **'Ghost mode'**
  String get ghostMode;

  /// No description provided for @zenMode.
  ///
  /// In en, this message translates to:
  /// **'Zen mode'**
  String get zenMode;

  /// No description provided for @exitZen.
  ///
  /// In en, this message translates to:
  /// **'Exit Zen'**
  String get exitZen;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String items(int count);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @inStack.
  ///
  /// In en, this message translates to:
  /// **'{count} in stack'**
  String inStack(int count);

  /// No description provided for @recordingMacro.
  ///
  /// In en, this message translates to:
  /// **'Recording macro'**
  String get recordingMacro;

  /// No description provided for @nothingToUndo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to undo'**
  String get nothingToUndo;

  /// No description provided for @nothingToRedo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to redo'**
  String get nothingToRedo;

  /// No description provided for @undone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get undone;

  /// No description provided for @redone.
  ///
  /// In en, this message translates to:
  /// **'Redone'**
  String get redone;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @clearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get clearFilter;

  /// No description provided for @copiedCount.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} item(s)'**
  String copiedCount(int count);

  /// No description provided for @movedCount.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} item(s)'**
  String movedCount(int count);

  /// No description provided for @pastedCount.
  ///
  /// In en, this message translates to:
  /// **'Pasted {count} item(s)'**
  String pastedCount(int count);

  /// No description provided for @deletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} item(s)'**
  String deletedCount(int count);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String operationFailed(String error);

  /// No description provided for @places.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get places;

  /// No description provided for @aliases.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get aliases;

  /// No description provided for @stacks.
  ///
  /// In en, this message translates to:
  /// **'Folder Stacks'**
  String get stacks;

  /// No description provided for @secureFreeze.
  ///
  /// In en, this message translates to:
  /// **'Secure Freeze'**
  String get secureFreeze;

  /// No description provided for @clipboardStack.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Stack'**
  String get clipboardStack;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modified;

  /// No description provided for @kind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get kind;

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Nexus needs storage access'**
  String get storageTitle;

  /// No description provided for @storageBody.
  ///
  /// In en, this message translates to:
  /// **'To browse, organize and manage your files, Nexus needs permission to read and write storage. Without it the app can still work inside its own folders (limited mode). You can change this any time in system settings.'**
  String get storageBody;

  /// No description provided for @grantStorage.
  ///
  /// In en, this message translates to:
  /// **'Grant storage access'**
  String get grantStorage;

  /// No description provided for @limitedMode.
  ///
  /// In en, this message translates to:
  /// **'Continue in limited mode'**
  String get limitedMode;

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get openSystemSettings;

  /// No description provided for @incomingShares.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file shared to Nexus — save it into your Downloads folder?} other{{count} files shared to Nexus — save them into your Downloads folder?}}'**
  String incomingShares(int count);

  /// No description provided for @saveToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Save to Downloads'**
  String get saveToDownloads;

  /// No description provided for @sessionSaved.
  ///
  /// In en, this message translates to:
  /// **'Session saved'**
  String get sessionSaved;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'id', 'ms'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
    case 'ms':
      return AppLocalizationsMs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
