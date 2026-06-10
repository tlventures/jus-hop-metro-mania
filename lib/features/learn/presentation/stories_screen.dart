import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/stories_provider.dart';

class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key});

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(storiesProvider.notifier).fetchStories();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stories = ref.watch(storiesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final completedCount = ref.watch(completedStoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Station Stories',
          style: AppTypography.headlineMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : stories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📚', style: AppTypography.displayLarge),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'No stories yet for your city',
                      textAlign: TextAlign.center,
                      style: AppTypography.titleMedium
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      'Station stories are coming soon — check back later.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
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
                            color: colorScheme.tertiary.withValues(alpha: 0.1),
                            borderRadius: AppRadius.borderRadiusL,
                            border: Border.all(
                              color: colorScheme.tertiary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📖 Stories Completed',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$completedCount/${stories.length}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.tertiary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s3),
                              ClipRRect(
                                borderRadius: AppRadius.borderRadiusS,
                                child: LinearProgressIndicator(
                                  value: stories.isEmpty ? 0.0 : completedCount / stories.length,
                                  minHeight: 8,
                                  backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
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
                        final story = stories[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                          child: _StoryCard(
                            story: story,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _StoryDetail(story: story),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: stories.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s6)),
              ],
            ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final dynamic story;
  final VoidCallback onTap;

  const _StoryCard({
    required this.story,
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
        child: Row(
          children: [
            Text(
              story.imageUrl ?? '📖',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.stationName,
                    style: AppTypography.labelLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    story.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Row(
                    children: [
                      Text(
                        '📚 ${story.frames.length} chapters',
                        style: AppTypography.labelSmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Text(
                        '⭐ +${story.points} pts',
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
            if (story.isCompleted)
              Container(
                padding: const EdgeInsets.all(AppSpacing.s1),
                decoration: BoxDecoration(
                  color: Colors.green,
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
      ),
    );
  }
}

class _StoryDetail extends ConsumerStatefulWidget {
  final dynamic story;

  const _StoryDetail({required this.story});

  @override
  ConsumerState<_StoryDetail> createState() => _StoryDetailState();
}

class _StoryDetailState extends ConsumerState<_StoryDetail> {
  late int currentFrameIndex;

  @override
  void initState() {
    super.initState();
    currentFrameIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final frames = widget.story.frames as List<dynamic>;
    final currentFrame = frames[currentFrameIndex];
    final isLastFrame = currentFrameIndex == frames.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.story.stationName,
          style: AppTypography.headlineMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chapter indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chapter ${currentFrameIndex + 1} of ${frames.length}',
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${((currentFrameIndex + 1) / frames.length * 100).toInt()}%',
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              ClipRRect(
                borderRadius: AppRadius.borderRadiusS,
                child: LinearProgressIndicator(
                  value: (currentFrameIndex + 1) / frames.length,
                  minHeight: 6,
                  backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),

              // Frame content
              Center(
                child: Text(
                  currentFrame.imageUrl ?? '📖',
                  style: const TextStyle(fontSize: 100),
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              Text(
                currentFrame.title,
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              Text(
                currentFrame.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),

              // Navigation buttons
              Row(
                children: [
                  if (currentFrameIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => currentFrameIndex--);
                        },
                        child: const Text('← Previous'),
                      ),
                    ),
                  if (currentFrameIndex > 0) const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (isLastFrame) {
                          ref.read(storiesProvider.notifier).completeStory(widget.story.id);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Story completed! +${widget.story.points} points'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } else {
                          setState(() => currentFrameIndex++);
                        }
                      },
                      child: Text(isLastFrame ? 'Finish Story ✓' : 'Next →'),
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
