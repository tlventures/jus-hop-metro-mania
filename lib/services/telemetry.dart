import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin, always-safe wrapper for reporting *non-fatal* errors to Crashlytics.
///
/// Use at `catch` sites in service/data paths that previously swallowed errors
/// silently (e.g. cache-parse failures, best-effort quest completions). These
/// failures are intentionally non-blocking for the user, but invisible failures
/// are impossible to debug in production — a non-fatal report keeps the UX
/// unchanged while surfacing the issue in the Crashlytics console.
///
/// Every method is defensive: reporting must never throw and never mask the
/// original control flow.
class Telemetry {
  Telemetry._();

  /// Report a caught, non-blocking error with a human-readable [reason] tag.
  static void recordNonFatal(
    Object error,
    StackTrace? stackTrace, {
    required String reason,
  }) {
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (e) {
      // Crashlytics not initialised (e.g. tests) — degrade to a debug log.
      debugPrint('Telemetry.recordNonFatal[$reason]: $error');
    }
  }
}
