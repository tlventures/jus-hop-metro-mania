import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/city/current_city_provider.dart';
import '../../../design_system/components/game_shell.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../application/games_provider.dart';

class WordPuzzleScreen extends ConsumerStatefulWidget {
  const WordPuzzleScreen({super.key});

  @override
  ConsumerState<WordPuzzleScreen> createState() => _WordPuzzleScreenState();
}

class _WordPuzzleScreenState extends ConsumerState<WordPuzzleScreen>
    with TickerProviderStateMixin {
  late List<PuzzleWord> words;
  late int currentWordIndex;
  late int score;
  late int elapsedSeconds;
  late bool timerRunning;
  late bool gameCompleted;

  late List<String> unscrambledLetters;
  late List<String> placedLetters;

  /// Dynamically built from the active city's station list — no hardcodes.
  List<Map<String, String>> wordList = [];

  /// Pick 5 station names from the active city for puzzle rounds.
  /// Filters out very long names (> 14 chars) so the UI stays usable.
  List<Map<String, String>> _buildWordList() {
    final stations = ref.read(cityStationsProvider);
    final city = ref.read(activeCityProvider);
    final cityName = city?.displayName('en') ?? 'Metro';
    final operator = city?.operatorShortName ?? 'Metro';

    if (stations.isEmpty) {
      // Generic fallback if no city loaded yet
      return [
        {'word': 'METRO', 'scrambled': 'TREMO', 'hint': 'Underground transit'},
        {
          'word': 'STATION',
          'scrambled': 'TANSITO',
          'hint': 'Where trains stop',
        },
        {'word': 'PLATFORM', 'scrambled': 'FORMLATP', 'hint': 'You board here'},
      ];
    }

    final candidates =
        stations.where((s) {
            final name = s.name.replaceAll(' ', '').replaceAll('.', '');
            return name.length >= 5 && name.length <= 14;
          }).toList()
          ..shuffle();

    return candidates.take(5).map((s) {
      final clean =
          s.name.replaceAll(' ', '').replaceAll('.', '').toUpperCase();
      final lineLabel = s.lineIds.isNotEmpty ? s.lineIds.first : '';
      return {
        'word': clean,
        'scrambled': (clean.split('')..shuffle()).join(),
        'hint':
            lineLabel.isNotEmpty
                ? '$operator $lineLabel line station in $cityName'
                : '$cityName Metro station',
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    wordList = _buildWordList();
    _initializeGame();
    _startTimer();
  }

  @override
  void dispose() {
    timerRunning = false;
    super.dispose();
  }

  void _initializeGame() {
    words =
        wordList.asMap().entries.map((entry) {
          return PuzzleWord(
            word: entry.value['word']!,
            hint: entry.value['hint']!,
            scrambled: entry.value['scrambled']!,
          );
        }).toList();

    currentWordIndex = 0;
    score = 0;
    elapsedSeconds = 0;
    timerRunning = false;
    gameCompleted = false;

    _loadCurrentWord();
  }

  void _loadCurrentWord() {
    final word = words[currentWordIndex].word;
    unscrambledLetters = word.split('')..shuffle();
    placedLetters = List.filled(word.length, '');
  }

  void _startTimer() {
    timerRunning = true;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && timerRunning && !gameCompleted) {
        setState(() => elapsedSeconds++);
        _startTimer();
      }
    });
  }

  void _placeLetter(int sourceIndex, int targetIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      String letter = unscrambledLetters[sourceIndex];
      unscrambledLetters.removeAt(sourceIndex);
      placedLetters[targetIndex] = letter;
    });
  }

  void _removeLetter(int targetIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      unscrambledLetters.add(placedLetters[targetIndex]);
      placedLetters[targetIndex] = '';
      unscrambledLetters.shuffle();
    });
  }

  void _checkWord() {
    final currentWord = words[currentWordIndex];
    final userWord = placedLetters.join();

    if (userWord == currentWord.word) {
      HapticFeedback.heavyImpact();
      setState(() => score += 25);

      if (currentWordIndex < words.length - 1) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              currentWordIndex++;
              _loadCurrentWord();
            });
          }
        });
      } else {
        _endGame();
      }
    } else {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not quite right, try again!')),
      );
    }
  }

  void _endGame() {
    timerRunning = false;
    setState(() => gameCompleted = true);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _showGameEnd();
    });
  }

  Future<void> _showGameEnd() async {
    final points = score > 100 ? 50 : 35;
    final result = await ref
        .read(gamesProvider.notifier)
        .updateGameScore('word_puzzle', score);
    if (!mounted) return;
    final accepted = result != null;
    final awardedPoints =
        accepted ? (result['pointsEarned'] as num?)?.toInt() ?? points : 0;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXXL),
      builder:
          (context) => GameEndBottomSheet(
            title:
                accepted
                    ? (score >= 100 ? '⭐ Outstanding!' : '👍 Well Done!')
                    : 'Ride Mode required',
            score: score,
            points: awardedPoints,
            message:
                accepted
                    ? 'Unscrambled ${words.length} words in ${_formatTime(elapsedSeconds)}'
                    : 'Unscramble while in transit to claim points.',
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      score = 0;
                      elapsedSeconds = 0;
                      gameCompleted = false;
                      _initializeGame();
                      _startTimer();
                    });
                  },
                  child: const Text('Play Again'),
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Share Score'),
                ),
              ),
            ],
          ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentWord = words[currentWordIndex];
    final isComplete = placedLetters.every((l) => l.isNotEmpty);

    final city = ref.watch(activeCityProvider);
    final locale = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? 'Metro';

    return GameShell(
      title: '$cityName Station Scramble',
      subtitle: 'Word ${currentWordIndex + 1}/${words.length}',
      onBack: () => Navigator.pop(context),
      elapsedTime: Duration(seconds: elapsedSeconds),
      showTimer: true,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            children: [
              // Score
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: AppRadius.borderRadiusS,
                    ),
                    child: Text(
                      '⭐ Score: $score',
                      style: AppTypography.labelSmall.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),

              // Hint
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.borderRadiusM,
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '💡 ${currentWord.hint}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Word slots
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      children: List.generate(
                        placedLetters.length,
                        (index) => GestureDetector(
                          onTap:
                              placedLetters[index].isNotEmpty
                                  ? () => _removeLetter(index)
                                  : null,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color:
                                  placedLetters[index].isNotEmpty
                                      ? colorScheme.primary
                                      : colorScheme.outline.withValues(
                                        alpha: 0.2,
                                      ),
                              borderRadius: AppRadius.borderRadiusM,
                              border: Border.all(
                                color: colorScheme.outline.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                placedLetters[index],
                                style: AppTypography.titleSmall.copyWith(
                                  color:
                                      placedLetters[index].isNotEmpty
                                          ? Colors.white
                                          : colorScheme.onSurface.withValues(
                                            alpha: 0.5,
                                          ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    if (isComplete)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _checkWord,
                          child: const Text('Check Word'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Letter tiles
              Text(
                'Available Letters',
                style: AppTypography.labelSmall.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: List.generate(
                  unscrambledLetters.length,
                  (index) => GestureDetector(
                    onTap: () {
                      final emptySlot = placedLetters.indexWhere(
                        (l) => l.isEmpty,
                      );
                      if (emptySlot != -1) {
                        _placeLetter(index, emptySlot);
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: AppRadius.borderRadiusM,
                        border: Border.all(
                          color: colorScheme.secondary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          unscrambledLetters[index],
                          style: AppTypography.titleSmall.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }
}

class PuzzleWord {
  final String word;
  final String hint;
  final String scrambled;

  PuzzleWord({required this.word, required this.hint, required this.scrambled});
}
