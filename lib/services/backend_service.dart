import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metrosafar/config/api_config.dart';
import 'package:metrosafar/core/commute/ride_verification.dart';
import 'package:metrosafar/models/metro_station.dart';
import 'package:metrosafar/services/sync/outbox.dart';

class BackendAuthException implements Exception {
  final String message;
  const BackendAuthException([this.message = 'Authentication required']);

  @override
  String toString() => message;
}

class BackendService {
  final http.Client _client;

  BackendService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  String _newRequestId() {
    final random = Random.secure().nextInt(1 << 32);
    return 'req_${DateTime.now().microsecondsSinceEpoch}_$random';
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('BackendService: could not get Firebase ID token: $e');
    }
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
  }

  Future<Map<String, dynamic>> getHomeData() {
    return _getMap('/api/home', cacheKey: 'cache_home');
  }

  Future<Map<String, dynamic>> getProfile() {
    return _getMap('/api/profile', cacheKey: 'cache_profile');
  }

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String email,
    required String phone,
    required bool notificationsEnabled,
    bool? digestNotificationsEnabled,
  }) {
    return _sendJson(
      'PATCH',
      '/api/profile',
      cacheKey: 'cache_profile',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'notificationsEnabled': notificationsEnabled,
        if (digestNotificationsEnabled != null)
          'digestNotificationsEnabled': digestNotificationsEnabled,
      },
    );
  }

  /// Fetch stations.
  /// [cityId] — use the v2 city-scoped endpoint when provided (preferred).
  /// Falls back to the legacy /api/stations endpoint (Hyderabad) otherwise.
  Future<List<MetroStation>> getStations({String? cityId}) async {
    final path =
        cityId != null ? '/api/v2/cities/$cityId/stations' : '/api/stations';
    final cacheKey =
        cityId != null ? 'cache_stations_$cityId' : 'cache_stations';
    final data = await _getMap(path, cacheKey: cacheKey);
    final stationsJson = data['stations'] as List<dynamic>? ?? [];
    return stationsJson
        .map((s) => MetroStation.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> getRewardsData() {
    return _getMap('/api/rewards', cacheKey: 'cache_rewards');
  }

  Future<Map<String, dynamic>> watchVideo(String videoId) {
    return _sendJson(
      'POST',
      '/api/rewards/watch/$videoId',
      cacheKey: 'cache_rewards',
    );
  }

  Future<Map<String, dynamic>> redeemReward(String rewardId) {
    return _sendJson(
      'POST',
      '/api/rewards/redeem/$rewardId',
      cacheKey: 'cache_rewards',
    );
  }

  Future<Map<String, dynamic>> getGamesData() {
    return _getMap('/api/games', cacheKey: 'cache_games');
  }

  Future<Map<String, dynamic>> toggleLandmarkVisited(String landmarkId) {
    return _sendJson(
      'PATCH',
      '/api/games/explorer/$landmarkId',
      cacheKey: 'cache_games',
    );
  }

  Future<Map<String, dynamic>> getSupportData() {
    return _getMap('/api/support', cacheKey: 'cache_support');
  }

  Future<Map<String, dynamic>> getLegalDocument(String type) {
    return _getMap('/api/legal/$type', cacheKey: 'cache_legal_$type');
  }

  Future<Map<String, dynamic>> completeGame({
    required String gameId,
    required int score,
    required int timeSpent,
    String? cityId,
    int? questionsAnswered,
    int? streak,
  }) {
    return _sendJson(
      'POST',
      '/api/games/$gameId/complete',
      cacheKey: 'cache_games',
      body: {
        'score': score,
        'timeSpent': timeSpent,
        if (cityId != null) 'cityId': cityId,
        if (questionsAnswered != null) 'questionsAnswered': questionsAnswered,
        if (streak != null) 'streak': streak,
      },
    );
  }

  Future<Map<String, dynamic>> getTriviaRank({String? cityId}) {
    final query =
        cityId == null ? '' : '?cityId=${Uri.encodeQueryComponent(cityId)}';
    return _getMap(
      '/api/games/trivia/rank$query',
      cacheKey: 'cache_trivia_rank',
    );
  }

  Future<Map<String, dynamic>> submitTriviaScore({
    required int score,
    String? cityId,
    int? questionsAnswered,
    int? streak,
    int? timeSpent,
  }) {
    return _sendJson(
      'POST',
      '/api/games/trivia/score',
      cacheKey: 'cache_trivia_rank',
      body: {
        'score': score,
        if (cityId != null) 'cityId': cityId,
        if (questionsAnswered != null) 'questionsAnswered': questionsAnswered,
        if (streak != null) 'streak': streak,
        if (timeSpent != null) 'timeSpent': timeSpent,
      },
    );
  }

  Future<Map<String, dynamic>> getTriviaLeaderboard({
    String? cityId,
    int limit = 10,
  }) {
    final params = <String, String>{'limit': '$limit'};
    if (cityId != null) params['cityId'] = cityId;
    return _getMap(
      '/api/games/trivia/leaderboard?${Uri(queryParameters: params).query}',
      cacheKey: 'cache_trivia_leaderboard',
    );
  }

  Future<Map<String, dynamic>> claimStreakBonus() {
    return _sendJson('POST', '/api/streak/claim', cacheKey: 'cache_home');
  }

  Future<Map<String, dynamic>> completeQuest(String questId) {
    return _sendJson(
      'POST',
      '/api/quests/$questId/complete',
      cacheKey: 'cache_home',
    );
  }

  Future<Map<String, dynamic>> getLeaderboard({String period = 'week'}) {
    return _getMap(
      '/api/games/leaderboard?period=$period',
      cacheKey: 'cache_leaderboard',
    );
  }

  Future<Map<String, dynamic>> scratchCard(String cardId) {
    return _sendJson(
      'POST',
      '/api/scratch-cards/$cardId/scratch',
      cacheKey: 'cache_games',
    );
  }

  Future<Map<String, dynamic>> getArticles() {
    return _getMap('/api/articles', cacheKey: 'cache_articles');
  }

  Future<Map<String, dynamic>> markArticleRead(String articleId) {
    return _sendJson(
      'POST',
      '/api/articles/$articleId/read',
      cacheKey: 'cache_articles',
    );
  }

  Future<Map<String, dynamic>> getSurveys() {
    return _getMap('/api/surveys', cacheKey: 'cache_surveys');
  }

  Future<Map<String, dynamic>> submitSurvey(
    String surveyId,
    String selectedOption,
  ) {
    return _sendJson(
      'POST',
      '/api/surveys/$surveyId/submit',
      cacheKey: 'cache_surveys',
      body: {'selectedOption': selectedOption},
    );
  }

  Future<Map<String, dynamic>> getStories() {
    return _getMap('/api/stories', cacheKey: 'cache_stories');
  }

  Future<Map<String, dynamic>> completeStory(String storyId) {
    return _sendJson(
      'POST',
      '/api/stories/$storyId/complete',
      cacheKey: 'cache_stories',
    );
  }

  Future<Map<String, dynamic>> getFeatureFlags() {
    return _getMap('/api/feature-flags', cacheKey: 'cache_feature_flags');
  }

  Future<Map<String, dynamic>> getRealtimeToken() {
    return _getMap('/api/realtime/token', cacheKey: 'cache_realtime_token');
  }

  Future<Map<String, dynamic>> registerDeviceToken({
    required String token,
    required String platform,
  }) {
    return _sendJson(
      'POST',
      '/api/devices/token',
      cacheKey: 'cache_device_token',
      body: {'token': token, 'platform': platform},
    );
  }

  Future<Map<String, dynamic>> startTrip({
    required String startStationId,
    String source = 'manual',
  }) {
    return _sendJson(
      'POST',
      '/api/trips/start',
      cacheKey: 'cache_active_trip',
      queueOffline: true,
      body: {
        'startStationId': startStationId,
        'source': source,
        'detectedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> getActiveTrip() {
    return _getMap('/api/trips/active', cacheKey: 'cache_active_trip');
  }

  Future<Map<String, dynamic>> endTrip({
    required String tripId,
    required String endStationId,
  }) {
    return _sendJson(
      'POST',
      '/api/trips/$tripId/end',
      cacheKey: 'cache_active_trip',
      queueOffline: true,
      body: {
        'endStationId': endStationId,
        'endedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> getTripHistory({int limit = 20}) {
    return _getMap(
      '/api/trips/history?limit=$limit',
      cacheKey: 'cache_trip_history',
    );
  }

  Future<Map<String, dynamic>> getEtas(List<String> stationIds) {
    final query = Uri.encodeQueryComponent(stationIds.join(','));
    return _getMap(
      '/api/intel/etas?stations=$query',
      cacheKey: 'cache_intel_etas',
    );
  }

  Future<Map<String, dynamic>> getDisruptions({List<String> lines = const []}) {
    final query = Uri.encodeQueryComponent(lines.join(','));
    return _getMap(
      '/api/intel/disruptions?lines=$query',
      cacheKey: 'cache_disruptions',
    );
  }

  Future<Map<String, dynamic>> getRoute({
    required String fromStationId,
    required String toStationId,
  }) {
    final from = Uri.encodeQueryComponent(fromStationId);
    final to = Uri.encodeQueryComponent(toStationId);
    return _getMap(
      '/api/intel/route?from=$from&to=$to',
      cacheKey: 'cache_route_${from}_$to',
    );
  }

  Future<Map<String, dynamic>> submitCrowdReport({
    required String trainId,
    required String coachId,
    required int crowdLevel,
  }) {
    return _sendJson(
      'POST',
      '/api/intel/crowd-report',
      cacheKey: 'cache_crowding_$trainId',
      queueOffline: true,
      body: {'trainId': trainId, 'coachId': coachId, 'crowdLevel': crowdLevel},
    );
  }

  Future<Map<String, dynamic>> getStampCatalog() {
    return _getMap('/api/stamps/catalog', cacheKey: 'cache_stamp_catalog');
  }

  Future<Map<String, dynamic>> getMyStamps() {
    return _getMap('/api/stamps/mine', cacheKey: 'cache_my_stamps');
  }

  Future<Map<String, dynamic>> claimStamp(String stationId) {
    return _sendJson(
      'POST',
      '/api/stamps/claim',
      cacheKey: 'cache_my_stamps',
      queueOffline: true,
      body: {'stationId': stationId},
    );
  }

  Future<Map<String, dynamic>> getCollections() {
    return _getMap('/api/collections', cacheKey: 'cache_collections');
  }

  Future<Map<String, dynamic>> getEpisodes() {
    return _getMap('/api/episodes', cacheKey: 'cache_episodes');
  }

  Future<Map<String, dynamic>> getTodayEpisode() {
    return _getMap('/api/episodes/today', cacheKey: 'cache_today_episode');
  }

  Future<Map<String, dynamic>> getEpisode(String episodeId) {
    return _getMap(
      '/api/episodes/$episodeId',
      cacheKey: 'cache_episode_$episodeId',
    );
  }

  Future<Map<String, dynamic>> getEpisodePosition(String episodeId) {
    return _getMap(
      '/api/episodes/$episodeId/position',
      cacheKey: 'cache_episode_position_$episodeId',
    );
  }

  Future<Map<String, dynamic>> updateEpisodePosition({
    required String episodeId,
    required int positionSeconds,
    required bool completed,
  }) {
    return _sendJson(
      'POST',
      '/api/episodes/$episodeId/position',
      cacheKey: 'cache_episode_position_$episodeId',
      queueOffline: true,
      body: {'positionSeconds': positionSeconds, 'completed': completed},
    );
  }

  Future<Map<String, dynamic>> getEventsSchedule() {
    return _getMap('/api/events/schedule', cacheKey: 'cache_events_schedule');
  }

  Future<Map<String, dynamic>> getEvent(String eventId) {
    return _getMap('/api/events/$eventId', cacheKey: 'cache_event_$eventId');
  }

  Future<Map<String, dynamic>> joinEvent(String eventId) {
    return _sendJson(
      'POST',
      '/api/events/$eventId/join',
      cacheKey: 'cache_event_$eventId',
      body: {},
    );
  }

  Future<Map<String, dynamic>> submitEventAnswer({
    required String eventId,
    required String questionId,
    required int answer,
  }) {
    return _sendJson(
      'POST',
      '/api/events/$eventId/submit',
      cacheKey: 'cache_event_result_$eventId',
      queueOffline: true,
      body: {
        'questionId': questionId,
        'answer': answer,
        'clientTimeMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<Map<String, dynamic>> getEventLeaderboard(String eventId) {
    return _getMap(
      '/api/events/$eventId/leaderboard',
      cacheKey: 'cache_event_leaderboard_$eventId',
    );
  }

  Future<Map<String, dynamic>> getQuestsToday() {
    return _getMap('/api/quests/today', cacheKey: 'cache_quests_today');
  }

  Future<Map<String, dynamic>> logActivityEvent({
    required String type,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) {
    return _sendJson(
      'POST',
      '/api/activity-events',
      cacheKey: 'cache_activity_event',
      body: {
        'type': type,
        if (entityId != null) 'entityId': entityId,
        if (metadata != null) 'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> getWalletTransactions() {
    return _getMap(
      '/api/wallet/transactions',
      cacheKey: 'cache_wallet_transactions',
    );
  }

  Future<Map<String, dynamic>> generateReferralCode() {
    return _sendJson(
      'POST',
      '/api/referral/generate',
      cacheKey: 'cache_referral_code',
    );
  }

  Future<Map<String, dynamic>> applyReferralCode(String token) {
    return _sendJson(
      'POST',
      '/api/referral/apply',
      cacheKey: 'cache_referral_status',
      body: {'token': token},
    );
  }

  Future<Map<String, dynamic>> getReferralStatus() {
    return _getMap('/api/referral/status', cacheKey: 'cache_referral_status');
  }

  Future<Map<String, dynamic>> createSocialInvite() {
    return _sendJson(
      'POST',
      '/api/social/invite',
      cacheKey: 'cache_social_invite',
    );
  }

  Future<Map<String, dynamic>> getFriends() {
    return _getMap('/api/social/friends', cacheKey: 'cache_friends');
  }

  Future<Map<String, dynamic>> addFriend({String? friendUid, String? token}) {
    return _sendJson(
      'POST',
      '/api/social/friends/add',
      cacheKey: 'cache_friends',
      body: {
        if (friendUid != null) 'friendUid': friendUid,
        if (token != null) 'token': token,
      },
    );
  }

  Future<Map<String, dynamic>> getWeeklyFriendLeaderboard({String? cityId}) {
    final query =
        cityId == null ? '' : '?cityId=${Uri.encodeQueryComponent(cityId)}';
    return _getMap(
      '/api/social/leaderboard/weekly$query',
      cacheKey: 'cache_weekly_friend_leaderboard',
    );
  }

  Future<Map<String, dynamic>> getWeeklyDigestPreview({String? cityId}) {
    final query =
        cityId == null ? '' : '?cityId=${Uri.encodeQueryComponent(cityId)}';
    return _getMap(
      '/api/weekly-digest/preview$query',
      cacheKey: 'cache_weekly_digest_preview',
    );
  }

  Future<Map<String, dynamic>> getActiveCommuteSession() {
    return _getMap(
      '/api/trip/commute-session/active',
      cacheKey: 'cache_commute_session',
    );
  }

  Future<Map<String, dynamic>> submitCommuteSignal({
    required double confidenceScore,
    double? vibrationScore,
    double? speedKmh,
    String? stationId,
    String? cityId,
    String? phase,
    RideVerification? ticketVerification,
  }) {
    return _sendJson(
      'POST',
      '/api/trip/commute-session',
      cacheKey: 'cache_commute_session',
      queueOffline: true,
      body: {
        'confidenceScore': confidenceScore,
        if (vibrationScore != null) 'vibrationScore': vibrationScore,
        if (speedKmh != null) 'speedKmh': speedKmh,
        if (stationId != null) 'stationId': stationId,
        if (cityId != null) 'cityId': cityId,
        if (phase != null) 'phase': phase,
        if (ticketVerification != null)
          'ticketVerification': ticketVerification.toJson(),
        'detectedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> endCommuteSession({
    required String sessionId,
    String? endStationId,
  }) {
    return _sendJson(
      'POST',
      '/api/trip/commute-session/$sessionId/end',
      cacheKey: 'cache_commute_session',
      queueOffline: true,
      body: {
        if (endStationId != null) 'endStationId': endStationId,
        'endedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> sendTripHeartbeat(String tripId) {
    return _sendJson(
      'POST',
      '/api/trips/$tripId/heartbeat',
      cacheKey: 'cache_trip_heartbeat',
      body: {'clientTimeMs': DateTime.now().millisecondsSinceEpoch},
    );
  }

  Future<int> outboxCount() => Outbox().count();

  Future<void> flushOutbox() async {
    final outbox = Outbox();
    final pending = await outbox.all();
    final failures = <PendingMutation>[];

    for (final mutation in pending) {
      try {
        final request = http.Request(mutation.method, _uri(mutation.path));
        request.headers.addAll(mutation.headers);
        if (mutation.body != null) {
          request.body = jsonEncode(mutation.body);
        }
        final streamed = await _client
            .send(request)
            .timeout(const Duration(seconds: 12));
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          failures.add(
            mutation.copyWith(
              retryCount: mutation.retryCount + 1,
              lastError: response.body,
            ),
          );
        }
      } catch (error) {
        failures.add(
          mutation.copyWith(
            retryCount: mutation.retryCount + 1,
            lastError: error.toString(),
          ),
        );
      }
    }

    await outbox.replaceAll(failures);
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    required String cacheKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final headers = await _headers();

    try {
      final response = await _client
          .get(_uri(path), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await prefs.setString(cacheKey, response.body);
        return Map<String, dynamic>.from(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      if (response.statusCode == 401) {
        throw const BackendAuthException();
      }
      throw Exception('Request failed with ${response.statusCode}');
    } on BackendAuthException {
      rethrow;
    } catch (_) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        return Map<String, dynamic>.from(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    required String cacheKey,
    Map<String, dynamic>? body,
    bool queueOffline = false,
  }) async {
    final idempotencyKey = _newRequestId();
    final headers = await _headers(idempotencyKey: idempotencyKey);
    final request = http.Request(method, _uri(path));
    request.headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        throw const BackendAuthException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          response.body.isNotEmpty ? response.body : 'Request failed',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      if (response.body.isNotEmpty) {
        await prefs.setString(cacheKey, response.body);
        return Map<String, dynamic>.from(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      return {};
    } catch (error) {
      if (queueOffline && error is! BackendAuthException) {
        await Outbox().enqueue(
          PendingMutation(
            id: idempotencyKey,
            method: method,
            path: path,
            headers: headers,
            body: body,
            createdAt: DateTime.now(),
            lastError: error.toString(),
          ),
        );
        return {
          'queued': true,
          'idempotencyKey': idempotencyKey,
          'message': 'Saved offline and will sync when the network returns.',
        };
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> joinWaitlist() {
    return _sendJson('POST', '/api/waitlist', cacheKey: 'cache_waitlist');
  }

  Future<void> deleteAccount() async {
    await _sendJson('DELETE', '/api/account', cacheKey: 'delete_account');
  }
}
