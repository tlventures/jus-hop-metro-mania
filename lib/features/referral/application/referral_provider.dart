import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend_service.dart';

class ReferralState {
  final bool isLoading;
  final String? code;
  final String? link;
  final String? shareMessage;
  final int usedCount;
  final int rewardedCount;
  final String? error;

  const ReferralState({
    this.isLoading = false,
    this.code,
    this.link,
    this.shareMessage,
    this.usedCount = 0,
    this.rewardedCount = 0,
    this.error,
  });

  ReferralState copyWith({
    bool? isLoading,
    String? code,
    String? link,
    String? shareMessage,
    int? usedCount,
    int? rewardedCount,
    String? error,
  }) {
    return ReferralState(
      isLoading: isLoading ?? this.isLoading,
      code: code ?? this.code,
      link: link ?? this.link,
      shareMessage: shareMessage ?? this.shareMessage,
      usedCount: usedCount ?? this.usedCount,
      rewardedCount: rewardedCount ?? this.rewardedCount,
      error: error,
    );
  }
}

class ReferralNotifier extends StateNotifier<ReferralState> {
  final BackendService _backend;

  ReferralNotifier(this._backend) : super(const ReferralState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _backend.generateReferralCode();
      state = state.copyWith(
        isLoading: false,
        code: data['token'] as String?,
        link: data['link'] as String?,
        shareMessage: data['shareMessage'] as String?,
        usedCount: (data['usedCount'] as num?)?.toInt() ?? state.usedCount,
        rewardedCount:
            (data['rewardedCount'] as num?)?.toInt() ?? state.rewardedCount,
      );
    } catch (error) {
      debugPrint('ReferralNotifier.load error: $error');
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<bool> apply(String token) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _backend.applyReferralCode(token);
      await load();
      return true;
    } catch (error) {
      debugPrint('ReferralNotifier.apply error: $error');
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }
}

final referralProvider = StateNotifierProvider<ReferralNotifier, ReferralState>(
  (ref) => ReferralNotifier(BackendService()),
);
