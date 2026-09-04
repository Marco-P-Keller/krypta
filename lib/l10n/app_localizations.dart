import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('nl'),
    Locale('pt'),
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Krypta ECC'**
  String get appName;

  /// No description provided for @calculator.
  ///
  /// In en, this message translates to:
  /// **'Calculator'**
  String get calculator;

  /// No description provided for @messenger.
  ///
  /// In en, this message translates to:
  /// **'Messenger'**
  String get messenger;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Krypta ECC'**
  String get setupTitle;

  /// No description provided for @setupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your secret codes to get started'**
  String get setupSubtitle;

  /// No description provided for @secretCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret Code'**
  String get secretCodeLabel;

  /// No description provided for @secretCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the code that unlocks your messenger'**
  String get secretCodeHint;

  /// No description provided for @deleteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete Code'**
  String get deleteCodeLabel;

  /// No description provided for @deleteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a code that wipes all data instantly'**
  String get deleteCodeHint;

  /// No description provided for @setupComplete.
  ///
  /// In en, this message translates to:
  /// **'Setup Complete'**
  String get setupComplete;

  /// No description provided for @setupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get setupContinue;

  /// No description provided for @setupCodesInfo.
  ///
  /// In en, this message translates to:
  /// **'All codes must be different and at least 4 digits'**
  String get setupCodesInfo;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get newChat;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessage;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'typing...'**
  String get typing;

  /// No description provided for @selfDestructTimer.
  ///
  /// In en, this message translates to:
  /// **'Self-destruct timer'**
  String get selfDestructTimer;

  /// No description provided for @seconds30.
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get seconds30;

  /// No description provided for @minutes5.
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get minutes5;

  /// No description provided for @hour1.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get hour1;

  /// No description provided for @day1.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get day1;

  /// No description provided for @week1.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get week1;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @emergencyDelete.
  ///
  /// In en, this message translates to:
  /// **'Emergency Delete'**
  String get emergencyDelete;

  /// No description provided for @emergencyDeleteDescription.
  ///
  /// In en, this message translates to:
  /// **'Immediately wipe all data, keys, and sign out'**
  String get emergencyDeleteDescription;

  /// No description provided for @allDataDeleted.
  ///
  /// In en, this message translates to:
  /// **'All data has been wiped'**
  String get allDataDeleted;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @securitySettings.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySettings;

  /// No description provided for @changeSecretCode.
  ///
  /// In en, this message translates to:
  /// **'Change Secret Code'**
  String get changeSecretCode;

  /// No description provided for @changeDeleteCode.
  ///
  /// In en, this message translates to:
  /// **'Change Delete Code'**
  String get changeDeleteCode;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get biometricUnlock;

  /// No description provided for @biometricDescription.
  ///
  /// In en, this message translates to:
  /// **'Require Face ID or fingerprint after code entry'**
  String get biometricDescription;

  /// No description provided for @autoDeleteMessages.
  ///
  /// In en, this message translates to:
  /// **'Auto-delete Messages'**
  String get autoDeleteMessages;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @privacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacySection;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get dangerZone;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account & Data'**
  String get deleteAccount;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About Krypta ECC'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(String version);

  /// No description provided for @noChats.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noChats;

  /// No description provided for @noChatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new chat to begin messaging securely'**
  String get noChatsSubtitle;

  /// No description provided for @encryptionInfo.
  ///
  /// In en, this message translates to:
  /// **'Messages are end-to-end encrypted'**
  String get encryptionInfo;

  /// No description provided for @anonymousUser.
  ///
  /// In en, this message translates to:
  /// **'Anonymous User'**
  String get anonymousUser;

  /// No description provided for @userIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Your ID'**
  String get userIdLabel;

  /// No description provided for @userIdCopied.
  ///
  /// In en, this message translates to:
  /// **'User ID copied to clipboard'**
  String get userIdCopied;

  /// No description provided for @addContactById.
  ///
  /// In en, this message translates to:
  /// **'Add contact by ID'**
  String get addContactById;

  /// No description provided for @contactIdHint.
  ///
  /// In en, this message translates to:
  /// **'Enter contact ID'**
  String get contactIdHint;

  /// No description provided for @addContact.
  ///
  /// In en, this message translates to:
  /// **'Add Contact'**
  String get addContact;

  /// No description provided for @cannotAddYourself.
  ///
  /// In en, this message translates to:
  /// **'Cannot add yourself'**
  String get cannotAddYourself;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @myQrCode.
  ///
  /// In en, this message translates to:
  /// **'My QR Code'**
  String get myQrCode;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @qrScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a Krypta QR code'**
  String get qrScanHint;

  /// No description provided for @qrShareHint.
  ///
  /// In en, this message translates to:
  /// **'Others can scan this QR code to add you as a contact.'**
  String get qrShareHint;

  /// No description provided for @yourQrCode.
  ///
  /// In en, this message translates to:
  /// **'Your QR Code'**
  String get yourQrCode;

  /// No description provided for @idCopied.
  ///
  /// In en, this message translates to:
  /// **'ID copied'**
  String get idCopied;

  /// No description provided for @qrWebUnavailable.
  ///
  /// In en, this message translates to:
  /// **'QR scanning is not available on web.\nUse a mobile device to scan QR codes.'**
  String get qrWebUnavailable;

  /// No description provided for @thatsYourOwnId.
  ///
  /// In en, this message translates to:
  /// **'That\'s your own ID'**
  String get thatsYourOwnId;

  /// No description provided for @renameChat.
  ///
  /// In en, this message translates to:
  /// **'Rename Chat'**
  String get renameChat;

  /// No description provided for @chatName.
  ///
  /// In en, this message translates to:
  /// **'Chat name'**
  String get chatName;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get deleteChat;

  /// No description provided for @deleteContact.
  ///
  /// In en, this message translates to:
  /// **'Delete Contact'**
  String get deleteContact;

  /// No description provided for @deleteContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete contact?'**
  String get deleteContactTitle;

  /// Rueckfrage vor dem Loeschen eines Kontakts aus der Kontaktliste
  ///
  /// In en, this message translates to:
  /// **'{name} disappears from your contact list, and your chat with them goes too. Nothing changes on their side. They can send you a new request later.'**
  String deleteContactBody(String name);

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear Chat'**
  String get clearChat;

  /// Rueckfrage vor dem Leeren; {name} ist der Kontakt
  ///
  /// In en, this message translates to:
  /// **'Delete all messages in this chat? On {name}\'s device the messages you sent will disappear too — their own stay. This cannot be undone.'**
  String clearChatConfirm(String name);

  /// No description provided for @autoDeleteTimer.
  ///
  /// In en, this message translates to:
  /// **'Auto-Delete Timer'**
  String get autoDeleteTimer;

  /// No description provided for @autoDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'New messages in this chat are deleted automatically after the selected time. The setting applies to both sides.'**
  String get autoDeleteHint;

  /// No description provided for @autoDeleteAfterRead.
  ///
  /// In en, this message translates to:
  /// **'Right after reading'**
  String get autoDeleteAfterRead;

  /// No description provided for @chatDefault.
  ///
  /// In en, this message translates to:
  /// **'Chat default'**
  String get chatDefault;

  /// No description provided for @chatDefaultWithTimer.
  ///
  /// In en, this message translates to:
  /// **'Chat default ({timer})'**
  String chatDefaultWithTimer(String timer);

  /// No description provided for @messagesAutoDelete.
  ///
  /// In en, this message translates to:
  /// **'Messages auto-delete after {timer}'**
  String messagesAutoDelete(String timer);

  /// No description provided for @onlyVisibleToYou.
  ///
  /// In en, this message translates to:
  /// **'Only visible to you'**
  String get onlyVisibleToYou;

  /// No description provided for @passwordProtected.
  ///
  /// In en, this message translates to:
  /// **'Password protected'**
  String get passwordProtected;

  /// No description provided for @lockMessage.
  ///
  /// In en, this message translates to:
  /// **'Lock Message'**
  String get lockMessage;

  /// No description provided for @lockMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Set a password for the next message. The recipient must enter this password to read it.'**
  String get lockMessageHint;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enterPassword;

  /// No description provided for @setPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get setPassword;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password Required'**
  String get passwordRequired;

  /// No description provided for @passwordRequiredHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the password to decrypt this message.'**
  String get passwordRequiredHint;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlocked;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get wrongPassword;

  /// No description provided for @tapToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Tap to unlock'**
  String get tapToUnlock;

  /// Shown on the sender own password-protected message. The sender cannot unlock it themselves: their copy holds the plaintext, not the password-encrypted blob. It becomes readable once the recipient unlocks it.
  ///
  /// In en, this message translates to:
  /// **'Visible once unlocked'**
  String get awaitingUnlock;

  /// Shown when the user tries to send to a contact they have blocked themselves. The text stays in the input field.
  ///
  /// In en, this message translates to:
  /// **'Unblock this contact to send messages.'**
  String get unblockToSend;

  /// System notice in the chat when the chat-wide delete timer was changed. Both sides see it.
  ///
  /// In en, this message translates to:
  /// **'Self-delete set to {dauer}'**
  String selfDestructSetTo(String dauer);

  /// System notice in the chat when the chat-wide delete timer was switched off.
  ///
  /// In en, this message translates to:
  /// **'Self-delete turned off'**
  String get selfDestructTurnedOff;

  /// No description provided for @nameThisContact.
  ///
  /// In en, this message translates to:
  /// **'Name this contact'**
  String get nameThisContact;

  /// No description provided for @nameContactHint.
  ///
  /// In en, this message translates to:
  /// **'Give this contact a name so you know who it is. Only you can see this label.'**
  String get nameContactHint;

  /// No description provided for @nameContactPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Alex, Mom, Work...'**
  String get nameContactPlaceholder;

  /// No description provided for @selfDestructTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'Self-Destruct Timer'**
  String get selfDestructTimerLabel;

  /// No description provided for @vaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Vault Password'**
  String get vaultPassword;

  /// No description provided for @vaultPasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Require a strong password after code entry before accessing the messenger'**
  String get vaultPasswordDescription;

  /// No description provided for @vaultPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault Locked'**
  String get vaultPasswordTitle;

  /// No description provided for @vaultPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your vault password to access the messenger.'**
  String get vaultPasswordHint;

  /// No description provided for @setVaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Vault Password'**
  String get setVaultPassword;

  /// No description provided for @changeVaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Change Vault Password'**
  String get changeVaultPassword;

  /// No description provided for @removeVaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Remove Vault Password'**
  String get removeVaultPassword;

  /// No description provided for @vaultPasswordSet.
  ///
  /// In en, this message translates to:
  /// **'Vault password set'**
  String get vaultPasswordSet;

  /// No description provided for @vaultPasswordRemoved.
  ///
  /// In en, this message translates to:
  /// **'Vault password removed'**
  String get vaultPasswordRemoved;

  /// No description provided for @vaultPasswordRules.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters, with uppercase, lowercase, number, and special character.'**
  String get vaultPasswordRules;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Password does not meet the requirements'**
  String get passwordTooWeak;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete Message'**
  String get deleteMessage;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'This message will be permanently deleted from this device.'**
  String get deleteMessageConfirm;

  /// No description provided for @deleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMe;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @deleteForEveryoneConfirm.
  ///
  /// In en, this message translates to:
  /// **'This message will be deleted for both you and the recipient.'**
  String get deleteForEveryoneConfirm;

  /// No description provided for @qrInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code format. Only Krypta QR codes are accepted.'**
  String get qrInvalidFormat;

  /// No description provided for @qrUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'Unsupported QR code version. Please update the app.'**
  String get qrUnsupportedVersion;

  /// No description provided for @qrFingerprintMismatch.
  ///
  /// In en, this message translates to:
  /// **'Security warning: QR code fingerprint is tampered. Operation aborted.'**
  String get qrFingerprintMismatch;

  /// No description provided for @qrKeyMismatch.
  ///
  /// In en, this message translates to:
  /// **'SECURITY WARNING: Server key does NOT match the QR code key. Possible attack detected. Contact has been blocked.'**
  String get qrKeyMismatch;

  /// No description provided for @qrVerified.
  ///
  /// In en, this message translates to:
  /// **'Key verified'**
  String get qrVerified;

  /// No description provided for @verificationStale.
  ///
  /// In en, this message translates to:
  /// **'Verification is older than 90 days'**
  String get verificationStale;

  /// No description provided for @verifyNow.
  ///
  /// In en, this message translates to:
  /// **'Re-verify'**
  String get verifyNow;

  /// No description provided for @showTutorial.
  ///
  /// In en, this message translates to:
  /// **'Show tutorial again'**
  String get showTutorial;

  /// No description provided for @showTutorialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replay the introduction'**
  String get showTutorialSubtitle;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get openSourceLicenses;

  /// No description provided for @openSourceLicensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Third-party libraries and notices'**
  String get openSourceLicensesSubtitle;

  /// No description provided for @aboutClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get aboutClose;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @lockedForSeconds.
  ///
  /// In en, this message translates to:
  /// **'Locked for {seconds} seconds.'**
  String lockedForSeconds(int seconds);

  /// No description provided for @wrongPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. {remaining, plural, =1{1 attempt left} other{{remaining} attempts left}} before all data is wiped.'**
  String wrongPasswordWarning(int remaining);

  /// No description provided for @keysNotPublishedDenied.
  ///
  /// In en, this message translates to:
  /// **'The server rejected your keys – others cannot message you.'**
  String get keysNotPublishedDenied;

  /// No description provided for @keysNotPublishedFailed.
  ///
  /// In en, this message translates to:
  /// **'Your keys could not be published – others cannot message you.'**
  String get keysNotPublishedFailed;

  /// No description provided for @biometricUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock Krypta Messenger'**
  String get biometricUnlockReason;

  /// No description provided for @deviceCompromised.
  ///
  /// In en, this message translates to:
  /// **'Device may be compromised.'**
  String get deviceCompromised;

  /// No description provided for @deviceCompromisedDegraded.
  ///
  /// In en, this message translates to:
  /// **'Device may be compromised. Hardware security disabled.'**
  String get deviceCompromisedDegraded;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @codeMinDigits.
  ///
  /// In en, this message translates to:
  /// **'At least {count} digits'**
  String codeMinDigits(int count);

  /// No description provided for @codeDigitsOnly.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get codeDigitsOnly;

  /// No description provided for @deleteCodeMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'The delete code must differ from your secret code.'**
  String get deleteCodeMustDiffer;

  /// No description provided for @setupFailed.
  ///
  /// In en, this message translates to:
  /// **'Setup failed. Please try again.'**
  String get setupFailed;

  /// No description provided for @setupSecretCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter this in the calculator to open your vault.'**
  String get setupSecretCodeSubtitle;

  /// No description provided for @setupDeleteCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Instantly erases everything. Use in emergencies only.'**
  String get setupDeleteCodeSubtitle;

  /// No description provided for @contactKeyChangedWarning.
  ///
  /// In en, this message translates to:
  /// **'The security key for this contact has changed. Messages are blocked until you verify their identity. Scan their QR code or compare safety numbers to resume messaging.'**
  String get contactKeyChangedWarning;

  /// No description provided for @verifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify Identity'**
  String get verifyIdentity;

  /// No description provided for @safetyNumberCompareHint.
  ///
  /// In en, this message translates to:
  /// **'Compare safety numbers or scan QR codes to verify end-to-end encryption.'**
  String get safetyNumberCompareHint;

  /// No description provided for @viewSafetyNumber.
  ///
  /// In en, this message translates to:
  /// **'View Safety Number'**
  String get viewSafetyNumber;

  /// No description provided for @safetyNumberTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety Number'**
  String get safetyNumberTitle;

  /// No description provided for @safetyNumberCopied.
  ///
  /// In en, this message translates to:
  /// **'Safety number copied'**
  String get safetyNumberCopied;

  /// No description provided for @safetyNumberMatchHint.
  ///
  /// In en, this message translates to:
  /// **'Compare this number with your contact. If they match, your conversation is secure.'**
  String get safetyNumberMatchHint;

  /// No description provided for @verificationFailedKeyMismatch.
  ///
  /// In en, this message translates to:
  /// **'Verification failed — the keys do not match'**
  String get verificationFailedKeyMismatch;

  /// No description provided for @markVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark Verified'**
  String get markVerified;

  /// No description provided for @securitySettingsReason.
  ///
  /// In en, this message translates to:
  /// **'Change security settings'**
  String get securitySettingsReason;

  /// No description provided for @vaultPasswordReAuthHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your vault password to change security settings.'**
  String get vaultPasswordReAuthHint;

  /// No description provided for @codeAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'Code already in use for another action.'**
  String get codeAlreadyInUse;

  /// No description provided for @deviceSecure.
  ///
  /// In en, this message translates to:
  /// **'Device secure'**
  String get deviceSecure;

  /// No description provided for @deviceCompromisedDetected.
  ///
  /// In en, this message translates to:
  /// **'Compromise detected'**
  String get deviceCompromisedDetected;

  /// No description provided for @deviceStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Status unknown'**
  String get deviceStatusUnknown;

  /// No description provided for @deviceSecureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No root/jailbreak/Frida indicators'**
  String get deviceSecureSubtitle;

  /// No description provided for @deviceCompromisedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Root, jailbreak or instrumentation detected. Hardware security disabled.'**
  String get deviceCompromisedSubtitle;

  /// No description provided for @deviceStatusUnknownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Integrity check failed — restricted mode active.'**
  String get deviceStatusUnknownSubtitle;

  /// No description provided for @hardwareEnclave.
  ///
  /// In en, this message translates to:
  /// **'Hardware enclave'**
  String get hardwareEnclave;

  /// No description provided for @hardwareTee.
  ///
  /// In en, this message translates to:
  /// **'TEE key store'**
  String get hardwareTee;

  /// No description provided for @hardwareSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software key store'**
  String get hardwareSoftware;

  /// No description provided for @hardwareBoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Database key bound to hardware'**
  String get hardwareBoundSubtitle;

  /// No description provided for @hardwareEnclaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'StrongBox/Secure Enclave available'**
  String get hardwareEnclaveSubtitle;

  /// No description provided for @hardwareTeeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Key held in the Trusted Execution Environment'**
  String get hardwareTeeSubtitle;

  /// No description provided for @hardwareSoftwareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No hardware security available'**
  String get hardwareSoftwareSubtitle;

  /// No description provided for @pushPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Push privacy'**
  String get pushPrivacy;

  /// No description provided for @pushPrivacyOn.
  ///
  /// In en, this message translates to:
  /// **'On — messages are fetched by polling'**
  String get pushPrivacyOn;

  /// No description provided for @pushPrivacyOff.
  ///
  /// In en, this message translates to:
  /// **'Off — push notifications active'**
  String get pushPrivacyOff;

  /// No description provided for @readReceipts.
  ///
  /// In en, this message translates to:
  /// **'Read receipts'**
  String get readReceipts;

  /// No description provided for @readReceiptsOn.
  ///
  /// In en, this message translates to:
  /// **'On — the sender sees when you read'**
  String get readReceiptsOn;

  /// No description provided for @readReceiptsOff.
  ///
  /// In en, this message translates to:
  /// **'Off — maximum privacy'**
  String get readReceiptsOff;

  /// No description provided for @privacyPolicyBody.
  ///
  /// In en, this message translates to:
  /// **'Krypta ECC — Privacy Policy\n\nLast updated: April 2026\n\n1. Controller\nConnexa GmbH\nContact: https://connexa-gmbh.ch\n\n2. What data is collected?\nKrypta collects as little data as is technically possible:\n• Anonymous Firebase ID (no email, no name, no phone number)\n• Public encryption key (X25519)\n• FCM push token (for notifications)\n\n3. Encryption\nAll messages are end-to-end encrypted (Signal protocol: X3DH + Double Ratchet). At no point does the server have access to the plaintext of your messages. Encryption: XChaCha20-Poly1305. Password hashing: Argon2id.\n\n4. Data storage\n• Messages are stored only on your device (encrypted)\n• The server acts solely as a temporary relay — messages are deleted after delivery\n• Keys are stored in the iOS Keychain / Android Keystore\n\n5. No trackers\nKrypta contains no analytics tools, no advertising and no trackers (0 of 432 known trackers).\n\n6. Data sharing\nNo personal data is passed on to third parties. Google Firebase is used as the infrastructure provider (anonymous authentication and push notifications).\n\n7. Data deletion\nYou can irreversibly delete all of your data at any time:\n• In the settings via \"Delete everything\"\n• By entering the delete code in the calculator\nThis destroys all local data, keys and server-side data.\n\n8. Your rights (GDPR)\nYou have the right to access, rectification, erasure and data portability. Contact us at: https://connexa-gmbh.ch\n\n9. Changes\nThis privacy policy may be updated. The current version is always available in the app.'**
  String get privacyPolicyBody;

  /// No description provided for @tutStartSetup.
  ///
  /// In en, this message translates to:
  /// **'Start setup'**
  String get tutStartSetup;

  /// No description provided for @tutWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Krypta'**
  String get tutWelcomeTitle;

  /// No description provided for @tutWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'A calculator on the outside. Your messages sit behind it, encrypted.'**
  String get tutWelcomeBody;

  /// No description provided for @tutAddContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Add contacts'**
  String get tutAddContactsTitle;

  /// No description provided for @tutChatFeaturesIntro.
  ///
  /// In en, this message translates to:
  /// **'Extra options for your messages.'**
  String get tutChatFeaturesIntro;

  /// No description provided for @tutLockMessageDesc.
  ///
  /// In en, this message translates to:
  /// **'Send messages that are protected with a password.'**
  String get tutLockMessageDesc;

  /// No description provided for @tutAutoDeleteDesc.
  ///
  /// In en, this message translates to:
  /// **'Set a timer for the whole chat. Messages are deleted automatically once they arrive.'**
  String get tutAutoDeleteDesc;

  /// No description provided for @tutReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get tutReadyTitle;

  /// No description provided for @tutReadyBody.
  ///
  /// In en, this message translates to:
  /// **'One point is still missing. It is the most important one.'**
  String get tutReadyBody;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @deviceSecuritySection.
  ///
  /// In en, this message translates to:
  /// **'Device security'**
  String get deviceSecuritySection;

  /// No description provided for @tutChatFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get tutChatFeaturesTitle;

  /// No description provided for @blockContact.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockContact;

  /// No description provided for @authentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get authentication;

  /// No description provided for @contactRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact request'**
  String get contactRequestTitle;

  /// No description provided for @contactRequestIncomingHint.
  ///
  /// In en, this message translates to:
  /// **'This person wants to message you. You can only write to each other once you accept.'**
  String get contactRequestIncomingHint;

  /// No description provided for @acceptRequest.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptRequest;

  /// No description provided for @declineRequest.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineRequest;

  /// No description provided for @contactRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get contactRequestSent;

  /// No description provided for @contactRequestWaitingHint.
  ///
  /// In en, this message translates to:
  /// **'You can write once the other person accepts.'**
  String get contactRequestWaitingHint;

  /// No description provided for @resendRequest.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get resendRequest;

  /// No description provided for @acceptToReply.
  ///
  /// In en, this message translates to:
  /// **'Accept the request to reply'**
  String get acceptToReply;

  /// No description provided for @requestBadge.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get requestBadge;

  /// No description provided for @blockContactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block this person? They will not be able to message you, and they will not be told.'**
  String get blockContactConfirm;

  /// No description provided for @unblockContact.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockContact;

  /// No description provided for @contactBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get contactBlocked;

  /// No description provided for @minute1.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get minute1;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @minutes30.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get minutes30;

  /// No description provided for @screenshotByYou.
  ///
  /// In en, this message translates to:
  /// **'You took a screenshot of the chat'**
  String get screenshotByYou;

  /// No description provided for @screenshotByPeer.
  ///
  /// In en, this message translates to:
  /// **'{name} took a screenshot of the chat'**
  String screenshotByPeer(String name);

  /// No description provided for @recordingByYou.
  ///
  /// In en, this message translates to:
  /// **'You are recording the screen'**
  String get recordingByYou;

  /// No description provided for @recordingByPeer.
  ///
  /// In en, this message translates to:
  /// **'{name} is recording the screen'**
  String recordingByPeer(String name);

  /// No description provided for @screenshotNotice.
  ///
  /// In en, this message translates to:
  /// **'Screenshot notice'**
  String get screenshotNotice;

  /// No description provided for @screenshotNoticeDescription.
  ///
  /// In en, this message translates to:
  /// **'Both sides are told when a screenshot or recording is made'**
  String get screenshotNoticeDescription;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @legalSection.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalSection;

  /// Ueberschrift des Identitaets-Bereichs in den Chat-Einstellungen
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identityTitle;

  /// Ueberschrift desselben Bereichs, wenn der Kontakt bestaetigt ist
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get identityVerified;

  /// Kurzes Abzeichen neben der Ueberschrift, wenn bestaetigt
  ///
  /// In en, this message translates to:
  /// **'Secure'**
  String get identityBadge;

  /// Knopf: den QR-Code der Gegenseite scannen
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get scanSafetyNumber;

  /// Hinweis im Scanner
  ///
  /// In en, this message translates to:
  /// **'Point the camera at your contact\'s safety number'**
  String get safetyNumberScanHint;

  /// Erfolg nach dem Scannen; {name} ist der Kontaktname
  ///
  /// In en, this message translates to:
  /// **'The numbers match — {name} is verified.'**
  String safetyNumberMatches(String name);

  /// Die gescannte Nummer weicht ab
  ///
  /// In en, this message translates to:
  /// **'The numbers do not match.'**
  String get safetyNumberDiffers;

  /// Was das bedeutet und was zu tun ist
  ///
  /// In en, this message translates to:
  /// **'Someone may be intercepting this conversation. Don\'t send anything sensitive until you have checked in person.'**
  String get safetyNumberDiffersHint;

  /// Der gescannte Code ist keine Sicherheitsnummer
  ///
  /// In en, this message translates to:
  /// **'That is not a safety number. Scan the code shown under your contact\'s safety number.'**
  String get safetyNumberNotRecognised;

  /// Steht im Chat klein unter dem Namen
  ///
  /// In en, this message translates to:
  /// **'verified'**
  String get verifiedContact;

  /// Hinweis im Verlauf nach der Notfall-Loeschung der Gegenseite
  ///
  /// In en, this message translates to:
  /// **'{name} no longer exists'**
  String accountGone(String name);

  /// Statt des Eingabefelds im Chat
  ///
  /// In en, this message translates to:
  /// **'This account no longer exists — you can\'t write here.'**
  String get accountGoneCannotWrite;

  /// No description provided for @identityKeyConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Security key confirmed'**
  String get identityKeyConfirmed;

  /// No description provided for @identityNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Contact not confirmed'**
  String get identityNotConfirmed;

  /// No description provided for @identityConfirmedHint.
  ///
  /// In en, this message translates to:
  /// **'This contact\'s security key has been checked against your device. That confirms the key, not who is holding the phone.'**
  String get identityConfirmedHint;

  /// No description provided for @identityNotConfirmedHint.
  ///
  /// In en, this message translates to:
  /// **'Your messages are end-to-end encrypted either way. Compare the QR code or the safety number to confirm this contact\'s security key as well.'**
  String get identityNotConfirmedHint;

  /// No description provided for @identityAlreadyConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Security key already confirmed'**
  String get identityAlreadyConfirmed;

  /// No description provided for @scanContactQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code from {name}'**
  String scanContactQr(String name);

  /// No description provided for @blockKeepsVerification.
  ///
  /// In en, this message translates to:
  /// **'The saved security status is kept.'**
  String get blockKeepsVerification;

  /// No description provided for @unblockedVerified.
  ///
  /// In en, this message translates to:
  /// **'{name} was unblocked. The contact stays confirmed.'**
  String unblockedVerified(String name);

  /// No description provided for @unblockedUnverified.
  ///
  /// In en, this message translates to:
  /// **'{name} was unblocked. The security key has not been confirmed yet.'**
  String unblockedUnverified(String name);

  /// No description provided for @unblockedKeyChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} was unblocked. The security key has changed and must be confirmed again.'**
  String unblockedKeyChanged(String name);

  /// No description provided for @tutDCalculator.
  ///
  /// In en, this message translates to:
  /// **'The calculator in front really works. Nothing gives it away.'**
  String get tutDCalculator;

  /// No description provided for @tutTEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End to end'**
  String get tutTEncrypted;

  /// No description provided for @tutDEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Only you and your contact can read along. The server sees nothing.'**
  String get tutDEncrypted;

  /// No description provided for @tutDLanguage.
  ///
  /// In en, this message translates to:
  /// **'Seven languages. Switch at any time.'**
  String get tutDLanguage;

  /// No description provided for @tutAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Your access'**
  String get tutAccessTitle;

  /// No description provided for @tutAccessIntro.
  ///
  /// In en, this message translates to:
  /// **'Four things protect the messenger. You set them up next.'**
  String get tutAccessIntro;

  /// No description provided for @tutTSecretCode.
  ///
  /// In en, this message translates to:
  /// **'Secret code'**
  String get tutTSecretCode;

  /// No description provided for @tutDSecretCode.
  ///
  /// In en, this message translates to:
  /// **'Type it into the calculator and press equals. The messenger opens.'**
  String get tutDSecretCode;

  /// No description provided for @tutTDeleteCode.
  ///
  /// In en, this message translates to:
  /// **'Delete code'**
  String get tutTDeleteCode;

  /// No description provided for @tutDDeleteCode.
  ///
  /// In en, this message translates to:
  /// **'A second code. It wipes everything at once, without asking.'**
  String get tutDDeleteCode;

  /// No description provided for @tutDVault.
  ///
  /// In en, this message translates to:
  /// **'An extra password after the code. Optional, but recommended.'**
  String get tutDVault;

  /// No description provided for @tutDScreenLock.
  ///
  /// In en, this message translates to:
  /// **'Face ID instead of typing. The app locks itself when you put it away.'**
  String get tutDScreenLock;

  /// No description provided for @tutContactsIntro.
  ///
  /// In en, this message translates to:
  /// **'Two ways to add someone. And one to be certain.'**
  String get tutContactsIntro;

  /// No description provided for @tutDAddById.
  ///
  /// In en, this message translates to:
  /// **'Exchange your ID and enter it. Works from a distance too.'**
  String get tutDAddById;

  /// No description provided for @tutTRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get tutTRequest;

  /// No description provided for @tutDRequest.
  ///
  /// In en, this message translates to:
  /// **'The other side has to accept your request before you can chat.'**
  String get tutDRequest;

  /// No description provided for @tutDQr.
  ///
  /// In en, this message translates to:
  /// **'Show or scan a QR code to add contacts directly.'**
  String get tutDQr;

  /// No description provided for @tutDSafetyNumber.
  ///
  /// In en, this message translates to:
  /// **'Compare safety numbers to verify who your contact really is and the end-to-end encryption of the chat.'**
  String get tutDSafetyNumber;

  /// No description provided for @tutProtectTitle.
  ///
  /// In en, this message translates to:
  /// **'Protection'**
  String get tutProtectTitle;

  /// No description provided for @tutProtectIntro.
  ///
  /// In en, this message translates to:
  /// **'More control over your chats and contacts.'**
  String get tutProtectIntro;

  /// No description provided for @tutDScreenshot.
  ///
  /// In en, this message translates to:
  /// **'You are always told when a screenshot or a screen recording of the chat is made.'**
  String get tutDScreenshot;

  /// No description provided for @tutDBlock.
  ///
  /// In en, this message translates to:
  /// **'Block contacts so they can no longer reach you, until you unblock them.'**
  String get tutDBlock;

  /// No description provided for @tutDClear.
  ///
  /// In en, this message translates to:
  /// **'Clear the chat history at any time. The messages you sent are removed for good on both devices.'**
  String get tutDClear;

  /// No description provided for @tutDDeleteChat.
  ///
  /// In en, this message translates to:
  /// **'Remove the whole chat from your list. The messages you sent are deleted on both devices.'**
  String get tutDDeleteChat;

  /// No description provided for @tutTEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency wipe'**
  String get tutTEmergency;

  /// No description provided for @tutDEmergency.
  ///
  /// In en, this message translates to:
  /// **'Deletes everything on the spot. Your contacts are told.'**
  String get tutDEmergency;

  /// No description provided for @tutDSettings.
  ///
  /// In en, this message translates to:
  /// **'Language, vault and codes are changed there.'**
  String get tutDSettings;

  /// No description provided for @tutTAgain.
  ///
  /// In en, this message translates to:
  /// **'This introduction'**
  String get tutTAgain;

  /// No description provided for @tutDAgain.
  ///
  /// In en, this message translates to:
  /// **'It lives in the settings. You can read it again at any time.'**
  String get tutDAgain;

  /// No description provided for @onceOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'View once'**
  String get onceOnlyMessage;

  /// No description provided for @openOnceMessage.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openOnceMessage;

  /// No description provided for @onceOnlyHiddenHint.
  ///
  /// In en, this message translates to:
  /// **'Can be opened once'**
  String get onceOnlyHiddenHint;

  /// No description provided for @onceOnlySentHint.
  ///
  /// In en, this message translates to:
  /// **'View-once message sent'**
  String get onceOnlySentHint;

  /// No description provided for @onceOnlyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Can be opened once'**
  String get onceOnlyConfirmTitle;

  /// No description provided for @onceOnlyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This message can be opened once. As soon as you close it, it is removed for good. That also applies if something interrupts you.'**
  String get onceOnlyConfirmBody;

  /// No description provided for @onceOnlyScreenshotHint.
  ///
  /// In en, this message translates to:
  /// **'A screenshot cannot be prevented. You will be told about it.'**
  String get onceOnlyScreenshotHint;

  /// No description provided for @onceOnlyConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm and open'**
  String get onceOnlyConfirmAction;

  /// No description provided for @tutDOnceOnly.
  ///
  /// In en, this message translates to:
  /// **'Send messages that can be opened and read only once.'**
  String get tutDOnceOnly;

  /// No description provided for @aboutSecurityLine.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted. The keys stay on your device.'**
  String get aboutSecurityLine;

  /// No description provided for @securityDetails.
  ///
  /// In en, this message translates to:
  /// **'Security details'**
  String get securityDetails;

  /// No description provided for @secIntro.
  ///
  /// In en, this message translates to:
  /// **'How Krypta protects your messages, from the device through delivery to the server. Everything here reflects how the app is actually built.'**
  String get secIntro;

  /// No description provided for @secMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Message encryption'**
  String get secMessagesTitle;

  /// No description provided for @secMessagesBody.
  ///
  /// In en, this message translates to:
  /// **'Every message is encrypted on your device and only becomes readable again on your contact\'s device. Encryption and authentication happen in one step, with extra data bound into the seal: a modified message is rejected rather than decrypted.'**
  String get secMessagesBody;

  /// No description provided for @secExchangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Key exchange'**
  String get secExchangeTitle;

  /// No description provided for @secExchangeBody.
  ///
  /// In en, this message translates to:
  /// **'On first contact both devices agree on a shared secret without ever transmitting it. Three Diffie-Hellman parts are combined and the session key is derived from them. The server only ever sees public keys.'**
  String get secExchangeBody;

  /// No description provided for @secForwardTitle.
  ///
  /// In en, this message translates to:
  /// **'Forward secrecy'**
  String get secForwardTitle;

  /// No description provided for @secForwardBody.
  ///
  /// In en, this message translates to:
  /// **'A fresh key is derived for every message and the old one is discarded. Anyone who steals a key can read neither earlier nor later messages. Missed messages catch up without giving that property away.'**
  String get secForwardBody;

  /// No description provided for @secIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity and verification'**
  String get secIdentityTitle;

  /// No description provided for @secIdentityBody.
  ///
  /// In en, this message translates to:
  /// **'Each device has an identity key pair. Prekeys and transparency entries are signed, so a server cannot swap them unnoticed. The safety number is computed from both identities and is the same on both devices.'**
  String get secIdentityBody;

  /// No description provided for @secPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Passwords and codes'**
  String get secPasswordTitle;

  /// No description provided for @secPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Passwords and codes are never stored, only their derivation. The method is deliberately slow and memory-hungry so attempts cannot be run in bulk.'**
  String get secPasswordBody;

  /// No description provided for @secLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'On the device'**
  String get secLocalTitle;

  /// No description provided for @secLocalBody.
  ///
  /// In en, this message translates to:
  /// **'Messages and keys are stored encrypted in the app\'s own storage. The master key lives in the operating system keychain and is readable only after the device has been unlocked once. Where available, it is additionally wrapped by a security chip.'**
  String get secLocalBody;

  /// No description provided for @secServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Server and delivery'**
  String get secServerTitle;

  /// No description provided for @secServerBody.
  ///
  /// In en, this message translates to:
  /// **'The server accepts encrypted envelopes and forwards them. It never holds a key and never sees content. Delivery uses a short-lived identifier of the recipient. Delivered envelopes are removed.'**
  String get secServerBody;

  /// No description provided for @secTransportTitle.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get secTransportTitle;

  /// No description provided for @secTransportBody.
  ///
  /// In en, this message translates to:
  /// **'The connection is encrypted and the app accepts only the expected certificates. This is enforced at the operating system level and therefore covers every connection the app makes.'**
  String get secTransportBody;

  /// No description provided for @secFooter.
  ///
  /// In en, this message translates to:
  /// **'These statements describe methods and parameters, never keys. They apply to the version shown above.'**
  String get secFooter;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'nl',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'nl':
      return AppLocalizationsNl();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
