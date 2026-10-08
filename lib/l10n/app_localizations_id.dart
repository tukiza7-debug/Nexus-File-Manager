// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appName => 'Nexus File Manager';

  @override
  String get tagline => 'Hebat. Presisi. Indah.';

  @override
  String get commandPalette => 'Palet perintah';

  @override
  String get ghostMode => 'Mode hantu';

  @override
  String get zenMode => 'Mode Zen';

  @override
  String get exitZen => 'Keluar Zen';

  @override
  String get menu => 'Menu';

  @override
  String items(int count) {
    return '$count butir';
  }

  @override
  String selectedCount(int count) {
    return '$count dipilih';
  }

  @override
  String inStack(int count) {
    return '$count di tumpukan';
  }

  @override
  String get recordingMacro => 'Merekam makro';

  @override
  String get nothingToUndo => 'Tidak ada yang bisa dibatalkan';

  @override
  String get nothingToRedo => 'Tidak ada yang bisa diulang';

  @override
  String get undone => 'Dibatalkan';

  @override
  String get redone => 'Diulang';

  @override
  String get undo => 'Batalkan';

  @override
  String get redo => 'Ulangi';

  @override
  String get cancel => 'Batal';

  @override
  String get confirm => 'Konfirmasi';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Simpan';

  @override
  String get discard => 'Buang';

  @override
  String get retry => 'Coba lagi';

  @override
  String get clearFilter => 'Bersihkan filter';

  @override
  String copiedCount(int count) {
    return '$count butir disalin';
  }

  @override
  String movedCount(int count) {
    return '$count butir dipindah';
  }

  @override
  String pastedCount(int count) {
    return '$count butir ditempel';
  }

  @override
  String deletedCount(int count) {
    return '$count butir dihapus';
  }

  @override
  String operationFailed(String error) {
    return 'Operasi gagal: $error';
  }

  @override
  String get places => 'Lokasi';

  @override
  String get aliases => 'Alias';

  @override
  String get stacks => 'Tumpukan Folder';

  @override
  String get secureFreeze => 'Beku Aman';

  @override
  String get clipboardStack => 'Tumpukan Papan Klip';

  @override
  String get name => 'Nama';

  @override
  String get size => 'Ukuran';

  @override
  String get modified => 'Diubah';

  @override
  String get kind => 'Jenis';

  @override
  String get storageTitle => 'Nexus butuh akses penyimpanan';

  @override
  String get storageBody =>
      'Untuk menjelajah, merapikan, dan mengelola berkas Anda, Nexus butuh izin membaca dan menulis penyimpanan. Tanpa izin itu, aplikasi tetap bisa bekerja di dalam foldernya sendiri (mode terbatas). Anda dapat mengubahnya kapan saja di pengaturan sistem.';

  @override
  String get grantStorage => 'Beri akses penyimpanan';

  @override
  String get limitedMode => 'Lanjut dalam mode terbatas';

  @override
  String get openSystemSettings => 'Buka pengaturan sistem';

  @override
  String incomingShares(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count berkas dibagikan ke Nexus — simpan ke folder Unduhan Anda?',
      one: '1 berkas dibagikan ke Nexus — simpan ke folder Unduhan Anda?',
    );
    return '$_temp0';
  }

  @override
  String get saveToDownloads => 'Simpan ke Unduhan';

  @override
  String get sessionSaved => 'Sesi tersimpan';
}
