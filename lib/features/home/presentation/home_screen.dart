import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/commute/commute_provider.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/user_display_name.dart';
import '../../../services/version_gate.dart';
import '../../commute/presentation/commute_overlay.dart';
import '../../intelligence/presentation/disruption_banner.dart';
import '../../intelligence/presentation/live_etas_card.dart';
import '../../notifications/application/notifications_provider.dart';
import '../../phase56/application/feature_flags_provider.dart';
import '../../play/application/games_provider.dart';
import '../../profile/presentation/profile_screen.dart' show profileProvider;
import '../../wallet/application/earn_provider.dart' as earn;
import '../../wallet/application/promo_provider.dart';
import '../../wallet/application/wallet_provider.dart';
import '../../wallet/data/rewards_service.dart' show StreakStatus;
import '../application/home_provider.dart';
import '../application/quest_provider.dart';
import '../application/streak_provider.dart';

/// Home — vibrant "bento" dashboard.
///
/// Layout: a gradient daily-mission hero (reward target + Start Ride), a
/// tappable daily-quests pill, a single horizontal scrollable row of secondary
/// earn actions, and a bento of games (large featured tile + vibrant 1×1 grid).
/// All actionable surfaces sit above/just-below the fold to maximise day-1
/// engagement and remove the dead whitespace of the previous layout.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

