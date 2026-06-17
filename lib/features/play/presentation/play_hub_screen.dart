import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/games_provider.dart';
import '../games/daily_spin_screen.dart';
import '../games/trivia_screen.dart';
import '../games/sudoku_screen.dart';
import '../games/word_puzzle_screen.dart';
import '../games/city_explorer_screen.dart';
import 'watch_and_earn_card.dart';
import '../../social/presentation/friends_screen.dart';

class PlayHubScreen extends ConsumerStatefulWidget {
  const PlayHubScreen({super.key});

  @override
  ConsumerState<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends ConsumerState<PlayHubScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gamesProvider.notifier).fetchScores());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final games = ref.watch(gamesProvider);
    final totalScore = ref.watch(totalGameScoreProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () => ref.read(gamesProvider.notifier).fetchScores(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              'Play & Earn',
              style: AppTypography.headlineMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s4,
                AppSpacing.s4,
                AppSpacing.s8 + 104,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 168,
                    child: _ScoreHero(totalScore: totalScore),
                  ),

                  const SizedBox(height: AppSpacing.s4),

                  _SocialChallengeCard(
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FriendsScreen(),
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  // Watch a rewarded video, earn points
                  const WatchAndEarnCard(),
                  const SizedBox(height: AppSpacing.s4),

                  // Games title
                  Text(
                    'Games',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  // Games grid - Daily Spin featured
                  SizedBox(
                    height: 136,
                    child: _GameCard(
                      game: games.firstWhere((g) => g.id == 'daily_spin'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DailySpinScreen(),
                          ),
                        );
                      },
                      featured: true,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s4),

                  // Other games — vertical list (predictable left-to-right
                  // reading; descriptions never truncate).
                  ...games.skip(1).map(
                        (game) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                          child: _GameCard(
                            game: game,
                            onTap: () => _launchGame(context, game),
                          ),
                        ),
                      ),

                  const SizedBox(height: AppSpacing.s8),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _launchGame(BuildContext context, GameRecord game) {
    Widget screen;

    switch (game.id) {
      case 'daily_spin':
        screen = const DailySpinScreen();
      case 'trivia':
        screen = const TriviaScreen();
      case 'sudoku':
        screen = const SudokuScreen();
      case 'word_puzzle':
        screen = const WordPuzzleScreen();
      case 'city_explorer':
        screen = const CityExplorerScreen();
      default:
        return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _ScoreHero extends StatelessWidget {
  final int totalScore;

  const _ScoreHero({required this.totalScore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cityInk,
        borderRadius: AppRadius.borderRadiusXL,
        boxShadow: [
          BoxShadow(
            color: AppColors.electricTeal.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusXL,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.electricTeal,
                      AppColors.skyPop.withValues(alpha: 0.75),
                      AppColors.signalPink,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -16,
              top: -22,
              child: Icon(
                // Filled (not thin-outline) so it reads as an intentional
                // brand watermark rather than a broken-image placeholder.
                Icons.emoji_events,
                size: 120,
                color: AppColors.neonLime.withValues(alpha: 0.20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Play streak power',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3,
                          vertical: AppSpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: AppRadius.borderRadiusFull,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'Game score',
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    '$totalScore',
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      'Rewards go straight to your wallet.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialChallengeCard extends StatelessWidget {
  final VoidCallback onTap;

  const _SocialChallengeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusXL,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: AppRadius.borderRadiusXL,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.signalPink.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusL,
              ),
              child: Icon(Icons.flag_outlined, color: AppColors.signalPink),
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Beat your friends this week',
                    style: AppTypography.titleSmall.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Invite commuters and climb the leaderboard.',
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameRecord game;
  final VoidCallback onTap;
  final bool featured;

  const _GameCard({
    required this.game,
    required this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (featured) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gradientStart.withValues(alpha: 0.2),
                AppColors.gradientEnd.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: AppRadius.borderRadiusXL,
            border: Border.all(
              color: AppColors.gradientStart.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: AppRadius.borderRadiusL,
                ),
                alignment: Alignment.center,
                child: Text(game.icon, style: const TextStyle(fontSize: 36)),
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      game.name,
                      style: AppTypography.titleMedium.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      game.description,
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Wrap(
                      spacing: AppSpacing.s2,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s3,
                            vertical: AppSpacing.s1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.goldPoints.withValues(alpha: 0.2),
                            borderRadius: AppRadius.borderRadiusS,
                          ),
                          child: Text(
                            '+${game.pointsPerRound} pts',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.goldPoints,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (game.commuteLengthLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s3,
                              vertical: AppSpacing.s1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: AppRadius.borderRadiusS,
                            ),
                            child: Text(
                              '🚇 ${game.commuteLengthLabel}',
                              style: AppTypography.labelSmall.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Regular card — full-width list row: icon · title+description · badges.
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusXL,
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: AppRadius.borderRadiusL,
              ),
              child: Text(game.icon, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: AppTypography.titleSmall.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    game.description,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.goldPoints.withValues(alpha: 0.2),
                    borderRadius: AppRadius.borderRadiusS,
                  ),
                  child: Text(
                    '+${game.pointsPerRound}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.goldPoints,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (game.commuteLengthLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    game.commuteLengthLabel,
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
