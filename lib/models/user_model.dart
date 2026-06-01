// lib/models/user_model.dart

/// Model class for User
class User {
  /// Unique identifier for the user
  final String id;

  /// User's full name
  final String name;

  /// User's email address
  final String email;

  /// User's phone number
  final String phone;

  /// Reward points earned by watching videos
  final int points;

  /// Constructor
  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.points = 0,
  });

  /// Create a copy of this User with modified properties
  User copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    int? points,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      points: points ?? this.points,
    );
  }

  /// Convert this User to a JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'points': points,
    };
  }

  /// Create a User from a JSON Map
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      points: json['points'] ?? 0,
    );
  }

  /// Get first name only
  String get firstName {
    final parts = name.split(' ');
    return parts.first;
  }

  /// Check if user has enough points for a reward
  bool hasEnoughPoints(int requiredPoints) {
    return points >= requiredPoints;
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, points: $points)';
  }
}