const Color _canvas = Color(0xFFF4F6F8);

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(unreadNotificationsProvider);
      ref.read(homeProvider.notifier).fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Force-update gate (server-driven minSupportedBuild via /api/home).
    ref.listen(homeProvider, (prev, next) {
      next.whenOrNull(
        data: (home) => VersionGate.enforce(context, home.appConfig),
      );
    });

    final homeAsync = ref.watch(homeProvider);
    if (homeAsync.isLoading) {
      return const Scaffold(
        backgroundColor: _canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (homeAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: TextButton(
            onPressed: () => ref.read(homeProvider.notifier).fetch(),
            child: const Text('Reload'),
          ),
        ),
      );
    }

    final streak = ref.watch(streakProvider);
    final quests = ref.watch(questsProvider);
    final wallet = ref.watch(walletProvider);
    final games = ref.watch(gamesProvider);
    final profileAsync = ref.watch(profileProvider);
    final flags = ref.watch(featureFlagsProvider).valueOrNull ?? FeatureFlags.empty;
    ref.watch(commuteAutoStartProvider);
    final commute = ref.watch(commuteProvider);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final profile = profileAsync.valueOrNull;
    final userName =
        UserDisplayName.name(firebaseUser: firebaseUser, profile: profile);
    final co2Kg = _asDouble(profile?['co2SavedKg']);

    final doneQuests = quests.where((q) => q.isCompleted).length;
    final totalQuests = quests.isEmpty ? 4 : quests.length;
    final earnedToday = quests
        .where((q) => q.isCompleted)
        .fold<int>(0, (s, q) => s + q.points);

    // Use push() (not go()) so the Android back button returns to Home instead
    // of exiting the app — go() replaces the navigation stack. Each chip points
    // to a DISTINCT destination (the Learn chips deep-link to their section).
    final quickActions = <_Action>[
      _Action(Icons.menu_book_rounded, 'Read', 15, AppColors.skyPop,
          () => context.push('/learn?section=articles')),
      _Action(Icons.quiz_rounded, 'Quiz', 25, AppColors.mangoPop,
          () => context.push('/learn?section=surveys')),
      _Action(Icons.auto_stories_rounded, 'Stories', 25, AppColors.signalPink,
          () => context.push('/learn?section=stories')),
      _Action(Icons.confirmation_number_rounded, 'Tickets', 0,
          AppColors.metroIndigo, () => context.push('/booking')),
      _Action(Icons.group_add_rounded, 'Refer', 0, AppColors.electricTeal,
          () => context.push('/referral')),
      if (flags.liveEtas)
        _Action(Icons.route_rounded, 'Journey', 0, AppColors.metroIndigo,
            () => context.push('/journey-planner')),
      if (flags.stamps)
        _Action(Icons.local_activity_rounded, 'Stamps', 0, AppColors.skyPop,
            () => context.push('/stamps')),
      if (flags.audioStories)
        _Action(Icons.headphones_rounded, 'Audio', 0, AppColors.electricTeal,
            () => context.push('/audio')),
    ];

    final gameSpecs = [
      for (final g in games)
        _BentoSpec(
          icon: _iconForGame(g.id),
          label: g.name,
          points: g.pointsPerRound,
          best: g.bestScore,
          onTap: () => context.push('/game/${g.id}'),
          accent: _accentForGame(g.id),
        ),
    ];
    final heroTile = gameSpecs.isNotEmpty ? gameSpecs.first : null;
    final gridTiles = gameSpecs.skip(gameSpecs.isEmpty ? 0 : 1).toList();

    final rewardTarget = gameSpecs.fold<int>(0, (s, t) => s + t.points) +
        quickActions.fold<int>(0, (s, a) => s + a.points) +
        quests
            .where((q) => !q.isCompleted)
            .fold<int>(0, (s, q) => s + q.points);

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4, AppSpacing.s2, AppSpacing.s4, AppSpacing.s6,
          ),
          children: [
            // Custom header (replaces AppBar — AppBar's own Row keeps
            // overflowing on tall-cutout devices like the Fold).
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/profile'),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      UserDisplayName.initial(userName.split(' ').first),
                      style: AppTypography.labelLarge.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Text(
                  'MetroSafar',
                  style: AppTypography.headlineMedium.copyWith(color: cs.onSurface),
                ),
                const Spacer(),
                Builder(
                  builder: (context) {
                    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
                    return IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => context.push('/notifications-inbox'),
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text(unread > 9 ? '9+' : '$unread'),
                        child: Icon(Icons.notifications_none, color: cs.onSurface),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: Icon(Icons.settings_outlined, color: cs.onSurface),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),

            if (flags.liveEtas) ...[
              const DisruptionBanner(),
              const SizedBox(height: AppSpacing.s3),
            ],

            // Streak + wallet chips — driven by the real backend endpoints
            // (streak from /api/v1/rewards/streak, balance from /api/v1/wallet/balance)
            // so the numbers users see match what they actually own.
            _EarnChipsRow(fallbackStreak: streak),
            const SizedBox(height: AppSpacing.s3),

            // Primary booking CTA — booking is now the first-class action.
            _BookTicketCard(
              onTap: () => context.push('/booking'),
            ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.04),
            const SizedBox(height: AppSpacing.s4),

            _DailyMissionCard(
              greeting: 'Hey ${userName.split(' ').first}',
              earnedToday: earnedToday,
              rewardTarget: rewardTarget,
              tier: wallet.tier,
              onStartRide: _startVerifiedCommute,
            ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.06),

            // Active-commute UI (only renders during a ride).
            const CommuteOverlay(),
            if (commute.isVisible) const SizedBox(height: AppSpacing.s3),
            const SizedBox(height: AppSpacing.s4),

            _QuestRail(
              done: doneQuests,
              total: totalQuests,
              onTap: () => _showQuestsSheet(context, quests),
            ).animate().fadeIn(delay: 50.ms, duration: 260.ms),
            const SizedBox(height: AppSpacing.s4),

            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: quickActions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.s3),
                itemBuilder: (context, i) =>
                    _ActionChip(action: quickActions[i])
                        .animate()
                        .fadeIn(delay: (40 + i * 30).ms, duration: 220.ms),
              ),
            ),
            const SizedBox(height: AppSpacing.s5),

            if (flags.liveEtas) ...[
              const LiveEtasCard(),
              const SizedBox(height: AppSpacing.s5),
            ],

            _SectionTitle('Earn & Play'),
            const SizedBox(height: AppSpacing.s3),

            if (heroTile != null) ...[
              _BentoHeroTile(spec: heroTile)
                  .animate()
                  .fadeIn(delay: 80.ms, duration: 240.ms)
                  .scaleXY(begin: 0.97),
              const SizedBox(height: AppSpacing.s3),
            ],

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: gridTiles.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.s3,
                crossAxisSpacing: AppSpacing.s3,
                mainAxisExtent: 108,
              ),
              itemBuilder: (context, i) => _BentoTile(spec: gridTiles[i])
                  .animate()
                  .fadeIn(delay: (110 + i * 40).ms, duration: 240.ms)
                  .scaleXY(begin: 0.96),
            ),

            if (co2Kg > 0) ...[
              const SizedBox(height: AppSpacing.s4),
              _EcoCard(co2Kg: co2Kg),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startVerifiedCommute() async {
    // Booking-first pivot: "Start Ride" now opens the booking flow instead of
    // the legacy station-QR verification sheet. Points are awarded on a
    // confirmed ticket, not on ride-tracking.
    HapticFeedback.selectionClick();
    context.push('/booking');
  }

  void _showQuestsSheet(BuildContext context, List<Quest> quests) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s5, 0, AppSpacing.s5, AppSpacing.s8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's quests",
                style: AppTypography.titleLarge
                    .copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.s3),
              ...quests.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                  child: Row(
                    children: [
                      Icon(
                        q.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: q.isCompleted
                            ? AppColors.mintSuccess
                            : AppColors.grey400,
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Text(
                          q.title,
                          style: AppTypography.bodyLarge.copyWith(
                            decoration: q.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: q.isCompleted
                                ? AppColors.grey500
                                : null,
                          ),
                        ),
                      ),
                      Text(
                        '+${q.points}',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.goldPoints,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (quests.isEmpty)
                Text('No quests yet — check back soon.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.grey600)),
            ],
          ),
        );
      },
    );
  }

  void _showStreakSheet(BuildContext context, Streak streak) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final days = List.generate(7, (i) => i < streak.currentDay);
        const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s5, 0, AppSpacing.s5, AppSpacing.s8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department,
                      color: AppColors.goldPoints, size: 26),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    '${streak.currentDay}-day streak',
                    style: AppTypography.titleLarge
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                streak.canClaim
                    ? 'Claim today to keep the chain alive (+${streak.pointsForClaim} pts)'
                    : 'Today secured — come back tomorrow for more.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.grey600),
              ),
              const SizedBox(height: AppSpacing.s5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 7; i++)
                    Column(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: days[i]
                              ? AppColors.goldPoints
                              : AppColors.grey200,
                          child: Icon(
                            days[i] ? Icons.check : Icons.circle_outlined,
                            size: 16,
                            color: days[i] ? Colors.white : AppColors.grey400,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(labels[i], style: AppTypography.labelSmall),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              if (streak.canClaim)
                SizedBox(
                  width: double.infinity,
                  height: AppSpacing.buttonHeight,
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      ref.read(streakProvider.notifier).claimStreak();
                      Navigator.of(ctx).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonLime,
                      foregroundColor: AppColors.cityInk,
                    ),
                    child: const Text('Claim today'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

// ─── icon / accent mapping for games ─────────────────────────────────────────
IconData _iconForGame(String id) {
  final k = id.toLowerCase();
  if (k.contains('spin')) return Icons.casino_rounded;
  if (k.contains('trivia')) return Icons.psychology_rounded;
  if (k.contains('sudoku')) return Icons.grid_on_rounded;
  if (k.contains('word')) return Icons.abc_rounded;
  if (k.contains('explor') || k.contains('city')) return Icons.explore_rounded;
  return Icons.sports_esports_rounded;
}

Color _accentForGame(String id) {
  final k = id.toLowerCase();
  if (k.contains('spin')) return AppColors.signalPink;
  if (k.contains('trivia')) return AppColors.electricTeal;
  if (k.contains('sudoku')) return AppColors.metroIndigo;
  if (k.contains('word')) return AppColors.skyPop;
  if (k.contains('explor') || k.contains('city')) return AppColors.mangoPop;
  return AppColors.electricTeal;
}

Color _onAccent(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : AppColors.cityInk;

const List<BoxShadow> _softShadow = [
  BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
];

// ─── Section title ───────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.titleMedium.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

// ─── App-bar stat chip ───────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool pulsing;
  final VoidCallback onTap;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.borderRadiusFull,
        boxShadow: _softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
    if (pulsing) {
      chip = chip
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(end: 1.08, duration: 700.ms, curve: Curves.easeInOut);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusFull,
      child: chip,
    );
  }
}

// ─── Daily mission hero ──────────────────────────────────────────────────────
class _DailyMissionCard extends StatelessWidget {
  final String greeting;
  final int earnedToday;
  final int rewardTarget;
  final String tier;
  final VoidCallback onStartRide;

  const _DailyMissionCard({
    required this.greeting,
    required this.earnedToday,
    required this.rewardTarget,
    required this.tier,
    required this.onStartRide,
  });

  @override
  Widget build(BuildContext context) {
    final total = earnedToday + rewardTarget;
    final pct = total == 0 ? 0.0 : (earnedToday / total).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusXL,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cityInk,
            AppColors.electricTeal,
            AppColors.signalPink
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.electricTeal.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.neonLime),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$earnedToday',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      'pts',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        greeting,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _TierBadge(tier: tier),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rewardTarget > 0
                      ? 'Earn up to +$rewardTarget pts on today’s rides'
                      : 'All caught up today 🎉',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                SizedBox(
                  height: 40,
                  // This CTA STARTS A RIDE to earn points (verified commute) —
                  // it does NOT buy a ticket. The label must say so, or it reads
                  // as a duplicate of the "Book a metro ticket" card above.
                  child: FilledButton.icon(
                    onPressed: onStartRide,
                    icon: const Icon(Icons.near_me_rounded, size: 18),
                    label: const Text('Start a ride'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonLime,
                      foregroundColor: AppColors.cityInk,
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                      textStyle: AppTypography.labelMedium
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
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

class _TierBadge extends StatelessWidget {
  final String tier;
  const _TierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            tier,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quest rail (tappable) ───────────────────────────────────────────────────
class _QuestRail extends StatelessWidget {
  final int done;
  final int total;
  final VoidCallback onTap;
  const _QuestRail(
      {required this.done, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusL,
        child: Ink(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.borderRadiusL,
            boxShadow: _softShadow,
          ),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded,
                  size: 18, color: AppColors.metroIndigo),
              const SizedBox(width: AppSpacing.s2),
              Text(
                'Daily Quests',
                style: AppTypography.labelLarge
                    .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
              const Spacer(),
              ...List.generate(
                total,
                (i) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    i < done ? Icons.circle : Icons.circle_outlined,
                    size: 11,
                    color: i < done ? AppColors.mintSuccess : AppColors.grey300,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                '$done/$total',
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick action chip (vibrant filled, horizontal row) ──────────────────────
class _Action {
  final IconData icon;
  final String label;
  final int points;
  final Color accent;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.points, this.accent, this.onTap);
}

class _ActionChip extends StatelessWidget {
  final _Action action;
  const _ActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    final onAccent = _onAccent(action.accent);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        action.onTap();
      },
      borderRadius: AppRadius.borderRadiusL,
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusL,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [action.accent, action.accent.withValues(alpha: 0.8)],
          ),
          boxShadow: [
            BoxShadow(
              color: action.accent.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(action.icon, color: onAccent, size: 24),
            const Spacer(),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: onAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (action.points > 0)
              Text(
                '+${action.points} pts',
                style: AppTypography.labelSmall.copyWith(
                  color: onAccent.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bento tiles (vibrant filled) ────────────────────────────────────────────
class _BentoSpec {
  final IconData icon;
  final String label;
  final int points;
  final int best;
  final VoidCallback onTap;
  final Color accent;
  const _BentoSpec({
    required this.icon,
    required this.label,
    required this.points,
    required this.best,
    required this.onTap,
    required this.accent,
  });
}

class _BentoHeroTile extends StatelessWidget {
  final _BentoSpec spec;
  const _BentoHeroTile({required this.spec});

  @override
  Widget build(BuildContext context) {
    final onAccent = _onAccent(spec.accent);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        spec.onTap();
      },
      borderRadius: AppRadius.borderRadiusXL,
      child: Container(
        height: 116,
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusXL,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [spec.accent, spec.accent.withValues(alpha: 0.78)],
          ),
          boxShadow: [
            BoxShadow(
              color: spec.accent.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: AppRadius.borderRadiusL,
              ),
              child: Icon(spec.icon, size: 30, color: onAccent),
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Featured',
                    style: AppTypography.labelSmall.copyWith(
                      color: onAccent.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleLarge.copyWith(
                      color: onAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (spec.points > 0)
                    _PointsPill(points: spec.points, onAccent: onAccent),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded,
                size: 34, color: onAccent.withValues(alpha: 0.9)),
          ],
        ),
      ),
    );
  }
}

class _BentoTile extends StatelessWidget {
  final _BentoSpec spec;
  const _BentoTile({required this.spec});

  @override
  Widget build(BuildContext context) {
    final onAccent = _onAccent(spec.accent);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        spec.onTap();
      },
      borderRadius: AppRadius.borderRadiusL,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusL,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [spec.accent, spec.accent.withValues(alpha: 0.8)],
          ),
          boxShadow: [
            BoxShadow(
              color: spec.accent.withValues(alpha: 0.26),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: AppRadius.borderRadiusM,
              ),
              child: Icon(spec.icon, size: 21, color: onAccent),
            ),
            const Spacer(),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w800,
                color: onAccent,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (spec.points > 0)
                  _PointsPill(points: spec.points, onAccent: onAccent),
                const Spacer(),
                if (spec.best > 0)
                  Text(
                    'Best ${spec.best}',
                    style: AppTypography.labelSmall.copyWith(
                      color: onAccent.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsPill extends StatelessWidget {
  final int points;
  final Color onAccent;
  const _PointsPill({required this.points, required this.onAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.18),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Text(
        '+$points',
        style: AppTypography.labelSmall.copyWith(
          color: onAccent,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ─── Eco impact card ─────────────────────────────────────────────────────────
class _EcoCard extends StatelessWidget {
  final double co2Kg;
  const _EcoCard({required this.co2Kg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.borderRadiusL,
        boxShadow: _softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.mintSuccess.withValues(alpha: 0.14),
              borderRadius: AppRadius.borderRadiusM,
            ),
            child: const Icon(Icons.eco_rounded,
                color: AppColors.mintSuccess, size: 24),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'ve saved ${co2Kg.toStringAsFixed(1)} kg CO₂',
                  style: AppTypography.labelLarge
                      .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
                Text(
                  'by choosing the metro over a car',
                  style: AppTypography.bodySmall
                      .copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Streak + wallet chips backed by real endpoints. Reads streak status and
/// wallet balance from the server; falls back to whatever the pre-existing
/// Home aggregate had while the requests are in flight.
class _EarnChipsRow extends ConsumerWidget {
  const _EarnChipsRow({required this.fallbackStreak});
  final Streak fallbackStreak;

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref.read(earn.earnServiceProvider).claimStreak();
      ref.invalidate(earn.streakStatusProvider);
      ref.invalidate(walletBalanceProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(
          res.pointsAwarded > 0
              ? 'Day ${res.currentDay} streak · +${res.pointsAwarded} pts'
              : 'Already claimed today',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Streak claim failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(earn.streakStatusProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);

    final StreakStatus? live = streakAsync.valueOrNull;
    final int day = live?.currentDay ?? fallbackStreak.currentDay;
    final bool canClaim = live?.canClaim ?? fallbackStreak.canClaim;
    final int nextPts = live?.nextRewardPoints ?? fallbackStreak.pointsForClaim;

    final int liveBalance = balanceAsync.valueOrNull?.points ?? 0;

    return Row(
      children: [
        _StatChip(
          icon: Icons.local_fire_department,
          iconColor: AppColors.goldPoints,
          label: day == 0
              ? (canClaim ? 'Claim +$nextPts pts' : 'Streak · $day')
              : '$day-day streak',
          pulsing: canClaim,
          onTap: () async {
            if (canClaim) {
              await _claim(context, ref);
            } else if (context.mounted) {
              // Show the sheet as before if there's nothing to claim right now.
              // The sheet's own claim button also hits the backend.
            }
          },
        ),
        const SizedBox(width: AppSpacing.s2),
        _StatChip(
          icon: Icons.account_balance_wallet,
          iconColor: AppColors.electricTeal,
          label: '$liveBalance pts',
          onTap: () => context.go('/wallet'),
        ),
      ],
    );
  }
}

/// Primary booking CTA card shown at the top of the Home bento. Kept compact
/// so it complements — not replaces — the existing quests/streaks/games layout.
class _BookTicketCard extends StatelessWidget {
  const _BookTicketCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusL,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusL,
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.95),
                AppColors.electricTeal.withValues(alpha: 0.90),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: AppRadius.borderRadiusM,
                ),
                child: const Icon(
                  Icons.directions_subway_filled_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Book a metro ticket',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pay via UPI · Earn reward points',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
