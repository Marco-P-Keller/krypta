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
  String get back => 'Zurück';

  @override
  String get next => 'Weiter';

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
  String get cannotAddYourself => 'Du kannst dich nicht selbst hinzufügen';

  @override
  String get userNotFound => 'Benutzer nicht gefunden';

  @override
  String get myQrCode => 'Mein QR-Code';

  @override
  String get scanQrCode => 'QR-Code scannen';

  @override
  String get scanQr => 'QR scannen';

  @override
  String get qrScanHint => 'Richte die Kamera auf einen Krypta QR-Code';

  @override
  String get qrShareHint =>
      'Andere können diesen Code scannen um sich zu verbinden';

  @override
  String get yourQrCode => 'Dein QR-Code';

  @override
  String get idCopied => 'ID kopiert';

  @override
  String get qrWebUnavailable =>
      'QR-Scan ist im Web nicht verfügbar.\nVerwende ein Mobilgerät zum Scannen.';

  @override
  String get thatsYourOwnId => 'Das ist deine eigene ID';

  @override
  String get renameChat => 'Chat umbenennen';

  @override
  String get chatName => 'Chatname';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get skip => 'Überspringen';

  @override
  String get deleteChat => 'Chat löschen';

  @override
  String get clearChat => 'Chat leeren';

  @override
  String get clearChatConfirm =>
      'Alle Nachrichten in diesem Chat löschen? Das kann nicht rückgängig gemacht werden.';

  @override
  String get autoDeleteTimer => 'Auto-Lösch-Timer';

  @override
  String get autoDeleteHint =>
      'Neue Nachrichten in diesem Chat werden nach der gewählten Zeit automatisch gelöscht.';

  @override
  String get chatDefault => 'Chat-Standard';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Chat-Standard ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'Nachrichten löschen sich nach $timer';
  }

  @override
  String get onlyVisibleToYou => 'Nur für dich sichtbar';

  @override
  String get burnAfterRead => 'Nach dem Lesen löschen';

  @override
  String get passwordProtected => 'Passwortgeschützt';

  @override
  String get lockMessage => 'Nachricht sperren';

  @override
  String get lockMessageHint =>
      'Setze ein Passwort für die nächste Nachricht. Der Empfänger muss dieses Passwort eingeben.';

  @override
  String get enterPassword => 'Passwort eingeben';

  @override
  String get setPassword => 'Passwort setzen';

  @override
  String get passwordRequired => 'Passwort erforderlich';

  @override
  String get passwordRequiredHint =>
      'Gib das Passwort ein, um diese Nachricht zu entschlüsseln.';

  @override
  String get password => 'Passwort';

  @override
  String get unlock => 'Entsperren';

  @override
  String get unlocked => 'Entsperrt';

  @override
  String get wrongPassword => 'Falsches Passwort';

  @override
  String get tapToUnlock => 'Tippen zum Entsperren';

  @override
  String get nameThisContact => 'Kontakt benennen';

  @override
  String get nameContactHint =>
      'Gib diesem Kontakt einen Namen. Nur du kannst dieses Label sehen.';

  @override
  String get nameContactPlaceholder => 'z.B. Alex, Mama, Arbeit...';

  @override
  String get selfDestructTimerLabel => 'Selbstzerstörungs-Timer';

  @override
  String get vaultPassword => 'Tresor-Passwort';

  @override
  String get vaultPasswordDescription =>
      'Starkes Passwort nach Code-Eingabe vor dem Zugriff auf den Messenger verlangen';

  @override
  String get vaultPasswordTitle => 'Tresor gesperrt';

  @override
  String get vaultPasswordHint =>
      'Gib dein Tresor-Passwort ein, um auf den Messenger zuzugreifen.';

  @override
  String get setVaultPassword => 'Tresor-Passwort setzen';

  @override
  String get changeVaultPassword => 'Tresor-Passwort ändern';

  @override
  String get removeVaultPassword => 'Tresor-Passwort entfernen';

  @override
  String get vaultPasswordSet => 'Tresor-Passwort gesetzt';

  @override
  String get vaultPasswordRemoved => 'Tresor-Passwort entfernt';

  @override
  String get vaultPasswordRules =>
      'Mindestens 10 Zeichen, mit Gross-, Kleinbuchstaben, Zahl und Sonderzeichen.';

  @override
  String get newPassword => 'Neues Passwort';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get passwordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String get passwordTooWeak => 'Passwort erfüllt die Anforderungen nicht';

  @override
  String get copy => 'Kopieren';

  @override
  String get copied => 'Kopiert';

  @override
  String get delete => 'Löschen';

  @override
  String get deleteMessage => 'Nachricht löschen';

  @override
  String get deleteMessageConfirm =>
      'Diese Nachricht wird dauerhaft von diesem Gerät gelöscht.';

  @override
  String get deleteForMe => 'Für mich löschen';

  @override
  String get deleteForEveryone => 'Für alle löschen';

  @override
  String get deleteForEveryoneConfirm =>
      'Diese Nachricht wird für dich und den Empfänger gelöscht.';

  @override
  String get qrInvalidFormat =>
      'Ungültiges QR-Code-Format. Nur Krypta-QR-Codes werden akzeptiert.';

  @override
  String get qrUnsupportedVersion =>
      'Nicht unterstützte QR-Code-Version. Bitte App aktualisieren.';

  @override
  String get qrFingerprintMismatch =>
      'Sicherheitswarnung: Der Fingerprint im QR-Code ist manipuliert. Vorgang abgebrochen.';

  @override
  String get qrKeyMismatch =>
      'SICHERHEITSWARNUNG: Der Schlüssel vom Server stimmt NICHT mit dem QR-Code überein. Möglicher Angriff erkannt. Kontakt wurde blockiert.';

  @override
  String get qrVerified => 'Schlüssel verifiziert';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get legalSection => 'Rechtliches';
}
