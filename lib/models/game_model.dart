class Game {
  final String id;
  final String name;
  final String description;
  final int points;
  final String type;
  final int bestScore;
  final String icon;

  Game({
    required this.id,
    required this.name,
    required this.description,
    required this.points,
    required this.type,
    this.bestScore = 0,
    required this.icon,
  });
}