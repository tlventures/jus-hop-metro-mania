// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserImpl _$$UserImplFromJson(Map<String, dynamic> json) => _$UserImpl(
  id: json['id'] as String,
  name: json['name'] as String,
  email: json['email'] as String,
  phone: json['phone'] as String,
  points: (json['points'] as num?)?.toInt() ?? 0,
  membershipTier: json['membershipTier'] as String? ?? 'Silver',
  watchedVideoIds:
      (json['watchedVideoIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  redeemedRewardIds:
      (json['redeemedRewardIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  coSavedKg: (json['coSavedKg'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$$UserImplToJson(_$UserImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'email': instance.email,
      'phone': instance.phone,
      'points': instance.points,
      'membershipTier': instance.membershipTier,
      'watchedVideoIds': instance.watchedVideoIds,
      'redeemedRewardIds': instance.redeemedRewardIds,
      'coSavedKg': instance.coSavedKg,
    };
