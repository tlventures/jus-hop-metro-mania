// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GameImpl _$$GameImplFromJson(Map<String, dynamic> json) => _$GameImpl(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
  points: (json['points'] as num).toInt(),
  type: json['type'] as String,
  bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
  icon: json['icon'] as String,
);

Map<String, dynamic> _$$GameImplToJson(_$GameImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'points': instance.points,
      'type': instance.type,
      'bestScore': instance.bestScore,
      'icon': instance.icon,
    };
