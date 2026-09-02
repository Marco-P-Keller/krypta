// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Calculator';

  @override
  String get messenger => 'Messenger';

  @override
  String get settings => 'Settings';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get setupTitle => 'Welcome to Krypta ECC';

  @override
  String get setupSubtitle => 'Set up your secret codes to get started';

  @override
  String get secretCodeLabel => 'Secret Code';

  @override
  String get secretCodeHint => 'Enter the code that unlocks your messenger';

  @override
  String get deleteCodeLabel => 'Delete Code';

  @override
  String get deleteCodeHint => 'Enter a code that wipes all data instantly';

  @override
  String get setupComplete => 'Setup Complete';

  @override
  String get setupContinue => 'Continue';

  @override
  String get setupCodesInfo =>
      'All codes must be different and at least 4 digits';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get newChat => 'New Chat';

  @override
  String get typeMessage => 'Type a message...';

  @override
  String get send => 'Send';

  @override
  String get delivered => 'Delivered';

  @override
  String get sent => 'Sent';

  @override
  String get read => 'Read';

  @override
  String get typing => 'typing...';

  @override
  String get selfDestructTimer => 'Self-destruct timer';

  @override
  String get seconds30 => '30 seconds';

  @override
  String get minutes5 => '5 minutes';

  @override
  String get hour1 => '1 hour';

  @override
  String get day1 => '1 day';

  @override
  String get week1 => '1 week';

  @override
  String get off => 'Off';

  @override
  String get emergencyDelete => 'Emergency Delete';

  @override
  String get emergencyDeleteDescription =>
      'Immediately wipe all data, keys, and sign out';

  @override
  String get allDataDeleted => 'All data has been wiped';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get securitySettings => 'Security';

  @override
  String get changeSecretCode => 'Change Secret Code';

  @override
  String get changeDeleteCode => 'Change Delete Code';

  @override
  String get biometricUnlock => 'Biometric Unlock';

  @override
  String get biometricDescription =>
      'Require Face ID or fingerprint after code entry';

  @override
  String get autoDeleteMessages => 'Auto-delete Messages';

  @override
  String get accountSection => 'Account';

  @override
  String get privacySection => 'Privacy';

  @override
  String get dangerZone => 'Danger Zone';

  @override
  String get deleteAccount => 'Delete Account & Data';

  @override
  String get about => 'About Krypta ECC';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get noChats => 'No conversations yet';

  @override
  String get noChatsSubtitle => 'Start a new chat to begin messaging securely';

  @override
  String get encryptionInfo => 'Messages are end-to-end encrypted';

  @override
  String get anonymousUser => 'Anonymous User';

  @override
  String get userIdLabel => 'Your ID';

  @override
  String get userIdCopied => 'User ID copied to clipboard';

  @override
  String get addContactById => 'Add contact by ID';

  @override
  String get contactIdHint => 'Enter contact ID';

  @override
  String get addContact => 'Add Contact';

  @override
  String get cannotAddYourself => 'Cannot add yourself';

  @override
  String get userNotFound => 'User not found';

  @override
  String get myQrCode => 'My QR Code';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get qrScanHint => 'Point your camera at a Krypta QR code';

  @override
  String get qrShareHint => 'Let others scan this to connect';

  @override
  String get yourQrCode => 'Your QR Code';

  @override
  String get idCopied => 'ID copied';

  @override
  String get qrWebUnavailable =>
      'QR scanning is not available on web.\nUse a mobile device to scan QR codes.';

  @override
  String get thatsYourOwnId => 'That\'s your own ID';

  @override
  String get renameChat => 'Rename Chat';

  @override
  String get chatName => 'Chat name';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get skip => 'Skip';

  @override
  String get deleteChat => 'Delete Chat';

  @override
  String get clearChat => 'Clear Chat';

  @override
  String clearChatConfirm(String name) {
    return 'Delete all messages in this chat? On $name\'s device the messages you sent will disappear too — their own stay. This cannot be undone.';
  }

  @override
  String get autoDeleteTimer => 'Auto-Delete Timer';

  @override
  String get autoDeleteHint =>
      'New messages in this chat will automatically self-destruct after the selected time.';

  @override
  String get chatDefault => 'Chat default';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Chat default ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'Messages auto-delete after $timer';
  }

  @override
  String get onlyVisibleToYou => 'Only visible to you';

  @override
  String get burnAfterRead => 'Burn after read';

  @override
  String get passwordProtected => 'Password protected';

  @override
  String get lockMessage => 'Lock Message';

  @override
  String get lockMessageHint =>
      'Set a password for the next message. The recipient must enter this password to read it.';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get setPassword => 'Set Password';

  @override
  String get passwordRequired => 'Password Required';

  @override
  String get passwordRequiredHint =>
      'Enter the password to decrypt this message.';

  @override
  String get password => 'Password';

  @override
  String get unlock => 'Unlock';

  @override
  String get unlocked => 'Unlocked';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get tapToUnlock => 'Tap to unlock';

  @override
  String get awaitingUnlock => 'Visible once unlocked';

  @override
  String get unblockToSend => 'Unblock this contact to send messages.';

  @override
  String selfDestructSetTo(String dauer) {
    return 'Self-delete set to $dauer';
  }

  @override
  String get selfDestructTurnedOff => 'Self-delete turned off';

  @override
  String get nameThisContact => 'Name this contact';

  @override
  String get nameContactHint =>
      'Give this contact a name so you know who it is. Only you can see this label.';

  @override
  String get nameContactPlaceholder => 'e.g. Alex, Mom, Work...';

  @override
  String get selfDestructTimerLabel => 'Self-Destruct Timer';

  @override
  String get vaultPassword => 'Vault Password';

  @override
  String get vaultPasswordDescription =>
      'Require a strong password after code entry before accessing the messenger';

  @override
  String get vaultPasswordTitle => 'Vault Locked';

  @override
  String get vaultPasswordHint =>
      'Enter your vault password to access the messenger.';

  @override
  String get setVaultPassword => 'Set Vault Password';

  @override
  String get changeVaultPassword => 'Change Vault Password';

  @override
  String get removeVaultPassword => 'Remove Vault Password';

  @override
  String get vaultPasswordSet => 'Vault password set';

  @override
  String get vaultPasswordRemoved => 'Vault password removed';

  @override
  String get vaultPasswordRules =>
      'At least 10 characters, with uppercase, lowercase, number, and special character.';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordTooWeak => 'Password does not meet the requirements';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get delete => 'Delete';

  @override
  String get deleteMessage => 'Delete Message';

  @override
  String get deleteMessageConfirm =>
      'This message will be permanently deleted from this device.';

  @override
  String get deleteForMe => 'Delete for me';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String get deleteForEveryoneConfirm =>
      'This message will be deleted for both you and the recipient.';

  @override
  String get qrInvalidFormat =>
      'Invalid QR code format. Only Krypta QR codes are accepted.';

  @override
  String get qrUnsupportedVersion =>
      'Unsupported QR code version. Please update the app.';

  @override
  String get qrFingerprintMismatch =>
      'Security warning: QR code fingerprint is tampered. Operation aborted.';

  @override
  String get qrKeyMismatch =>
      'SECURITY WARNING: Server key does NOT match the QR code key. Possible attack detected. Contact has been blocked.';

  @override
  String get qrVerified => 'Key verified';

  @override
  String get verificationStale => 'Verification is older than 90 days';

  @override
  String get verifyNow => 'Re-verify';

  @override
  String get showTutorial => 'Show tutorial again';

  @override
  String get showTutorialSubtitle => 'Replay the introduction';

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String get openSourceLicensesSubtitle => 'Third-party libraries and notices';

  @override
  String get aboutClose => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String lockedForSeconds(int seconds) {
    return 'Locked for $seconds seconds.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining attempts left',
      one: '1 attempt left',
    );
    return 'Wrong password. $_temp0 before all data is wiped.';
  }

  @override
  String get keysNotPublishedDenied =>
      'The server rejected your keys – others cannot message you.';

  @override
  String get keysNotPublishedFailed =>
      'Your keys could not be published – others cannot message you.';

  @override
  String get biometricUnlockReason => 'Unlock Krypta Messenger';

  @override
  String get deviceCompromised => 'Device may be compromised.';

  @override
  String get deviceCompromisedDegraded =>
      'Device may be compromised. Hardware security disabled.';

  @override
  String get fieldRequired => 'Required';

  @override
  String codeMinDigits(int count) {
    return 'At least $count digits';
  }

  @override
  String get codeDigitsOnly => 'Digits only';

  @override
  String get deleteCodeMustDiffer =>
      'The delete code must differ from your secret code.';

  @override
  String get setupFailed => 'Setup failed. Please try again.';

  @override
  String get setupSecretCodeSubtitle =>
      'Enter this in the calculator to open your vault.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Instantly erases everything. Use in emergencies only.';

  @override
  String get contactKeyChangedWarning =>
      'The security key for this contact has changed. Messages are blocked until you verify their identity. Scan their QR code or compare safety numbers to resume messaging.';

  @override
  String get verifyIdentity => 'Verify Identity';

  @override
  String get safetyNumberCompareHint =>
      'Compare safety numbers or scan QR codes to verify end-to-end encryption.';

  @override
  String get viewSafetyNumber => 'View Safety Number';

  @override
  String get safetyNumberTitle => 'Safety Number';

  @override
  String get safetyNumberCopied => 'Safety number copied';

  @override
  String get safetyNumberMatchHint =>
      'Compare this number with your contact. If they match, your conversation is secure.';

  @override
  String get verificationFailedKeyMismatch =>
      'Verification failed — the keys do not match';

  @override
  String get markVerified => 'Mark Verified';

  @override
  String get securitySettingsReason => 'Change security settings';

  @override
  String get vaultPasswordReAuthHint =>
      'Enter your vault password to change security settings.';

  @override
  String get codeAlreadyInUse => 'Code already in use for another action.';

  @override
  String get deviceSecure => 'Device secure';

  @override
  String get deviceCompromisedDetected => 'Compromise detected';

  @override
  String get deviceStatusUnknown => 'Status unknown';

  @override
  String get deviceSecureSubtitle => 'No root/jailbreak/Frida indicators';

  @override
  String get deviceCompromisedSubtitle =>
      'Root, jailbreak or instrumentation detected. Hardware security disabled.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'Integrity check failed — restricted mode active.';

  @override
  String get hardwareEnclave => 'Hardware enclave';

  @override
  String get hardwareTee => 'TEE key store';

  @override
  String get hardwareSoftware => 'Software key store';

  @override
  String get hardwareBoundSubtitle => 'Database key bound to hardware';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave available';

  @override
  String get hardwareTeeSubtitle =>
      'Key held in the Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle => 'No hardware security available';

  @override
  String get pushPrivacy => 'Push privacy';

  @override
  String get pushPrivacyOn => 'On — messages are fetched by polling';

  @override
  String get pushPrivacyOff => 'Off — push notifications active';

  @override
  String get readReceipts => 'Read receipts';

  @override
  String get readReceiptsOn => 'On — the sender sees when you read';

  @override
  String get readReceiptsOff => 'Off — maximum privacy';

  @override
  String get deliveryReceipts => 'Delivery receipts';

  @override
  String get deliveryReceiptsOn => 'On — the sender sees when delivered';

  @override
  String get deliveryReceiptsOff => 'Off — maximum privacy';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Privacy Policy\n\nLast updated: April 2026\n\n1. Controller\nConnexa GmbH\nContact: https://connexa-gmbh.ch\n\n2. What data is collected?\nKrypta collects as little data as is technically possible:\n• Anonymous Firebase ID (no email, no name, no phone number)\n• Public encryption key (X25519)\n• FCM push token (for notifications)\n\n3. Encryption\nAll messages are end-to-end encrypted (Signal protocol: X3DH + Double Ratchet). At no point does the server have access to the plaintext of your messages. Encryption: XChaCha20-Poly1305. Password hashing: Argon2id.\n\n4. Data storage\n• Messages are stored only on your device (encrypted)\n• The server acts solely as a temporary relay — messages are deleted after delivery\n• Keys are stored in the iOS Keychain / Android Keystore\n\n5. No trackers\nKrypta contains no analytics tools, no advertising and no trackers (0 of 432 known trackers).\n\n6. Data sharing\nNo personal data is passed on to third parties. Google Firebase is used as the infrastructure provider (anonymous authentication and push notifications).\n\n7. Data deletion\nYou can irreversibly delete all of your data at any time:\n• In the settings via \"Delete everything\"\n• By entering the delete code in the calculator\nThis destroys all local data, keys and server-side data.\n\n8. Your rights (GDPR)\nYou have the right to access, rectification, erasure and data portability. Contact us at: https://connexa-gmbh.ch\n\n9. Changes\nThis privacy policy may be updated. The current version is always available in the app.';

  @override
  String get tutStartSetup => 'Start setup';

  @override
  String get tutWelcomeTitle => 'Welcome to Krypta';

  @override
  String get tutWelcomeBody =>
      'Krypta is a secret messenger.\n\nTo everyone else the app looks like an ordinary calculator — nobody will suspect that an encrypted chat is hiding behind it.\n\nWe recommend reading this tutorial carefully.';

  @override
  String get tutSecretCodeTitle => 'Your secret code';

  @override
  String get tutSecretCodeBody =>
      'During setup you choose a numeric code.\n\nThis code is your key — it is the only way to open the hidden messenger.';

  @override
  String get tutDeleteCodeBody =>
      'The second code is for emergencies.\n\nEntering it erases everything immediately — messages, keys, account. Irreversibly.\n\nChoose a code you will not enter by accident.';

  @override
  String get tutDeleteCodeWarning =>
      'Everything is erased immediately.\nNo recovery is possible.';

  @override
  String get tutOpenMessengerTitle => 'Open the messenger';

  @override
  String get tutOpenMessengerBody =>
      'To open your messenger:\n\n1. Enter your secret code in the calculator\n2. Press the = key\n\nThe messenger opens right away.';

  @override
  String get tutPressEquals => 'Press =';

  @override
  String get tutMessengerUnlocked => 'Messenger unlocked';

  @override
  String get tutVaultBody =>
      'In the settings you can enable an additional password.\n\nAfter the secret code the vault password is then requested as well — double security for your messages.';

  @override
  String get tutAddContactsTitle => 'Add contacts';

  @override
  String get tutAddContactsBody =>
      'There are two ways to add contacts:\n\n• Scan a QR code — quick and simple\n• Enter a user ID — when you are not in the same place\n\nAfter that you can write to each other.';

  @override
  String get tutQrFast => 'Quick & simple';

  @override
  String get tutEnterUserId => 'Enter user ID';

  @override
  String get tutForRemoteContacts => 'For remote contacts';

  @override
  String get tutEmergencyBody =>
      'You will find red emergency buttons in the app.\n\nThey erase everything immediately — just like the delete code. Use them only when it really matters.';

  @override
  String get tutInSettings => 'In the settings';

  @override
  String get tutChatFeaturesIntro => 'A chat gives you three special features:';

  @override
  String get tutLockMessageDesc =>
      'Protect individual messages with a password';

  @override
  String get tutAutoDeleteDesc => 'Messages delete themselves after a set time';

  @override
  String get tutBurnAfterReadDesc =>
      'The message is deleted immediately after reading';

  @override
  String get tutReadyTitle => 'All set!';

  @override
  String get tutReadyBody =>
      'You now know everything you need.\n\nIn the next step you set up your codes — after that your messenger is ready to use.';

  @override
  String get language => 'Language';

  @override
  String get chooseLanguage => 'Choose your language';

  @override
  String get deviceSecuritySection => 'Device security';

  @override
  String get tutDeleteCodeTitle => 'Emergency code';

  @override
  String get tutEmergencyTitle => 'Emergency buttons';

  @override
  String get tutChatFeaturesTitle => 'Chat features';

  @override
  String get blockContact => 'Block';

  @override
  String get authentication => 'Authentication';

  @override
  String get contactRequestTitle => 'Contact request';

  @override
  String get contactRequestIncomingHint =>
      'This person wants to message you. You can only write to each other once you accept.';

  @override
  String get acceptRequest => 'Accept';

  @override
  String get declineRequest => 'Decline';

  @override
  String get contactRequestSent => 'Request sent';

  @override
  String get contactRequestWaitingHint =>
      'You can write once the other person accepts.';

  @override
  String get resendRequest => 'Request again';

  @override
  String get acceptToReply => 'Accept the request to reply';

  @override
  String get requestBadge => 'Request';

  @override
  String get blockContactConfirm =>
      'Block this person? They will not be able to message you, and they will not be told.';

  @override
  String get unblockContact => 'Unblock';

  @override
  String get contactBlocked => 'Blocked';

  @override
  String get minute1 => '1 minute';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get minutes30 => '30 minutes';

  @override
  String get screenshotByYou => 'You took a screenshot of the chat';

  @override
  String screenshotByPeer(String name) {
    return '$name took a screenshot of the chat';
  }

  @override
  String get recordingByYou => 'You are recording the screen';

  @override
  String recordingByPeer(String name) {
    return '$name is recording the screen';
  }

  @override
  String get screenshotNotice => 'Screenshot notice';

  @override
  String get screenshotNoticeDescription =>
      'Both sides are told when a screenshot or recording is made';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get legalSection => 'Legal';

  @override
  String get identityTitle => 'Identity';

  @override
  String get identityVerified => 'Verified';

  @override
  String get identityBadge => 'Secure';

  @override
  String get scanSafetyNumber => 'Scan code';

  @override
  String get safetyNumberScanHint =>
      'Point the camera at your contact\'s safety number';

  @override
  String safetyNumberMatches(String name) {
    return 'The numbers match — $name is verified.';
  }

  @override
  String get safetyNumberDiffers => 'The numbers do not match.';

  @override
  String get safetyNumberDiffersHint =>
      'Someone may be intercepting this conversation. Don\'t send anything sensitive until you have checked in person.';

  @override
  String get safetyNumberNotRecognised =>
      'That is not a safety number. Scan the code shown under your contact\'s safety number.';

  @override
  String get verifiedContact => 'verified';

  @override
  String accountGone(String name) {
    return '$name no longer exists';
  }

  @override
  String get accountGoneCannotWrite =>
      'This account no longer exists — you can\'t write here.';

  @override
  String get identityKeyConfirmed => 'Security key confirmed';

  @override
  String get identityNotConfirmed => 'Contact not confirmed';

  @override
  String get identityConfirmedHint =>
      'This contact\'s security key has been checked against your device. That confirms the key, not who is holding the phone.';

  @override
  String get identityNotConfirmedHint =>
      'Your messages are end-to-end encrypted either way. Compare the QR code or the safety number to confirm this contact\'s security key as well.';

  @override
  String get identityAlreadyConfirmed => 'Security key already confirmed';

  @override
  String scanContactQr(String name) {
    return 'Scan the QR code from $name';
  }

  @override
  String get blockKeepsVerification => 'The saved security status is kept.';

  @override
  String unblockedVerified(String name) {
    return '$name was unblocked. The contact stays confirmed.';
  }

  @override
  String unblockedUnverified(String name) {
    return '$name was unblocked. The security key has not been confirmed yet.';
  }

  @override
  String unblockedKeyChanged(String name) {
    return '$name was unblocked. The security key has changed and must be confirmed again.';
  }
}
