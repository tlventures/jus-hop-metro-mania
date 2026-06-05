import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/colors.dart';
import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';
import '../../application/user_preferences_provider.dart';
import '../../domain/user_preferences.dart';

/// Post-signup interest-selection flow.
///
/// Steps:
///   0 — What content do you enjoy?       (ContentType, multi-select)
///   1 — What kind of games? [conditional] (GameGenre, multi-select)
///   2 — What topics excite you?           (ContentTopic, multi-select)
///   3 — All set! (summary + CTA)
class InterestsScreen extends ConsumerStatefulWidget {
  const InterestsScreen({super.key});

  @override
  ConsumerState<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends ConsumerState<InterestsScreen> {
  int _step = 0;
  late final PageController _pageCtrl;
  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // Returns the ordered list of active step indices based on selections.
  List<int> _activeSteps(UserPreferences prefs) {
    // step 0: content type (always)
    // step 1: game genres (only if games selected)
    // step 2: topics (always)
    // step 3: summary (always)
    return [0, if (prefs.contentTypes.contains('games')) 1, 2, 3];
  }

  int _totalSteps(UserPreferences prefs) => _activeSteps(prefs).length;

  void _next(UserPreferences prefs) {
    final steps = _activeSteps(prefs);
    final currentIndex = steps.indexOf(_step);
    if (currentIndex < steps.length - 1) {
      final nextStep = steps[currentIndex + 1];
      _pageCtrl.animateToPage(
        nextStep,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
      setState(() => _step = nextStep);
    }
  }

  void _back(UserPreferences prefs) {
    final steps = _activeSteps(prefs);
    final currentIndex = steps.indexOf(_step);
    if (currentIndex > 0) {
      final prevStep = steps[currentIndex - 1];
      _pageCtrl.animateToPage(
        prevStep,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
      setState(() => _step = prevStep);
    }
  }

  Future<void> _finish() async {
    await ref.read(userPreferencesProvider.notifier).save();
    if (mounted) context.go('/home');
  }

  void _skip() {
    ref.read(userPreferencesProvider.notifier).save();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPreferencesProvider);
    final cs = Theme.of(context).colorScheme;
    final steps = _activeSteps(prefs);
    final stepIndex = steps.indexOf(_step);
    final total = _totalSteps(prefs);
    final isLast = _step == 3;
    final canAdvance = _canAdvance(prefs);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, 0),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => _back(prefs),
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      'Skip',
                      style: AppTypography.labelLarge
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6, vertical: AppSpacing.s3),
              child: _StepProgress(
                current: stepIndex,
                total: total,
              ),
            ),

            // ── Page content ─────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Page 0 – content types
                  _SelectionPage(
                    emoji: '✨',
                    title: 'What do you love?',
                    subtitle:
                        'Pick everything you enjoy — we\'ll personalise your feed.',
                    options: ContentType.all,
                    selected: prefs.contentTypes,
                    onToggle: (key) => ref
                        .read(userPreferencesProvider.notifier)
                        .toggleContentType(key),
                  ),
                  // Page 1 – game genres (conditional; keep in PageView for
                  // smooth animation even when skipped)
                  _SelectionPage(
                    emoji: '🎮',
                    title: 'Pick your game style',
                    subtitle:
                        'Choose the kinds of games you\'d like during your commute.',
                    options: GameGenre.all,
                    selected: prefs.gameGenres,
                    onToggle: (key) => ref
                        .read(userPreferencesProvider.notifier)
                        .toggleGameGenre(key),
                  ),
                  // Page 2 – topics
                  _SelectionPage(
                    emoji: '📡',
                    title: 'Topics you care about',
                    subtitle:
                        'We\'ll surface stories, news and content that match your vibe.',
                    options: ContentTopic.all,
                    selected: prefs.topics,
                    onToggle: (key) => ref
                        .read(userPreferencesProvider.notifier)
                        .toggleTopic(key),
                  ),
                  // Page 3 – summary
                  _SummaryPage(prefs: prefs),
                ],
              ),
            ),

            // ── CTA button ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s6, AppSpacing.s4,
                  AppSpacing.s6, AppSpacing.s8),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: FilledButton(
                  onPressed: (!isLast && !canAdvance)
                      ? null
                      : isLast
                          ? _finish
                          : () => _next(prefs),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.borderRadiusXL),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLast ? 'Start exploring 🚀' : 'Continue',
                        style: AppTypography.labelLarge
                            .copyWith(color: cs.onPrimary),
                      ),
                      if (!isLast) ...[
                        const SizedBox(width: AppSpacing.s2),
                        Icon(Icons.arrow_forward_rounded,
                            size: 18, color: cs.onPrimary),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvance(UserPreferences prefs) {
    switch (_step) {
      case 0:
        return prefs.contentTypes.isNotEmpty;
      case 1:
        return prefs.gameGenres.isNotEmpty;
      case 2:
        return prefs.topics.isNotEmpty;
      default:
        return true;
    }
  }
}

