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
  String get verificationStale => 'Verifizierung älter als 90 Tage';

  @override
  String get verifyNow => 'Neu verifizieren';

  @override
  String get showTutorial => 'Tutorial erneut anzeigen';

  @override
  String get showTutorialSubtitle => 'Einführung wiederholen';

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get openSourceLicensesSubtitle =>
      'Verwendete Bibliotheken und Hinweise';

  @override
  String get aboutClose => 'Schließen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String lockedForSeconds(int seconds) {
    return 'Gesperrt für $seconds Sekunden.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining Versuche',
      one: '1 Versuch',
    );
    return 'Falsches Passwort. Noch $_temp0, danach werden alle Daten gelöscht.';
  }

  @override
  String get keysNotPublishedDenied =>
      'Deine Schlüssel wurden vom Server abgelehnt – andere können dir nicht schreiben.';

  @override
  String get keysNotPublishedFailed =>
      'Deine Schlüssel konnten nicht hinterlegt werden – andere können dir nicht schreiben.';

  @override
  String get biometricUnlockReason => 'Krypta Messenger entsperren';

  @override
  String get deviceCompromised => 'Gerät möglicherweise kompromittiert.';

  @override
  String get deviceCompromisedDegraded =>
      'Gerät möglicherweise kompromittiert. Hardware-Sicherheit deaktiviert.';

  @override
  String get fieldRequired => 'Erforderlich';

  @override
  String codeMinDigits(int count) {
    return 'Mindestens $count Ziffern';
  }

  @override
  String get codeDigitsOnly => 'Nur Ziffern';

  @override
  String get deleteCodeMustDiffer =>
      'Der Löschcode muss sich vom Geheimcode unterscheiden.';

  @override
  String get setupFailed =>
      'Einrichtung fehlgeschlagen. Bitte noch einmal versuchen.';

  @override
  String get setupSecretCodeSubtitle =>
      'Diesen Code im Rechner eingeben, um den Tresor zu öffnen.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Löscht sofort alles. Nur im Notfall verwenden.';

  @override
  String get contactKeyChangedWarning =>
      'Der Sicherheitsschlüssel dieses Kontakts hat sich geändert. Nachrichten sind blockiert, bis du seine Identität bestätigt hast. Scanne seinen QR-Code oder vergleicht die Sicherheitsnummern, um weiterzuschreiben.';

  @override
  String get verifyIdentity => 'Identität bestätigen';

  @override
  String get safetyNumberCompareHint =>
      'Vergleicht die Sicherheitsnummern oder scannt die QR-Codes, um die Ende-zu-Ende-Verschlüsselung zu bestätigen.';

  @override
  String get viewSafetyNumber => 'Sicherheitsnummer anzeigen';

  @override
  String get safetyNumberTitle => 'Sicherheitsnummer';

  @override
  String get safetyNumberCopied => 'Sicherheitsnummer kopiert';

  @override
  String get safetyNumberMatchHint =>
      'Vergleiche diese Nummer mit deinem Kontakt. Stimmen sie überein, ist euer Gespräch sicher.';

  @override
  String get verificationFailedKeyMismatch =>
      'Verifikation fehlgeschlagen — Schlüssel stimmen nicht überein';

  @override
  String get markVerified => 'Als bestätigt markieren';

  @override
  String get securitySettingsReason => 'Sicherheitseinstellungen ändern';

  @override
  String get vaultPasswordReAuthHint =>
      'Tresor-Passwort eingeben um Sicherheitseinstellungen zu ändern.';

  @override
  String get codeAlreadyInUse =>
      'Dieser Code wird bereits für eine andere Aktion verwendet.';

  @override
  String get deviceSecure => 'Gerät sicher';

  @override
  String get deviceCompromisedDetected => 'Kompromittierung erkannt';

  @override
  String get deviceStatusUnknown => 'Status unbekannt';

  @override
  String get deviceSecureSubtitle => 'Keine Root/Jailbreak/Frida-Indikatoren';

  @override
  String get deviceCompromisedSubtitle =>
      'Root, Jailbreak oder Instrumentierung erkannt. Hardware-Sicherheit deaktiviert.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'Integritätsprüfung fehlgeschlagen — eingeschränkter Modus aktiv.';

  @override
  String get hardwareEnclave => 'Hardware-Enklave';

  @override
  String get hardwareTee => 'TEE-Schlüsselspeicher';

  @override
  String get hardwareSoftware => 'Software-Schlüsselspeicher';

  @override
  String get hardwareBoundSubtitle => 'Datenbankschlüssel an Hardware gebunden';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave verfügbar';

  @override
  String get hardwareTeeSubtitle =>
      'Schlüssel im Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle => 'Keine Hardware-Sicherheit verfügbar';

  @override
  String get pushPrivacy => 'Push-Privatsphäre';

  @override
  String get pushPrivacyOn =>
      'Aktiv — Nachrichten werden per Polling abgerufen';

  @override
  String get pushPrivacyOff => 'Deaktiviert — Push-Benachrichtigungen aktiv';

  @override
  String get readReceipts => 'Lesebestätigungen';

  @override
  String get readReceiptsOn => 'Aktiv — Absender sieht, wann du liest';

  @override
  String get readReceiptsOff => 'Deaktiviert — maximale Privatsphäre';

  @override
  String get deliveryReceipts => 'Zustellbestätigungen';

  @override
  String get deliveryReceiptsOn => 'Aktiv — Absender sieht, wann zugestellt';

  @override
  String get deliveryReceiptsOff => 'Deaktiviert — maximale Privatsphäre';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Datenschutzerklärung\n\nStand: April 2026\n\n1. Verantwortlicher\nConnexa GmbH\nKontakt: https://connexa-gmbh.ch\n\n2. Welche Daten werden erhoben?\nKrypta erhebt so wenig Daten wie technisch möglich:\n• Anonyme Firebase-ID (keine E-Mail, kein Name, keine Telefonnummer)\n• Öffentlicher Verschlüsselungsschlüssel (X25519)\n• FCM-Push-Token (für Benachrichtigungen)\n\n3. Verschlüsselung\nAlle Nachrichten sind Ende-zu-Ende-verschlüsselt (Signal-Protokoll: X3DH + Double Ratchet). Der Server hat zu keinem Zeitpunkt Zugriff auf den Klartext Ihrer Nachrichten. Verschlüsselung: XChaCha20-Poly1305. Passwort-Hashing: Argon2id.\n\n4. Datenspeicherung\n• Nachrichten werden nur auf Ihrem Gerät gespeichert (verschlüsselt)\n• Der Server fungiert nur als temporärer Relay — Nachrichten werden nach Zustellung gelöscht\n• Schlüssel werden im iOS Keychain / Android Keystore gespeichert\n\n5. Keine Tracker\nKrypta enthält keine Analyse-Tools, keine Werbung und keine Tracker (0 von 432 bekannten Trackern).\n\n6. Datenweitergabe\nEs werden keine personenbezogenen Daten an Dritte weitergegeben. Google Firebase wird als Infrastruktur-Anbieter verwendet (anonyme Authentifizierung und Push-Benachrichtigungen).\n\n7. Datenlöschung\nSie können jederzeit alle Ihre Daten unwiderruflich löschen:\n• In den Einstellungen über \"Alles löschen\"\n• Durch Eingabe des Lösch-Codes im Taschenrechner\nDabei werden alle lokalen Daten, Schlüssel und Server-Daten vernichtet.\n\n8. Ihre Rechte (DSGVO)\nSie haben das Recht auf Auskunft, Berichtigung, Löschung und Datenübertragbarkeit. Kontaktieren Sie uns unter: https://connexa-gmbh.ch\n\n9. Änderungen\nDiese Datenschutzerklärung kann aktualisiert werden. Die aktuelle Version ist immer in der App einsehbar.';

  @override
  String get tutStartSetup => 'Setup starten';

  @override
  String get tutWelcomeTitle => 'Willkommen bei Krypta';

  @override
  String get tutWelcomeBody =>
      'Krypta ist ein geheimer Messenger.\n\nFür alle anderen sieht die App aus wie ein ganz normaler Taschenrechner — niemand wird vermuten, dass sich dahinter ein verschlüsselter Chat versteckt.\n\nWir empfehlen, dieses Tutorial ausführlich zu lesen.';

  @override
  String get tutSecretCodeTitle => 'Dein Geheimcode';

  @override
  String get tutSecretCodeBody =>
      'Beim Einrichten legst du einen Zahlencode fest.\n\nDieser Code ist dein Schlüssel — nur damit kannst du den versteckten Messenger öffnen.';

  @override
  String get tutDeleteCodeBody =>
      'Der zweite Code ist für den Notfall.\n\nWenn du diesen Code eingibst, wird sofort alles gelöscht — Nachrichten, Schlüssel, Account. Unwiderruflich.\n\nNur im Ernstfall verwenden!';

  @override
  String get tutDeleteCodeWarning =>
      'Alles wird sofort gelöscht.\nKeine Wiederherstellung möglich.';

  @override
  String get tutOpenMessengerTitle => 'Messenger öffnen';

  @override
  String get tutOpenMessengerBody =>
      'Um deinen Messenger zu öffnen:\n\n1. Gib deinen Geheimcode im Taschenrechner ein\n2. Drücke die = Taste\n\nDer Messenger öffnet sich sofort.';

  @override
  String get tutPressEquals => 'Drücke =';

  @override
  String get tutMessengerUnlocked => 'Messenger entsperrt';

  @override
  String get tutVaultBody =>
      'In den Einstellungen kannst du ein zusätzliches Passwort aktivieren.\n\nNach dem Geheimcode wird dann noch das Tresor-Passwort abgefragt — doppelte Sicherheit.\n\nWir empfehlen das aus Sicherheitsgründen.';

  @override
  String get tutAddContactsTitle => 'Kontakte hinzufügen';

  @override
  String get tutAddContactsBody =>
      'Du kannst Kontakte auf zwei Arten hinzufügen:\n\n• QR-Code scannen — schnell und einfach\n• User-ID eingeben — wenn ihr nicht am selben Ort seid\n\nDanach kannst du der Person einen Namen geben.';

  @override
  String get tutQrFast => 'Schnell & einfach';

  @override
  String get tutEnterUserId => 'User-ID eingeben';

  @override
  String get tutForRemoteContacts => 'Für Fernkontakte';

  @override
  String get tutEmergencyBody =>
      'In der App findest du rote Notfall-Knöpfe.\n\nSie löschen sofort alles — genau wie der Delete-Code. Verwende sie nur im Ernstfall.';

  @override
  String get tutInSettings => 'In den Einstellungen';

  @override
  String get tutChatFeaturesIntro =>
      'Im Chat hast du drei besondere Funktionen:';

  @override
  String get tutLockMessageDesc => 'Einzelne Nachrichten mit Passwort schützen';

  @override
  String get tutAutoDeleteDesc =>
      'Nachrichten löschen sich nach einer Zeit automatisch';

  @override
  String get tutBurnAfterReadDesc =>
      'Nachricht wird nach dem Lesen sofort gelöscht';

  @override
  String get tutReadyTitle => 'Alles klar!';

  @override
  String get tutReadyBody =>
      'Du weisst jetzt alles was du brauchst.\n\nIm nächsten Schritt richtest du deine Codes ein — danach ist dein Messenger einsatzbereit.';

  @override
  String get language => 'Sprache';

  @override
  String get chooseLanguage => 'Wähle deine Sprache';

  @override
  String get deviceSecuritySection => 'Gerätesicherheit';

  @override
  String get tutDeleteCodeTitle => 'Notfall-Code';

  @override
  String get tutEmergencyTitle => 'Notfall-Knöpfe';

  @override
  String get tutChatFeaturesTitle => 'Chat-Funktionen';

  @override
  String get blockContact => 'Blockieren';

  @override
  String get authentication => 'Authentifizierung';

  @override
  String get contactRequestTitle => 'Kontaktanfrage';

  @override
  String get contactRequestIncomingHint =>
      'Diese Person möchte dir schreiben. Schreiben könnt ihr euch erst, wenn du annimmst.';

  @override
  String get acceptRequest => 'Annehmen';

  @override
  String get declineRequest => 'Ablehnen';

  @override
  String get contactRequestSent => 'Anfrage gesendet';

  @override
  String get contactRequestWaitingHint =>
      'Schreiben kannst du, sobald die andere Person annimmt.';

  @override
  String get resendRequest => 'Erneut anfragen';

  @override
  String get acceptToReply => 'Nimm die Anfrage an, um zu antworten';

  @override
  String get requestBadge => 'Anfrage';

  @override
  String get blockContactConfirm =>
      'Diese Person blockieren? Sie kann dir dann nicht mehr schreiben und erfährt nichts davon.';

  @override
  String get unblockContact => 'Blockierung aufheben';

  @override
  String get contactBlocked => 'Blockiert';

  @override
  String get minute1 => '1 Minute';

  @override
  String get welcomeBack => 'Willkommen zurück';

  @override
  String get minutes30 => '30 Minuten';

  @override
  String get screenshotByYou => 'Du hast einen Screenshot vom Chat gemacht';

  @override
  String screenshotByPeer(String name) {
    return '$name hat einen Screenshot vom Chat gemacht';
  }

  @override
  String get recordingByYou => 'Du nimmst den Bildschirm auf';

  @override
  String recordingByPeer(String name) {
    return '$name nimmt den Bildschirm auf';
  }

  @override
  String get screenshotNotice => 'Screenshot-Hinweis';

  @override
  String get screenshotNoticeDescription =>
      'Beide Seiten erfahren von Screenshots und Bildschirmaufnahmen';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get legalSection => 'Rechtliches';

  @override
  String get identityTitle => 'Identität';

  @override
  String get identityVerified => 'Bestätigt';

  @override
  String get identityBadge => 'Sicher';

  @override
  String get scanSafetyNumber => 'Code scannen';

  @override
  String get safetyNumberScanHint =>
      'Richte die Kamera auf die Sicherheitsnummer deines Kontakts';

  @override
  String safetyNumberMatches(String name) {
    return 'Die Nummern stimmen überein — $name ist bestätigt.';
  }

  @override
  String get safetyNumberDiffers => 'Die Nummern stimmen nicht überein.';

  @override
  String get safetyNumberDiffersHint =>
      'Möglicherweise hört jemand mit. Schick nichts Vertrauliches, bis ihr das persönlich geklärt habt.';

  @override
  String get safetyNumberNotRecognised =>
      'Das ist keine Sicherheitsnummer. Scanne den Code, der bei deinem Kontakt unter der Sicherheitsnummer steht.';

  @override
  String get verifiedContact => 'bestätigt';
}
