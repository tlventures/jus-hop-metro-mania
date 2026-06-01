# Game Screen Implementation Template

Use this template to implement Phase 2 game screens with consistent polish and UX.

## File Structure

```
lib/features/play/games/
  ├── game_shell.dart          # Shared GameShell widget
  ├── trivia_screen.dart       # Trivia game (example)
  ├── sudoku_screen.dart
  ├── word_puzzle_screen.dart
  ├── city_explorer_screen.dart
  ├── daily_spin_screen.dart   # NEW
  └── widgets/                 # Game-specific widgets
      ├── trivia_widgets.dart
      ├── sudoku_widgets.dart
      └── ...
```

## GameShell Pattern

All games should wrap their UI in a `GameShell` that provides:

```dart
class GameShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottomAction;
  final int? currentScore;
  final int? maxScore;
  final Duration? elapsedTime;
  final VoidCallback? onBack;

  // Renders:
  // 1. Gradient header (6, Back, Title, subtitle)
  // 2. Progress/score chip (top-right)
  // 3. Body (scrollable)
  // 4. Bottom action bar
  // 5. Handles end-of-round celebration (Lottie + share)
}
```

## Example: Trivia Screen

```dart
class TriviaPregameScreen extends StatefulWidget {
  const TriviaPregameScreen({super.key});
  @override
  State<TriviaPregameScreen> createState() => _TriviaPregameScreenState();
}

class _TriviaPregameScreenState extends State<TriviaPregameScreen> {
  int currentQuestion = 0;
  int score = 0;
  late List<Question> questions;

  @override
  void initState() {
    super.initState();
    questions = _loadQuestions(); // from backend or hardcoded
  }

  @override
  Widget build(BuildContext context) {
    final q = questions[currentQuestion];
    final isLastQuestion = currentQuestion == questions.length - 1;

    return GameShell(
      title: 'Metro Trivia',
      subtitle: '${currentQuestion + 1}/${questions.length}',
      currentScore: score,
      maxScore: questions.length * 10,
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (currentQuestion + 1) / questions.length,
          ),
          // Question card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(q.question, style: AppTypography.headlineSmall),
                  SizedBox(height: 24),
                  // Answer options (stagger animated chips)
                  ...q.options.asMap().entries.map((e) =>
                    _AnswerChip(
                      label: e.value,
                      isCorrect: e.key == q.correctIndex,
                      onSelected: (selected) => _onAnswerSelected(selected, e.key == q.correctIndex),
                      delay: Duration(milliseconds: e.key * 100),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomAction: FilledButton(
        onPressed: isLastQuestion ? _finishGame : () {}, // hidden if not last
        child: Text(isLastQuestion ? 'Finish' : 'Next'),
      ),
    );
  }

  void _onAnswerSelected(bool correct, bool isCorrectAnswer) {
    if (isCorrectAnswer) {
      setState(() => score += 10);
      // Green pulse + haptic
      HapticFeedback.heavyImpact();
    } else {
      // Red shake + haptic
      HapticFeedback.lightImpact();
    }
    Future.delayed(Duration(milliseconds: 800), () {
      if (currentQuestion < questions.length - 1) {
        setState(() => currentQuestion++);
      }
    });
  }

  void _finishGame() {
    // Show end-of-round bottom sheet via GameShell
    // Lottie confetti + score + share card
  }
}
```

## Engagement Mechanics to Add

### 1. Daily Spin
**File**: `lib/features/play/games/daily_spin_screen.dart`

```dart
class DailySpinScreen extends StatefulWidget {
  @override
  State<DailySpinScreen> createState() => _DailySpinScreenState();
}

class _DailySpinScreenState extends State<DailySpinScreen> with TickerProviderStateMixin {
  late AnimationController _wheelController;
  int selectedSegment = 0;

  @override
  void initState() {
    super.initState();
    _wheelController = AnimationController(
      duration: Duration(seconds: 5),
      vsync: this,
    );
  }

  void _spin() {
    final randomSegment = Random().nextInt(8);
    final rotations = 5 + (randomSegment / 8);

    _wheelController.forward(from: 0.0);
    // On completion, reveal reward
    Future.delayed(Duration(seconds: 5), () {
      _showRewardBottomSheet(rewards[randomSegment]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: 'Daily Spin',
      subtitle: 'One free spin per day',
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie wheel (8 segments with prizes)
          RotationTransition(
            turns: _wheelController,
            child: _WheelWidget(
              segments: [
                '🎫 +50 pts',
                '🎁 Coupon',
                '⭐ +100 pts',
                '🎉 Surprise',
                // ... 4 more
              ],
            ),
          ),
          SizedBox(height: 48),
          FloatingActionButton.extended(
            onPressed: _spin,
            label: const Text('Spin'),
            icon: const Icon(Icons.casino),
          ),
        ],
      ),
    );
  }
}
```

