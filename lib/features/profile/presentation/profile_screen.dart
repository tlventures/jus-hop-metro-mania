import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../wallet/application/wallet_provider.dart';
import '../../learn/application/articles_provider.dart';
import '../../learn/application/surveys_provider.dart';
import '../../learn/application/stories_provider.dart';
import '../../home/application/streak_provider.dart';
import '../../../app/router.dart' show clearOnboardingFlag;
import '../../../services/backend_service.dart';
import '../../../services/user_display_name.dart';
import 'language_selector_screen.dart';

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final svc = BackendService();
  final data = await svc.getProfile();
  return data['profile'] as Map<String, dynamic>? ?? data;
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _notificationsEnabled = true;
  bool _digestEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _digestEnabled = prefs.getBool('digest_notifications_enabled') ?? true;
      });
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  Future<void> _toggleDigest(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('digest_notifications_enabled', value);
    if (mounted) setState(() => _digestEnabled = value);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final profile = ref.read(profileProvider).value;
    try {
      await BackendService().updateProfile(
        name: UserDisplayName.name(
          firebaseUser: firebaseUser,
          profile: profile,
        ),
        email: UserDisplayName.email(
          firebaseUser: firebaseUser,
          profile: profile,
        ),
        phone: (profile?['phone'] ?? '').toString(),
        notificationsEnabled: _notificationsEnabled,
        digestNotificationsEnabled: value,
      );
      ref.invalidate(profileProvider);
    } catch (e) {
      debugPrint('Digest preference sync failed: $e');
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    await clearOnboardingFlag();
    if (mounted) context.go('/login');
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Account'),
            content: const Text(
              'This will permanently delete your account, all points, streaks, and activity history. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BackendService().deleteAccount();
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      await clearOnboardingFlag();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
    }
  }

  void _showLegalDoc(String type, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LegalDocSheet(type: type, title: title),
    );
  }

  void _showSupport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final colorScheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support',
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Need help? Reach us at:',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              _SupportRow(
                icon: Icons.email_outlined,
                label: 'support@metrosafar.in',
              ),
              const SizedBox(height: AppSpacing.s2),
              _SupportRow(
                icon: Icons.access_time,
                label: 'Mon–Sat, 9 AM – 6 PM IST',
              ),
              const SizedBox(height: AppSpacing.s6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
            ],
          ),
        );
      },
    );
  }

  void _showDigestPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _WeeklyDigestSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(profileProvider);
    final wallet = ref.watch(walletProvider);
    final streak = ref.watch(streakProvider);
    final articlesRead = ref.watch(readArticlesProvider);
    final surveysCompleted = ref.watch(completedSurveysProvider);
    final storiesCompleted = ref.watch(completedStoriesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              'Profile',
              style: AppTypography.headlineMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User hero — show Firebase user data immediately, override with profile once loaded
                  Builder(
                    builder: (context) {
                      final firebaseUser = FirebaseAuth.instance.currentUser;
                      return profileAsync.when(
                        loading:
                            () => _UserHero(
                              name: UserDisplayName.name(
                                firebaseUser: firebaseUser,
                                profile: null,
                              ),
                              email: UserDisplayName.email(
                                firebaseUser: firebaseUser,
                                profile: null,
                              ),
                              tier: wallet.tier,
                              points: wallet.points,
                            ),
                        error:
                            (_, __) => _UserHero(
                              name: UserDisplayName.name(
                                firebaseUser: firebaseUser,
                                profile: null,
                              ),
                              email: UserDisplayName.email(
                                firebaseUser: firebaseUser,
                                profile: null,
                              ),
                              tier: wallet.tier,
                              points: wallet.points,
                            ),
                        data:
                            (profile) => _UserHero(
                              name: UserDisplayName.name(
                                firebaseUser: firebaseUser,
                                profile: profile,
                              ),
                              email: UserDisplayName.email(
                                firebaseUser: firebaseUser,
                                profile: profile,
                              ),
                              tier: wallet.tier,
                              points: wallet.points,
                            ),
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.s6),

                  // Stats row
                  Text(
                    'Your Activity',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: '🔥',
                          value: '${streak.currentDay}',
                          label: 'Day Streak',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: _StatCard(
                          icon: '📖',
                          value: '$articlesRead',
                          label: 'Articles Read',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: _StatCard(
                          icon: '📋',
                          value: '$surveysCompleted',
                          label: 'Surveys Done',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: _StatCard(
                          icon: '📚',
                          value: '$storiesCompleted',
                          label: 'Stories Read',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s8),

                  // Settings section
                  Text(
                    'Settings',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  _SettingsTile(
                    icon: '🌐',
                    title: 'Language',
                    subtitle: 'Change app language',
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LanguageSelectorScreen(),
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '🔔',
                    title: 'Notifications',
                    subtitle: 'Manage alerts and reminders',
                    trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '📊',
                    title: 'Weekly Digest',
                    subtitle: 'Sunday recap and next-week goal',
                    trailing: Switch(
                      value: _digestEnabled,
                      onChanged: _toggleDigest,
                    ),
                    onTap: _showDigestPreview,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '🏁',
                    title: 'Friend Leaderboard',
                    subtitle: 'Weekly ranking among people you know',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/friends'),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '🎁',
                    title: 'Invite & Referrals',
                    subtitle: 'Give 100 pts, earn 150 pts',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/referral'),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '🌙',
                    title: 'Dark Mode',
                    subtitle: 'Follows system setting',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Dark mode follows your device system setting',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.s8),

                  // Legal section
                  Text(
                    'Legal',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  _SettingsTile(
                    icon: '🔒',
                    title: 'Privacy Policy',
                    subtitle: 'How we use your data',
                    onTap: () => _showLegalDoc('privacy', 'Privacy Policy'),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '📄',
                    title: 'Terms of Service',
                    subtitle: 'Usage terms and conditions',
                    onTap: () => _showLegalDoc('terms', 'Terms of Service'),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '💬',
                    title: 'Support',
                    subtitle: 'Get help or report an issue',
                    onTap: _showSupport,
                  ),

                  const SizedBox(height: AppSpacing.s3),
                  _SettingsTile(
                    icon: '🚪',
                    title: 'Sign Out',
                    subtitle: 'Log out of your account',
                    onTap: _signOut,
                    trailing: const Icon(Icons.logout),
                  ),

                  const SizedBox(height: AppSpacing.s8),

                  // Danger zone
                  Text(
                    'Account',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  GestureDetector(
                    onTap: _confirmDeleteAccount,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: AppRadius.borderRadiusL,
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever_outlined,
                            color: colorScheme.error,
                            size: 24,
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delete Account',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Permanently remove your data',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colorScheme.error),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s8),

                  // App version — read at runtime so it never goes stale
                  Center(
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snap) {
                        final v = snap.data?.version ?? '';
                        final b = snap.data?.buildNumber ?? '';
                        final label = v.isEmpty
                            ? 'MetroSafar'
                            : 'MetroSafar v$v${b.isNotEmpty ? ' ($b)' : ''}';
                        return Text(
                          label,
                          style: AppTypography.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6 + 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SupportRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.s3),
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _LegalDocSheet extends StatefulWidget {
  final String type;
  final String title;

  const _LegalDocSheet({required this.type, required this.title});

  @override
  State<_LegalDocSheet> createState() => _LegalDocSheetState();
}

class _LegalDocSheetState extends State<_LegalDocSheet> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await BackendService().getLegalDocument(widget.type);
      if (mounted) {
        setState(() {
          _content =
              data['content'] as String? ??
              data['body'] as String? ??
              data['text'] as String? ??
              'Content unavailable.';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _content = 'Unable to load content. Please try again later.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            const SizedBox(height: AppSpacing.s3),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s6),
              child: Text(
                widget.title,
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s6,
                          vertical: AppSpacing.s2,
                        ),
                        child: Text(
                          _content ?? '',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.6,
                          ),
                        ),
                      ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.s6,
                AppSpacing.s4,
                AppSpacing.s6,
                AppSpacing.s6 + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeeklyDigestSheet extends StatelessWidget {
  const _WeeklyDigestSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6 + MediaQuery.of(context).padding.bottom,
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: BackendService().getWeeklyDigestPreview(),
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data ?? {};
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your MetroSafar Week',
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                snapshot.hasError
                    ? 'Digest preview is not available yet.'
                    : (data['notificationText'] ??
                            'Your weekly recap will appear here every Sunday.')
                        .toString(),
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s5),
              Row(
                children: [
                  Expanded(
                    child: _DigestMetric(
                      label: 'Games',
                      value: '${data['gamesPlayed'] ?? 0}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: _DigestMetric(
                      label: 'Articles',
                      value: '${data['articlesRead'] ?? 0}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: _DigestMetric(
                      label: 'Rank',
                      value:
                          data['weeklyRank'] == null
                              ? '--'
                              : '#${data['weeklyRank']}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Text(
                  'Goal for next week: ${data['nextRankTarget'] ?? 'Top 50'}',
                  style: AppTypography.labelLarge.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DigestMetric extends StatelessWidget {
  final String label;
  final String value;

  const _DigestMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
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
        gradient: LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                UserDisplayName.initial(name),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: AppRadius.borderRadiusFull,
                      ),
                      child: Text(
                        '$tierEmoji $tier',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Text(
                      '$points pts',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
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

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

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
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
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
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
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
            trailing ??
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
