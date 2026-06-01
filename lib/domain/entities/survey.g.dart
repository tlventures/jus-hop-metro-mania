// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'survey.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SurveyImpl _$$SurveyImplFromJson(Map<String, dynamic> json) => _$SurveyImpl(
  id: json['id'] as String,
  question: json['question'] as String,
  options: (json['options'] as List<dynamic>).map((e) => e as String).toList(),
  points: (json['points'] as num).toInt(),
  isCompleted: json['isCompleted'] as bool? ?? false,
);

Map<String, dynamic> _$$SurveyImplToJson(_$SurveyImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'question': instance.question,
      'options': instance.options,
      'points': instance.points,
      'isCompleted': instance.isCompleted,
    };

_$SurveyResponseImpl _$$SurveyResponseImplFromJson(Map<String, dynamic> json) =>
    _$SurveyResponseImpl(
      surveyId: json['surveyId'] as String,
      selectedOption: json['selectedOption'] as String,
      submittedAt: DateTime.parse(json['submittedAt'] as String),
    );

Map<String, dynamic> _$$SurveyResponseImplToJson(
  _$SurveyResponseImpl instance,
) => <String, dynamic>{
  'surveyId': instance.surveyId,
  'selectedOption': instance.selectedOption,
  'submittedAt': instance.submittedAt.toIso8601String(),
};
