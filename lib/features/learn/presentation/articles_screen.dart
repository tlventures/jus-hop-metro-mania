import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/articles_provider.dart';

class ArticlesScreen extends ConsumerStatefulWidget {
  const ArticlesScreen({super.key});

  @override
  ConsumerState<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends ConsumerState<ArticlesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(articlesProvider.notifier).fetchArticles(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(articlesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final readCount = ref.watch(readArticlesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Articles',
          style: AppTypography.headlineMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: articles.isEmpty
          ? Center(
              child: CircularProgressIndicator(),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Progress indicator
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.s4),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: AppRadius.borderRadiusL,
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📖 Articles Read',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$readCount/${articles.length}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s3),
                              ClipRRect(
                                borderRadius: AppRadius.borderRadiusS,
                                child: LinearProgressIndicator(
                                  value: articles.isEmpty ? 0.0 : readCount / articles.length,
                                  minHeight: 8,
                                  backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final article = articles[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                          child: _ArticleCard(
                            article: article,
                            onTap: () => _showArticleDetail(context, article),
                          ),
                        );
                      },
                      childCount: articles.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s6)),
              ],
            ),
    );
  }

  void _showArticleDetail(BuildContext context, dynamic article) {
    ref.read(articlesProvider.notifier).markArticleRead(article.id);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      builder: (context) => _ArticleDetail(article: article),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final dynamic article;
  final VoidCallback onTap;

  const _ArticleCard({
    required this.article,
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
                Text(
                  article.coverUrl ?? '📄',
                  style: const TextStyle(fontSize: 48),
                ),
                const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Row(
                        children: [
                          Text(
                            '⏱️ ${article.readTimeMinutes} min',
                            style: AppTypography.labelSmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Text(
                            '⭐ +${article.points} pts',
                            style: AppTypography.labelSmall.copyWith(
                              color: const Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (article.isRead)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s1),
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '✓',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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

class _ArticleDetail extends ConsumerWidget {
  final dynamic article;

  const _ArticleDetail({required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Text(
                article.coverUrl ?? '📄',
                style: const TextStyle(fontSize: 80),
              ),
            ),
            const SizedBox(height: AppSpacing.s6),

            Text(
              article.title,
              style: AppTypography.headlineSmall.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),

            // Meta info
            Row(
              children: [
                Text(
                  '⏱️ ${article.readTimeMinutes} min read',
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  '⭐ +${article.points} pts',
                  style: AppTypography.bodySmall.copyWith(
                    color: const Color(0xFFF59E0B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),

            // Content
            Text(
              article.body,
              style: AppTypography.bodyMedium.copyWith(
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),

            // CTA
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done Reading'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
