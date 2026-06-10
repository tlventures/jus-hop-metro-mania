import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/survey.dart';
import '../../../services/backend_service.dart';

class SurveysNotifier extends StateNotifier<List<Survey>> {
  final BackendService _backendService;

  SurveysNotifier(this._backendService) : super([]);

  Future<void> fetchSurveys() async {
    try {
      final data = await _backendService.getSurveys();
      if (!mounted) return;
      final surveys =
          (data['surveys'] as List<dynamic>? ?? [])
              .map((s) => Survey.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList();
      state = surveys;
    } catch (e) {
      debugPrint('SurveysNotifier.fetchSurveys error: $e');
      if (mounted) state = [];
    }
  }

  Future<bool> submitSurvey(String surveyId, String selectedOption) async {
    try {
      await _backendService.submitSurvey(surveyId, selectedOption);
    } catch (e) {
      debugPrint('SurveysNotifier.submitSurvey error: $e');
      return false;
    }

    if (!mounted) return false;
    state =
        state.map((survey) {
          if (survey.id == surveyId) {
            return survey.copyWith(isCompleted: true);
          }
          return survey;
        }).toList();
    return true;
  }

  int get completedCount => state.where((s) => s.isCompleted).length;
  int get totalPoints =>
      state.fold(0, (sum, s) => sum + (s.isCompleted ? s.points : 0));
}

final backendServiceSurveysProvider = Provider((ref) => BackendService());

final surveysProvider = StateNotifierProvider<SurveysNotifier, List<Survey>>((
  ref,
) {
  final backendService = ref.watch(backendServiceSurveysProvider);
  return SurveysNotifier(backendService);
});

final completedSurveysProvider = Provider<int>((ref) {
  final surveys = ref.watch(surveysProvider);
  return surveys.where((s) => s.isCompleted).length;
});

final surveyPointsProvider = Provider<int>((ref) {
  final surveys = ref.watch(surveysProvider);
  return surveys.fold(0, (sum, s) => sum + (s.isCompleted ? s.points : 0));
});
