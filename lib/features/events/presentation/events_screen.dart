import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/events/application/events_provider.dart';
import 'package:metrosafar/services/backend_service.dart';
import 'package:metrosafar/services/realtime_service.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure WS connection is alive while this screen is shown.
    ref.watch(realtimeServiceProvider);
    final schedule = ref.watch(eventsScheduleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Live Events')),
      body: schedule.when(
        data: (events) => ListView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          children: [
            _HeroBanner(),
            const SizedBox(height: AppSpacing.s6),
            ...events
                .take(10)
                .map((event) => _EventCard(event: event)),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load events')),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.warmCoral, AppColors.goldPoints],
        ),
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Events',
            style: AppTypography.titleLarge.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Join in real time. Answer questions before the timer runs out and climb the leaderboard.',
            style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event card — shows live question flow with real answer selection
// ---------------------------------------------------------------------------

enum _CardPhase { idle, joining, lobby, question, answered, error }

class _EventCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  _CardPhase _phase = _CardPhase.idle;
  String? _errorMessage;

  // Question state
  Map<String, dynamic>? _currentQuestion;
  int? _selectedAnswer;
  bool _answered = false;
  Map<String, dynamic>? _answerResult;

  // Server-driven countdown (uses serverTimeMs + deadlineMs, never client clock)
  int _secondsLeft = 0;
  Timer? _countdownTimer;

  // WS subscription
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  String get _eventId => widget.event['id'] as String;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _wsSub?.cancel();
    ref.read(realtimeServiceProvider).unsubscribeFromEvent(_eventId);
    super.dispose();
  }

  // ----- Actions -----

  Future<void> _joinEvent() async {
    setState(() => _phase = _CardPhase.joining);
    try {
      final backend = BackendService();
      await backend.joinEvent(_eventId);

      // Cancel any existing subscription before creating a new one.
      await _wsSub?.cancel();
      _wsSub = null;

      // Subscribe to WS room so server can push questions.
      final realtime = ref.read(realtimeServiceProvider);
      realtime.subscribeToEvent(_eventId);
      _wsSub = realtime.eventQuestions().listen(_onQuestionPushed);

      // Fetch current state — server may have already pushed a question.
      final detail = await backend.getEvent(_eventId);
      final questions = detail['questions'] as List<dynamic>? ?? [];

      if (questions.isNotEmpty) {
        final q = Map<String, dynamic>.from(questions.first as Map);
        _startQuestion(q, detail['serverTimeMs'] as int?, detail['deadlineMs'] as int?);
      } else {
        setState(() => _phase = _CardPhase.lobby);
      }
    } catch (e) {
      setState(() {
        _phase = _CardPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _onQuestionPushed(Map<String, dynamic> payload) {
    if (!mounted) return;
    _startQuestion(
      payload,
      payload['serverTimeMs'] as int?,
      payload['deadlineMs'] as int?,
    );
  }

  void _startQuestion(
    Map<String, dynamic> question,
    int? serverTimeMs,
    int? deadlineMs,
  ) {
    _countdownTimer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Lock-step: always derive remaining time from server timestamps.
    int remaining = 20;
    if (serverTimeMs != null && deadlineMs != null) {
      remaining = ((deadlineMs - serverTimeMs) / 1000).ceil();
      // Adjust for latency by subtracting elapsed since server sent the msg.
      final elapsed = ((now - serverTimeMs) / 1000).floor();
      remaining = (remaining - elapsed).clamp(0, 60);
    }

    setState(() {
      _phase = _CardPhase.question;
      _currentQuestion = question;
      _selectedAnswer = null;
      _answered = false;
      _answerResult = null;
      _secondsLeft = remaining;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_answered) {
          setState(() => _answered = true); // timed out
        }
      }
    });
  }

  Future<void> _submitAnswer(int answerIndex) async {
    if (_answered || _currentQuestion == null) return;
    _countdownTimer?.cancel();
    setState(() {
      _selectedAnswer = answerIndex;
      _answered = true;
    });
    try {
      final result = await BackendService().submitEventAnswer(
        eventId: _eventId,
        questionId: _currentQuestion!['id'] as String,
        answer: answerIndex,
      );
      if (mounted) setState(() => _answerResult = result);
    } catch (_) {
      // Non-critical — answer may have been queued offline.
    }
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scheduled = DateTime.tryParse(
      widget.event['scheduledFor'] as String? ?? '',
    );
    final timeLabel = scheduled == null
        ? 'Scheduled soon'
        : '${scheduled.day}/${scheduled.month} '
            '${scheduled.hour.toString().padLeft(2, '0')}:'
            '${scheduled.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.event['title'] as String? ?? 'Live Event',
                  style: AppTypography.titleMedium
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              _StatusChip(status: widget.event['status'] as String? ?? 'scheduled'),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            timeLabel,
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s4),
          _buildBody(colorScheme),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    switch (_phase) {
      case _CardPhase.idle:
        return FilledButton(
          onPressed: _joinEvent,
          child: const Text('Join Event'),
        );

      case _CardPhase.joining:
        return const Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: AppSpacing.s3),
          Text('Joining…'),
        ]);

      case _CardPhase.lobby:
        return Text(
          'You\'re in the lobby — waiting for host to start.',
          style: AppTypography.bodyMedium
              .copyWith(color: colorScheme.onSurfaceVariant),
        );

      case _CardPhase.question:
        return _QuestionView(
          question: _currentQuestion!,
          secondsLeft: _secondsLeft,
          selectedAnswer: _selectedAnswer,
          answered: _answered,
          answerResult: _answerResult,
          onSelect: _submitAnswer,
        );

      case _CardPhase.answered:
        return const Text('Answers submitted — check leaderboard!');

      case _CardPhase.error:
        return Text(
          _errorMessage ?? 'Something went wrong.',
          style: AppTypography.bodySmall
              .copyWith(color: colorScheme.error),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Question view widget
// ---------------------------------------------------------------------------

class _QuestionView extends StatelessWidget {
  final Map<String, dynamic> question;
  final int secondsLeft;
  final int? selectedAnswer;
  final bool answered;
  final Map<String, dynamic>? answerResult;
  final void Function(int) onSelect;

  const _QuestionView({
    required this.question,
    required this.secondsLeft,
    required this.selectedAnswer,
    required this.answered,
    required this.answerResult,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = (question['options'] as List<dynamic>? ?? [])
        .map((o) => o as String)
        .toList();
    final correctIndex = question['correctIndex'] as int?;
    final pts = answerResult?['pointsAwarded'] as int?;
    final timedOut = answered && selectedAnswer == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                question['prompt'] as String? ?? '',
                style: AppTypography.titleSmall
                    .copyWith(color: colorScheme.onSurface),
              ),
            ),
            if (!answered) _CountdownBadge(seconds: secondsLeft),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        ...options.asMap().entries.map((entry) {
          final idx = entry.key;
          final label = entry.value;
          final isSelected = selectedAnswer == idx;
          final isCorrect = correctIndex != null && idx == correctIndex;
          final showResult = answered && correctIndex != null;

          Color? tileColor;
          if (showResult) {
            if (isCorrect) {
              tileColor = Colors.green.shade100;
            } else if (isSelected) {
              tileColor = Colors.red.shade100;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Material(
              color: tileColor ?? colorScheme.surface,
              borderRadius: AppRadius.borderRadiusL,
              child: InkWell(
                onTap: answered ? null : () => onSelect(idx),
                borderRadius: AppRadius.borderRadiusL,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (showResult && isCorrect)
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      if (showResult && isSelected && !isCorrect)
                        const Icon(Icons.cancel, color: Colors.red, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        if (answered) ...[
          const SizedBox(height: AppSpacing.s3),
          if (timedOut)
            Text(
              'Time\'s up! No answer submitted.',
              style: AppTypography.bodySmall
                  .copyWith(color: colorScheme.onSurfaceVariant),
            )
          else if (pts != null)
            Text(
              pts > 0 ? '+$pts pts earned!' : 'Incorrect — better luck next question!',
              style: AppTypography.bodyMedium.copyWith(
                color: pts > 0 ? Colors.green : colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final color = seconds > 10
        ? AppColors.goldPoints
        : seconds > 5
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.borderRadiusM,
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        '${seconds}s',
        style: AppTypography.labelMedium.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'live' => ('● LIVE', AppColors.warmCoral),
      'lobby_open' => ('Lobby open', AppColors.goldPoints),
      'ended' => ('Ended', Colors.grey),
      'settled' => ('Settled', Colors.grey),
      _ => ('Scheduled', AppColors.metroIndigo),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusM,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}
