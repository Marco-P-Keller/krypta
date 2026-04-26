abstract final class AppConstants {
  static const String appName = 'Krypta ECC';
  static const String appVersion = '1.0.0';

  static const int minCodeLength = 4;
  static const int maxCodeLength = 12;

  static const Duration messageRelayTTL = Duration(hours: 24);
  static const Duration typingTimeout = Duration(seconds: 5);

  /// Maximum session age before forced re-handshake (forward secrecy renewal).
  static const Duration sessionMaxAge = Duration(days: 14);

  /// Maximum verification age before prompting re-verification.
  static const Duration verificationMaxAge = Duration(days: 90);

  /// Minimum password entropy bits for password-protected messages.
  static const int minPasswordEntropyBits = 28;

  static const List<Duration> selfDestructOptions = [
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 7),
  ];
}
