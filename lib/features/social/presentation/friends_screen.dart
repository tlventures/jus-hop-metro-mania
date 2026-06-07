import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/city/current_city_provider.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/social_provider.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() {
    final cityId = ref.read(activeCityProvider)?.id;
    return ref.read(socialProvider.notifier).load(cityId: cityId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final resetText =
        state.resetsAt == null
            ? 'Resets Monday'
            : 'Resets in ${state.resetsAt!.difference(DateTime.now()).inDays.clamp(0, 7)}d';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Leaderboard'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.s6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: AppRadius.borderRadiusXL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This Week',
                    style: AppTypography.headlineSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    resetText,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(socialProvider.notifier).createInvite();
                      final message = ref.read(socialProvider).inviteMessage;
                      if (message != null) {
                        SharePlus.instance.share(
                          ShareParams(
                            text: message,
                            subject: 'Beat me on MetroSafar',
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Invite Friends'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            _AddFriendCard(
              controller: _codeController,
              isLoading: state.isLoading,
              onAdd: () async {
                final code = _codeController.text.trim();
                if (code.isEmpty) return;
                final ok = await ref
                    .read(socialProvider.notifier)
                    .addByCode(code, cityId: ref.read(activeCityProvider)?.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Friend added' : 'Could not add friend'),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'Friends',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            if (state.weekly.isEmpty)
              _EmptyFriendsCard(
                onInvite: () async {
                  await ref.read(socialProvider.notifier).createInvite();
                  final message = ref.read(socialProvider).inviteMessage;
                  if (message != null) {
                    SharePlus.instance.share(ShareParams(text: message));
                  }
                },
              )
            else
              ...state.weekly.map((entry) => _LeaderboardRow(entry: entry)),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'City Top 10',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            if (state.cityTop.isEmpty)
              Text(
                'City rankings will fill in as people earn points this week.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...state.cityTop.map((entry) => _LeaderboardRow(entry: entry)),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(state.error!, style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddFriendCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onAdd;

  const _AddFriendCard({
    required this.controller,
    required this.isLoading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add by referral code',
            style: AppTypography.labelLarge.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'METRO-XK9F2',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isLoading ? null : onAdd,
              child: const Text('Add Friend'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFriendsCard extends StatelessWidget {
  final VoidCallback onInvite;

  const _EmptyFriendsCard({required this.onInvite});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        children: [
          const Text('🏁', style: TextStyle(fontSize: 40)),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'No friends yet',
            style: AppTypography.titleMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Invite commuters you know and make the weekly leaderboard personal.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          OutlinedButton(onPressed: onInvite, child: const Text('Invite now')),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final FriendEntry entry;

  const _LeaderboardRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final medal = switch (entry.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '${entry.rank}',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s2),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color:
            entry.isYou
                ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                : colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              medal,
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Text(
              entry.isYou ? 'You' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colorScheme.onSurface,
                fontWeight: entry.isYou ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${entry.points} pts',
            style: AppTypography.labelLarge.copyWith(
              color:
                  entry.isYou
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
