import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/surveys_provider.dart';

class SurveysScreen extends ConsumerStatefulWidget {
  const SurveysScreen({super.key});

  @override
  ConsumerState<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends ConsumerState<SurveysScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(surveysProvider.notifier).fetchSurveys(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surveys = ref.watch(surveysProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final completedCount = ref.watch(completedSurveysProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Surveys',
          style: AppTypography.headlineMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: surveys.isEmpty
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
                            color: colorScheme.secondary.withValues(alpha: 0.1),
                            borderRadius: AppRadius.borderRadiusL,
                            border: Border.all(
                              color: colorScheme.secondary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📋 Surveys Completed',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$completedCount/${surveys.length}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.secondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s3),
                              ClipRRect(
                                borderRadius: AppRadius.borderRadiusS,
                                child: LinearProgressIndicator(
                                  value: surveys.isEmpty ? 0.0 : completedCount / surveys.length,
                                  minHeight: 8,
                                  backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation(colorScheme.secondary),
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
                        final survey = surveys[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                          child: _SurveyCard(
                            survey: survey,
                            onTap: () => _showSurveyDialog(context, survey),
                          ),
                        );
                      },
                      childCount: surveys.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s6)),
              ],
            ),
    );
  }

  void _showSurveyDialog(BuildContext context, dynamic survey) {
    showDialog(
      context: context,
      builder: (context) => _SurveyDialog(survey: survey),
    );
  }
}

class _SurveyCard extends StatelessWidget {
  final dynamic survey;
  final VoidCallback onTap;

  const _SurveyCard({
    required this.survey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: survey.isCompleted ? null : onTap,
      child: Opacity(
        opacity: survey.isCompleted ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusL,
            border: Border.all(
              color: survey.isCompleted
                  ? colorScheme.outline.withValues(alpha: 0.5)
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📋',
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          survey.question,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          '⭐ +${survey.points} pts',
                          style: AppTypography.labelSmall.copyWith(
                            color: const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (survey.isCompleted)
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
                          fontSize: 12,
                        ),
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

class _SurveyDialog extends ConsumerWidget {
  final dynamic survey;

  const _SurveyDialog({required this.survey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              survey.question,
              style: AppTypography.headlineSmall.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            ...survey.options.map((rawOption) {
              final option = rawOption as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                child: GestureDetector(
                  onTap: () {
                    ref.read(surveysProvider.notifier).submitSurvey(survey.id, option);
                    Navigator.pop(context);
                    _showThankYou(context, survey.points);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.s4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: AppRadius.borderRadiusM,
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      option,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.s6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThankYou(BuildContext context, int points) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Thank you! You earned +$points points'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
