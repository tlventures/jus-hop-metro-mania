// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'station_story.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$StationStoryImpl _$$StationStoryImplFromJson(Map<String, dynamic> json) =>
    _$StationStoryImpl(
      id: json['id'] as String,
      stationName: json['stationName'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String,
      frames:
          (json['frames'] as List<dynamic>)
              .map((e) => StoryFrame.fromJson(e as Map<String, dynamic>))
              .toList(),
      points: (json['points'] as num?)?.toInt() ?? 25,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );

Map<String, dynamic> _$$StationStoryImplToJson(_$StationStoryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'stationName': instance.stationName,
      'description': instance.description,
      'imageUrl': instance.imageUrl,
      'frames': instance.frames,
      'points': instance.points,
      'isCompleted': instance.isCompleted,
    };

_$StoryFrameImpl _$$StoryFrameImplFromJson(Map<String, dynamic> json) =>
    _$StoryFrameImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      imageUrl: json['imageUrl'] as String,
      order: (json['order'] as num).toInt(),
    );

Map<String, dynamic> _$$StoryFrameImplToJson(_$StoryFrameImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'content': instance.content,
      'imageUrl': instance.imageUrl,
      'order': instance.order,
    };
