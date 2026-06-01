class RideVerification {
  final String method;
  final String code;

  const RideVerification({required this.method, required this.code});

  Map<String, dynamic> toJson() => {'method': method, 'code': code};
}
