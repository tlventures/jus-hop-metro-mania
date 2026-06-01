import 'package:firebase_auth/firebase_auth.dart';

class UserDisplayName {
  static String name({
    required User? firebaseUser,
    required Map<String, dynamic>? profile,
    int maxLength = 8,
    String fallback = 'there',
  }) {
    final firebaseName = _clean(firebaseUser?.displayName);
    if (firebaseName != null && !_isGeneric(firebaseName)) {
      return _truncate(_firstName(firebaseName), maxLength);
    }

    final profileName = _clean(_stringValue(profile?['name']));
    if (profileName != null && !_isGeneric(profileName)) {
      return _truncate(_firstName(profileName), maxLength);
    }

    final emailName = _clean(_bestEmail(firebaseUser, profile)?.split('@').first);
    if (emailName != null && !_isGeneratedEmailLocal(emailName)) {
      return _truncate(_firstName(emailName.replaceAll('.', ' ')), maxLength);
    }

    return fallback;
  }

  static String email({
    required User? firebaseUser,
    required Map<String, dynamic>? profile,
  }) {
    final firebaseEmail = _clean(firebaseUser?.email);
    if (firebaseEmail != null) return firebaseEmail;

    final profileEmail = _clean(_stringValue(profile?['email']));
    if (profileEmail == null || _isGeneratedEmail(profileEmail)) return '';
    return profileEmail;
  }

  static String initial(String name) {
    final cleaned = _clean(name);
    return cleaned == null ? '?' : cleaned[0].toUpperCase();
  }

  static String _firstName(String value) => value.trim().split(RegExp(r'\s+')).first;

  static String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) return trimmed;
    return trimmed.substring(0, maxLength);
  }

  static String? _bestEmail(User? firebaseUser, Map<String, dynamic>? profile) {
    return firebaseUser?.email ?? _stringValue(profile?['email']);
  }

  static String? _stringValue(Object? value) => value?.toString();

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isGeneric(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'metro' ||
        normalized == 'member' ||
        normalized == 'traveler' ||
        normalized == 'metro member' ||
        normalized == 'metro traveler';
  }

  static bool _isGeneratedEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return normalized.startsWith('member-') &&
        normalized.endsWith('@metrosafar.app');
  }

  static bool _isGeneratedEmailLocal(String localPart) {
    return localPart.trim().toLowerCase().startsWith('member-');
  }
}
