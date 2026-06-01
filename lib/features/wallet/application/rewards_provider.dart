import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backend_service.dart';

class Reward {
  final String id;
  final String title;
  final String discount;
  final String description;
  final int points;
  final String category;
  final bool redeemed;

  const Reward({
    required this.id,
    required this.title,
    required this.discount,
    required this.description,
    required this.points,
    required this.category,
    this.redeemed = false,
  });

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        discount: json['discount'] as String? ?? '',
        description: json['description'] as String? ?? '',
        points: (json['points'] as num?)?.toInt() ?? 0,
        category: json['category'] as String? ?? 'Other',
        redeemed: json['redeemed'] as bool? ?? false,
      );
}

class RewardsState {
  final List<Reward> rewards;
  final bool isLoading;

  const RewardsState({this.rewards = const [], this.isLoading = true});

  List<Reward> byCategory(String category) =>
      rewards.where((r) => r.category == category).toList();

  List<String> get categories {
    final seen = <String>{};
    return rewards.map((r) => r.category).where(seen.add).toList();
  }

  RewardsState copyWith({List<Reward>? rewards, bool? isLoading}) =>
      RewardsState(
        rewards: rewards ?? this.rewards,
        isLoading: isLoading ?? this.isLoading,
      );
}

class RewardsNotifier extends StateNotifier<RewardsState> {
  final BackendService _backendService;

  RewardsNotifier(this._backendService) : super(const RewardsState());

  Future<void> fetchRewards() async {
    try {
      final data = await _backendService.getRewardsData();
      final raw = data['rewards'] as List<dynamic>? ?? [];
      final rewards =
          raw.map((r) => Reward.fromJson(r as Map<String, dynamic>)).toList();
      state = state.copyWith(rewards: rewards, isLoading: false);
    } catch (e) {
      debugPrint('RewardsNotifier.fetchRewards error: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final rewardsProvider =
    StateNotifierProvider<RewardsNotifier, RewardsState>((ref) {
  return RewardsNotifier(BackendService());
});
