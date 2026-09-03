// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Calculatrice';

  @override
  String get messenger => 'Messagerie';

  @override
  String get settings => 'Réglages';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get setupTitle => 'Bienvenue dans Krypta ECC';

  @override
  String get setupSubtitle => 'Configurez vos codes secrets pour commencer';

  @override
  String get secretCodeLabel => 'Code secret';

  @override
  String get secretCodeHint =>
      'Saisissez le code qui déverrouille votre messagerie';

  @override
  String get deleteCodeLabel => 'Code d’effacement';

  @override
  String get deleteCodeHint =>
      'Saisissez un code qui efface toutes les données immédiatement';

  @override
  String get setupComplete => 'Configuration terminée';

  @override
  String get setupContinue => 'Continuer';

  @override
  String get setupCodesInfo =>
      'Tous les codes doivent être différents et comporter au moins 4 chiffres';

  @override
  String get back => 'Retour';

  @override
  String get next => 'Suivant';

  @override
  String get newChat => 'Nouvelle discussion';

  @override
  String get typeMessage => 'Écrivez un message...';

  @override
  String get send => 'Envoyer';

  @override
  String get delivered => 'Remis';

  @override
  String get sent => 'Envoyé';

  @override
  String get read => 'Lu';

  @override
  String get typing => 'en train d’écrire...';

  @override
  String get selfDestructTimer => 'Minuteur d’autodestruction';

  @override
  String get seconds30 => '30 secondes';

  @override
  String get minutes5 => '5 minutes';

  @override
  String get hour1 => '1 heure';

  @override
  String get day1 => '1 jour';

  @override
  String get week1 => '1 semaine';

  @override
  String get off => 'Désactivé';

  @override
  String get emergencyDelete => 'Effacement d’urgence';

  @override
  String get emergencyDeleteDescription =>
      'Effacer immédiatement toutes les données et les clés, puis se déconnecter';

  @override
  String get allDataDeleted => 'Toutes les données ont été effacées';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get securitySettings => 'Sécurité';

  @override
  String get changeSecretCode => 'Changer le code secret';

  @override
  String get changeDeleteCode => 'Changer le code d’effacement';

  @override
  String get biometricUnlock => 'Déverrouillage biométrique';

  @override
  String get biometricDescription =>
      'Exiger Face ID ou l’empreinte après la saisie du code';

  @override
  String get autoDeleteMessages => 'Effacement automatique des messages';

  @override
  String get accountSection => 'Compte';

  @override
  String get privacySection => 'Confidentialité';

  @override
  String get dangerZone => 'Zone sensible';

  @override
  String get deleteAccount => 'Supprimer le compte et les données';

  @override
  String get about => 'À propos de Krypta ECC';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get noChats => 'Aucune conversation pour l’instant';

  @override
  String get noChatsSubtitle =>
      'Démarrez une discussion pour échanger en toute sécurité';

  @override
  String get encryptionInfo => 'Les messages sont chiffrés de bout en bout';

  @override
  String get anonymousUser => 'Utilisateur anonyme';

  @override
  String get userIdLabel => 'Votre identifiant';

  @override
  String get userIdCopied => 'Identifiant copié dans le presse-papiers';

  @override
  String get addContactById => 'Ajouter un contact par identifiant';

  @override
  String get contactIdHint => 'Saisissez l’identifiant du contact';

  @override
  String get addContact => 'Ajouter le contact';

  @override
  String get cannotAddYourself => 'Vous ne pouvez pas vous ajouter vous-même';

  @override
  String get userNotFound => 'Utilisateur introuvable';

  @override
  String get myQrCode => 'Mon code QR';

  @override
  String get scanQrCode => 'Scanner un code QR';

  @override
  String get scanQr => 'Scanner le QR';

  @override
  String get qrScanHint => 'Dirigez l’appareil photo vers un code QR Krypta';

  @override
  String get qrShareHint =>
      'Les autres peuvent scanner ce code QR pour t’ajouter comme contact.';

  @override
  String get yourQrCode => 'Votre code QR';

  @override
  String get idCopied => 'Identifiant copié';

  @override
  String get qrWebUnavailable =>
      'Le scan de codes QR n’est pas disponible sur le web.\nUtilisez un appareil mobile pour scanner des codes QR.';

  @override
  String get thatsYourOwnId => 'C’est votre propre identifiant';

  @override
  String get renameChat => 'Renommer la discussion';

  @override
  String get chatName => 'Nom de la discussion';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get skip => 'Ignorer';

  @override
  String get deleteChat => 'Supprimer la discussion';

  @override
  String get deleteContact => 'Supprimer le contact';

  @override
  String get deleteContactTitle => 'Supprimer le contact ?';

  @override
  String deleteContactBody(String name) {
    return '$name disparaît de votre liste de contacts, ainsi que votre discussion. Rien ne change de l’autre côté. Cette personne pourra vous envoyer une nouvelle demande plus tard.';
  }

  @override
  String get clearChat => 'Vider la discussion';

  @override
  String clearChatConfirm(String name) {
    return 'Supprimer tous les messages de cette conversation ? Chez $name, les messages que tu as envoyés disparaîtront aussi — les siens restent. Cette action est irréversible.';
  }

  @override
  String get autoDeleteTimer => 'Minuteur d’effacement automatique';

  @override
  String get autoDeleteHint =>
      'Les nouveaux messages de cette discussion s’autodétruiront après le délai choisi.';

  @override
  String get chatDefault => 'Réglage par défaut de la discussion';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Réglage par défaut de la discussion ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'Les messages s’effacent automatiquement après $timer';
  }

  @override
  String get onlyVisibleToYou => 'Visible uniquement par vous';

  @override
  String get passwordProtected => 'Protégé par mot de passe';

  @override
  String get lockMessage => 'Verrouiller le message';

  @override
  String get lockMessageHint =>
      'Définissez un mot de passe pour le prochain message. Le destinataire devra le saisir pour le lire.';

  @override
  String get enterPassword => 'Saisissez le mot de passe';

  @override
  String get setPassword => 'Définir le mot de passe';

  @override
  String get passwordRequired => 'Mot de passe requis';

  @override
  String get passwordRequiredHint =>
      'Saisissez le mot de passe pour déchiffrer ce message.';

  @override
  String get password => 'Mot de passe';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get unlocked => 'Déverrouillé';

  @override
  String get wrongPassword => 'Mot de passe incorrect';

  @override
  String get tapToUnlock => 'Touchez pour déverrouiller';

  @override
  String get awaitingUnlock => 'Visible une fois déverrouillé';

  @override
  String get unblockToSend => 'Débloque ce contact pour envoyer des messages.';

  @override
  String selfDestructSetTo(String dauer) {
    return 'Autodestruction réglée sur $dauer';
  }

  @override
  String get selfDestructTurnedOff => 'Autodestruction désactivée';

  @override
  String get nameThisContact => 'Nommez ce contact';

  @override
  String get nameContactHint =>
      'Donnez un nom à ce contact pour savoir de qui il s’agit. Vous seul voyez cette étiquette.';

  @override
  String get nameContactPlaceholder => 'p. ex. Alex, maman, travail...';

  @override
  String get selfDestructTimerLabel => 'Minuteur d’autodestruction';

  @override
  String get vaultPassword => 'Mot de passe du coffre';

  @override
  String get vaultPasswordDescription =>
      'Exiger un mot de passe fort après le code, avant d’accéder à la messagerie';

  @override
  String get vaultPasswordTitle => 'Coffre verrouillé';

  @override
  String get vaultPasswordHint =>
      'Saisissez le mot de passe du coffre pour accéder à la messagerie.';

  @override
  String get setVaultPassword => 'Définir le mot de passe du coffre';

  @override
  String get changeVaultPassword => 'Changer le mot de passe du coffre';

  @override
  String get removeVaultPassword => 'Supprimer le mot de passe du coffre';

  @override
  String get vaultPasswordSet => 'Mot de passe du coffre défini';

  @override
  String get vaultPasswordRemoved => 'Mot de passe du coffre supprimé';

  @override
  String get vaultPasswordRules =>
      'Au moins 10 caractères, avec majuscule, minuscule, chiffre et caractère spécial.';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get confirmPassword => 'Confirmer le mot de passe';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get passwordTooWeak => 'Le mot de passe ne respecte pas les exigences';

  @override
  String get copy => 'Copier';

  @override
  String get copied => 'Copié';

  @override
  String get delete => 'Supprimer';

  @override
  String get deleteMessage => 'Supprimer le message';

  @override
  String get deleteMessageConfirm =>
      'Ce message sera définitivement supprimé de cet appareil.';

  @override
  String get deleteForMe => 'Supprimer pour moi';

  @override
  String get deleteForEveryone => 'Supprimer pour tout le monde';

  @override
  String get deleteForEveryoneConfirm =>
      'Ce message sera supprimé pour vous comme pour le destinataire.';

  @override
  String get qrInvalidFormat =>
      'Format de code QR invalide. Seuls les codes QR Krypta sont acceptés.';

  @override
  String get qrUnsupportedVersion =>
      'Version de code QR non prise en charge. Veuillez mettre l’application à jour.';

  @override
  String get qrFingerprintMismatch =>
      'Alerte de sécurité : l’empreinte du code QR a été altérée. Opération annulée.';

  @override
  String get qrKeyMismatch =>
      'ALERTE DE SÉCURITÉ : la clé du serveur ne correspond PAS à celle du code QR. Attaque possible détectée. Le contact a été bloqué.';

  @override
  String get qrVerified => 'Clé vérifiée';

  @override
  String get verificationStale => 'La vérification date de plus de 90 jours';

  @override
  String get verifyNow => 'Vérifier à nouveau';

  @override
  String get showTutorial => 'Revoir le tutoriel';

  @override
  String get showTutorialSubtitle => 'Rejouer l’introduction';

  @override
  String get openSourceLicenses => 'Licences open source';

  @override
  String get openSourceLicensesSubtitle => 'Bibliothèques tierces et mentions';

  @override
  String get aboutClose => 'Fermer';

  @override
  String get confirm => 'Confirmer';

  @override
  String lockedForSeconds(int seconds) {
    return 'Verrouillé pendant $seconds secondes.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Il reste $remaining tentatives',
      one: 'Il reste 1 tentative',
    );
    return 'Mot de passe incorrect. $_temp0 avant l’effacement de toutes les données.';
  }

  @override
  String get keysNotPublishedDenied =>
      'Le serveur a refusé vos clés – personne ne peut vous écrire.';

  @override
  String get keysNotPublishedFailed =>
      'Vos clés n’ont pas pu être publiées – personne ne peut vous écrire.';

  @override
  String get biometricUnlockReason => 'Déverrouiller Krypta Messenger';

  @override
  String get deviceCompromised => 'L’appareil est peut-être compromis.';

  @override
  String get deviceCompromisedDegraded =>
      'L’appareil est peut-être compromis. Sécurité matérielle désactivée.';

  @override
  String get fieldRequired => 'Obligatoire';

  @override
  String codeMinDigits(int count) {
    return 'Au moins $count chiffres';
  }

  @override
  String get codeDigitsOnly => 'Chiffres uniquement';

  @override
  String get deleteCodeMustDiffer =>
      'Le code d’effacement doit être différent de votre code secret.';

  @override
  String get setupFailed => 'La configuration a échoué. Veuillez réessayer.';

  @override
  String get setupSecretCodeSubtitle =>
      'Saisissez-le dans la calculatrice pour ouvrir votre coffre.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Efface tout immédiatement. À n’utiliser qu’en cas d’urgence.';

  @override
  String get contactKeyChangedWarning =>
      'La clé de sécurité de ce contact a changé. Les messages sont bloqués tant que vous n’avez pas vérifié son identité. Scannez son code QR ou comparez vos numéros de sécurité pour reprendre la conversation.';

  @override
  String get verifyIdentity => 'Vérifier l’identité';

  @override
  String get safetyNumberCompareHint =>
      'Comparez les numéros de sécurité ou scannez les codes QR pour vérifier le chiffrement de bout en bout.';

  @override
  String get viewSafetyNumber => 'Afficher le numéro de sécurité';

  @override
  String get safetyNumberTitle => 'Numéro de sécurité';

  @override
  String get safetyNumberCopied => 'Numéro de sécurité copié';

  @override
  String get safetyNumberMatchHint =>
      'Comparez ce numéro avec votre contact. S’ils correspondent, votre conversation est sécurisée.';

  @override
  String get verificationFailedKeyMismatch =>
      'La vérification a échoué – les clés ne correspondent pas';

  @override
  String get markVerified => 'Marquer comme vérifié';

  @override
  String get securitySettingsReason => 'Modifier les réglages de sécurité';

  @override
  String get vaultPasswordReAuthHint =>
      'Saisissez le mot de passe du coffre pour modifier les réglages de sécurité.';

  @override
  String get codeAlreadyInUse =>
      'Ce code est déjà utilisé pour une autre action.';

  @override
  String get deviceSecure => 'Appareil sûr';

  @override
  String get deviceCompromisedDetected => 'Compromission détectée';

  @override
  String get deviceStatusUnknown => 'État inconnu';

  @override
  String get deviceSecureSubtitle =>
      'Aucun indice de root, de jailbreak ou de Frida';

  @override
  String get deviceCompromisedSubtitle =>
      'Root, jailbreak ou instrumentation détectés. Sécurité matérielle désactivée.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'Échec du contrôle d’intégrité – mode restreint actif.';

  @override
  String get hardwareEnclave => 'Enclave matérielle';

  @override
  String get hardwareTee => 'Magasin de clés TEE';

  @override
  String get hardwareSoftware => 'Magasin de clés logiciel';

  @override
  String get hardwareBoundSubtitle => 'Clé de base de données liée au matériel';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave disponible';

  @override
  String get hardwareTeeSubtitle =>
      'Clé conservée dans le Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle =>
      'Aucune sécurité matérielle disponible';

  @override
  String get pushPrivacy => 'Confidentialité des notifications';

  @override
  String get pushPrivacyOn =>
      'Activée – les messages sont récupérés par interrogation';

  @override
  String get pushPrivacyOff => 'Désactivée – notifications push actives';

  @override
  String get readReceipts => 'Accusés de lecture';

  @override
  String get readReceiptsOn => 'Activés – l’expéditeur voit quand vous lisez';

  @override
  String get readReceiptsOff => 'Désactivés – confidentialité maximale';

  @override
  String get deliveryReceipts => 'Accusés de réception';

  @override
  String get deliveryReceiptsOn =>
      'Activés – l’expéditeur voit quand le message est remis';

  @override
  String get deliveryReceiptsOff => 'Désactivés – confidentialité maximale';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Politique de confidentialité\n\nDernière mise à jour : avril 2026\n\n1. Responsable du traitement\nConnexa GmbH\nContact : https://connexa-gmbh.ch\n\n2. Quelles données sont collectées ?\nKrypta collecte aussi peu de données que techniquement possible :\n• Identifiant Firebase anonyme (pas d’e-mail, pas de nom, pas de numéro de téléphone)\n• Clé publique de chiffrement (X25519)\n• Jeton push FCM (pour les notifications)\n\n3. Chiffrement\nTous les messages sont chiffrés de bout en bout (protocole Signal : X3DH + Double Ratchet). À aucun moment le serveur n’a accès au texte en clair de vos messages. Chiffrement : XChaCha20-Poly1305. Hachage des mots de passe : Argon2id.\n\n4. Conservation des données\n• Les messages sont conservés uniquement sur votre appareil (chiffrés)\n• Le serveur ne sert que de relais temporaire — les messages sont supprimés après remise\n• Les clés sont conservées dans le trousseau iOS / Android Keystore\n\n5. Aucun traceur\nKrypta ne contient aucun outil d’analyse, aucune publicité et aucun traceur (0 sur 432 traceurs connus).\n\n6. Transmission des données\nAucune donnée personnelle n’est transmise à des tiers. Google Firebase est utilisé comme fournisseur d’infrastructure (authentification anonyme et notifications push).\n\n7. Suppression des données\nVous pouvez supprimer irréversiblement toutes vos données à tout moment :\n• Dans les réglages, via « Tout supprimer »\n• En saisissant le code d’effacement dans la calculatrice\nCela détruit toutes les données locales, les clés et les données côté serveur.\n\n8. Vos droits (RGPD)\nVous disposez d’un droit d’accès, de rectification, d’effacement et de portabilité des données. Contactez-nous à : https://connexa-gmbh.ch\n\n9. Modifications\nCette politique de confidentialité peut être mise à jour. La version en vigueur est toujours consultable dans l’application.';

  @override
  String get tutStartSetup => 'Démarrer la configuration';

  @override
  String get tutWelcomeTitle => 'Bienvenue dans Krypta';

  @override
  String get tutWelcomeBody =>
      'Une calculatrice à l’extérieur. Derrière, tes messages, chiffrés.';

  @override
  String get tutAddContactsTitle => 'Ajouter des contacts';

  @override
  String get tutChatFeaturesIntro =>
      'Des options supplémentaires pour tes messages.';

  @override
  String get tutLockMessageDesc =>
      'Envoie des messages protégés par un mot de passe.';

  @override
  String get tutAutoDeleteDesc =>
      'Règle un minuteur pour toute la discussion. Les messages sont supprimés après la remise.';

  @override
  String get tutReadyTitle => 'Prêt';

  @override
  String get tutReadyBody => 'Il reste un point. C’est le plus important.';

  @override
  String get language => 'Langue';

  @override
  String get chooseLanguage => 'Choisissez votre langue';

  @override
  String get deviceSecuritySection => 'Sécurité de l’appareil';

  @override
  String get tutChatFeaturesTitle => 'Messages';

  @override
  String get blockContact => 'Bloquer';

  @override
  String get authentication => 'Authentification';

  @override
  String get contactRequestTitle => 'Demande de contact';

  @override
  String get contactRequestIncomingHint =>
      'Cette personne souhaite vous écrire. Vous ne pourrez échanger qu’après votre acceptation.';

  @override
  String get acceptRequest => 'Accepter';

  @override
  String get declineRequest => 'Refuser';

  @override
  String get contactRequestSent => 'Demande envoyée';

  @override
  String get contactRequestWaitingHint =>
      'Vous pourrez écrire dès que l’autre personne aura accepté.';

  @override
  String get resendRequest => 'Redemander';

  @override
  String get acceptToReply => 'Acceptez la demande pour répondre';

  @override
  String get requestBadge => 'Demande';

  @override
  String get blockContactConfirm =>
      'Bloquer cette personne ? Elle ne pourra plus vous écrire et n’en sera pas informée.';

  @override
  String get unblockContact => 'Débloquer';

  @override
  String get contactBlocked => 'Bloqué';

  @override
  String get minute1 => '1 minute';

  @override
  String get welcomeBack => 'Bon retour';

  @override
  String get minutes30 => '30 minutes';

  @override
  String get screenshotByYou => 'Vous avez fait une capture de la discussion';

  @override
  String screenshotByPeer(String name) {
    return '$name a fait une capture de la discussion';
  }

  @override
  String get recordingByYou => 'Vous enregistrez l’écran';

  @override
  String recordingByPeer(String name) {
    return '$name enregistre l’écran';
  }

  @override
  String get screenshotNotice => 'Avis de capture';

  @override
  String get screenshotNoticeDescription =>
      'Les deux parties sont informées des captures et enregistrements';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get legalSection => 'Mentions légales';

  @override
  String get identityTitle => 'Identité';

  @override
  String get identityVerified => 'Vérifié';

  @override
  String get identityBadge => 'Sécurisé';

  @override
  String get scanSafetyNumber => 'Scanner le code';

  @override
  String get safetyNumberScanHint =>
      'Dirige la caméra vers le numéro de sécurité de ton contact';

  @override
  String safetyNumberMatches(String name) {
    return 'Les numéros correspondent — $name est vérifié.';
  }

  @override
  String get safetyNumberDiffers => 'Les numéros ne correspondent pas.';

  @override
  String get safetyNumberDiffersHint =>
      'Quelqu\'un intercepte peut-être cette conversation. N\'envoie rien de confidentiel avant d\'avoir vérifié en personne.';

  @override
  String get safetyNumberNotRecognised =>
      'Ce n\'est pas un numéro de sécurité. Scanne le code affiché sous le numéro de sécurité de ton contact.';

  @override
  String get verifiedContact => 'vérifié';

  @override
  String accountGone(String name) {
    return '$name n\'existe plus';
  }

  @override
  String get accountGoneCannotWrite =>
      'Ce compte n\'existe plus — impossible d\'écrire ici.';

  @override
  String get identityKeyConfirmed => 'Clé de sécurité confirmée';

  @override
  String get identityNotConfirmed => 'Contact non confirmé';

  @override
  String get identityConfirmedHint =>
      'La clé de sécurité de ce contact a été comparée avec ton appareil. Cela confirme la clé, pas qui tient le téléphone.';

  @override
  String get identityNotConfirmedHint =>
      'Vos messages sont chiffrés de bout en bout dans tous les cas. Comparez le code QR ou le numéro de sécurité pour confirmer aussi la clé de sécurité.';

  @override
  String get identityAlreadyConfirmed => 'Clé de sécurité déjà confirmée';

  @override
  String scanContactQr(String name) {
    return 'Scanner le code QR de $name';
  }

  @override
  String get blockKeepsVerification =>
      'Le statut de sécurité enregistré est conservé.';

  @override
  String unblockedVerified(String name) {
    return '$name a été débloqué. Le contact reste confirmé.';
  }

  @override
  String unblockedUnverified(String name) {
    return '$name a été débloqué. La clé de sécurité n\'a pas encore été confirmée.';
  }

  @override
  String unblockedKeyChanged(String name) {
    return '$name a été débloqué. La clé de sécurité a changé et doit être confirmée à nouveau.';
  }

  @override
  String get tutDCalculator =>
      'La calculatrice fonctionne vraiment. Rien ne la trahit.';

  @override
  String get tutTEncrypted => 'De bout en bout';

  @override
  String get tutDEncrypted =>
      'Toi et ton contact seuls pouvez lire. Le serveur ne voit rien.';

  @override
  String get tutDLanguage => 'Sept langues. Modifiables à tout moment.';

  @override
  String get tutAccessTitle => 'Ton accès';

  @override
  String get tutAccessIntro =>
      'Quatre choses protègent la messagerie. Tu les règles maintenant.';

  @override
  String get tutTSecretCode => 'Code secret';

  @override
  String get tutDSecretCode =>
      'Tape le dans la calculatrice et appuie sur égal. La messagerie s’ouvre.';

  @override
  String get tutTDeleteCode => 'Code d’effacement';

  @override
  String get tutDDeleteCode =>
      'Un second code. Il efface tout sur le champ, sans demander.';

  @override
  String get tutDVault =>
      'Un mot de passe en plus après le code. Facultatif, mais conseillé.';

  @override
  String get tutDScreenLock =>
      'Face ID au lieu de taper. L’app se verrouille seule quand tu la poses.';

  @override
  String get tutContactsIntro =>
      'Deux façons d’ajouter. Et une pour en être sûr.';

  @override
  String get tutDAddById =>
      'Échange ton ID et saisis le. Cela marche aussi à distance.';

  @override
  String get tutTRequest => 'Demande';

  @override
  String get tutDRequest =>
      'L’autre doit accepter ta demande avant que vous puissiez discuter.';

  @override
  String get tutDQr =>
      'Montre ou scanne un code QR pour ajouter des contacts directement.';

  @override
  String get tutDSafetyNumber =>
      'Compare les numéros de sécurité pour vérifier qui est ton contact et le chiffrement de bout en bout.';

  @override
  String get tutProtectTitle => 'Protection';

  @override
  String get tutProtectIntro =>
      'Plus de contrôle sur tes discussions et tes contacts.';

  @override
  String get tutDScreenshot =>
      'Tu es toujours prévenu si une capture ou un enregistrement de la discussion est réalisé.';

  @override
  String get tutDBlock =>
      'Bloque des contacts pour qu’ils ne puissent plus te joindre, jusqu’à ce que tu les débloques.';

  @override
  String get tutDClear =>
      'Efface l’historique quand tu veux. Les messages que tu as envoyés disparaissent définitivement des deux côtés.';

  @override
  String get tutDDeleteChat =>
      'Retire toute la discussion de ta liste. Les messages que tu as envoyés sont supprimés des deux côtés.';

  @override
  String get tutTEmergency => 'Effacement d’urgence';

  @override
  String get tutDEmergency =>
      'Efface tout immédiatement. Tes contacts en sont informés.';

  @override
  String get tutDSettings => 'Langue, coffre et codes se changent là bas.';

  @override
  String get tutTAgain => 'Cette introduction';

  @override
  String get tutDAgain =>
      'Elle est dans les réglages. Tu peux la relire quand tu veux.';

  @override
  String get onceOnlyMessage => 'Voir une fois';

  @override
  String get openOnceMessage => 'Ouvrir';

  @override
  String get onceOnlyHiddenHint => 'Ouvrable une seule fois';

  @override
  String get onceOnlyConfirmTitle => 'Ouvrable une seule fois';

  @override
  String get onceOnlyConfirmBody =>
      'Ce message ne peut être ouvert qu’une fois. Dès que tu le fermes, il est supprimé définitivement. Cela vaut aussi si quelque chose t’interrompt.';

  @override
  String get onceOnlyScreenshotHint =>
      'Une capture ne peut pas être empêchée. Tu en seras informé.';

  @override
  String get onceOnlyConfirmAction => 'Confirmer et ouvrir';

  @override
  String get tutDOnceOnly =>
      'Envoie des messages qui ne peuvent être ouverts et lus qu’une fois.';

  @override
  String get aboutSecurityLine =>
      'Chiffré de bout en bout. Les clés restent sur ton appareil.';

  @override
  String get securityDetails => 'Détails de sécurité';

  @override
  String get secIntro =>
      'Comment Krypta protège tes messages, de l’appareil à la remise jusqu’au serveur. Tout ce qui suit reflète la construction réelle de l’application.';

  @override
  String get secMessagesTitle => 'Chiffrement des messages';

  @override
  String get secMessagesBody =>
      'Chaque message est chiffré sur ton appareil et ne redevient lisible que sur celui de ton contact. Le chiffrement et l’authentification se font en une seule étape, avec des données supplémentaires liées au sceau : un message modifié est rejeté au lieu d’être déchiffré.';

  @override
  String get secExchangeTitle => 'Échange de clés';

  @override
  String get secExchangeBody =>
      'Au premier contact, les deux appareils conviennent d’un secret commun sans jamais le transmettre. Trois parts Diffie-Hellman sont combinées et la clé de session en est dérivée. Le serveur ne voit que des clés publiques.';

  @override
  String get secForwardTitle => 'Forward secrecy';

  @override
  String get secForwardBody =>
      'Une nouvelle clé est dérivée pour chaque message et l’ancienne est jetée. Qui vole une clé ne peut lire ni les messages précédents ni les suivants. Les messages manqués rattrapent leur retard sans abandonner cette propriété.';

  @override
  String get secIdentityTitle => 'Identité et vérification';

  @override
  String get secIdentityBody =>
      'Chaque appareil possède une paire de clés d’identité. Les préclés et les entrées de transparence sont signées, pour qu’un serveur ne puisse pas les remplacer sans que cela se voie. Le numéro de sécurité est calculé à partir des deux identités et il est identique sur les deux appareils.';

  @override
  String get secPasswordTitle => 'Mots de passe et codes';

  @override
  String get secPasswordBody =>
      'Les mots de passe et les codes ne sont jamais enregistrés, seulement leur dérivation. La méthode est volontairement lente et gourmande en mémoire, pour empêcher les essais en masse.';

  @override
  String get secLocalTitle => 'Sur l’appareil';

  @override
  String get secLocalBody =>
      'Les messages et les clés sont stockés chiffrés dans l’espace de l’application. La clé principale se trouve dans le trousseau du système et n’est lisible qu’après le premier déverrouillage de l’appareil. Là où il existe, une puce de sécurité l’enveloppe en plus.';

  @override
  String get secServerTitle => 'Serveur et remise';

  @override
  String get secServerBody =>
      'Le serveur reçoit des envois chiffrés et les transmet. Il ne détient jamais de clé et ne voit aucun contenu. La remise utilise un identifiant éphémère du destinataire. Les envois remis sont supprimés.';

  @override
  String get secTransportTitle => 'Transport';

  @override
  String get secTransportBody =>
      'La connexion est chiffrée et l’application n’accepte que les certificats attendus. Cela s’applique au niveau du système d’exploitation, donc à chaque connexion de l’application.';

  @override
  String get secFooter =>
      'Ces indications décrivent des méthodes et des paramètres, jamais des clés. Elles valent pour la version affichée ci-dessus.';
}
