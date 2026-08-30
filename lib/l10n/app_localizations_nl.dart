// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Rekenmachine';

  @override
  String get messenger => 'Berichten';

  @override
  String get settings => 'Instellingen';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacten';

  @override
  String get setupTitle => 'Welkom bij Krypta ECC';

  @override
  String get setupSubtitle => 'Stel je geheime codes in om te beginnen';

  @override
  String get secretCodeLabel => 'Geheime code';

  @override
  String get secretCodeHint => 'Voer de code in die je berichten ontgrendelt';

  @override
  String get deleteCodeLabel => 'Wiscode';

  @override
  String get deleteCodeHint => 'Voer een code in die alle gegevens direct wist';

  @override
  String get setupComplete => 'Instellen voltooid';

  @override
  String get setupContinue => 'Doorgaan';

  @override
  String get setupCodesInfo =>
      'Alle codes moeten verschillend zijn en minstens 4 cijfers hebben';

  @override
  String get back => 'Terug';

  @override
  String get next => 'Volgende';

  @override
  String get newChat => 'Nieuw gesprek';

  @override
  String get typeMessage => 'Typ een bericht...';

  @override
  String get send => 'Verstuur';

  @override
  String get delivered => 'Bezorgd';

  @override
  String get sent => 'Verzonden';

  @override
  String get read => 'Gelezen';

  @override
  String get typing => 'aan het typen...';

  @override
  String get selfDestructTimer => 'Zelfvernietigingstimer';

  @override
  String get seconds30 => '30 seconden';

  @override
  String get minutes5 => '5 minuten';

  @override
  String get hour1 => '1 uur';

  @override
  String get day1 => '1 dag';

  @override
  String get week1 => '1 week';

  @override
  String get off => 'Uit';

  @override
  String get emergencyDelete => 'Noodwissing';

  @override
  String get emergencyDeleteDescription =>
      'Wis direct alle gegevens en sleutels en meld af';

  @override
  String get allDataDeleted => 'Alle gegevens zijn gewist';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get securitySettings => 'Beveiliging';

  @override
  String get changeSecretCode => 'Geheime code wijzigen';

  @override
  String get changeDeleteCode => 'Wiscode wijzigen';

  @override
  String get biometricUnlock => 'Biometrisch ontgrendelen';

  @override
  String get biometricDescription =>
      'Face ID of vingerafdruk vereisen na het invoeren van de code';

  @override
  String get autoDeleteMessages => 'Berichten automatisch wissen';

  @override
  String get accountSection => 'Account';

  @override
  String get privacySection => 'Privacy';

  @override
  String get dangerZone => 'Risicozone';

  @override
  String get deleteAccount => 'Account en gegevens verwijderen';

  @override
  String get about => 'Over Krypta ECC';

  @override
  String version(String version) {
    return 'Versie $version';
  }

  @override
  String get noChats => 'Nog geen gesprekken';

  @override
  String get noChatsSubtitle =>
      'Begin een nieuw gesprek om veilig te berichten';

  @override
  String get encryptionInfo => 'Berichten zijn end-to-end versleuteld';

  @override
  String get anonymousUser => 'Anonieme gebruiker';

  @override
  String get userIdLabel => 'Jouw ID';

  @override
  String get userIdCopied => 'Gebruikers-ID naar het klembord gekopieerd';

  @override
  String get addContactById => 'Contact toevoegen via ID';

  @override
  String get contactIdHint => 'Voer de contact-ID in';

  @override
  String get addContact => 'Contact toevoegen';

  @override
  String get cannotAddYourself => 'Je kunt jezelf niet toevoegen';

  @override
  String get userNotFound => 'Gebruiker niet gevonden';

  @override
  String get myQrCode => 'Mijn QR-code';

  @override
  String get scanQrCode => 'QR-code scannen';

  @override
  String get scanQr => 'QR scannen';

  @override
  String get qrScanHint => 'Richt je camera op een QR-code van Krypta';

  @override
  String get qrShareHint => 'Laat anderen deze scannen om verbinding te maken';

  @override
  String get yourQrCode => 'Jouw QR-code';

  @override
  String get idCopied => 'ID gekopieerd';

  @override
  String get qrWebUnavailable =>
      'QR-codes scannen is niet beschikbaar op het web.\nGebruik een mobiel apparaat om QR-codes te scannen.';

  @override
  String get thatsYourOwnId => 'Dat is je eigen ID';

  @override
  String get renameChat => 'Gesprek hernoemen';

  @override
  String get chatName => 'Naam van het gesprek';

  @override
  String get save => 'Bewaren';

  @override
  String get cancel => 'Annuleren';

  @override
  String get skip => 'Overslaan';

  @override
  String get deleteChat => 'Gesprek verwijderen';

  @override
  String get clearChat => 'Gesprek leegmaken';

  @override
  String clearChatConfirm(String name) {
    return 'Alle berichten in deze chat verwijderen? Bij $name verdwijnen ook de berichten die jij hebt gestuurd — die van hen blijven staan. Dit kan niet ongedaan worden gemaakt.';
  }

  @override
  String get autoDeleteTimer => 'Timer voor automatisch wissen';

  @override
  String get autoDeleteHint =>
      'Nieuwe berichten in dit gesprek vernietigen zichzelf na de gekozen tijd.';

  @override
  String get chatDefault => 'Standaard voor dit gesprek';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Standaard voor dit gesprek ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'Berichten worden automatisch gewist na $timer';
  }

  @override
  String get onlyVisibleToYou => 'Alleen zichtbaar voor jou';

  @override
  String get burnAfterRead => 'Vernietigen na lezen';

  @override
  String get passwordProtected => 'Beveiligd met wachtwoord';

  @override
  String get lockMessage => 'Bericht vergrendelen';

  @override
  String get lockMessageHint =>
      'Stel een wachtwoord in voor het volgende bericht. De ontvanger moet dit invoeren om het te lezen.';

  @override
  String get enterPassword => 'Voer het wachtwoord in';

  @override
  String get setPassword => 'Wachtwoord instellen';

  @override
  String get passwordRequired => 'Wachtwoord vereist';

  @override
  String get passwordRequiredHint =>
      'Voer het wachtwoord in om dit bericht te ontsleutelen.';

  @override
  String get password => 'Wachtwoord';

  @override
  String get unlock => 'Ontgrendelen';

  @override
  String get unlocked => 'Ontgrendeld';

  @override
  String get wrongPassword => 'Onjuist wachtwoord';

  @override
  String get tapToUnlock => 'Tik om te ontgrendelen';

  @override
  String get nameThisContact => 'Geef dit contact een naam';

  @override
  String get nameContactHint =>
      'Geef dit contact een naam zodat je weet wie het is. Alleen jij ziet dit label.';

  @override
  String get nameContactPlaceholder => 'bijv. Alex, mama, werk...';

  @override
  String get selfDestructTimerLabel => 'Zelfvernietigingstimer';

  @override
  String get vaultPassword => 'Kluiswachtwoord';

  @override
  String get vaultPasswordDescription =>
      'Een sterk wachtwoord vereisen na de code, voordat je de berichten opent';

  @override
  String get vaultPasswordTitle => 'Kluis vergrendeld';

  @override
  String get vaultPasswordHint =>
      'Voer je kluiswachtwoord in om bij je berichten te komen.';

  @override
  String get setVaultPassword => 'Kluiswachtwoord instellen';

  @override
  String get changeVaultPassword => 'Kluiswachtwoord wijzigen';

  @override
  String get removeVaultPassword => 'Kluiswachtwoord verwijderen';

  @override
  String get vaultPasswordSet => 'Kluiswachtwoord ingesteld';

  @override
  String get vaultPasswordRemoved => 'Kluiswachtwoord verwijderd';

  @override
  String get vaultPasswordRules =>
      'Minstens 10 tekens, met hoofdletter, kleine letter, cijfer en speciaal teken.';

  @override
  String get newPassword => 'Nieuw wachtwoord';

  @override
  String get confirmPassword => 'Wachtwoord bevestigen';

  @override
  String get passwordsDoNotMatch => 'De wachtwoorden komen niet overeen';

  @override
  String get passwordTooWeak => 'Het wachtwoord voldoet niet aan de eisen';

  @override
  String get copy => 'Kopiëren';

  @override
  String get copied => 'Gekopieerd';

  @override
  String get delete => 'Verwijderen';

  @override
  String get deleteMessage => 'Bericht verwijderen';

  @override
  String get deleteMessageConfirm =>
      'Dit bericht wordt definitief van dit apparaat verwijderd.';

  @override
  String get deleteForMe => 'Voor mij verwijderen';

  @override
  String get deleteForEveryone => 'Voor iedereen verwijderen';

  @override
  String get deleteForEveryoneConfirm =>
      'Dit bericht wordt zowel bij jou als bij de ontvanger verwijderd.';

  @override
  String get qrInvalidFormat =>
      'Ongeldig QR-codeformaat. Alleen QR-codes van Krypta worden geaccepteerd.';

  @override
  String get qrUnsupportedVersion =>
      'Niet-ondersteunde QR-codeversie. Werk de app bij.';

  @override
  String get qrFingerprintMismatch =>
      'Beveiligingswaarschuwing: de vingerafdruk van de QR-code is gemanipuleerd. Bewerking afgebroken.';

  @override
  String get qrKeyMismatch =>
      'BEVEILIGINGSWAARSCHUWING: de sleutel van de server komt NIET overeen met die van de QR-code. Mogelijke aanval gedetecteerd. Het contact is geblokkeerd.';

  @override
  String get qrVerified => 'Sleutel geverifieerd';

  @override
  String get verificationStale => 'De verificatie is ouder dan 90 dagen';

  @override
  String get verifyNow => 'Opnieuw verifiëren';

  @override
  String get showTutorial => 'Uitleg opnieuw bekijken';

  @override
  String get showTutorialSubtitle => 'De introductie opnieuw afspelen';

  @override
  String get openSourceLicenses => 'Opensourcelicenties';

  @override
  String get openSourceLicensesSubtitle =>
      'Bibliotheken van derden en vermeldingen';

  @override
  String get aboutClose => 'Sluiten';

  @override
  String get confirm => 'Bevestigen';

  @override
  String lockedForSeconds(int seconds) {
    return 'Vergrendeld gedurende $seconds seconden.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Nog $remaining pogingen',
      one: 'Nog 1 poging',
    );
    return 'Onjuist wachtwoord. $_temp0 voordat alle gegevens worden gewist.';
  }

  @override
  String get keysNotPublishedDenied =>
      'De server heeft je sleutels geweigerd – niemand kan je berichten sturen.';

  @override
  String get keysNotPublishedFailed =>
      'Je sleutels konden niet worden gepubliceerd – niemand kan je berichten sturen.';

  @override
  String get biometricUnlockReason => 'Krypta Messenger ontgrendelen';

  @override
  String get deviceCompromised => 'Het apparaat is mogelijk gecompromitteerd.';

  @override
  String get deviceCompromisedDegraded =>
      'Het apparaat is mogelijk gecompromitteerd. Hardwarebeveiliging uitgeschakeld.';

  @override
  String get fieldRequired => 'Verplicht';

  @override
  String codeMinDigits(int count) {
    return 'Minstens $count cijfers';
  }

  @override
  String get codeDigitsOnly => 'Alleen cijfers';

  @override
  String get deleteCodeMustDiffer =>
      'De wiscode moet verschillen van je geheime code.';

  @override
  String get setupFailed => 'Instellen is mislukt. Probeer het opnieuw.';

  @override
  String get setupSecretCodeSubtitle =>
      'Voer deze in de rekenmachine in om je kluis te openen.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Wist alles onmiddellijk. Gebruik dit alleen in noodgevallen.';

  @override
  String get contactKeyChangedWarning =>
      'De beveiligingssleutel van dit contact is gewijzigd. Berichten zijn geblokkeerd totdat je zijn identiteit hebt geverifieerd. Scan zijn QR-code of vergelijk de veiligheidsnummers om verder te gaan.';

  @override
  String get verifyIdentity => 'Identiteit verifiëren';

  @override
  String get safetyNumberCompareHint =>
      'Vergelijk de veiligheidsnummers of scan de QR-codes om de end-to-endversleuteling te verifiëren.';

  @override
  String get viewSafetyNumber => 'Veiligheidsnummer tonen';

  @override
  String get safetyNumberTitle => 'Veiligheidsnummer';

  @override
  String get safetyNumberCopied => 'Veiligheidsnummer gekopieerd';

  @override
  String get safetyNumberMatchHint =>
      'Vergelijk dit nummer met je contact. Komen ze overeen, dan is jullie gesprek veilig.';

  @override
  String get verificationFailedKeyMismatch =>
      'Verificatie mislukt – de sleutels komen niet overeen';

  @override
  String get markVerified => 'Als geverifieerd markeren';

  @override
  String get securitySettingsReason => 'Beveiligingsinstellingen wijzigen';

  @override
  String get vaultPasswordReAuthHint =>
      'Voer je kluiswachtwoord in om de beveiligingsinstellingen te wijzigen.';

  @override
  String get codeAlreadyInUse =>
      'Deze code wordt al voor een andere actie gebruikt.';

  @override
  String get deviceSecure => 'Apparaat veilig';

  @override
  String get deviceCompromisedDetected => 'Compromittering gedetecteerd';

  @override
  String get deviceStatusUnknown => 'Status onbekend';

  @override
  String get deviceSecureSubtitle =>
      'Geen aanwijzingen voor root, jailbreak of Frida';

  @override
  String get deviceCompromisedSubtitle =>
      'Root, jailbreak of instrumentatie gedetecteerd. Hardwarebeveiliging uitgeschakeld.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'Integriteitscontrole mislukt – beperkte modus actief.';

  @override
  String get hardwareEnclave => 'Hardware-enclave';

  @override
  String get hardwareTee => 'TEE-sleutelopslag';

  @override
  String get hardwareSoftware => 'Softwarematige sleutelopslag';

  @override
  String get hardwareBoundSubtitle => 'Databasesleutel aan hardware gebonden';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave beschikbaar';

  @override
  String get hardwareTeeSubtitle =>
      'Sleutel bewaard in de Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle => 'Geen hardwarebeveiliging beschikbaar';

  @override
  String get pushPrivacy => 'Privacy van meldingen';

  @override
  String get pushPrivacyOn => 'Aan – berichten worden opgehaald via polling';

  @override
  String get pushPrivacyOff => 'Uit – pushmeldingen actief';

  @override
  String get readReceipts => 'Leesbevestigingen';

  @override
  String get readReceiptsOn => 'Aan – de afzender ziet wanneer je leest';

  @override
  String get readReceiptsOff => 'Uit – maximale privacy';

  @override
  String get deliveryReceipts => 'Bezorgbevestigingen';

  @override
  String get deliveryReceiptsOn =>
      'Aan – de afzender ziet wanneer het bericht is bezorgd';

  @override
  String get deliveryReceiptsOff => 'Uit – maximale privacy';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Privacyverklaring\n\nLaatst bijgewerkt: april 2026\n\n1. Verwerkingsverantwoordelijke\nConnexa GmbH\nContact: https://connexa-gmbh.ch\n\n2. Welke gegevens worden verzameld?\nKrypta verzamelt zo weinig gegevens als technisch mogelijk is:\n• Anoniem Firebase-ID (geen e-mailadres, geen naam, geen telefoonnummer)\n• Openbare versleutelingssleutel (X25519)\n• FCM-pushtoken (voor meldingen)\n\n3. Versleuteling\nAlle berichten zijn end-to-end versleuteld (Signal-protocol: X3DH + Double Ratchet). De server heeft op geen enkel moment toegang tot de leesbare tekst van je berichten. Versleuteling: XChaCha20-Poly1305. Wachtwoord-hashing: Argon2id.\n\n4. Gegevensopslag\n• Berichten worden alleen op je eigen apparaat bewaard (versleuteld)\n• De server dient uitsluitend als tijdelijke doorgeefluik — berichten worden na bezorging verwijderd\n• Sleutels worden bewaard in de iOS-sleutelhanger / Android Keystore\n\n5. Geen trackers\nKrypta bevat geen analysetools, geen advertenties en geen trackers (0 van 432 bekende trackers).\n\n6. Doorgifte van gegevens\nEr worden geen persoonsgegevens aan derden doorgegeven. Google Firebase wordt gebruikt als infrastructuuraanbieder (anonieme authenticatie en pushmeldingen).\n\n7. Gegevens wissen\nJe kunt al je gegevens op elk moment onherroepelijk wissen:\n• In de instellingen via «Alles wissen»\n• Door de wiscode in de rekenmachine in te voeren\nDaarmee worden alle lokale gegevens, sleutels en servergegevens vernietigd.\n\n8. Jouw rechten (AVG)\nJe hebt recht op inzage, rectificatie, wissing en overdraagbaarheid van gegevens. Neem contact met ons op via: https://connexa-gmbh.ch\n\n9. Wijzigingen\nDeze privacyverklaring kan worden bijgewerkt. De geldende versie is altijd in de app te raadplegen.';

  @override
  String get tutStartSetup => 'Instellen starten';

  @override
  String get tutWelcomeTitle => 'Welkom bij Krypta';

  @override
  String get tutWelcomeBody =>
      'Krypta is een geheime berichtenapp.\n\nVoor iedereen anders ziet de app eruit als een gewone rekenmachine — niemand zal vermoeden dat er een versleuteld gesprek achter schuilgaat.\n\nWe raden je aan deze uitleg aandachtig te lezen.';

  @override
  String get tutSecretCodeTitle => 'Je geheime code';

  @override
  String get tutSecretCodeBody =>
      'Bij het instellen kies je een cijfercode.\n\nDeze code is je sleutel: alleen daarmee open je de verborgen berichtenapp.';

  @override
  String get tutDeleteCodeBody =>
      'De tweede code is voor noodgevallen.\n\nAls je die invoert wordt alles onmiddellijk gewist: berichten, sleutels, account. Onherroepelijk.\n\nKies een code die je niet per ongeluk invoert.';

  @override
  String get tutDeleteCodeWarning =>
      'Alles wordt onmiddellijk gewist.\nHerstel is niet mogelijk.';

  @override
  String get tutOpenMessengerTitle => 'De berichtenapp openen';

  @override
  String get tutOpenMessengerBody =>
      'Zo open je je berichtenapp:\n\n1. Voer je geheime code in op de rekenmachine\n2. Druk op de =-toets\n\nDe berichtenapp gaat meteen open.';

  @override
  String get tutPressEquals => 'Druk op =';

  @override
  String get tutMessengerUnlocked => 'Berichtenapp ontgrendeld';

  @override
  String get tutVaultBody =>
      'In de instellingen kun je een extra wachtwoord inschakelen.\n\nNa de geheime code wordt dan ook het kluiswachtwoord gevraagd — dubbele beveiliging voor je berichten.';

  @override
  String get tutAddContactsTitle => 'Contacten toevoegen';

  @override
  String get tutAddContactsBody =>
      'Er zijn twee manieren om contacten toe te voegen:\n\n• Een QR-code scannen — snel en eenvoudig\n• Een gebruikers-ID invoeren — als jullie niet op dezelfde plek zijn\n\nDaarna kunnen jullie elkaar berichten sturen.';

  @override
  String get tutQrFast => 'Snel en eenvoudig';

  @override
  String get tutEnterUserId => 'Gebruikers-ID invoeren';

  @override
  String get tutForRemoteContacts => 'Voor contacten op afstand';

  @override
  String get tutEmergencyBody =>
      'In de app vind je rode noodknoppen.\n\nZe wissen alles onmiddellijk — net als de wiscode. Gebruik ze alleen als het er echt op aankomt.';

  @override
  String get tutInSettings => 'In de instellingen';

  @override
  String get tutChatFeaturesIntro =>
      'In een gesprek heb je drie bijzondere functies:';

  @override
  String get tutLockMessageDesc =>
      'Losse berichten met een wachtwoord beschermen';

  @override
  String get tutAutoDeleteDesc =>
      'Berichten wissen zichzelf na een ingestelde tijd';

  @override
  String get tutBurnAfterReadDesc =>
      'Het bericht wordt direct na het lezen verwijderd';

  @override
  String get tutReadyTitle => 'Klaar!';

  @override
  String get tutReadyBody =>
      'Je weet nu alles wat je nodig hebt.\n\nIn de volgende stap stel je je codes in — daarna is je berichtenapp klaar voor gebruik.';

  @override
  String get language => 'Taal';

  @override
  String get chooseLanguage => 'Kies je taal';

  @override
  String get deviceSecuritySection => 'Apparaatbeveiliging';

  @override
  String get tutDeleteCodeTitle => 'Noodcode';

  @override
  String get tutEmergencyTitle => 'Noodknoppen';

  @override
  String get tutChatFeaturesTitle => 'Gespreksfuncties';

  @override
  String get blockContact => 'Blokkeren';

  @override
  String get authentication => 'Authenticatie';

  @override
  String get contactRequestTitle => 'Contactverzoek';

  @override
  String get contactRequestIncomingHint =>
      'Deze persoon wil je berichten sturen. Jullie kunnen elkaar pas schrijven als je accepteert.';

  @override
  String get acceptRequest => 'Accepteren';

  @override
  String get declineRequest => 'Weigeren';

  @override
  String get contactRequestSent => 'Verzoek verstuurd';

  @override
  String get contactRequestWaitingHint =>
      'Je kunt schrijven zodra de ander accepteert.';

  @override
  String get resendRequest => 'Opnieuw verzoeken';

  @override
  String get acceptToReply => 'Accepteer het verzoek om te antwoorden';

  @override
  String get requestBadge => 'Verzoek';

  @override
  String get blockContactConfirm =>
      'Deze persoon blokkeren? Diegene kan je dan niet meer berichten sturen en hoort daar niets over.';

  @override
  String get unblockContact => 'Deblokkeren';

  @override
  String get contactBlocked => 'Geblokkeerd';

  @override
  String get minute1 => '1 minuut';

  @override
  String get welcomeBack => 'Welkom terug';

  @override
  String get minutes30 => '30 minuten';

  @override
  String get screenshotByYou =>
      'Je hebt een schermafbeelding van het gesprek gemaakt';

  @override
  String screenshotByPeer(String name) {
    return '$name heeft een schermafbeelding van het gesprek gemaakt';
  }

  @override
  String get recordingByYou => 'Je neemt het scherm op';

  @override
  String recordingByPeer(String name) {
    return '$name neemt het scherm op';
  }

  @override
  String get screenshotNotice => 'Melding bij schermafbeelding';

  @override
  String get screenshotNoticeDescription =>
      'Beide kanten horen het bij schermafbeeldingen en opnames';

  @override
  String get privacyPolicy => 'Privacyverklaring';

  @override
  String get legalSection => 'Juridisch';

  @override
  String get identityTitle => 'Identiteit';

  @override
  String get identityVerified => 'Geverifieerd';

  @override
  String get identityBadge => 'Veilig';

  @override
  String get scanSafetyNumber => 'Code scannen';

  @override
  String get safetyNumberScanHint =>
      'Richt de camera op het veiligheidsnummer van je contact';

  @override
  String safetyNumberMatches(String name) {
    return 'De nummers komen overeen — $name is geverifieerd.';
  }

  @override
  String get safetyNumberDiffers => 'De nummers komen niet overeen.';

  @override
  String get safetyNumberDiffersHint =>
      'Mogelijk luistert iemand mee. Stuur niets vertrouwelijks totdat je dit persoonlijk hebt nagegaan.';

  @override
  String get safetyNumberNotRecognised =>
      'Dat is geen veiligheidsnummer. Scan de code die bij je contact onder het veiligheidsnummer staat.';

  @override
  String get verifiedContact => 'geverifieerd';

  @override
  String accountGone(String name) {
    return '$name bestaat niet meer';
  }

  @override
  String get accountGoneCannotWrite =>
      'Dit account bestaat niet meer — hier kun je niets meer schrijven.';
}
