import 'package:flutter/foundation.dart';
import '../models/game_model.dart';

class GamesProvider with ChangeNotifier {
  int _totalPoints = 0;
  final List<Game> _games = [
    Game(
      id: 'trivia',
      name: 'Metro Trivia',
      description: 'Test your knowledge about your city and its metro',
      points: 50,
      type: 'quiz',
      icon: 'assets/icons/quiz.png',
    ),
    Game(
      id: 'word_puzzle',
      name: 'Station Scramble',
      description: 'Unscramble station names',
      points: 30,
      type: 'puzzle',
      icon: 'assets/icons/puzzle.png',
    ),
    Game(
      id: 'memory',
      name: 'Route Memory',
      description: 'Remember and match metro routes',
      points: 40,
      type: 'memory',
      icon: 'assets/icons/memory.png',
    ),
  ];

  List<Game> get games => [..._games];
  int get totalPoints => _totalPoints;

  void addPoints(int points) {
    _totalPoints += points;
    notifyListeners();
  }
}