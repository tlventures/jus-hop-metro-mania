import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../core/commute/commute_provider.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../../../services/user_display_name.dart';
import '../application/streak_provider.dart';
import '../application/quest_provider.dart';
import '../application/home_provider.dart';
import '../../wallet/application/wallet_provider.dart';
import '../../play/application/games_provider.dart';
import '../../profile/presentation/profile_screen.dart' show profileProvider;
import '../../intelligence/presentation/disruption_banner.dart';
import '../../intelligence/presentation/live_etas_card.dart';
import '../../phase56/application/feature_flags_provider.dart';
import '../../commute/presentation/commute_overlay.dart';
import '../../commute/presentation/ticket_verification_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Single aggregate call — replaces 3–5 separate fetches.
    // Hydrates streak, quests, and wallet summary in one round-trip.
    Future.microtask(() => ref.read(homeProvider.notifier).fetch());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final streak = ref.watch(streakProvider);
    final quests = ref.watch(questsProvider);
    final wallet = ref.watch(walletProvider);
    final games = ref.watch(gamesProvider);
    final profileAsync = ref.watch(profileProvider);
    final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.empty;
    ref.watch(commuteAutoStartProvider);
    final commute = ref.watch(commuteProvider);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final profile = profileAsync.value;
    final userName = UserDisplayName.name(
      firebaseUser: firebaseUser,
      profile: profile,
    );
    final co2Kg = _asDouble(profile?['co2SavedKg']);

    // Empty-state heuristic: brand-new account, no activity yet
    final isFreshUser =
        wallet.points == 0 && streak.currentDay == 0 && !wallet.isLoading;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _CompactHeader(
              name: userName,
              tier: wallet.tier,
              points: wallet.points,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s4,
                  AppSpacing.s4,
                  AppSpacing.s8,
                ),
                children: [
                  if (flags.liveEtas) ...[
                    const DisruptionBanner(),
                    const SizedBox(height: AppSpacing.s3),
                  ],

                  _LaunchHero(
                    name: userName,
                    wallet: wallet,
                    streak: streak,
                    isFreshUser: isFreshUser,
                    onStart: _startVerifiedCommute,
                    onWallet: () => context.go('/wallet'),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  const CommuteOverlay(),
                  if (!commute.isVisible) ...[
                    _Phase56ActionCard(
                      icon: Icons.train_outlined,
                      title: 'Commute Auto-Mode',
                      subtitle: 'Start a 1.5x earning session for this ride.',
                      cta: 'Start',
                      onTap: _startVerifiedCommute,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],

                  _StreakStrip(
                    streak: streak,
                    onClaim:
                        streak.canClaim
                            ? () =>
                                ref.read(streakProvider.notifier).claimStreak()
                            : null,
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  _DailyQuestsSection(quests: quests),
                  const SizedBox(height: AppSpacing.s5),

                  if (flags.tripMode) ...[
                    _Phase56ActionCard(
                      icon: Icons.route_outlined,
                      title: 'Ride Mode',
                      subtitle: 'Start a tunnel-ready commute session.',
                      cta: 'Start',
                      onTap: () => context.go('/ride'),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],
                  if (flags.liveEtas) ...[
                    const LiveEtasCard(),
                    const SizedBox(height: AppSpacing.s5),
                  ],

                  _SectionHeader(title: 'Quick Earn'),
                  const SizedBox(height: AppSpacing.s3),
                  SizedBox(
                    height: 132,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ...games
                            .take(3)
                            .map(
                              (g) => Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.s3,
                                ),
                                child: _EarnCard(
                                  icon: g.icon,
                                  label: g.name,
                                  points: '+${g.pointsPerRound}',
                                  onTap: () => context.go('/play'),
                                ),
                              ),
                            ),
                        _EarnCard(
                          icon: '📖',
                          label: 'Articles',
                          points: '+15',
                          onTap: () => context.go('/learn'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  if (flags.stamps ||
                      flags.audioStories ||
                      flags.liveEvents) ...[
                    _Phase56Shelf(flags: flags),
                    const SizedBox(height: AppSpacing.s5),
                  ],

                  if (co2Kg > 0) _EcoImpactCard(co2Kg: co2Kg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startVerifiedCommute() async {
    final verification = await showRideVerificationSheet(context);
    if (!mounted || verification == null) return;
    await ref
        .read(commuteProvider.notifier)
        .startManual(
          cityId: ref.read(activeCityProvider)?.id,
          ticketVerification: verification,
        );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

// =============================================================================
// Compact header — single row: avatar · name · tier chip · settings
// =============================================================================

class _CompactHeader extends ConsumerWidget {
  final String name;
  final String tier;
  final int points;

  const _CompactHeader({
    required this.name,
    required this.tier,
    required this.points,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstName = name.split(' ').first;
    final initial = UserDisplayName.initial(firstName);
    final tierEmoji = switch (tier.toLowerCase()) {
      'platinum' => '💎',
      'gold' => '🥇',
      'silver' => '🥈',
      _ => '🥉',
    };

    // Keep greeting city-aware, but do not show a city label in the header.
    final city = ref.watch(activeCityProvider);
    final locale = ref.watch(localeProvider).languageCode;
    final greeting =
        city != null ? city.greetings.greetingFor(locale) : _defaultGreeting();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              initial,
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(tierEmoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      tier,
                      style: AppTypography.labelMedium.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () => context.go('/profile'),
            tooltip: '',
          ),
        ],
      ),
    );
  }

  String _defaultGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// =============================================================================
// Launch hero — daily rewards command center
// =============================================================================

class _LaunchHero extends ConsumerWidget {
  final String name;
  final WalletState wallet;
  final Streak streak;
  final bool isFreshUser;
  final Future<void> Function() onStart;
  final VoidCallback onWallet;

  const _LaunchHero({
    required this.name,
    required this.wallet,
    required this.streak,
    required this.isFreshUser,
    required this.onStart,
    required this.onWallet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = name.split(' ').first;
    final prompt =
        isFreshUser
            ? 'Start your first reward run'
            : streak.canClaim
            ? 'Claim today, keep the chain hot'
            : 'Next ride can still stack points';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cityInk,
        borderRadius: AppRadius.borderRadiusXL,
        boxShadow: [
          BoxShadow(
            color: AppColors.electricTeal.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 16),
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
                      AppColors.cityInk,
                      AppColors.electricTeal.withValues(alpha: 0.9),
                      AppColors.signalPink.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.52, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -38,
              top: -18,
              child: Icon(
                Icons.trip_origin,
                size: 190,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _HeroPill(icon: Icons.bolt_outlined, label: 'Today'),
                      const Spacer(),
                      InkWell(
                        onTap: onWallet,
                        borderRadius: AppRadius.borderRadiusFull,
                        child: _HeroPill(
                          icon: Icons.account_balance_wallet_outlined,
                          label: '${wallet.points} pts',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'Hey $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    prompt,
                    style: AppTypography.displayLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          label: 'Streak',
                          value:
                              streak.currentDay == 0
                                  ? 'New'
                                  : '${streak.currentDay}d',
                          icon: Icons.local_fire_department_outlined,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: _HeroStat(
                          label: 'Tier',
                          value: wallet.tier,
                          icon: Icons.workspace_premium_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onStart,
                          icon: const Icon(Icons.train_outlined),
                          label: const Text('Start Ride'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.neonLime,
                            foregroundColor: AppColors.cityInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      IconButton.filledTonal(
                        onPressed: onWallet,
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Open wallet',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          foregroundColor: Colors.white,
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
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: AppSpacing.s1),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.neonLime, size: 20),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Streak strip — 7-day visual calendar (Duolingo-style)
// =============================================================================

class _StreakStrip extends StatelessWidget {
  final Streak streak;
  final VoidCallback? onClaim;

  const _StreakStrip({required this.streak, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayIdx = now.weekday - 1; // Mon=0..Sun=6
    final labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final isClaimable = streak.canClaim;
    final isFresh = streak.currentDay == 0;

    // Filled days = the past (currentDay) days going backward from today.
    // For the strip we cap at 7 days.
    final filledIndices = <int>{};
    for (var i = 0; i < streak.currentDay && i < 7; i++) {
      filledIndices.add((todayIdx - i + 7) % 7);
    }

    String subtitle;
    if (isFresh) {
      subtitle = 'Start your streak today — ride the metro to earn +5 pts';
    } else if (isClaimable) {
      subtitle = 'Tap to claim today — +${(streak.currentDay + 1) * 5} pts';
    } else {
      subtitle = 'See you tomorrow to continue your streak';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusXL,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🔥', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: AppSpacing.s2),
              Text(
                isFresh ? 'No streak yet' : '${streak.currentDay}-day streak',
                style: AppTypography.titleMedium.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isClaimable && !isFresh && onClaim != null)
                FilledButton(
                  onPressed: onClaim,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text('+${(streak.currentDay + 1) * 5}'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final isToday = i == todayIdx;
              final isFilled = filledIndices.contains(i);
              return _StreakDay(
                label: labels[i],
                state:
                    isToday
                        ? (isClaimable
                            ? _DayState.todayClaimable
                            : _DayState.todayDone)
                        : (isFilled ? _DayState.filled : _DayState.empty),
              );
            }),
          ),
        ],
      ),
    );
  }
}

enum _DayState { empty, filled, todayClaimable, todayDone }

class _StreakDay extends StatelessWidget {
  final String label;
  final _DayState state;

  const _StreakDay({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color bg, border, fg;
    switch (state) {
      case _DayState.empty:
        bg = Colors.transparent;
        border = colorScheme.outlineVariant;
        fg = colorScheme.onSurfaceVariant;
      case _DayState.filled:
        bg = AppColors.goldPoints.withValues(alpha: 0.15);
        border = AppColors.goldPoints;
        fg = AppColors.goldPoints;
      case _DayState.todayClaimable:
        bg = colorScheme.primary;
        border = colorScheme.primary;
        fg = colorScheme.onPrimary;
      case _DayState.todayDone:
        bg = AppColors.goldPoints;
        border = AppColors.goldPoints;
        fg = Colors.white;
    }
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1.5),
          ),
          alignment: Alignment.center,
          child:
              state == _DayState.filled || state == _DayState.todayDone
                  ? Icon(Icons.check, size: 16, color: fg)
                  : Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
        ),
      ],
    );
  }
}

// =============================================================================
// Daily Quests — vertical list with progress header
// =============================================================================

class _DailyQuestsSection extends StatelessWidget {
  final List<Quest> quests;
  const _DailyQuestsSection({required this.quests});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final done = quests.where((q) => q.isCompleted).length;
    final total = quests.length;
    final progress = total == 0 ? 0.0 : done / total;
    final pending = quests.where((q) => !q.isCompleted).toList();
    final completed = quests.where((q) => q.isCompleted).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Daily Quests',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$done / $total',
              style: AppTypography.labelMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(AppColors.mintSuccess),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        ...pending.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: _QuestRow(quest: q, completed: false),
          ),
        ),
        if (completed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s2),
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s1,
              bottom: AppSpacing.s2,
            ),
            child: Text(
              'Done today',
              style: AppTypography.labelSmall.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...completed.map(
            (q) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s2),
              child: _QuestRow(quest: q, completed: true),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestRow extends StatelessWidget {
  final Quest quest;
  final bool completed;
  const _QuestRow({required this.quest, required this.completed});

  static const _icons = {
    'play_game': '🎮',
    'watch_video': '🎬',
    'read_article': '📖',
    'ride_started': '🚇',
    'station_quiz': '🧠',
    'check_passport': '📍',
    'survey': '📝',
  };

  static const _routes = {
    'ride_started': '/ride',
    'play_game': '/play',
    'read_article': '/learn',
    'watch_video': '/play',
    'station_quiz': '/play',
    'check_passport': '/stamps',
    'survey': '/learn',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = _icons[quest.id] ?? '⭐';
    final route = _routes[quest.id];

    return InkWell(
      onTap: completed || route == null ? null : () => context.go(route),
      borderRadius: AppRadius.borderRadiusL,
      child: Opacity(
        opacity: completed ? 0.7 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color:
                completed
                    ? AppColors.mintSuccess.withValues(alpha: 0.08)
                    : colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusL,
            border: Border.all(
              color:
                  completed
                      ? AppColors.mintSuccess.withValues(alpha: 0.3)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  quest.title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (completed)
                Icon(Icons.check_circle, color: AppColors.mintSuccess, size: 20)
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.goldPoints.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '+${quest.points}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.goldPoints,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.titleMedium.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _EcoImpactCard extends StatelessWidget {
  final double co2Kg;
  const _EcoImpactCard({required this.co2Kg});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppColors.mintSuccess.withValues(alpha: 0.1),
        borderRadius: AppRadius.borderRadiusXL,
        border: Border.all(color: AppColors.mintSuccess.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text('🌱', style: const TextStyle(fontSize: 32)),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You've saved ${co2Kg.toStringAsFixed(1)} kg CO₂",
                  style: AppTypography.titleSmall.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Keep riding to grow your impact',
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Preserved widgets — unchanged from original
// =============================================================================

class _EarnCard extends StatelessWidget {
  final String icon;
  final String label;
  final String points;
  final VoidCallback onTap;

  const _EarnCard({
    required this.icon,
    required this.label,
    required this.points,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 124,
        margin: const EdgeInsets.only(right: AppSpacing.s2),
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusL,
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.goldPoints.withValues(alpha: 0.2),
                borderRadius: AppRadius.borderRadiusS,
              ),
              child: Text(
                points,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.goldPoints,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Phase56Shelf extends StatelessWidget {
  final FeatureFlags flags;
  const _Phase56Shelf({required this.flags});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (flags.stamps)
        _MiniPhaseCard(
          icon: Icons.confirmation_number_outlined,
          label: 'Station Stamps',
          onTap: () => context.go('/stamps'),
        ),
      if (flags.audioStories)
        _MiniPhaseCard(
          icon: Icons.headphones_outlined,
          label: 'Metro Tales',
          onTap: () => context.go('/audio'),
        ),
      if (flags.liveEvents)
        _MiniPhaseCard(
          icon: Icons.bolt_outlined,
          label: 'Live Events',
          onTap: () => context.go('/events'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Metro Companion'),
        const SizedBox(height: AppSpacing.s3),
        Row(children: cards),
      ],
    );
  }
}

class _Phase56ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  const _Phase56ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusXL,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: AppRadius.borderRadiusXL,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primary,
              child: Icon(icon, color: colorScheme.onPrimary, size: 20),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.76,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Text(
              cta,
              style: AppTypography.labelLarge.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _MiniPhaseCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniPhaseCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s2),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusL,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s4,
              horizontal: AppSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusL,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: AppColors.metroIndigo, size: 22),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
