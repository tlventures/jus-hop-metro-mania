import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Signs the user out and returns to /login. Optionally confirms first.
///
/// Intentionally does NOT clear the onboarding flag — logging out should not
/// replay the full first-run onboarding flow on next sign-in.
Future<void> signOutAndReturnToLogin(
  BuildContext context, {
  bool confirm = true,
}) async {
  if (confirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await FirebaseAuth.instance.signOut();
  if (context.mounted) context.go('/login');
}
