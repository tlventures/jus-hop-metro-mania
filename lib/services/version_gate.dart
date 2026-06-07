import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Force-update gate.
///
/// The backend includes an `appConfig` block in the GET /api/home response, e.g.
/// ```json
/// "appConfig": {
///   "minSupportedBuild": 24,        // hard floor — below this we block
///   "latestBuild": 30,              // optional — for a soft "update available" nudge
///   "storeUrl": "https://play.google.com/store/apps/details?id=com.tlventures.metrosafar"
/// }
/// ```
/// If the running build number is below `minSupportedBuild`, we show a blocking,
/// non-dismissible dialog directing the user to the store. This lets us retire
/// clients that depend on a removed/breaking API without bricking them silently.
///
/// The gate fails OPEN: if `appConfig` is missing or malformed, or the build
/// number can't be read, the app continues normally. A backend hiccup must
/// never lock everyone out.
class VersionGate {
  VersionGate._();

  static bool _shownThisSession = false;

  /// Default store URL used when the backend doesn't supply one.
  static const String _defaultStoreUrl =
      'https://play.google.com/store/apps/details?id=com.tlventures.metrosafar';

  /// Evaluate [appConfig] and, if the current build is unsupported, show the
  /// blocking dialog. Safe to call repeatedly (e.g. on every home fetch); the
  /// dialog is only ever shown once per app session.
  static Future<void> enforce(
    BuildContext context,
    Map<String, dynamic> appConfig,
  ) async {
    if (_shownThisSession) return;

    final minBuild = _asInt(appConfig['minSupportedBuild']);
    if (minBuild == null) return; // nothing to enforce

    int currentBuild;
    try {
      final info = await PackageInfo.fromPlatform();
      currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      debugPrint('VersionGate: could not read build number: $e');
      return; // fail open
    }

    if (currentBuild >= minBuild) return; // supported

    if (!context.mounted) return;
    _shownThisSession = true;

    final storeUrl = appConfig['storeUrl']?.toString() ?? _defaultStoreUrl;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false, // block the system back button
        child: AlertDialog(
          title: const Text('Update required'),
          content: const Text(
            'This version of MetroSafar is no longer supported. '
            'Please update to the latest version to continue.',
          ),
          actions: [
            FilledButton(
              onPressed: () => _openStore(storeUrl),
              child: const Text('Update now'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openStore(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('VersionGate: failed to open store URL "$url": $e');
    }
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Test seam — reset the once-per-session guard.
  @visibleForTesting
  static void resetForTest() => _shownThisSession = false;

  /// Exposed for callers that want platform context (unused placeholder kept
  /// for symmetry with a future iOS App Store URL split).
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
}
