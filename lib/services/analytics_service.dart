import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  static const String _consentKey = 'analytics_consent';
  static const String _marketingConsentKey = 'marketing_consent';

  static Future<bool> isAnalyticsConsented() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<bool> isMarketingConsented() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_marketingConsentKey) ?? false;
  }

  static Future<void> setAnalyticsConsent(bool consent, {bool marketing = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, consent);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(consent);
    if (consent) {
      await prefs.setBool(_marketingConsentKey, marketing);
    }
  }

  // Log analytics events only if user has consented.
  static Future<void> logEvent(String eventName, {Map<String, dynamic>? parameters}) async {
    final consented = await isAnalyticsConsented();
    if (!consented) return;

    await FirebaseAnalytics.instance.logEvent(
      name: eventName,
      parameters: _firebaseParameters(parameters),
    );
    debugPrint('Analytics Event: $eventName ${parameters ?? ''}');
  }

  static Map<String, Object>? _firebaseParameters(
    Map<String, dynamic>? parameters,
  ) {
    if (parameters == null || parameters.isEmpty) return null;
    return parameters.map((key, value) {
      final safeValue = value is num || value is bool || value is String
          ? value as Object
          : value.toString();
      return MapEntry(key, safeValue);
    });
  }

  static Future<void> setUserId(String? userId) async {
    final consented = await isAnalyticsConsented();
    if (!consented) return;
    await FirebaseAnalytics.instance.setUserId(id: userId);
  }

  // Convenience methods for common events
  static Future<void> logGameCompleted(String gameId, int score) async {
    await logEvent('game_completed', parameters: {
      'game_id': gameId,
      'score': score,
    });
  }

  static Future<void> logArticleRead(String articleId, int readTimeSeconds) async {
    await logEvent('article_read', parameters: {
      'article_id': articleId,
      'read_time_seconds': readTimeSeconds,
    });
  }

  static Future<void> logSurveySubmitted(String surveyId) async {
    await logEvent('survey_submitted', parameters: {
      'survey_id': surveyId,
    });
  }

  static Future<void> logQuestCompleted(String questId) async {
    await logEvent('quest_completed', parameters: {
      'quest_id': questId,
    });
  }

  static Future<void> logStreakClaimed(int streakDay) async {
    await logEvent('streak_claimed', parameters: {
      'streak_day': streakDay,
    });
  }

  static Future<void> logOnboardingCompleted() async {
    await logEvent('onboarding_completed');
  }

  static Future<void> logPermissionGranted(String permissionType) async {
    await logEvent('permission_granted', parameters: {
      'permission_type': permissionType,
    });
  }

  static Future<void> logPermissionDenied(String permissionType) async {
    await logEvent('permission_denied', parameters: {
      'permission_type': permissionType,
    });
  }

  static Future<void> logLanguageChanged(String languageCode) async {
    await logEvent('language_changed', parameters: {
      'language_code': languageCode,
    });
  }

  static Future<void> logStoryCompleted(String storyId) async {
    await logEvent('story_completed', parameters: {
      'story_id': storyId,
    });
  }
}
