import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_preferences.dart';

const _kPrefsKey = 'user_preferences_v1';
const _kInterestsDoneKey = 'hasCompletedInterests';

class UserPreferencesNotifier extends StateNotifier<UserPreferences> {
  UserPreferencesNotifier() : super(const UserPreferences());

  /// Load saved preferences from local storage.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null) {
      try {
        state = UserPreferences.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {/* corrupt data – start fresh */}
    }
  }

  /// Persist current state and mark the interests flow as done.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(state.toJson()));
    await prefs.setBool(_kInterestsDoneKey, true);
  }

  /// Returns true if the user has already completed the interests flow.
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kInterestsDoneKey) ?? false;
  }

  // ── mutators ──────────────────────────────────────────────────────────────

  void toggleContentType(String key) {
    final updated = Set<String>.from(state.contentTypes);
    if (updated.contains(key)) {
      updated.remove(key);
      // If 'games' deselected, clear game genres too.
      if (key == 'games') {
        state = state.copyWith(contentTypes: updated, gameGenres: {});
        return;
      }
    } else {
      updated.add(key);
    }
    state = state.copyWith(contentTypes: updated);
  }

  void toggleGameGenre(String key) {
    final updated = Set<String>.from(state.gameGenres);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    state = state.copyWith(gameGenres: updated);
  }

  void toggleTopic(String key) {
    final updated = Set<String>.from(state.topics);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    state = state.copyWith(topics: updated);
  }
}

final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesNotifier, UserPreferences>(
  (ref) => UserPreferencesNotifier(),
);
