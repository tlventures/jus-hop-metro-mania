import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalizationService {
  static const String _languageKey = 'app_language';
  static const List<String> supportedLanguageCodes = [
    'en', 'hi', 'ta', 'te', 'kn', 'mr',
    'bn', // Bengali   — Kolkata Metro (Phase B)
    'ml', // Malayalam — Kochi Metro   (Phase B)
    'gu', // Gujarati  — Ahmedabad     (Phase B)
    'ur', // Urdu      — Hyderabad / Delhi
    'pa', // Punjabi   — Delhi NCR
  ];

  static const Map<String, String> languageNames = {
    'en': 'English',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'kn': 'ಕನ್ನಡ',
    'mr': 'मराठी',
    'bn': 'বাংলা',
    'ml': 'മലയാളം',
    'gu': 'ગુજરાતી',
    'ur': 'اردو',
    'pa': 'ਪੰਜਾਬੀ',
  };

  /// Returns the primary locales for the given cityId so the locale picker
  /// can pre-select the right languages during onboarding.
  static List<String> primaryLocalesForCity(String cityId) {
    return switch (cityId) {
      'hyd' => ['te', 'ur', 'hi', 'en'],
      'del' => ['hi', 'pa', 'ur', 'en'],
      'blr' => ['kn', 'en', 'hi'],
      'che' => ['ta', 'en', 'hi'],
      'mum' => ['mr', 'hi', 'en'],
      'kol' => ['bn', 'en', 'hi'],
      'koc' => ['ml', 'en'],
      _     => ['en'],
    };
  }

  // keep the existing map around for older reference; the full one is above
  // ignore: unused_field
  static const Map<String, String> _legacyLanguageNames = {
    'en': 'English',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'kn': 'ಕನ್ನಡ',
    'mr': 'मराठी',
  };

  static Future<String> getSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? _getDeviceLanguage();
  }

  static Future<void> setLanguage(String languageCode) async {
    if (supportedLanguageCodes.contains(languageCode)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    }
  }

  static String _getDeviceLanguage() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final deviceLanguageCode = deviceLocale.languageCode;

    if (supportedLanguageCodes.contains(deviceLanguageCode)) {
      return deviceLanguageCode;
    }
    return 'en';
  }

  static Locale localeFromCode(String languageCode) {
    return Locale(languageCode);
  }
}

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en'));

  Future<void> initialize() async {
    final savedLanguage = await LocalizationService.getSavedLanguage();
    state = LocalizationService.localeFromCode(savedLanguage);
  }

  Future<void> setLocale(String languageCode) async {
    await LocalizationService.setLanguage(languageCode);
    state = LocalizationService.localeFromCode(languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
