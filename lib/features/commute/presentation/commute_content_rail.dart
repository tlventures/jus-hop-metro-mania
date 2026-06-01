import 'package:flutter/material.dart';

import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';

class CommuteContentRail extends StatelessWidget {
  final int estimatedMinutes;

  const CommuteContentRail({required this.estimatedMinutes, super.key});

  @override
  Widget build(BuildContext context) {
    final items = _itemsForDuration(estimatedMinutes);
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s3),
        itemBuilder: (context, index) => _ContentCard(item: items[index]),
      ),
    );
  }

  List<_CommuteContentItem> _itemsForDuration(int minutes) {
    if (minutes >= 30) {
      return const [
        _CommuteContentItem('📚', 'Story chapter', '12 min'),
        _CommuteContentItem('📖', 'City explorer', '8 min'),
        _CommuteContentItem('🔢', 'Sudoku', '10 min'),
      ];
    }
    if (minutes >= 15) {
      return const [
        _CommuteContentItem('📚', 'Story chapter', '12 min'),
        _CommuteContentItem('🔢', 'Sudoku', '10 min'),
      ];
    }
    if (minutes >= 5) {
      return const [
        _CommuteContentItem('🧠', 'Trivia sprint', '5 min'),
        _CommuteContentItem('📖', 'Quick article', '7 min'),
      ];
    }
    return const [
      _CommuteContentItem('🧠', '3-question trivia', '2 min'),
      _CommuteContentItem('🔥', 'Streak claim', '1 min'),
    ];
  }
}

class _CommuteContentItem {
  final String icon;
  final String title;
  final String duration;

  const _CommuteContentItem(this.icon, this.title, this.duration);
}

class _ContentCard extends StatelessWidget {
  final _CommuteContentItem item;

  const _ContentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 142,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 28)),
          const Spacer(),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            item.duration,
            style: AppTypography.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
