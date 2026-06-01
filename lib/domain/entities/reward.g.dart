// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RewardImpl _$$RewardImplFromJson(Map<String, dynamic> json) => _$RewardImpl(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String,
  pointsCost: (json['pointsCost'] as num).toInt(),
  category: json['category'] as String,
  couponCode: json['couponCode'] as String?,
  imageUrl: json['imageUrl'] as String?,
  isRedeemed: json['isRedeemed'] as bool? ?? false,
);

Map<String, dynamic> _$$RewardImplToJson(_$RewardImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'pointsCost': instance.pointsCost,
      'category': instance.category,
      'couponCode': instance.couponCode,
      'imageUrl': instance.imageUrl,
      'isRedeemed': instance.isRedeemed,
    };
