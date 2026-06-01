// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'article.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArticleImpl _$$ArticleImplFromJson(Map<String, dynamic> json) =>
    _$ArticleImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      coverUrl: json['coverUrl'] as String,
      readTimeMinutes: (json['readTimeMinutes'] as num).toInt(),
      points: (json['points'] as num).toInt(),
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
    );

Map<String, dynamic> _$$ArticleImplToJson(_$ArticleImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'coverUrl': instance.coverUrl,
      'readTimeMinutes': instance.readTimeMinutes,
      'points': instance.points,
      'publishedAt': instance.publishedAt.toIso8601String(),
      'isRead': instance.isRead,
    };
