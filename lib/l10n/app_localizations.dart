import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_ur.dart';

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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
    Locale('mr'),
    Locale('pa'),
    Locale('ta'),
    Locale('ur')
  ];

  /// No description provided for @helloWorld.
  ///
  /// In en, this message translates to:
  /// **'Hello'**
  String get helloWorld;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @loginTo.
  ///
  /// In en, this message translates to:
  /// **'Login To Your Account'**
  String get loginTo;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @registerSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Register Speaker'**
  String get registerSpeaker;

  /// No description provided for @identifySpeaker.
  ///
  /// In en, this message translates to:
  /// **'Identify Speaker'**
  String get identifySpeaker;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @friendBook.
  ///
  /// In en, this message translates to:
  /// **'Friend Book'**
  String get friendBook;

  /// No description provided for @speakerBook.
  ///
  /// In en, this message translates to:
  /// **'Speaker Book'**
  String get speakerBook;

  /// No description provided for @addFriends.
  ///
  /// In en, this message translates to:
  /// **'Add Friends'**
  String get addFriends;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @updateProfile.
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get updateProfile;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotificationFound.
  ///
  /// In en, this message translates to:
  /// **'No notifications found!'**
  String get noNotificationFound;

  /// No description provided for @speakMyMsg.
  ///
  /// In en, this message translates to:
  /// **'Speak my messages in meetings'**
  String get speakMyMsg;

  /// No description provided for @showTextMyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Show text in my language'**
  String get showTextMyLanguage;

  /// No description provided for @yourMsgWillBe.
  ///
  /// In en, this message translates to:
  /// **'Your messages will be spoken aloud to everyone.'**
  String get yourMsgWillBe;

  /// No description provided for @yourMsgWillNotBe.
  ///
  /// In en, this message translates to:
  /// **'Your messages will not be auto-spoken. You can tap play to speak.'**
  String get yourMsgWillNotBe;

  /// No description provided for @myTransactions.
  ///
  /// In en, this message translates to:
  /// **'My Transactions'**
  String get myTransactions;

  /// No description provided for @viewPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'View payment history & receipts'**
  String get viewPaymentHistory;

  /// No description provided for @legalAndPolicies.
  ///
  /// In en, this message translates to:
  /// **'Legal & Policies'**
  String get legalAndPolicies;

  /// No description provided for @termsAndConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsAndConditions;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @getHelpOrReport.
  ///
  /// In en, this message translates to:
  /// **'Get help or report issues'**
  String get getHelpOrReport;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @tapMicToStart.
  ///
  /// In en, this message translates to:
  /// **'Tap mic to start/stop listening'**
  String get tapMicToStart;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get listening;

  /// No description provided for @noConversationYet.
  ///
  /// In en, this message translates to:
  /// **'No conversation yet.\nStart a group talk!'**
  String get noConversationYet;

  /// No description provided for @typeAMsg.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeAMsg;

  /// No description provided for @tapBelowToRegister.
  ///
  /// In en, this message translates to:
  /// **'Tap below to register a new speaker.'**
  String get tapBelowToRegister;

  /// No description provided for @registerNewContact.
  ///
  /// In en, this message translates to:
  /// **'Register New Contact'**
  String get registerNewContact;

  /// No description provided for @enterAFriendlyName.
  ///
  /// In en, this message translates to:
  /// **'Enter a friendly name for this contact.\nThis helps identify them by voice.'**
  String get enterAFriendlyName;

  /// No description provided for @hintName.
  ///
  /// In en, this message translates to:
  /// **'e.g. Vivek Sharma'**
  String get hintName;

  /// No description provided for @noSpeakerRegister.
  ///
  /// In en, this message translates to:
  /// **'No speakers registered yet!'**
  String get noSpeakerRegister;

  /// No description provided for @saveContinue.
  ///
  /// In en, this message translates to:
  /// **'Save & Continue'**
  String get saveContinue;

  /// No description provided for @friendList.
  ///
  /// In en, this message translates to:
  /// **'Friend List'**
  String get friendList;

  /// No description provided for @myFriends.
  ///
  /// In en, this message translates to:
  /// **'My Friends'**
  String get myFriends;

  /// No description provided for @updateYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Update Your Profile'**
  String get updateYourProfile;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @age.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @maritalStatus.
  ///
  /// In en, this message translates to:
  /// **'Marital Status'**
  String get maritalStatus;

  /// No description provided for @supportReplied.
  ///
  /// In en, this message translates to:
  /// **'Support replied'**
  String get supportReplied;

  /// No description provided for @myTransaction.
  ///
  /// In en, this message translates to:
  /// **'My Transaction'**
  String get myTransaction;

  /// No description provided for @termsAndCondition.
  ///
  /// In en, this message translates to:
  /// **'Terms And Conditions'**
  String get termsAndCondition;

  /// No description provided for @areYourSureYouWantLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get areYourSureYouWantLogout;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @tapMicToRecord.
  ///
  /// In en, this message translates to:
  /// **'Tap mic to record your answer'**
  String get tapMicToRecord;

  /// No description provided for @recordingSpeakClearly.
  ///
  /// In en, this message translates to:
  /// **'Recording... Speak the sentence clearly.'**
  String get recordingSpeakClearly;

  /// No description provided for @youAreOnQuestion.
  ///
  /// In en, this message translates to:
  /// **'You\'re on question'**
  String get youAreOnQuestion;

  /// No description provided for @of_text.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get of_text;

  /// No description provided for @thisWillPermanently.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and all data. Continue?'**
  String get thisWillPermanently;

  /// No description provided for @goPremium.
  ///
  /// In en, this message translates to:
  /// **'Go Premium'**
  String get goPremium;

  /// No description provided for @awa.
  ///
  /// In en, this message translates to:
  /// **'AWA'**
  String get awa;

  /// No description provided for @premium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get premium;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'Chat History'**
  String get chatHistory;

  /// No description provided for @groupChat.
  ///
  /// In en, this message translates to:
  /// **'Group Chat'**
  String get groupChat;

  /// No description provided for @conversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversation;

  /// No description provided for @removeFriend.
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get removeFriend;

  /// No description provided for @areYouSure.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove'**
  String get areYouSure;

  /// No description provided for @removeFromFriend.
  ///
  /// In en, this message translates to:
  /// **'from your friends?'**
  String get removeFromFriend;

  /// No description provided for @noMsgYet.
  ///
  /// In en, this message translates to:
  /// **'No message yet.'**
  String get noMsgYet;

  /// No description provided for @startTheConversation.
  ///
  /// In en, this message translates to:
  /// **'Start the conversation!'**
  String get startTheConversation;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'Typing...'**
  String get typing;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhoto;

  /// No description provided for @noUserFound.
  ///
  /// In en, this message translates to:
  /// **'No users found!'**
  String get noUserFound;

  /// No description provided for @inviteOrSearch.
  ///
  /// In en, this message translates to:
  /// **'Invite or search for new friends.'**
  String get inviteOrSearch;

  /// No description provided for @addedSuccessFully.
  ///
  /// In en, this message translates to:
  /// **'added successfully!'**
  String get addedSuccessFully;

  /// No description provided for @voiceMatched.
  ///
  /// In en, this message translates to:
  /// **'Voice Matched!'**
  String get voiceMatched;

  /// No description provided for @voiceNotClear.
  ///
  /// In en, this message translates to:
  /// **'Voice not clear or not detected. Please try again.'**
  String get voiceNotClear;

  /// No description provided for @voiceRegisteredOnly.
  ///
  /// In en, this message translates to:
  /// **'Voice Registered Only'**
  String get voiceRegisteredOnly;

  /// No description provided for @deleteSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Delete Speaker'**
  String get deleteSpeaker;

  /// No description provided for @addSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Add Speaker'**
  String get addSpeaker;

  /// No description provided for @single.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get single;

  /// No description provided for @married.
  ///
  /// In en, this message translates to:
  /// **'Married'**
  String get married;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @feMale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get feMale;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @trialExpired.
  ///
  /// In en, this message translates to:
  /// **'Trial Expired'**
  String get trialExpired;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get hindi;

  /// No description provided for @nameFieldIntro.
  ///
  /// In en, this message translates to:
  /// **'Add the speaker\'s name to easily recognize their voice.'**
  String get nameFieldIntro;

  /// No description provided for @repeatSentenceHint.
  ///
  /// In en, this message translates to:
  /// **'Repeat the displayed sentence to complete all questions.'**
  String get repeatSentenceHint;

  /// No description provided for @speakerListIntro.
  ///
  /// In en, this message translates to:
  /// **'This screen lists your registered speakers.'**
  String get speakerListIntro;

  /// No description provided for @speakerAddIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap Add Speaker to register a new voice.'**
  String get speakerAddIntro;

  /// No description provided for @friendListIntro.
  ///
  /// In en, this message translates to:
  /// **'Browse people and send them a friend request.'**
  String get friendListIntro;

  /// No description provided for @friendAddIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap the add icon to connect and start chatting.'**
  String get friendAddIntro;

  /// No description provided for @friendBookIntro.
  ///
  /// In en, this message translates to:
  /// **'Your approved friends appear here.'**
  String get friendBookIntro;

  /// No description provided for @friendChatIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap the chat bubble to start a conversation.'**
  String get friendChatIntro;

  /// No description provided for @permissionRequiredMic.
  ///
  /// In en, this message translates to:
  /// **'Mic Permission is Required'**
  String get permissionRequiredMic;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['bn', 'en', 'gu', 'hi', 'mr', 'pa', 'ta', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn': return AppLocalizationsBn();
    case 'en': return AppLocalizationsEn();
    case 'gu': return AppLocalizationsGu();
    case 'hi': return AppLocalizationsHi();
    case 'mr': return AppLocalizationsMr();
    case 'pa': return AppLocalizationsPa();
    case 'ta': return AppLocalizationsTa();
    case 'ur': return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
