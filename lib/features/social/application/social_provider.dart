import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend_service.dart';

class FriendEntry {
  final String uid;
  final String name;
  final int points;
  final int rank;
  final bool isYou;

  const FriendEntry({
    required this.uid,
    required this.name,
    required this.points,
    required this.rank,
    required this.isYou,
  });

  factory FriendEntry.fromJson(Map<String, dynamic> json) {
    return FriendEntry(
      uid: (json['uid'] ?? json['friendUid'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? json['displayName'] ?? 'Metro Rider').toString(),
      points:
          (json['points'] as num?)?.toInt() ??
          (json['pointsEarned'] as num?)?.toInt() ??
          0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      isYou: json['isYou'] == true,
    );
  }
}

class SocialState {
  final bool isLoading;
  final String? error;
  final String? inviteLink;
  final String? inviteMessage;
  final List<FriendEntry> friends;
  final List<FriendEntry> weekly;
  final List<FriendEntry> cityTop;
  final DateTime? resetsAt;

  const SocialState({
    this.isLoading = false,
    this.error,
    this.inviteLink,
    this.inviteMessage,
    this.friends = const [],
    this.weekly = const [],
    this.cityTop = const [],
    this.resetsAt,
  });

  SocialState copyWith({
    bool? isLoading,
    String? error,
    String? inviteLink,
    String? inviteMessage,
    List<FriendEntry>? friends,
    List<FriendEntry>? weekly,
    List<FriendEntry>? cityTop,
    DateTime? resetsAt,
  }) {
    return SocialState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      inviteLink: inviteLink ?? this.inviteLink,
      inviteMessage: inviteMessage ?? this.inviteMessage,
      friends: friends ?? this.friends,
      weekly: weekly ?? this.weekly,
      cityTop: cityTop ?? this.cityTop,
      resetsAt: resetsAt ?? this.resetsAt,
    );
  }
}

class SocialNotifier extends StateNotifier<SocialState> {
  final BackendService _backend;

  SocialNotifier(this._backend) : super(const SocialState());

  Future<void> load({String? cityId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        _backend.getFriends(),
        _backend.getWeeklyFriendLeaderboard(cityId: cityId),
      ]);
      final friends =
          (results[0]['friends'] as List<dynamic>? ?? [])
              .map(
                (item) => FriendEntry.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
      final board = results[1];
      final weekly =
          (board['friends'] as List<dynamic>? ?? [])
              .map(
                (item) => FriendEntry.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
      final cityTop =
          (board['cityTop'] as List<dynamic>? ?? [])
              .map(
                (item) => FriendEntry.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
      state = state.copyWith(
        isLoading: false,
        friends: friends,
        weekly: weekly,
        cityTop: cityTop,
        resetsAt: DateTime.tryParse((board['resetsAt'] ?? '').toString()),
      );
    } catch (error) {
      debugPrint('SocialNotifier.load error: $error');
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> createInvite() async {
    try {
      final data = await _backend.createSocialInvite();
      state = state.copyWith(
        inviteLink: data['link'] as String?,
        inviteMessage: data['shareMessage'] as String?,
      );
    } catch (error) {
      debugPrint('SocialNotifier.createInvite error: $error');
      state = state.copyWith(error: error.toString());
    }
  }

  Future<bool> addByCode(String code, {String? cityId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _backend.addFriend(token: code);
      await load(cityId: cityId);
      return true;
    } catch (error) {
      debugPrint('SocialNotifier.addByCode error: $error');
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }
}

final socialProvider = StateNotifierProvider<SocialNotifier, SocialState>(
  (ref) => SocialNotifier(BackendService()),
);
