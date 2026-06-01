import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/services/backend_service.dart';

class StampsState {
  final bool isLoading;
  final List<Map<String, dynamic>> stamps;
  final List<Map<String, dynamic>> collections;
  final String? message;

  const StampsState({
    this.isLoading = true,
    this.stamps = const [],
    this.collections = const [],
    this.message,
  });

  StampsState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? stamps,
    List<Map<String, dynamic>>? collections,
    String? message,
  }) {
    return StampsState(
      isLoading: isLoading ?? this.isLoading,
      stamps: stamps ?? this.stamps,
      collections: collections ?? this.collections,
      message: message,
    );
  }
}

class StampsNotifier extends StateNotifier<StampsState> {
  final BackendService _backendService;

  StampsNotifier(this._backendService) : super(const StampsState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final mine = await _backendService.getMyStamps();
      final collections = await _backendService.getCollections();
      state = state.copyWith(
        isLoading: false,
        stamps:
            (mine['stamps'] as List<dynamic>? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
        collections:
            (collections['collections'] as List<dynamic>? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
      );
    } catch (error) {
      debugPrint('StampsNotifier.load error: $error');
      state = state.copyWith(
        isLoading: false,
        message: 'Stamp catalog is available offline after the first sync.',
      );
    }
  }

  Future<void> claim(String stationId) async {
    try {
      final result = await _backendService.claimStamp(stationId);
      final stamp = Map<String, dynamic>.from(result['stamp'] as Map? ?? {});
      state = state.copyWith(
        message:
            result['queued'] == true
                ? 'Stamp claim saved offline.'
                : 'Claimed ${stamp['name'] ?? 'station stamp'} for ${result['pointsAwarded'] ?? 0} points.',
      );
      await load();
    } catch (error) {
      debugPrint('StampsNotifier.claim error: $error');
      state = state.copyWith(message: 'Could not claim this stamp yet.');
    }
  }
}

final stampsProvider = StateNotifierProvider<StampsNotifier, StampsState>((
  ref,
) {
  return StampsNotifier(BackendService());
});
