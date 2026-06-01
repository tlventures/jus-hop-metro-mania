import 'package:freezed_annotation/freezed_annotation.dart';

part 'survey.freezed.dart';
part 'survey.g.dart';

@freezed
class Survey with _$Survey {
  const factory Survey({
    required String id,
    required String question,
    required List<String> options,
    required int points,
    @Default(false) bool isCompleted,
  }) = _Survey;

  factory Survey.fromJson(Map<String, dynamic> json) => _$SurveyFromJson(json);
}

@freezed
class SurveyResponse with _$SurveyResponse {
  const factory SurveyResponse({
    required String surveyId,
    required String selectedOption,
    required DateTime submittedAt,
  }) = _SurveyResponse;

  factory SurveyResponse.fromJson(Map<String, dynamic> json) =>
      _$SurveyResponseFromJson(json);
}
