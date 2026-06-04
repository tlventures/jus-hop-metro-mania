import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/compliance/minor_status.dart';
import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

/// DPDPA §9 compliant age-verification screen.
///
/// Uses three CupertinoPicker wheels (Day / Month / Year) with NO
/// pre-selected value — the user must actively scroll to their birthday.
/// There is no skip button.  Completing this screen stores the DOB via
/// [MinorStatus.setDob()] and routes to either:
///   • [onAdult]  — age ≥ 18, proceed normally
///   • [onMinor]  — age < 18, proceed to parental-consent flow
class AgeGateScreen extends StatefulWidget {
  final VoidCallback onAdult;
  final VoidCallback onMinor;
  final VoidCallback? onBack;

  const AgeGateScreen({
    required this.onAdult,
    required this.onMinor,
    this.onBack,
    super.key,
  });

  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  static const _minYear = 1920;

  final _now = DateTime.now();

  // Picker controllers
  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _yearCtrl;

  // Currently selected values (null = not yet set, forces scroll interaction)
  int? _day;
  int? _month;
  int? _year;

  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _dayCtrl   = FixedExtentScrollController();
    _monthCtrl = FixedExtentScrollController();
    _yearCtrl  = FixedExtentScrollController();
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm => _day != null && _month != null && _year != null;

  Future<void> _confirm() async {
    if (!_canConfirm || _confirming) return;
    setState(() => _confirming = true);

    final dob = DateTime(_year!, _month!, _day!);
    await MinorStatus.setDob(dob);

    if (!mounted) return;
    setState(() => _confirming = false);

    if (MinorStatus.isMinorCached) {
      widget.onMinor();
    } else {
      widget.onAdult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalYears = _now.year - _minYear + 1;

    return PopScope(
      canPop: false, // DPDPA: must complete age verification
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Your birthday',
                  style: AppTypography.headlineMedium.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  'We use your age to personalise your experience and comply with data protection laws.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.s6),

                // Three picker wheels
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: AppRadius.borderRadiusXL,
                  ),
                  child: Row(
                    children: [
                      // Day — item 0 is a "– –" sentinel; real days at 1–31
                      Expanded(
                        child: _LabelledPicker(
                          label: 'Day',
                          controller: _dayCtrl,
                          itemCount: 32,           // 1 sentinel + 31 days
                          labelBuilder: (i) => i == 0 ? '– –' : '$i',
                          onChanged: (i) => setState(() => _day = i == 0 ? null : i),
                        ),
                      ),
                      _divider(colorScheme),
                      // Month — item 0 is a "– –" sentinel; real months at 1–12
                      Expanded(
                        flex: 2,
                        child: _LabelledPicker(
                          label: 'Month',
                          controller: _monthCtrl,
                          itemCount: 13,           // 1 sentinel + 12 months
                          labelBuilder: (i) => i == 0 ? '– – –' : _monthName(i),
                          onChanged: (i) => setState(() => _month = i == 0 ? null : i),
                        ),
                      ),
                      _divider(colorScheme),
                      // Year — item 0 is a "– – – –" sentinel; real years follow
                      Expanded(
                        child: _LabelledPicker(
                          label: 'Year',
                          controller: _yearCtrl,
                          itemCount: totalYears + 1, // 1 sentinel + years
                          labelBuilder: (i) => i == 0 ? '– – – –' : '${_minYear + i - 1}',
                          onChanged: (i) => setState(() => _year = i == 0 ? null : _minYear + i - 1),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_canConfirm && !_confirming) ? _confirm : null,
                    child: _confirming
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                Center(
                  child: Text(
                    'Your birthday is never shared or sold.',
                    style: AppTypography.labelSmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Container(
        width: 1,
        height: double.infinity,
        color: cs.outlineVariant.withValues(alpha: 0.4),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _monthName(int m) => _months[m - 1];
}

class _LabelledPicker extends StatelessWidget {
  final String label;
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;

  const _LabelledPicker({
    required this.label,
    required this.controller,
    required this.itemCount,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: 40,
            onSelectedItemChanged: onChanged,
            selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
              background: colorScheme.primary.withValues(alpha: 0.08),
            ),
            children: List.generate(
              itemCount,
              (i) => Center(
                child: Text(
                  labelBuilder(i),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
