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
  String get decoyCodeLabel => 'Decoy Code';

  @override
  String get decoyCodeHint => 'Enter a code that opens a fake messenger';

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
  String get changeDecoyCode => 'Change Decoy Code';

  @override
  String get changeDeleteCode => 'Change Delete Code';

  @override
  String get biometricUnlock => 'Biometric Unlock';

  @override
  String get biometricDescription =>
      'Require Face ID or fingerprint after code entry';

  @override
  String get screenshotProtection => 'Screenshot Protection';

  @override
  String get screenshotDescription => 'Block screenshots in the messenger';

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
  String get decoyTitle => 'Messages';

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
  String get clearChatConfirm =>
      'Delete all messages in this chat? This cannot be undone.';

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
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get legalSection => 'Legal';
}
