import 'package:freezed_annotation/freezed_annotation.dart';

part 'station_story.freezed.dart';
part 'station_story.g.dart';

@freezed
class StationStory with _$StationStory {
  const factory StationStory({
    required String id,
    required String stationName,
    required String description,
    required String imageUrl,
    required List<StoryFrame> frames,
    // Display-only; server awards a fixed `story_completed` reward (25). Default
    // so stories without an explicit points field still parse (was `required`,
    // which threw on the real payload and left the screen blank).
    @Default(25) int points,
    @Default(false) bool isCompleted,
  }) = _StationStory;

  factory StationStory.fromJson(Map<String, dynamic> json) => _$StationStoryFromJson(json);
}

@freezed
class StoryFrame with _$StoryFrame {
  const factory StoryFrame({
    required String id,
    required String title,
    required String content,
    required String imageUrl,
    required int order,
  }) = _StoryFrame;

  factory StoryFrame.fromJson(Map<String, dynamic> json) => _$StoryFrameFromJson(json);
}
