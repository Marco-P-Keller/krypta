import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

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

  /// No description provided for @decoyCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Decoy Code'**
  String get decoyCodeLabel;

  /// No description provided for @decoyCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a code that opens a fake messenger'**
  String get decoyCodeHint;

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

  /// No description provided for @changeDecoyCode.
  ///
  /// In en, this message translates to:
  /// **'Change Decoy Code'**
  String get changeDecoyCode;

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

  /// No description provided for @screenshotProtection.
  ///
  /// In en, this message translates to:
  /// **'Screenshot Protection'**
  String get screenshotProtection;

  /// No description provided for @screenshotDescription.
  ///
  /// In en, this message translates to:
  /// **'Block screenshots in the messenger'**
  String get screenshotDescription;

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

  /// No description provided for @decoyTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get decoyTitle;

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

  /// No description provided for @qrScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a Krypta QR code'**
  String get qrScanHint;

  /// No description provided for @qrShareHint.
  ///
  /// In en, this message translates to:
  /// **'Let others scan this to connect'**
  String get qrShareHint;

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

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get deleteChat;

  /// No description provided for @autoDeleteTimer.
  ///
  /// In en, this message translates to:
  /// **'Auto-Delete Timer'**
  String get autoDeleteTimer;

  /// No description provided for @autoDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'New messages in this chat will automatically self-destruct after the selected time.'**
  String get autoDeleteHint;

  /// No description provided for @chatDefault.
  ///
  /// In en, this message translates to:
  /// **'Chat default'**
  String get chatDefault;

  /// No description provided for @burnAfterRead.
  ///
  /// In en, this message translates to:
  /// **'Burn after read'**
  String get burnAfterRead;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

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
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
