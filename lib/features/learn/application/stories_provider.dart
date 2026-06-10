import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/station_story.dart';
import '../../../services/backend_service.dart';

class StoriesNotifier extends StateNotifier<List<StationStory>> {
  final BackendService _backendService;

  StoriesNotifier(this._backendService) : super([]);

  Future<void> fetchStories() async {
    try {
      final data = await _backendService.getStories();
      final stories = (data['stories'] as List<dynamic>? ?? [])
          .map((s) => StationStory.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
      state = stories;
    } catch (e) {
      debugPrint('StoriesNotifier.fetchStories error: $e');
      state = [];
    }
  }

  Future<bool> completeStory(String storyId) async {
    try {
      await _backendService.completeStory(storyId);
    } catch (e) {
      debugPrint('StoriesNotifier.completeStory error: $e');
      return false;
    }

    state = state.map((story) {
      if (story.id == storyId) {
        return story.copyWith(isCompleted: true);
      }
      return story;
    }).toList();
    return true;
  }

  int get completedCount => state.where((s) => s.isCompleted).length;
  int get totalPoints => state.fold(0, (sum, s) => sum + (s.isCompleted ? s.points : 0));
}

final backendServiceStoriesProvider = Provider((ref) => BackendService());

final storiesProvider = StateNotifierProvider<StoriesNotifier, List<StationStory>>((ref) {
  final backendService = ref.watch(backendServiceStoriesProvider);
  return StoriesNotifier(backendService);
});

final completedStoriesProvider = Provider<int>((ref) {
  final stories = ref.watch(storiesProvider);
  return stories.where((s) => s.isCompleted).length;
});

final storyPointsProvider = Provider<int>((ref) {
  final stories = ref.watch(storiesProvider);
  return stories.fold(0, (sum, s) => sum + (s.isCompleted ? s.points : 0));
});
