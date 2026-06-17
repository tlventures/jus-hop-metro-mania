import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../wallet/application/wallet_provider.dart';
import '../../learn/application/articles_provider.dart';
import '../../learn/application/surveys_provider.dart';
import '../../learn/application/stories_provider.dart';
import '../../home/application/streak_provider.dart';
import '../../../services/backend_service.dart';
import '../../../services/user_display_name.dart';
import '../../auth/auth_actions.dart';

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final svc = BackendService();
  final data = await svc.getProfile();
  return data['profile'] as Map<String, dynamic>? ?? data;
});

/// Identity + activity only. Preferences, legal and account actions now live
/// in the dedicated Settings page (gear icon in the Home app bar → /settings).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(profileProvider);
    final wallet = ref.watch(walletProvider);
    final streak = ref.watch(streakProvider);
    final articlesRead = ref.watch(readArticlesProvider);
    final surveysCompleted = ref.watch(completedSurveysProvider);
    final storiesCompleted = ref.watch(completedStoriesProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          await ref.read(profileProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              'Profile',
              style: AppTypography.headlineMedium.copyWith(color: colorScheme.onSurface),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final firebaseUser = FirebaseAuth.instance.currentUser;
                      return profileAsync.when(
                        loading: () => _UserHero(
                          name: UserDisplayName.name(firebaseUser: firebaseUser, profile: null),
                          email: UserDisplayName.email(firebaseUser: firebaseUser, profile: null),
                          tier: wallet.tier,
                          points: wallet.points,
                        ),
                        error: (_, __) => _UserHero(
                          name: UserDisplayName.name(firebaseUser: firebaseUser, profile: null),
                          email: UserDisplayName.email(firebaseUser: firebaseUser, profile: null),
                          tier: wallet.tier,
                          points: wallet.points,
                        ),
                        data: (profile) => _UserHero(
                          name: UserDisplayName.name(firebaseUser: firebaseUser, profile: profile),
                          email: UserDisplayName.email(firebaseUser: firebaseUser, profile: profile),
                          tier: wallet.tier,
                          points: wallet.points,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text('Your Activity',
                      style: AppTypography.titleMedium.copyWith(color: colorScheme.onSurface)),
                  const SizedBox(height: AppSpacing.s4),
                  Row(
                    children: [
                      Expanded(child: _StatCard(icon: '🔥', value: '${streak.currentDay}', label: 'Day Streak')),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(child: _StatCard(icon: '📖', value: '$articlesRead', label: 'Articles Read')),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(child: _StatCard(icon: '📋', value: '$surveysCompleted', label: 'Surveys Done')),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(child: _StatCard(icon: '📚', value: '$storiesCompleted', label: 'Stories Read')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  // Pointer to the dedicated Settings page.
                  GestureDetector(
                    onTap: () => context.push('/settings'),
                    child: _SettingsHintRow(colorScheme: colorScheme),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  // Quick logout — discoverable here, not only buried in Settings.
                  OutlinedButton.icon(
                    onPressed: () => signOutAndReturnToLogin(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6 + 80),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SettingsHintRow extends StatelessWidget {
  final ColorScheme colorScheme;
  const _SettingsHintRow({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Text('Settings, legal & account',
                style: AppTypography.labelLarge.copyWith(
                    color: colorScheme.onSurface, fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _UserHero extends StatelessWidget {
  final String name;
  final String email;
  final String tier;
  final int points;

  const _UserHero({
    required this.name,
    required this.email,
    required this.tier,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final tierEmoji = switch (tier.toLowerCase()) {
      'platinum' => '💎',
      'gold' => '🥇',
      'silver' => '🥈',
      _ => '🥉',
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.gradientStart, AppColors.gradientEnd]),
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: Center(
              child: Text(
                UserDisplayName.initial(name),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                if (email.isNotEmpty)
                  Text(email,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(color: Colors.white70)),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3, vertical: AppSpacing.s1),
                      decoration: BoxDecoration(
                          color: Colors.white24, borderRadius: AppRadius.borderRadiusFull),
                      child: Text('$tierEmoji $tier',
                          style: AppTypography.labelSmall.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Text('$points pts',
                        style: AppTypography.labelSmall.copyWith(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _StatCard({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: AppSpacing.s1),
          Text(value,
              style: AppTypography.titleMedium.copyWith(
                  color: colorScheme.onSurface, fontWeight: FontWeight.w700)),
          Text(label,
              style: AppTypography.labelSmall.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
