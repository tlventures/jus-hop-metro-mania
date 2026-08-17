import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import '../../../core/city/content_pack_provider.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../design_system/components/game_shell.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../application/games_provider.dart';

class SudokuScreen extends ConsumerStatefulWidget {
  final int difficulty;

  const SudokuScreen({this.difficulty = 1, super.key});

  @override
  ConsumerState<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends ConsumerState<SudokuScreen>
    with TickerProviderStateMixin {
  late List<List<int>> solution;
  late List<List<int>> board;
  late List<List<bool>> isOriginal;
  late List<List<bool>> isInvalid;

  int selectedRow = -1;
  int selectedCol = -1;
  int mistakes = 0;
  int elapsedSeconds = 0;
  bool timerRunning = false;
  bool gameCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeGame();
    _startTimer();
  }

  @override
  void dispose() {
    timerRunning = false;
    super.dispose();
  }

  void _initializeGame() {
    solution = _generateSudokuSolution();
    board = List.generate(9, (_) => List.generate(9, (_) => 0));
    isOriginal = List.generate(9, (_) => List.generate(9, (_) => false));
    isInvalid = List.generate(9, (_) => List.generate(9, (_) => false));

    int cellsToReveal = switch (widget.difficulty) {
      1 => 40,
      2 => 30,
      3 => 24,
      _ => 35,
    };

    _revealCells(cellsToReveal);
  }