### 2. Streak Tracking
**Provider**:

```dart
final streakProvider = StateNotifierProvider<StreakNotifier, AsyncValue<Streak>>((ref) {
  return StreakNotifier(ref.watch(userRepositoryProvider));
});

class Streak {
  final int days;
  final DateTime lastClaimedAt;
  final int totalPoints;
  // methods: canClaim(), claim()
}
```

### 3. Daily Quests
**Provider**:

```dart
final dailyQuestsProvider = StateNotifierProvider<QuestsNotifier, AsyncValue<List<Quest>>>((ref) {
  return QuestsNotifier(ref.watch(userRepositoryProvider));
});

class Quest {
  final String id;
  final String title;
  final int points;
  final String type; // 'play_game' | 'watch_video' | 'read_article'
  final bool isCompleted;
  
  void complete() => userRepo.completeQuest(id);
}
```

## End-of-Round Experience (Bottom Sheet)

All games should show this when completed:

```dart
void _showGameEndBottomSheet(GameResult result) {
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusXXL,
    ),
    builder: (context) => GameEndBottomSheet(
      icon: Lottie.asset('assets/lottie/confetti.json'),
      title: result.isWin ? '🎉 Great Job!' : 'Keep Playing',
      score: result.score,
      points: result.pointsEarned,
      actions: [
        FilledButton(
          onPressed: () => _playAgain(),
          child: Text('Play Again'),
        ),
        TextButton(
          onPressed: () => _shareScore(result),
          child: Text('Share'),
        ),
      ],
    ),
  );
}
```

## Haptic Feedback & Animations

```dart
// Correct answer
HapticFeedback.heavyImpact();
_animateCorrect(answerWidget); // green pulse via flutter_animate

// Wrong answer
HapticFeedback.lightImpact();
_animateWrong(answerWidget); // red shake

// Button press
HapticFeedback.selectionClick();

// End of game
HapticFeedback.vibrate();
```

## Color Scheme for Games

Use `Theme.of(context).colorScheme.*` throughout:

```dart
- Primary: for headers, important CTAs
- Secondary: for accents (rewards, bonuses)
- Tertiary: for success states
- Error: for mistakes
- Surface/surfaceContainer: for cards
```

## Loading & Empty States

```dart
// Loading
ShimmerBox(width: double.infinity, height: 300)

// Empty (no games played)
EmptyState(
  icon: Icons.sports_esports_outlined,
  title: 'No games played yet',
  subtitle: 'Start by choosing a game above',
  ctaLabel: 'Browse Games',
  onCtaTapped: () => context.go('/play'),
)

// Error
ErrorState(
  message: 'Failed to load game',
  onRetry: () => _loadGame(),
)
```

## Riverpod Integration Example

```dart
class GameScreenExample extends ConsumerWidget {
  const GameScreenExample({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(currentGameProvider);
    
    return gameState.when(
      data: (game) => _GameUI(game),
      loading: () => const LoadingScaffold(),
      error: (err, st) => ErrorState(message: err.toString()),
    );
  }
}

// Provider
final currentGameProvider = StateNotifierProvider<GameNotifier, AsyncValue<Game>>((ref) {
  return GameNotifier(ref.watch(gamesRepositoryProvider));
});
```

## Testing Checklist for Each Game

- [ ] Starts cleanly (no build errors)
- [ ] Input validation works (no invalid moves)
- [ ] Scoring correct
- [ ] Haptic feedback fires
- [ ] End-of-round bottom sheet shows
- [ ] Share button works
- [ ] Play again resets state
- [ ] Works on small screens (Pixel 4a)
- [ ] Dark mode renders correctly

---

Use this pattern for all Phase 2 games. Consistency = premium feel.
