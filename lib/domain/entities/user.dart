import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class User with _$User {
  const factory User({
    required String id,
    required String name,
    required String email,
    required String phone,
    @Default(0) int points,
    @Default('Silver') String membershipTier,
    @Default([]) List<String> watchedVideoIds,
    @Default([]) List<String> redeemedRewardIds,
    @Default(0) int coSavedKg,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  const User._();

  String get firstName => name.split(' ').first;

  bool hasEnoughPoints(int required) => points >= required;

  String get avatarInitials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }
}
