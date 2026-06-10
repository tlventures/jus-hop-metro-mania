import 'package:flutter_test/flutter_test.dart';
import 'package:metrosafar/domain/entities/station_story.dart';

void main() {
  // Mirrors the real /api/stories payload shape (backend db.json), which has
  // NO `points` field. Previously this threw because `points` was `required`,
  // leaving the Stories screen blank. It must now parse with points defaulting.
  test('parses a story payload without a points field', () {
    final json = {
      'id': 'story_1',
      'stationName': 'Charminar',
      'description': 'The iconic gateway of Hyderabad',
      'imageUrl': '🕌',
      'frames': [
        {
          'id': 'frame_1_1',
          'title': 'Welcome to Charminar',
          'content': 'Built in 1591 ...',
          'imageUrl': '🕌',
          'order': 1,
        },
      ],
    };

    final story = StationStory.fromJson(json);

    expect(story.id, 'story_1');
    expect(story.stationName, 'Charminar');
    expect(story.frames.single.title, 'Welcome to Charminar');
    expect(story.points, 25); // default applied
    expect(story.isCompleted, false);
  });
}
