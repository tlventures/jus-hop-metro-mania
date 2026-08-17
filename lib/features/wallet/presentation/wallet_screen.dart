import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../domain/entities/activity_event.dart';
import '../application/wallet_provider.dart';
import '../application/rewards_provider.dart';
import 'my_redemptions_screen.dart';
import '../../play/presentation/watch_and_earn_card.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(walletProvider.notifier).fetchWallet();
      ref.read(walletProvider.notifier).fetchTransactions();
      ref.read(rewardsProvider.notifier).fetchRewards();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wallet = ref.watch(walletProvider);
    final rewards = ref.watch(rewardsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              'Wallet',
              style: AppTypography.headlineMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child:
                wallet.isLoading
                    ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.s8),
                        child: CircularProgressIndicator(),
                      ),
                    )
                    : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s6),
                        child: Column(
                          children: [
                            _WalletBalanceHero(wallet: wallet),

                            const SizedBox(height: AppSpacing.s5),

                            // Convert points → promo code entry point.
                            InkWell(
                              onTap: () => context.push('/wallet/redeem'),
                              borderRadius: AppRadius.borderRadiusL,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.s4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.10),
                                  borderRadius: AppRadius.borderRadiusL,
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.card_giftcard_rounded,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: AppSpacing.s3),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Redeem points for a promo code',
                                            style: AppTypography.titleMedium.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '10 pts = ₹1 off your next ticket. Codes are valid 30 days.',
                                            style: AppTypography.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.s5),

                            // Transaction history preview
                            _TransactionHistorySection(wallet: wallet),

                            const SizedBox(height: AppSpacing.s8),

                            // Earn methods
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'How to Earn',
                                  style: AppTypography.titleMedium.copyWith(
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                _EarnMethodTile(
                                  icon: '🎮',
                                  title: 'Play Games',
                                  subtitle: 'Trivia, Sudoku, Puzzles',
                                  onTap: () => context.go('/play'),
                                ),
                                const SizedBox(height: AppSpacing.s3),
                                _EarnMethodTile(
                                  icon: '🎬',
                                  title: 'Watch Videos',
                                  subtitle: 'Learn about metro & culture',
                                  onTap: () => context.go('/learn'),
                                ),
                                const SizedBox(height: AppSpacing.s3),
                                _EarnMethodTile(
                                  icon: '📖',
                                  title: 'Read Articles',
                                  subtitle: 'Daily stories & guides',
                                  onTap: () => context.go('/learn'),
                                ),
                                const SizedBox(height: AppSpacing.s3),
                                _EarnMethodTile(
                                  icon: '📝',
                                  title: 'Take Surveys',
                                  subtitle: 'Share your feedback',
                                  onTap: () => context.go('/learn'),
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.s6),

                            // Earn more — rewarded video
                            const WatchAndEarnCard(),

                            const SizedBox(height: AppSpacing.s8),

                            // Redeem section
                            _RedeemSection(
                              rewards: rewards,
                              userPoints: wallet.points,
                            ),

                            const SizedBox(height: AppSpacing.s8),
                          ],
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _WalletBalanceHero extends StatelessWidget {
  final WalletState wallet;

  const _WalletBalanceHero({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final progressLabel =
        wallet.pointsToNextTier > 0
            ? '${wallet.pointsToNextTier} pts to ${wallet.nextTier}'
            : 'Top tier unlocked';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: AppColors.cityInk,
        borderRadius: AppRadius.borderRadiusXL,
        boxShadow: [
          BoxShadow(
            color: AppColors.signalPink.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 18),
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
                      AppColors.skyPop.withValues(alpha: 0.8),
                      AppColors.signalPink.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -36,
              bottom: -42,
              child: Icon(
                Icons.token_outlined,
                size: 180,
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
                      _WalletChip(
                        icon: Icons.workspace_premium_outlined,
                        label: wallet.tier,
                      ),
                      const Spacer(),
                      _WalletChip(
                        icon: Icons.trending_up,
                        label: progressLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    _formatPoints(wallet.points),
                    style: AppTypography.displayLarge.copyWith(
                      color: Colors.white,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    'points ready to spend',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  ClipRRect(
                    borderRadius: AppRadius.borderRadiusFull,
                    child: LinearProgressIndicator(
                      value: wallet.tierProgress,
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.neonLime,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Row(
                    children: [
                      _MiniWalletStat(
                        label: 'Next drop',
                        value: wallet.nextTier,
                        icon: Icons.bolt_outlined,
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      _MiniWalletStat(
                        label: 'Status',
                        value: wallet.tierProgress >= 1 ? 'Maxed' : 'Rising',
                        icon: Icons.auto_awesome_outlined,
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

  String _formatPoints(int points) {
    if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(points % 1000 == 0 ? 0 : 1)}K';
    }
    return '$points';
  }
}

class _WalletChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _WalletChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.neonLime, size: 16),
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

class _MiniWalletStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniWalletStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: AppRadius.borderRadiusL,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.neonLime, size: 18),
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
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
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

class _TransactionHistorySection extends StatelessWidget {
  final WalletState wallet;

  const _TransactionHistorySection({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final txns = wallet.transactions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Earnings',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            if (txns.isNotEmpty)
              TextButton(
                onPressed: () => _showAllTransactions(context, txns),
                child: const Text('View all'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        if (wallet.transactionsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (txns.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.s6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusL,
            ),
            child: Center(
              child: Text(
                'Complete quests, play games, or start a ride to earn points.',
                style: AppTypography.bodySmall.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...txns.take(4).map((t) => _TransactionTile(transaction: t)),
      ],
    );
  }

  void _showAllTransactions(
    BuildContext context,
    List<WalletTransaction> txns,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TransactionHistorySheet(transactions: txns),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final diff = now.difference(transaction.createdAt);
    final timeLabel =
        diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusL,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.mintSuccess.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _typeEmoji(transaction.type),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    style: AppTypography.labelMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    timeLabel,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '+${transaction.pointsAwarded} pts',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.mintSuccess,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeEmoji(String type) {
    switch (type) {
      case 'game_completed':
        return '🎮';
      case 'quest_completed':
        return '✅';
      case 'article_read':
        return '📖';
      case 'survey_submitted':
        return '📝';
      case 'story_completed':
        return '🗺️';
      case 'ride_started':
        return '🚇';
      case 'ride_completed':
        return '🏁';
      case 'stamp_claimed':
        return '📍';
      case 'station_quiz_completed':
        return '🧠';
      case 'passport_viewed':
        return '🛂';
      default:
        return '⭐';
    }
  }
}

class _TransactionHistorySheet extends StatelessWidget {
  final List<WalletTransaction> transactions;

  const _TransactionHistorySheet({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Group by date
    final grouped = <String, List<WalletTransaction>>{};
    for (final t in transactions) {
      final key = _dateLabel(t.createdAt);
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder:
          (_, controller) => Column(
            children: [
              const SizedBox(height: AppSpacing.s3),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s6),
                child: Text(
                  'Point History',
                  style: AppTypography.headlineMedium.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                  ),
                  itemCount: grouped.length,
                  itemBuilder: (_, i) {
                    final dateKey = grouped.keys.elementAt(i);
                    final dayTxns = grouped[dateKey]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s3,
                          ),
                          child: Text(
                            dateKey,
                            style: AppTypography.labelMedium.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ...dayTxns.map((t) => _TransactionTile(transaction: t)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  static String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(txDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _EarnMethodTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EarnMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusL,
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(icon, style: AppTypography.displayMedium),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RedeemSection extends ConsumerWidget {
  final RewardsState rewards;
  final int userPoints;

  const _RedeemSection({required this.rewards, required this.userPoints});

  static const _fallbackCategories = [
    'Food',
    'Shopping',
    'Travel',
    'Experiences',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    if (rewards.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final cats = rewards.categories;

    // No rewards loaded — show a compact, styled empty state instead of a
    // tall blank TabBarView with placeholder categories (the old "giant gray
    // rectangle" bug).
    if (cats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Redeem Rewards',
                style: AppTypography.titleMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/my-redemptions'),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('My Redemptions'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s8,
              horizontal: AppSpacing.s6,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusXL,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.redeem_outlined,
                  size: 40,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: AppSpacing.s3),
                Text(
                  'Rewards coming soon',
                  style: AppTypography.titleSmall.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  'Keep earning points — exciting rewards will appear here.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Redeem Rewards',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push('/my-redemptions'),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('My Redemptions'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        // DefaultTabController owns the lifecycle — no manual disposal needed.
        DefaultTabController(
          key: ValueKey(cats.join(',')),
          length: cats.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabs: cats.map((c) => Tab(text: c)).toList(),
              ),
              const SizedBox(height: AppSpacing.s4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final gridH = (constraints.maxWidth * 0.95).clamp(
                    240.0,
                    340.0,
                  );
                  return SizedBox(
                    height: gridH,
                    child: TabBarView(
                      children:
                          cats.map((cat) {
                            final items = rewards.byCategory(cat);
                            if (items.isEmpty) {
                              return Center(
                                child: Text(
                                  'No rewards in this category yet.',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            return GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: AppSpacing.s4,
                                    mainAxisSpacing: AppSpacing.s4,
                                    childAspectRatio: 1.2,
                                  ),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final reward = items[i];
                                final canAfford = userPoints >= reward.points;
                                return _CouponCard(
                                  title: reward.title,
                                  discount: reward.discount,
                                  cost: '${reward.points} pts',
                                  canAfford: canAfford && !reward.redeemed,
                                  redeemed: reward.redeemed,
                                  onRedeem:
                                      () => _confirmRedeem(
                                        context,
                                        ref,
                                        reward.id,
                                        reward.title,
                                        reward.points,
                                      ),
                                );
                              },
                            );
                          }).toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmRedeem(
    BuildContext context,
    WidgetRef ref,
    String rewardId,
    String title,
    int cost,
  ) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirm Redemption'),
            content: Text(
              'Redeem "$title" for $cost points?\n\nYou currently have $userPoints points.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final success = await ref
                      .read(walletProvider.notifier)
                      .redeemReward(rewardId, cost);
                  if (success) {
                    // Refresh lists so the new redemption + redeemed state show.
                    ref.invalidate(myRedemptionsProvider);
                    ref.read(rewardsProvider.notifier).fetchRewards();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? '🎉 "$title" redeemed! Check My Redemptions for your code.'
                              : 'Redemption failed. Please try again.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        action: success
                            ? SnackBarAction(
                                label: 'View',
                                onPressed: () => context.push('/my-redemptions'),
                              )
                            : null,
                      ),
                    );
                  }
                },
                child: const Text('Redeem'),
              ),
            ],
          ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final String title;
  final String discount;
  final String cost;
  final bool canAfford;
  final bool redeemed;
  final VoidCallback onRedeem;

  const _CouponCard({
    required this.title,
    required this.discount,
    required this.cost,
    required this.canAfford,
    required this.onRedeem,
    this.redeemed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: canAfford ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: canAfford ? onRedeem : null,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.warmCoral.withValues(alpha: 0.2),
                AppColors.warmCoral.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: AppColors.warmCoral.withValues(alpha: 0.4),
            ),
            borderRadius: AppRadius.borderRadiusXL,
          ),
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Text(
                    discount,
                    style: AppTypography.displaySmall.copyWith(
                      color: AppColors.warmCoral,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    cost,
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          canAfford ? AppColors.warmCoral : colorScheme.outline,
                      borderRadius: AppRadius.buttonRadius,
                    ),
                    child: Text(
                      redeemed
                          ? 'Redeemed ✓'
                          : canAfford
                          ? 'Redeem'
                          : 'Need more pts',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
