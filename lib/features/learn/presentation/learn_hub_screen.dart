import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../application/articles_provider.dart';
import '../application/surveys_provider.dart';
import '../application/stories_provider.dart';
import 'articles_screen.dart';
import 'surveys_screen.dart';
import 'stories_screen.dart';

class LearnHubScreen extends ConsumerStatefulWidget {
  /// Optional deep-link target: 'articles' | 'surveys' | 'stories'. When set,
  /// the matching sub-screen is opened immediately (so the Home quick-actions
  /// land on the right content instead of all on the hub).
  final String? initialSection;

  const LearnHubScreen({super.key, this.initialSection});

  @override
  ConsumerState<LearnHubScreen> createState() => _LearnHubScreenState();
}

class _LearnHubScreenState extends ConsumerState<LearnHubScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(articlesProvider.notifier).fetchArticles();
      ref.read(surveysProvider.notifier).fetchSurveys();
      ref.read(storiesProvider.notifier).fetchStories();
    });
    _openInitialSection();
  }

  void _openInitialSection() {
    final section = widget.initialSection;
    if (section == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Widget? target = switch (section) {
        'articles' => const ArticlesScreen(),
        'surveys' => const SurveysScreen(),
        'stories' => const StoriesScreen(),
        _ => null,
      };
      if (target != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final articles = ref.watch(articlesProvider);
    final surveys = ref.watch(surveysProvider);
    final stories = ref.watch(storiesProvider);

    // City-aware copy for Story tile
    final city     = ref.watch(activeCityProvider);
    final locale   = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? 'your city';
    final cityIdentity = city?.signature.identity;
    final storyDescription = cityIdentity != null && cityIdentity.isNotEmpty
        ? 'Explore the rich history of $cityName — $cityIdentity'
        : 'Explore the rich history of $cityName';

    final readArticles = ref.watch(readArticlesProvider);
    final completedSurveys = ref.watch(completedSurveysProvider);
    final completedStories = ref.watch(completedStoriesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              'Learn & Grow',
              style: AppTypography.headlineMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s6, AppSpacing.s6, AppSpacing.s6, AppSpacing.s6 + 80,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total content banner
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gradientStart,
                          AppColors.gradientEnd,
                        ],
                      ),
                      borderRadius: AppRadius.borderRadiusXL,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Learning Progress',
                              style: AppTypography.bodySmall.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              '${readArticles + completedSurveys + completedStories} items',
                              style: AppTypography.displayMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '📚',
                          style: AppTypography.displayLarge,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s8),

                  // Content title
                  Text(
                    'Content Library',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),

                  // Articles card
                  _ContentCard(
                    icon: '📖',
                    title: 'Articles',
                    description: 'Read about metro, sustainability, and more',
                    completed: readArticles,
                    total: articles.length,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ArticlesScreen()),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s4),

                  // Surveys card
                  _ContentCard(
                    icon: '📋',
                    title: 'Surveys',
                    description: 'Share your feedback and earn rewards',
                    completed: completedSurveys,
                    total: surveys.length,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SurveysScreen()),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s4),

                  // Stories card
                  _ContentCard(
                    icon: '📚',
                    title: 'Station Stories',
                    description: storyDescription,
                    completed: completedStories,
                    total: stories.length,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StoriesScreen()),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final String icon;
  final String title;
  final String description;
  final int completed;
  final int total;
  final VoidCallback onTap;

  const _ContentCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.completed,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusXL,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(icon, style: const TextStyle(fontSize: 48)),
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
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        description,
                        style: AppTypography.bodySmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$completed/$total completed',
                  style: AppTypography.labelSmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
                    child: ClipRRect(
                      borderRadius: AppRadius.borderRadiusS,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: AppTypography.labelSmall.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
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
