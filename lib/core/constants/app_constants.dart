abstract final class AppConstants {
  static const String appName = 'Krypta ECC';

  /// Marketing-Version und Build-Nummer, vom Build durchgereicht.
  ///
  /// Vorher stand hier eine feste `'1.0.0'`. Die war spätestens ab Version 2.0
  /// falsch und behauptete auf dem Einstellungs-Bildschirm weiter 1.0.0,
  /// während im App Store längst 4.0.0 auslieferte — aufgefallen ist das erst
  /// beim Gerätetest von Build 85. Eine Zahl, die man von Hand nachziehen
  /// muss, wird irgendwann nicht mehr nachgezogen.
  ///
  /// Die Werte kommen jetzt über `--dart-define` aus demselben `pubspec.yaml`,
  /// aus dem auch `CFBundleShortVersionString` gefüllt wird. Ohne die Defines
  /// — also bei einem lokalen Lauf ohne CI — steht bewusst `dev` da, statt
  /// eine Zahl zu behaupten, die niemand gesetzt hat.
  static const String _version = String.fromEnvironment('APP_VERSION');
  static const String _build = String.fromEnvironment('APP_BUILD');

  /// Was der Nutzer sieht: `4.1.0 (85)`, oder `dev` außerhalb der CI.
  static String get appVersion => formatVersion(_version, _build);

  /// Reine Formatierung, damit sie ohne Build-Umgebung testbar ist.
  static String formatVersion(String version, String build) {
    final v = version.trim();
    final b = build.trim();
    if (v.isEmpty) return 'dev';
    return b.isEmpty ? v : '$v ($b)';
  }

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