  void _startTimer() {
    timerRunning = true;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && timerRunning && !gameCompleted) {
        setState(() => elapsedSeconds++);
        _startTimer();
      }
    });
  }

  void _revealCells(int cellsToReveal) {
    final random = Random();
    int cellsRevealed = 0;

    while (cellsRevealed < cellsToReveal) {
      int row = random.nextInt(9);
      int col = random.nextInt(9);

      if (board[row][col] == 0) {
        board[row][col] = solution[row][col];
        isOriginal[row][col] = true;
        cellsRevealed++;
      }
    }
  }

  List<List<int>> _generateSudokuSolution() {
    List<List<int>> grid = List.generate(9, (_) => List.generate(9, (_) => 0));
    _solveSudoku(grid);
    return grid;
  }

  bool _solveSudoku(List<List<int>> grid) {
    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        if (grid[row][col] == 0) {
          List<int> nums = [1, 2, 3, 4, 5, 6, 7, 8, 9];
          nums.shuffle();

          for (int num in nums) {
            if (_isValidPlacement(grid, row, col, num)) {
              grid[row][col] = num;
              if (_solveSudoku(grid)) return true;
              grid[row][col] = 0;
            }
          }
          return false;
        }
      }
    }
    return true;
  }

  bool _isValidPlacement(List<List<int>> grid, int row, int col, int num) {
    for (int c = 0; c < 9; c++) {
      if (grid[row][c] == num) return false;
    }

    for (int r = 0; r < 9; r++) {
      if (grid[r][col] == num) return false;
    }

    int boxRow = (row ~/ 3) * 3;
    int boxCol = (col ~/ 3) * 3;
    for (int r = boxRow; r < boxRow + 3; r++) {
      for (int c = boxCol; c < boxCol + 3; c++) {
        if (grid[r][c] == num) return false;
      }
    }
    return true;
  }

  void _placeNumber(int num) {
    if (selectedRow == -1 || selectedCol == -1) return;
    if (isOriginal[selectedRow][selectedCol]) return;

    HapticFeedback.lightImpact();

    setState(() {
      if (board[selectedRow][selectedCol] == num) {
        board[selectedRow][selectedCol] = 0;
        isInvalid[selectedRow][selectedCol] = false;
      } else {
        board[selectedRow][selectedCol] = num;
        isInvalid[selectedRow][selectedCol] =
            num != solution[selectedRow][selectedCol];

        if (isInvalid[selectedRow][selectedCol]) {
          mistakes++;
        }
      }
    });

    _checkCompletion();
  }

  void _checkCompletion() {
    bool isSolved = true;
    for (int i = 0; i < 9; i++) {
      for (int j = 0; j < 9; j++) {
        if (board[i][j] != solution[i][j]) {
          isSolved = false;
          break;
        }
      }
      if (!isSolved) break;
    }

    if (isSolved) {
      timerRunning = false;
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _showGameEnd();
      });
    }
  }

  Future<void> _showGameEnd() async {
    final score = 100 - (mistakes * 5).clamp(0, 90);
    final defaultPoints = (score > 50 ? 25 : 15);
    final result = await ref
        .read(gamesProvider.notifier)
        .updateGameScore('sudoku', score);
    if (!mounted) return;
    final accepted = result != null;
    final points =
        accepted
            ? (result['pointsEarned'] as num?)?.toInt() ?? defaultPoints
            : 0;

    setState(() => gameCompleted = true);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXXL),
      builder:
          (context) => GameEndBottomSheet(
            title:
                accepted
                    ? (score > 70 ? '⭐ Excellent!' : '👍 Good Job!')
                    : 'Ride Mode required',
            score: score,
            points: points,
            message:
                accepted
                    ? 'Completed in ${_formatTime(elapsedSeconds)}${mistakes > 0 ? ' with $mistakes mistakes' : ' perfectly!'}'
                    : 'Solve while in transit to claim points.',
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      mistakes = 0;
                      elapsedSeconds = 0;
                      gameCompleted = false;
                      _initializeGame();
                    });
                  },
                  child: const Text('Play Again'),
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Share Score'),
                ),
              ),
            ],
          ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  /// Render a board cell: city icon if a Sudoku icon pack is available
  /// for the active city, otherwise the plain digit.
  String _renderValue(int value, List<String>? icons) {
    if (value == 0) return '';
    if (icons != null && icons.length == 9 && value >= 1 && value <= 9) {
      return icons[value - 1];
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final city = ref.watch(activeCityProvider);
    final locale = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? '';

    // City icon pack (may be null if not yet loaded / no pack uploaded)
    final iconPackAsync = ref.watch(citySudokuIconsProvider);
    final iconPack = iconPackAsync.valueOrNull;
    final icons = iconPack?.icons;
    final hasIcons = icons != null && icons.length == 9;
    final isEmoji = hasIcons;

    return GameShell(
      title:
          hasIcons
              ? iconPack!.localizedTitle(locale)
              : '${cityName.isEmpty ? "" : "$cityName "}Sudoku',
      subtitle: _difficultyLabel(widget.difficulty),
      onBack: () => Navigator.pop(context),
      elapsedTime: Duration(seconds: elapsedSeconds),
      showTimer: true,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            children: [
              // Mistakes indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          mistakes > 2
                              ? Color(0xFFEF4444).withValues(alpha: 0.2)
                              : colorScheme.surfaceContainer,
                      borderRadius: AppRadius.borderRadiusS,
                    ),
                    child: Text(
                      '❌ $mistakes/3 mistakes',
                      style: AppTypography.labelSmall.copyWith(
                        color:
                            mistakes > 2
                                ? Color(0xFFEF4444)
                                : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),

              // Sudoku grid
              AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: AppRadius.borderRadiusL,
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 9,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                    itemCount: 81,
                    itemBuilder: (context, index) {
                      final row = index ~/ 9;
                      final col = index % 9;
                      final isSelected =
                          selectedRow == row && selectedCol == col;
                      final isInSameRow =
                          selectedRow == row && selectedCol != -1;
                      final isInSameCol =
                          selectedCol == col && selectedRow != -1;
                      final isInSameBox =
                          (selectedRow ~/ 3 == row ~/ 3) &&
                          (selectedCol ~/ 3 == col ~/ 3) &&
                          !(selectedRow == row && selectedCol == col);

                      return GestureDetector(
                        onTap:
                            () => setState(() {
                              selectedRow = row;
                              selectedCol = col;
                            }),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? colorScheme.primary.withValues(alpha: 0.3)
                                    : isInSameRow || isInSameCol || isInSameBox
                                    ? colorScheme.primary.withValues(alpha: 0.1)
                                    : Colors.transparent,
                            border: Border.all(
                              color:
                                  (row % 3 == 2 || col % 3 == 2)
                                      ? colorScheme.outlineVariant
                                      : colorScheme.outline.withValues(
                                        alpha: 0.3,
                                      ),
                              width: (row % 3 == 2 || col % 3 == 2) ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _renderValue(board[row][col], icons),
                              style: (isEmoji
                                      ? const TextStyle(fontSize: 22)
                                      : AppTypography.headlineSmall)
                                  .copyWith(
                                    color:
                                        isOriginal[row][col]
                                            ? colorScheme.onSurface
                                            : isInvalid[row][col]
                                            ? const Color(0xFFEF4444)
                                            : colorScheme.primary,
                                    fontWeight:
                                        isOriginal[row][col]
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Number pad
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 9,
                  crossAxisSpacing: AppSpacing.s2,
                  mainAxisSpacing: AppSpacing.s2,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  final num = index + 1;
                  return GestureDetector(
                    onTap: selectedRow == -1 ? null : () => _placeNumber(num),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: AppRadius.borderRadiusM,
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _renderValue(num, icons),
                          style: (isEmoji
                                  ? const TextStyle(fontSize: 20)
                                  : AppTypography.titleSmall)
                              .copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _difficultyLabel(int difficulty) {
    return switch (difficulty) {
      1 => 'Easy',
      2 => 'Medium',
      3 => 'Hard',
      _ => 'Normal',
    };
  }
}
