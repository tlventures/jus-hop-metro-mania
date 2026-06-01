import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/city/content_pack_provider.dart';
import '../../../core/city/current_city_provider.dart';
import '../../../design_system/components/game_shell.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/localization_service.dart';
import '../application/games_provider.dart';

class CityExplorerScreen extends ConsumerStatefulWidget {
  const CityExplorerScreen({super.key});

  @override
  ConsumerState<CityExplorerScreen> createState() => _CityExplorerScreenState();
}

class _CityExplorerScreenState extends ConsumerState<CityExplorerScreen> with TickerProviderStateMixin {
  late List<Landmark> landmarks;
  late int discoveredCount;
  late int score;
  late int elapsedSeconds;
  late bool timerRunning;
  late bool gameCompleted;
  late String selectedFilter;

  // Loaded from the active city's landmarks pack.
  List<Landmark> allLandmarks = [];

  /// Build the landmark list from the city content pack.
  /// Falls back to a single generic placeholder if no pack is available.
  List<Landmark> _buildLandmarksFromPack(String locale) {
    final pack = ref.read(cityLandmarksProvider).valueOrNull;
    if (pack == null || pack.isEmpty) {
      // Generic fallback so the game never crashes on empty data
      return [
        Landmark(id: 'generic', name: 'Metro Station', category: 'transit',
                 lat: 0, lng: 0, description: 'Start exploring your city!', image: '🚇'),
      ];
    }
    return pack.landmarks.map((l) => Landmark(
      id: l.id,
      name: l.localizedName(locale),
      category: _capitalize(l.category),
      lat: l.lat,
      lng: l.lng,
      description: l.localizedDescription(locale),
      image: l.icon,
    )).toList();
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void initState() {
    super.initState();
    // Defer until first frame so providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locale = ref.read(localeProvider).languageCode;
      setState(() {
        allLandmarks = _buildLandmarksFromPack(locale);
        _initializeGame();
      });
      _startTimer();
    });
    // Provide initial empty state so build doesn't crash
    landmarks       = [];
    discoveredCount = 0;
    score           = 0;
    elapsedSeconds  = 0;
    timerRunning    = false;
    gameCompleted   = false;
    selectedFilter  = 'All';
  }

  @override
  void dispose() {
    timerRunning = false;
    super.dispose();
  }

  void _initializeGame() {
    landmarks = allLandmarks.map((l) => Landmark(
          id: l.id,
          name: l.name,
          category: l.category,
          lat: l.lat,
          lng: l.lng,
          description: l.description,
          image: l.image,
          discovered: false,
        )).toList();

    discoveredCount = 0;
    score = 0;
    elapsedSeconds = 0;
    timerRunning = false;
    gameCompleted = false;
    selectedFilter = 'All';
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

  void _discoverLandmark(String landmarkId) {
    HapticFeedback.heavyImpact();
    setState(() {
      final landmark = landmarks.firstWhere((l) => l.id == landmarkId);
      if (!landmark.discovered) {
        landmark.discovered = true;
        discoveredCount++;
        score += 20;

        if (discoveredCount == landmarks.length) {
          _endGame();
        }
      }
    });
  }

  void _endGame() {
    timerRunning = false;
    setState(() => gameCompleted = true);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _showGameEnd();
    });
  }

  void _showGameEnd() {
    final points = score > 80 ? 50 : 35;

    ref.read(gamesProvider.notifier).updateGameScore('city_explorer', score);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      builder: (context) => GameEndBottomSheet(
        title: score >= 80 ? '⭐ Expert Explorer!' : '👍 Great Explorer!',
        score: score,
        points: points,
        message: 'Discovered all $discoveredCount landmarks in ${_formatTime(elapsedSeconds)}',
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  score = 0;
                  discoveredCount = 0;
                  elapsedSeconds = 0;
                  gameCompleted = false;
                  _initializeGame();
                  _startTimer();
                });
              },
              child: const Text('Explore Again'),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Share Discovery'),
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

  List<Landmark> get filteredLandmarks {
    if (selectedFilter == 'All') return landmarks;
    return landmarks.where((l) => l.category == selectedFilter).toList();
  }

  Set<String> get categories => landmarks.map((l) => l.category).toSet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final city     = ref.watch(activeCityProvider);
    final locale   = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? 'City';

    // Trigger landmark pack load + watch for it
    ref.watch(cityLandmarksProvider);

    if (landmarks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('$cityName Explorer')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return GameShell(
      title: '$cityName Explorer',
      subtitle: 'Discover ${city?.signature.identity ?? "landmarks"}',
      onBack: () => Navigator.pop(context),
      elapsedTime: Duration(seconds: elapsedSeconds),
      showTimer: true,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            children: [
              // Discovery progress
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
                          '🗺️ Discovered',
                          style: AppTypography.labelSmall.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$discoveredCount/${landmarks.length}',
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
                        value: discoveredCount / landmarks.length,
                        minHeight: 8,
                        backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Score
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.borderRadiusS,
                ),
                child: Text(
                  '⭐ Score: $score',
                  style: AppTypography.labelSmall.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Category filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CategoryChip(
                      label: 'All',
                      selected: selectedFilter == 'All',
                      onTap: () => setState(() => selectedFilter = 'All'),
                    ),
                    ...categories.map((category) => _CategoryChip(
                          label: category,
                          selected: selectedFilter == category,
                          onTap: () => setState(() => selectedFilter = category),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Landmarks grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.s4,
                  mainAxisSpacing: AppSpacing.s4,
                  childAspectRatio: 0.9,
                ),
                itemCount: filteredLandmarks.length,
                itemBuilder: (context, index) {
                  final landmark = filteredLandmarks[index];
                  return GestureDetector(
                    onTap: () => _discoverLandmark(landmark.id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: landmark.discovered
                            ? colorScheme.primary.withValues(alpha: 0.2)
                            : colorScheme.surfaceContainer,
                        borderRadius: AppRadius.borderRadiusL,
                        border: Border.all(
                          color: landmark.discovered
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : colorScheme.outline.withValues(alpha: 0.3),
                          width: landmark.discovered ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  landmark.image,
                                  style: const TextStyle(fontSize: 48),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Text(
                                  landmark.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s1),
                                Text(
                                  landmark.category,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (landmark.discovered)
                            Positioned(
                              top: AppSpacing.s2,
                              right: AppSpacing.s2,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.s1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
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
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusS,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: selected ? Colors.white : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class Landmark {
  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String description;
  final String image;
  bool discovered;

  Landmark({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.description,
    required this.image,
    this.discovered = false,
  });
}
