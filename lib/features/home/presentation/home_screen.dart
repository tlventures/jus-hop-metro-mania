import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../core/commute/commute_provider.dart';
import '../../../design_system/components/state_views.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/backend_service.dart';
import '../../../services/user_display_name.dart';
import '../../notifications/application/notifications_provider.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Single aggregate call — replaces 3–5 separate fetches.
    // Hydrates streak, quests, and wallet summary in one round-trip.
    Future.microtask(() {
      ref.read(homeProvider.notifier).fetch();
      ref.invalidate(unreadNotificationsProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app (e.g. after tapping/seeing a push) refreshes the
    // unread bell badge and home data.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(unreadNotificationsProvider);
      ref.read(homeProvider.notifier).fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show the skeleton only on the FIRST load (no data yet). On later
    // refreshes (resume, post-earn) we keep the existing data on screen so the
    // home doesn't blink to a skeleton every time.
    final homeAsync = ref.watch(homeProvider);
    if (homeAsync.isLoading && !homeAsync.hasValue) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(child: AppLoadingSkeleton.home()),
      );
    }
    if (homeAsync.hasError && !homeAsync.hasValue) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: AppErrorState(
            icon: Icons.cloud_off,
            title: "Couldn't load your home",
            message: 'Check your connection and try again.',
            onRetry: () => ref.read(homeProvider.notifier).fetch(),
          ),
        ),
      );
    }

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
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.s4),
          child: GestureDetector(
            onTap: () => context.go('/profile'),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                UserDisplayName.initial(userName.split(' ').first),
                style: AppTypography.labelLarge.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'MetroSafar',
          style: AppTypography.headlineMedium.copyWith(color: colorScheme.onSurface),
        ),
        actions: [
          Builder(
            builder: (context) {
              final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
              return IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.push('/notifications-inbox'),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 9 ? '9+' : '$unread'),
                  child: Icon(Icons.notifications_none, color: colorScheme.onSurface),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                    onWallet: () => context.go('/wallet'),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  // Active-commute UI (only renders during a ride). The
                  // "start" action now lives in the docked Start Ride bar,
                  // so the duplicate Commute Auto-Mode card was removed.
                  const CommuteOverlay(),
                  if (commute.isVisible) const SizedBox(height: AppSpacing.s4),

                  _StreakStrip(
                    streak: streak,
                    onClaim: streak.canClaim
                        ? () {
                            HapticFeedback.mediumImpact();
                            ref.read(streakProvider.notifier).claimStreak();
                          }
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  _DailyQuestsSection(quests: quests),
                  const SizedBox(height: AppSpacing.s5),

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
                                  onTap: () => context.push('/game/${g.id}'),
                                ),
                              ),
                            ),
                        _EarnCard(
                          icon: '📖',
                          label: 'Articles',
                          points: '+15',
                          onTap: () => context.push('/learn'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),

                  if (co2Kg > 0) _EcoImpactCard(co2Kg: co2Kg),
                ],
              ),
            ),
          ],
        ),
      ),
      // Primary action as a right-aligned floating action bar. Hidden while a
      // commute is already running (the overlay takes over then).
      floatingActionButton: commute.isVisible
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _startVerifiedCommute();
              },
              backgroundColor: AppColors.neonLime,
              foregroundColor: AppColors.cityInk,
              icon: const Icon(Icons.train_rounded),
              label: Text(
                'Start Ride',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }

  Future<void> _startVerifiedCommute() async {
    final verification = await showRideVerificationSheet(context);
    if (!mounted || verification == null) return;
    try {
      await ref
          .read(commuteProvider.notifier)
          .startManual(
            cityId: ref.read(activeCityProvider)?.id,
            ticketVerification: verification,
          );
    } on BackendRequestException catch (e) {
      // e.g. ticket already verified by another rider / not today's ticket.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}


// =============================================================================
// Launch hero — daily rewards command center
// =============================================================================

class _LaunchHero extends ConsumerWidget {
  final String name;
  final WalletState wallet;
  final Streak streak;
  final bool isFreshUser;
  final VoidCallback onWallet;

  const _LaunchHero({
    required this.name,
    required this.wallet,
    required this.streak,
    required this.isFreshUser,
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
                  const SizedBox(height: AppSpacing.s5),
                  Text(
                    'Hey $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    prompt,
                    style: AppTypography.titleLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
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
        // Dark scrim (not low-opacity white) so values stay legible in
        // bright outdoor light against the teal/magenta gradient (WCAG AA).
        color: AppColors.cityInk.withValues(alpha: 0.55),
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
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
      subtitle = 'Open the app daily to build your streak — +5 pts a day';
    } else if (isClaimable) {
      subtitle = 'Tap to lock in today — +${(streak.currentDay + 1) * 5} pts';
    } else {
      subtitle = 'Today secured ✓ — back tomorrow for +${(streak.currentDay + 1) * 5} pts';
    }
    final nextIdx = (todayIdx + 1) % 7;
    final nextPts = (streak.currentDay + (isClaimable ? 2 : 1)) * 5;

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
              const Icon(Icons.local_fire_department,
                  size: 20, color: _StreakDay._flame),
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
          // Connected 7-day timeline: a faint line links the circles to convey
          // progression; completed days fill solid with a check.
          Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                top: 15,
                child: Container(
                  height: 2,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final isToday = i == todayIdx;
                  final isFilled = filledIndices.contains(i);
                  return _StreakDay(
                    label: labels[i],
                    // Pull the user forward: show tomorrow's reward.
                    subLabel: i == nextIdx ? '+$nextPts' : null,
                    state: isToday
                        ? (isClaimable
                            ? _DayState.todayClaimable
                            : _DayState.todayDone)
                        : (isFilled ? _DayState.filled : _DayState.empty),
                  );
                }),
              ),
            ],
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
  final String? subLabel;

  const _StreakDay({required this.label, required this.state, this.subLabel});

  // One consistent streak colour — flame orange (reserve lime for CTAs).
  static const Color _flame = Color(0xFFFF7A1A);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color bg, border, fg;
    switch (state) {
      case _DayState.empty:
        bg = colorScheme.surface;
        border = colorScheme.outlineVariant;
        fg = colorScheme.onSurfaceVariant;
      case _DayState.filled:
        bg = _flame;
        border = _flame;
        fg = Colors.white;
      case _DayState.todayClaimable:
        bg = colorScheme.primary;
        border = colorScheme.primary;
        fg = colorScheme.onPrimary;
      case _DayState.todayDone:
        bg = _flame;
        border = _flame;
        fg = Colors.white;
    }
    final isDone = state == _DayState.filled || state == _DayState.todayDone;
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          child: isDone
              ? Icon(Icons.check, size: 16, color: fg)
              : Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          subLabel ?? '',
          style: AppTypography.labelSmall.copyWith(
            color: _flame,
            fontWeight: FontWeight.w800,
            fontSize: 10,
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
      onTap: completed || route == null
          ? null
          : () => navigateAppPath(context, route),
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