// ─── Step progress dots ───────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final int current;
  final int total;
  const _StepProgress({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(total, (i) {
        final isActive = i == current;
        final isDone = i < current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            decoration: BoxDecoration(
              color: isDone || isActive ? cs.primary : cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Selection page ───────────────────────────────────────────────────────────

class _SelectionPage extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final List<InterestOption> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _SelectionPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s6, AppSpacing.s4, AppSpacing.s6, AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.s4),
          Text(title, style: AppTypography.displaySmall),
          const SizedBox(height: AppSpacing.s2),
          Text(subtitle,
              style: AppTypography.bodyMedium
                  .copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.s6),
          // Grid of option cards
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.s3,
              mainAxisSpacing: AppSpacing.s3,
              childAspectRatio: 1.55,
            ),
            itemCount: options.length,
            itemBuilder: (context, i) {
              final opt = options[i];
              final isSelected = selected.contains(opt.key);
              return _OptionCard(
                option: opt,
                selected: isSelected,
                onTap: () => onToggle(opt.key),
              );
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          if (selected.isEmpty)
            Center(
              child: Text(
                'Select at least one to continue',
                style: AppTypography.bodySmall
                    .copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Option card ──────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final InterestOption option;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusXL,
        border: Border.all(
          color: selected ? cs.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusXL,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(option.emoji,
                      style: const TextStyle(fontSize: 26)),
                  const Spacer(),
                  if (selected)
                    AnimatedScale(
                      scale: selected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 14, color: cs.onPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                option.label,
                style: AppTypography.titleSmall.copyWith(
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                option.description,
                style: AppTypography.bodySmall.copyWith(
                  color: selected
                      ? cs.onPrimaryContainer.withValues(alpha: 0.75)
                      : cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Summary page ─────────────────────────────────────────────────────────────

class _SummaryPage extends StatelessWidget {
  final UserPreferences prefs;
  const _SummaryPage({required this.prefs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Collect friendly labels for everything selected.
    final contentLabels = ContentType.all
        .where((o) => prefs.contentTypes.contains(o.key))
        .map((o) => '${o.emoji} ${o.label}')
        .toList();
    final gameLabels = GameGenre.all
        .where((o) => prefs.gameGenres.contains(o.key))
        .map((o) => '${o.emoji} ${o.label}')
        .toList();
    final topicLabels = ContentTopic.all
        .where((o) => prefs.topics.contains(o.key))
        .map((o) => '${o.emoji} ${o.label}')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s6, AppSpacing.s4, AppSpacing.s6, AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Celebration header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: AppRadius.borderRadiusXXL,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 48)),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Your feed is ready!',
                  style: AppTypography.displaySmall
                      .copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  'We\'ve tailored MetroSafar just for you. '
                  'Your commute just got a whole lot better.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s6),

          // Summary chips
          if (contentLabels.isNotEmpty) ...[
            _SummarySection(
                title: 'Content you enjoy', chips: contentLabels),
            const SizedBox(height: AppSpacing.s5),
          ],
          if (gameLabels.isNotEmpty) ...[
            _SummarySection(title: 'Game styles', chips: gameLabels),
            const SizedBox(height: AppSpacing.s5),
          ],
          if (topicLabels.isNotEmpty) ...[
            _SummarySection(title: 'Your topics', chips: topicLabels),
            const SizedBox(height: AppSpacing.s5),
          ],

          // Edit hint
          Container(
            padding: const EdgeInsets.all(AppSpacing.s4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: AppRadius.borderRadiusL,
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Text(
                    'You can update your interests anytime in Profile → Settings.',
                    style: AppTypography.bodySmall
                        .copyWith(color: cs.onSurfaceVariant),
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

class _SummarySection extends StatelessWidget {
  final String title;
  final List<String> chips;
  const _SummarySection({required this.title, required this.chips});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppTypography.titleSmall
                .copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.s3),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: chips
              .map(
                (label) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: AppRadius.borderRadiusXXL,
                  ),
                  child: Text(
                    label,
                    style: AppTypography.labelMedium
                        .copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
