import 'package:freezed_annotation/freezed_annotation.dart';

part 'reward.freezed.dart';
part 'reward.g.dart';

@freezed
class Reward with _$Reward {
  const factory Reward({
    required String id,
    required String title,
    required String description,
    required int pointsCost,
    required String category,
    String? couponCode,
    String? imageUrl,
    @Default(false) bool isRedeemed,
  }) = _Reward;

  factory Reward.fromJson(Map<String, dynamic> json) => _$RewardFromJson(json);
}
