import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

/// First-run permission onboarding (audit item 22).
///
/// Nothing is requested before the first frame: the user sees WHY Nexus
/// needs storage access, then a single button requests the right
/// permission for their Android version:
///  * Android 11+  → MANAGE_EXTERNAL_STORAGE ("All files access");
///  * Android 10−  → legacy storage prompt;
///  * Android 13+  → READ_MEDIA_* equivalents (photos/videos/audio).
///
/// Declining is fine — the app stays in a graceful limited mode (app
/// directories only) with a button that opens the system settings screen.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate> {
  bool? _granted; // null = still checking
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Request only AFTER the first frame (audit item 22).
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    if (kIsWeb || !Platform.isAndroid) {
      setState(() => _granted = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('perm.onboarded') ?? false;
    final ok = seen ? await _checkGranted() : false;
    if (!mounted) return;
    setState(() => _granted = ok);
  }

  Future<bool> _checkGranted() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // Parse the ART version prefix ("3.22.1 (stable)..." on an ART VM).
        final sdkMatch = RegExp(r'^(\d+)').firstMatch(Platform.version);
        final sdk = int.tryParse(sdkMatch?.group(1) ?? '') ?? 30;
        if (sdk >= 30) {
          await Permission.manageExternalStorage.request();
          await Permission.photos.request();
          await Permission.videos.request();
          await Permission.audio.request();
        } else {
          await Permission.storage.request();
        }
      }
      final ok = await _checkGranted();
      if (!mounted) return;
      setState(() => _granted = ok);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('perm.onboarded', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueLimited() {
    // Limited mode: proceed without storage access; app dirs still work.
    setState(() => _granted = true);
    SharedPreferences.getInstance().then((p) => p.setBool('perm.onboarded', true));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) return widget.child;
    final granted = _granted;
    if (granted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (granted) return widget.child;
    final theme = Theme.of(context);
    // Audit item 45: onboarding copy ships in en / id / ms via ARB files.
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.folder_special_rounded,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    l10n.storageTitle,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.storageBody,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _busy ? null : _request,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(l10n.grantStorage),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : _continueLimited,
                    child: Text(l10n.limitedMode),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: openAppSettings,
                    child: Text(l10n.openSystemSettings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
