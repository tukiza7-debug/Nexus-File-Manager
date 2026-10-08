// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class AppLocalizationsMs extends AppLocalizations {
  AppLocalizationsMs([String locale = 'ms']) : super(locale);

  @override
  String get appName => 'Nexus File Manager';

  @override
  String get tagline => 'Berkuasa. Tepat. Cantik.';

  @override
  String get commandPalette => 'Palet perintah';

  @override
  String get ghostMode => 'Mod hantu';

  @override
  String get zenMode => 'Mod Zen';

  @override
  String get exitZen => 'Keluar Zen';

  @override
  String get menu => 'Menu';

  @override
  String items(int count) {
    return '$count item';
  }

  @override
  String selectedCount(int count) {
    return '$count dipilih';
  }

  @override
  String inStack(int count) {
    return '$count dalam tindanan';
  }

  @override
  String get recordingMacro => 'Merakam makro';

  @override
  String get nothingToUndo => 'Tiada apa-apa untuk dibatalkan';

  @override
  String get nothingToRedo => 'Tiada apa-apa untuk dibuat semula';

  @override
  String get undone => 'Dibatalkan';

  @override
  String get redone => 'Dibuat semula';

  @override
  String get undo => 'Batal';

  @override
  String get redo => 'Buat semula';

  @override
  String get cancel => 'Batal';

  @override
  String get confirm => 'Sahkan';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Simpan';

  @override
  String get discard => 'Buang';

  @override
  String get retry => 'Cuba lagi';

  @override
  String get clearFilter => 'Kosongkan tapisan';

  @override
  String copiedCount(int count) {
    return '$count item disalin';
  }

  @override
  String movedCount(int count) {
    return '$count item dipindah';
  }

  @override
  String pastedCount(int count) {
    return '$count item ditampal';
  }

  @override
  String deletedCount(int count) {
    return '$count item dipadam';
  }

  @override
  String operationFailed(String error) {
    return 'Operasi gagal: $error';
  }

  @override
  String get places => 'Tempat';

  @override
  String get aliases => 'Alias';

  @override
  String get stacks => 'Tindanan Folder';

  @override
  String get secureFreeze => 'Beku Selamat';

  @override
  String get clipboardStack => 'Tindanan Papan Keratan';

  @override
  String get name => 'Nama';

  @override
  String get size => 'Saiz';

  @override
  String get modified => 'Diubah suai';

  @override
  String get kind => 'Jenis';

  @override
  String get storageTitle => 'Nexus perlu akses storan';

  @override
  String get storageBody =>
      'Untuk melayar, menyusun dan mengurus fail anda, Nexus perlu kebenaran membaca dan menulis storan. Tanpanya, aplikasi masih boleh berfungsi dalam foldernya sendiri (mod terhad). Anda boleh mengubahnya bila-bila masa dalam tetapan sistem.';

  @override
  String get grantStorage => 'Beri akses storan';

  @override
  String get limitedMode => 'Teruskan dalam mod terhad';

  @override
  String get openSystemSettings => 'Buka tetapan sistem';

  @override
  String incomingShares(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fail dikongsi ke Nexus — simpan ke folder Muat Turun anda?',
      one: '1 fail dikongsi ke Nexus — simpan ke folder Muat Turun anda?',
    );
    return '$_temp0';
  }

  @override
  String get saveToDownloads => 'Simpan ke Muat Turun';

  @override
  String get sessionSaved => 'Sesi disimpan';
}
