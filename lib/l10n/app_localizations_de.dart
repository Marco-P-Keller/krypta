// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Taschenrechner';

  @override
  String get messenger => 'Messenger';

  @override
  String get settings => 'Einstellungen';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Kontakte';

  @override
  String get setupTitle => 'Willkommen bei Krypta ECC';

  @override
  String get setupSubtitle => 'Richte deine Geheimcodes ein, um zu starten';

  @override
  String get secretCodeLabel => 'Geheimcode';

  @override
  String get secretCodeHint => 'Code der den Messenger öffnet';

  @override
  String get decoyCodeLabel => 'Tarncode';

  @override
  String get decoyCodeHint => 'Code der einen Fake-Messenger öffnet';

  @override
  String get deleteCodeLabel => 'Löschcode';

  @override
  String get deleteCodeHint => 'Code der sofort alle Daten löscht';

  @override
  String get setupComplete => 'Einrichtung abgeschlossen';

  @override
  String get setupContinue => 'Weiter';

  @override
  String get setupCodesInfo =>
      'Alle Codes müssen unterschiedlich und mindestens 4 Ziffern lang sein';

  @override
  String get newChat => 'Neuer Chat';

  @override
  String get typeMessage => 'Nachricht eingeben...';

  @override
  String get send => 'Senden';

  @override
  String get delivered => 'Zugestellt';

  @override
  String get sent => 'Gesendet';

  @override
  String get read => 'Gelesen';

  @override
  String get typing => 'tippt...';

  @override
  String get selfDestructTimer => 'Selbstzerstörungs-Timer';

  @override
  String get seconds30 => '30 Sekunden';

  @override
  String get minutes5 => '5 Minuten';

  @override
  String get hour1 => '1 Stunde';

  @override
  String get day1 => '1 Tag';

  @override
  String get week1 => '1 Woche';

  @override
  String get off => 'Aus';

  @override
  String get emergencyDelete => 'Notfall-Löschung';

  @override
  String get emergencyDeleteDescription =>
      'Sofort alle Daten, Schlüssel löschen und abmelden';

  @override
  String get allDataDeleted => 'Alle Daten wurden gelöscht';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get securitySettings => 'Sicherheit';

  @override
  String get changeSecretCode => 'Geheimcode ändern';

  @override
  String get changeDecoyCode => 'Tarncode ändern';

  @override
  String get changeDeleteCode => 'Löschcode ändern';

  @override
  String get biometricUnlock => 'Biometrische Entsperrung';

  @override
  String get biometricDescription =>
      'Face ID oder Fingerabdruck nach Codeeingabe verlangen';

  @override
  String get screenshotProtection => 'Screenshot-Schutz';

  @override
  String get screenshotDescription => 'Screenshots im Messenger blockieren';

  @override
  String get autoDeleteMessages => 'Nachrichten automatisch löschen';

  @override
  String get accountSection => 'Konto';

  @override
  String get privacySection => 'Datenschutz';

  @override
  String get dangerZone => 'Gefahrenzone';

  @override
  String get deleteAccount => 'Konto & Daten löschen';

  @override
  String get about => 'Über Krypta ECC';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get noChats => 'Noch keine Unterhaltungen';

  @override
  String get noChatsSubtitle =>
      'Starte einen neuen Chat für sichere Nachrichten';

  @override
  String get decoyTitle => 'Nachrichten';

  @override
  String get encryptionInfo => 'Nachrichten sind Ende-zu-Ende-verschlüsselt';

  @override
  String get anonymousUser => 'Anonymer Benutzer';

  @override
  String get userIdLabel => 'Deine ID';

  @override
  String get userIdCopied => 'Benutzer-ID kopiert';

  @override
  String get addContactById => 'Kontakt per ID hinzufügen';

  @override
  String get contactIdHint => 'Kontakt-ID eingeben';

  @override
  String get addContact => 'Kontakt hinzufügen';

  @override
  String get myQrCode => 'Mein QR-Code';

  @override
  String get scanQrCode => 'QR-Code scannen';

  @override
  String get qrScanHint => 'Richte die Kamera auf einen Krypta QR-Code';

  @override
  String get qrShareHint =>
      'Andere können diesen Code scannen um sich zu verbinden';

  @override
  String get renameChat => 'Chat umbenennen';

  @override
  String get chatName => 'Chatname';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get deleteChat => 'Chat löschen';

  @override
  String get autoDeleteTimer => 'Auto-Lösch-Timer';

  @override
  String get autoDeleteHint =>
      'Neue Nachrichten in diesem Chat werden nach der gewählten Zeit automatisch gelöscht.';

  @override
  String get chatDefault => 'Chat-Standard';

  @override
  String get burnAfterRead => 'Nach dem Lesen löschen';
}
