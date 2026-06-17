// lib/features/play/games/trivia_screen.dart
//
// Multi-city trivia. Questions come from the city's content pack
// (cityTriviaPackProvider). Falls back to a generic metro pack if the
// active city has no trivia uploaded yet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/city/content_pack_models.dart';
import '../../../core/city/content_pack_provider.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../design_system/components/game_shell.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../application/games_provider.dart';
import '../application/trivia_score_provider.dart';

class TriviaScreen extends ConsumerStatefulWidget {
  const TriviaScreen({super.key});

  @override
  ConsumerState<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends ConsumerState<TriviaScreen> {
  // Game state
  int currentQuestion = 0;
  int score = 0;
  bool isAnswered = false;
  int? selectedAnswer;
  int streak = 0;
  int bestStreak = 0;
  int secondsLeft = 15;
  bool timedOut = false;
  bool _submitting = false;
  Timer? _timer;
  DateTime _gameStartedAt = DateTime.now();
  DateTime _questionStartedAt = DateTime.now();
  String? _rankLoadedForCity;

  // Loaded questions (city-specific)
  List<TriviaQuestion> _questions = [];

  /// Generic fallback questions — only used if the active city has no trivia
  /// uploaded yet (so the game never shows an empty state).
  static final List<TriviaQuestion> _genericFallback = [
    const TriviaQuestion(
      id: 'generic_001',
      question: {'en': 'What does "Metro" generally stand for?'},
      options: {
        'en': [
          'Metropolitan rail',
          'Mega train',
          'Metric route',
          'Modern transit',
        ],
      },
      correctIndex: 0,
    ),
    const TriviaQuestion(
      id: 'generic_002',
      question: {
        'en': 'Which country had the world\'s first underground metro?',
      },
      options: {
        'en': ['United Kingdom', 'United States', 'France', 'Russia'],
      },
      correctIndex: 0,
      explanation: {'en': 'The London Underground opened in 1863.'},
    ),
    const TriviaQuestion(
      id: 'generic_003',
      question: {'en': 'Metros generally reduce which kind of pollution?'},
      options: {
        'en': [
          'Air pollution',
          'Light pollution',
          'Sound pollution only',
          'None',
        ],
      },
      correctIndex: 0,
    ),
  ];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startQuestionTimer() {
    _timer?.cancel();
    secondsLeft = 15;
    _questionStartedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || isAnswered) {
        timer.cancel();
        return;
      }
      if (secondsLeft <= 1) {
        timer.cancel();
        _selectAnswer(-1);
        return;
      }
      setState(() => secondsLeft--);
    });
  }

  int _speedBonus() {
    final elapsed = DateTime.now().difference(_questionStartedAt).inSeconds;
    if (elapsed < 5) return 5;
    if (elapsed < 10) return 3;
    return 1;
  }

  double _streakMultiplier(int nextStreak) {
    if (nextStreak >= 5) return 2.0;
    if (nextStreak >= 3) return 1.5;
    return 1.0;
  }

  void _selectAnswer(int index) {
    if (isAnswered) return;
    if (_questions.isEmpty) return;

    HapticFeedback.heavyImpact();
    _timer?.cancel();

    final isCorrect = index == _questions[currentQuestion].correctIndex;

    setState(() {
      isAnswered = true;
      selectedAnswer = index;
      timedOut = index < 0;
      if (isCorrect) {
        final nextStreak = streak + 1;
        final multiplier = _streakMultiplier(nextStreak);
        score += ((10 + _speedBonus()) * multiplier).round();
        streak = nextStreak;
        bestStreak = bestStreak > streak ? bestStreak : streak;
      } else {
        streak = 0;
      }
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (currentQuestion < _questions.length - 1) {
        setState(() {
          currentQuestion++;
          isAnswered = false;
          selectedAnswer = null;
          timedOut = false;
        });
        _startQuestionTimer();
      } else {
        _showGameEnd();
      }
    });
  }

  Future<void> _showGameEnd() async {
    _timer?.cancel();
    if (_submitting) return;
    setState(() => _submitting = true);

    final city = ref.read(activeCityProvider);
    final elapsed = DateTime.now().difference(_gameStartedAt).inSeconds;
    final result = await ref
        .read(gamesProvider.notifier)
        .updateGameScore(
          'trivia',
          score,
          cityId: city?.id,
          questionsAnswered: _questions.length,
          streak: bestStreak,
          timeSpent: elapsed,
        );
    final rankData =
        result?['trivia'] is Map
            ? TriviaRankSnapshot.fromJson(
              Map<String, dynamic>.from(result!['trivia'] as Map),
            )
            : null;
    final pointsEarned = (result?['pointsEarned'] as num?)?.toInt() ?? score;
    if (rankData != null) {
      ref.read(triviaScoreProvider.notifier).replace(rankData);
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    final rankLine =
        rankData?.rank == null
            ? 'City rank will appear once more players join today.'
            : 'City rank: #${rankData!.rank} of ${rankData.playerCount} players today';
    final personalBest = rankData != null && score >= rankData.personalRecord;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXXL),
      builder:
          (context) => GameEndBottomSheet(
            title:
                personalBest
                    ? '🏆 New personal best!'
                    : (score > 80 ? '🌟 Awesome!' : '👏 Nice Job!'),
            score: score,
            points: pointsEarned,
            message: [
              rankLine,
              'Best streak: $bestStreak',
              if ((result?['commuteMultiplier'] as num?)?.toDouble() == 1.5)
                'Commute bonus applied: 1.5x reward points',
            ].join('\n'),
            icon: Center(
              child: Text(
                personalBest ? '🏆' : '🎯',
                style: const TextStyle(fontSize: 80),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetGame();
                  },
                  child: const Text('Play Again'),
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'I scored $score on MetroSafar Trivia. Beat my rank today!',
                        subject: 'MetroSafar Trivia Challenge',
                      ),
                    );
                  },
                  child: const Text('Challenge a Friend'),
                ),
              ),
            ],
          ),
    );
  }

  void _resetGame() {
    setState(() {
      currentQuestion = 0;
      score = 0;
      streak = 0;
      bestStreak = 0;
      isAnswered = false;
      selectedAnswer = null;
      timedOut = false;
      _submitting = false;
      _gameStartedAt = DateTime.now();
      _questions = _shuffleQuestions(_questions);
    });
    _startQuestionTimer();
  }

  List<TriviaQuestion> _shuffleQuestions(List<TriviaQuestion> source) {
    final copy = List<TriviaQuestion>.from(source)..shuffle();
    return copy.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final triviaAsync = ref.watch(cityTriviaPackProvider);
    final city = ref.watch(activeCityProvider);
    final locale = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? 'Metro';
    final rankAsync = ref.watch(triviaScoreProvider);

    if (_rankLoadedForCity != city?.id) {
      _rankLoadedForCity = city?.id;
      Future.microtask(() {
        if (mounted) {
          ref.read(triviaScoreProvider.notifier).load(cityId: city?.id);
        }
      });
    }

    return triviaAsync.when(
      loading: () => _LoadingScaffold(title: '$cityName Trivia'),
      error: (e, st) => _ErrorScaffold(title: '$cityName Trivia', error: e),
      data: (pack) {
        // Lazily set questions on first build
        if (_questions.isEmpty) {
          final sample =
              pack.isEmpty ? _genericFallback : pack.randomSample(10);
          _questions = sample.isEmpty ? _genericFallback : sample;
          _gameStartedAt = DateTime.now();
          _startQuestionTimer();
        }

        if (_questions.isEmpty) {
          return _ErrorScaffold(
            title: '$cityName Trivia',
            error: 'No trivia available yet for $cityName.',
          );
        }

        final q = _questions[currentQuestion];
        final progress = (currentQuestion + 1) / _questions.length;
        final localizedOptions = q.localizedOptions(locale);
        final localizedQuestion = q.localizedQuestion(locale);
        final maxPossibleScore = _questions.length * 30;

        return GameShell(
          title: '$cityName Trivia',
          subtitle:
              '${currentQuestion + 1}/${_questions.length} · ${secondsLeft}s',
          currentScore: score,
          maxScore: maxPossibleScore,
          onBack: () => Navigator.pop(context),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s6),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.borderRadiusS,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  _ScoreToBeatCard(rankAsync: rankAsync),
                  const SizedBox(height: AppSpacing.s5),

                  _TimerAndMultiplier(
                    secondsLeft: secondsLeft,
                    streak: streak,
                    multiplier: _streakMultiplier(streak),
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  if (streak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCD34D).withValues(alpha: 0.2),
                        borderRadius: AppRadius.borderRadiusS,
                      ),
                      child: Text(
                        '🔥 $streak in a row!',
                        style: AppTypography.labelMedium.copyWith(
                          color: const Color(0xFFFCD34D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (streak > 0) const SizedBox(height: AppSpacing.s6),

                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: AppRadius.borderRadiusXL,
                    ),
                    child: Text(
                      localizedQuestion,
                      style: AppTypography.headlineSmall.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),

                  ...localizedOptions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final isCorrect = index == q.correctIndex;
                    final isSelected =
                        selectedAnswer == index ||
                        (timedOut && isAnswered && isCorrect);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                      child: GameAnswerChip(
                        label: option,
                        onSelected: () => _selectAnswer(index),
                        isSelected: isSelected,
                        isCorrect: isCorrect,
                        delay: Duration(milliseconds: index * 100),
                      ),
                    );
                  }),

                  // Show explanation after answer
                  if (isAnswered &&
                      q.localizedExplanation(locale).isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: AppRadius.borderRadiusM,
                      ),
                      child: Text(
                        q.localizedExplanation(locale),
                        style: AppTypography.bodySmall.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: AppSpacing.s6),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreToBeatCard extends StatelessWidget {
  final AsyncValue<TriviaRankSnapshot> rankAsync;

  const _ScoreToBeatCard({required this.rankAsync});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = rankAsync.valueOrNull;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ScoreMetric(
              label: 'Best today',
              value: snapshot == null ? '...' : '${snapshot.bestToday}',
            ),
          ),
          Expanded(
            child: _ScoreMetric(
              label: 'Record',
              value: snapshot == null ? '...' : '${snapshot.personalRecord}',
            ),
          ),
          Expanded(
            child: _ScoreMetric(
              label: 'City rank',
              value: snapshot?.rank == null ? '--' : '#${snapshot!.rank}',
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ScoreMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TimerAndMultiplier extends StatelessWidget {
  final int secondsLeft;
  final int streak;
  final double multiplier;

  const _TimerAndMultiplier({
    required this.secondsLeft,
    required this.streak,
    required this.multiplier,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = secondsLeft / 15.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  secondsLeft <= 5 ? AppColors.warning : colorScheme.primary,
                ),
              ),
              Center(
                child: Text(
                  '$secondsLeft',
                  style: AppTypography.titleMedium.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDD5),
            borderRadius: AppRadius.borderRadiusL,
          ),
          child: Text(
            streak == 0
                ? 'Build a streak'
                : '🔥 $streak · ${multiplier.toStringAsFixed(1)}x',
            style: AppTypography.labelLarge.copyWith(
              color: const Color(0xFF9A3412),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  final String title;
  const _LoadingScaffold({required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorScaffold extends StatelessWidget {
  final String title;
  final Object error;
  const _ErrorScaffold({required this.title, required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Text(
          'Could not load trivia.\n\n$error',
          style: AppTypography.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
