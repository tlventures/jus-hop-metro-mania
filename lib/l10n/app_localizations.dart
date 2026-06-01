import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';
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
    Locale('bn'),
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('pa'),
    Locale('ta'),
    Locale('te'),
    Locale('ur'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MetroSafar'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @learn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get learn;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String goodMorning(Object name);

  /// No description provided for @readyToExplore.
  ///
  /// In en, this message translates to:
  /// **'Ready to explore today?'**
  String get readyToExplore;

  /// No description provided for @streak.
  ///
  /// In en, this message translates to:
  /// **'{days}-day streak'**
  String streak(Object days);

  /// No description provided for @tapToClaim.
  ///
  /// In en, this message translates to:
  /// **'Tap to claim 20 pts'**
  String get tapToClaim;

  /// No description provided for @dailyQuests.
  ///
  /// In en, this message translates to:
  /// **'Daily Quests'**
  String get dailyQuests;

  /// No description provided for @playGame.
  ///
  /// In en, this message translates to:
  /// **'Play 1 game'**
  String get playGame;

  /// No description provided for @watchVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch video'**
  String get watchVideo;

  /// No description provided for @readArticle.
  ///
  /// In en, this message translates to:
  /// **'Read article'**
  String get readArticle;

  /// No description provided for @yourWallet.
  ///
  /// In en, this message translates to:
  /// **'Your Wallet'**
  String get yourWallet;

  /// No description provided for @pointsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Points available'**
  String get pointsAvailable;

  /// No description provided for @silverTier.
  ///
  /// In en, this message translates to:
  /// **'Silver 🥈'**
  String get silverTier;

  /// No description provided for @ptsToGold.
  ///
  /// In en, this message translates to:
  /// **'points to Gold'**
  String get ptsToGold;

  /// No description provided for @quickEarn.
  ///
  /// In en, this message translates to:
  /// **'Quick Earn'**
  String get quickEarn;

  /// No description provided for @ecoImpact.
  ///
  /// In en, this message translates to:
  /// **'You saved {kg} kg CO₂'**
  String ecoImpact(Object kg);

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @surveys.
  ///
  /// In en, this message translates to:
  /// **'Surveys'**
  String get surveys;

  /// No description provided for @surveysCompleted.
  ///
  /// In en, this message translates to:
  /// **'Surveys Completed'**
  String get surveysCompleted;

  /// No description provided for @articles.
  ///
  /// In en, this message translates to:
  /// **'Articles'**
  String get articles;

  /// No description provided for @articlesRead.
  ///
  /// In en, this message translates to:
  /// **'Articles Read'**
  String get articlesRead;

  /// No description provided for @stories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get stories;

  /// No description provided for @storiesCompleted.
  ///
  /// In en, this message translates to:
  /// **'Stories Completed'**
  String get storiesCompleted;

  /// No description provided for @learnAndGrow.
  ///
  /// In en, this message translates to:
  /// **'Learn & Grow'**
  String get learnAndGrow;

  /// No description provided for @playAndEarn.
  ///
  /// In en, this message translates to:
  /// **'Play & Earn'**
  String get playAndEarn;

  /// No description provided for @contentLibrary.
  ///
  /// In en, this message translates to:
  /// **'Content Library'**
  String get contentLibrary;

  /// No description provided for @readAboutMetro.
  ///
  /// In en, this message translates to:
  /// **'Read about metro, sustainability, and more'**
  String get readAboutMetro;

  /// No description provided for @shareYourFeedback.
  ///
  /// In en, this message translates to:
  /// **'Share your feedback and earn rewards'**
  String get shareYourFeedback;

  /// No description provided for @exploreHistory.
  ///
  /// In en, this message translates to:
  /// **'Explore the rich history of {cityName}'**
  String exploreHistory(String cityName);

  /// No description provided for @howToEarn.
  ///
  /// In en, this message translates to:
  /// **'How to Earn'**
  String get howToEarn;

  /// No description provided for @playGames.
  ///
  /// In en, this message translates to:
  /// **'Play Games'**
  String get playGames;

  /// No description provided for @triviaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trivia, Sudoku, Puzzles'**
  String get triviaSubtitle;

  /// No description provided for @watchVideos.
  ///
  /// In en, this message translates to:
  /// **'Watch Videos'**
  String get watchVideos;

  /// No description provided for @learnAboutMetro.
  ///
  /// In en, this message translates to:
  /// **'Learn about metro & culture'**
  String get learnAboutMetro;

  /// No description provided for @readArticles.
  ///
  /// In en, this message translates to:
  /// **'Read Articles'**
  String get readArticles;

  /// No description provided for @dailyStoriesGuides.
  ///
  /// In en, this message translates to:
  /// **'Daily stories & guides'**
  String get dailyStoriesGuides;

  /// No description provided for @takeSurveys.
  ///
  /// In en, this message translates to:
  /// **'Take Surveys'**
  String get takeSurveys;

  /// No description provided for @redeemRewards.
  ///
  /// In en, this message translates to:
  /// **'Redeem Rewards'**
  String get redeemRewards;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @food.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get food;

  /// No description provided for @shopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get shopping;

  /// No description provided for @travel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get travel;

  /// No description provided for @experiences.
  ///
  /// In en, this message translates to:
  /// **'Experiences'**
  String get experiences;

  /// No description provided for @redeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get redeem;

  /// No description provided for @stationStories.
  ///
  /// In en, this message translates to:
  /// **'Station Stories'**
  String get stationStories;

  /// No description provided for @chapters.
  ///
  /// In en, this message translates to:
  /// **'chapters'**
  String get chapters;

  /// No description provided for @chapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter {current} of {total}'**
  String chapter(Object current, Object total);

  /// No description provided for @previousButton.
  ///
  /// In en, this message translates to:
  /// **'← Previous'**
  String get previousButton;

  /// No description provided for @nextButton.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get nextButton;

  /// No description provided for @finishStory.
  ///
  /// In en, this message translates to:
  /// **'Finish Story ✓'**
  String get finishStory;

  /// No description provided for @storyCompleted.
  ///
  /// In en, this message translates to:
  /// **'Story completed! +{points} points'**
  String storyCompleted(Object points);

  /// No description provided for @thankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you! You earned +{points} points'**
  String thankYou(Object points);

  /// No description provided for @onboardingWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to MetroSafar'**
  String get onboardingWelcome;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore rewards, games, learn & earn points'**
  String get onboardingSubtitle;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNow;

  /// No description provided for @playEarnGames.
  ///
  /// In en, this message translates to:
  /// **'Play & Earn'**
  String get playEarnGames;

  /// No description provided for @playGameDescription.
  ///
  /// In en, this message translates to:
  /// **'Play 5 exciting games daily:\n\n🎡 Daily Spin\n🧠 Trivia Quiz\n🎯 Sudoku\n🧩 Word Puzzle\n🗺️ City Explorer\n\nEarn points with every game!'**
  String get playGameDescription;

  /// No description provided for @learnExplore.
  ///
  /// In en, this message translates to:
  /// **'Learn & Explore'**
  String get learnExplore;

  /// No description provided for @learnDescription.
  ///
  /// In en, this message translates to:
  /// **'Discover fascinating content:\n\n📖 Articles about metro & culture\n📋 Community surveys\n🏛️ Station stories with rich history\n\nLearn something new every day!'**
  String get learnDescription;

  /// No description provided for @earnRedeem.
  ///
  /// In en, this message translates to:
  /// **'Earn & Redeem'**
  String get earnRedeem;

  /// No description provided for @earnDescription.
  ///
  /// In en, this message translates to:
  /// **'Collect points from all activities:\n\n🎮 Play games\n📚 Read articles\n📝 Take surveys\n🔥 Daily streaks\n\nRedeem for food, shopping & travel vouchers!'**
  String get earnDescription;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enableNotifications;

  /// No description provided for @locationAccess.
  ///
  /// In en, this message translates to:
  /// **'Location Access'**
  String get locationAccess;

  /// No description provided for @showNearbyStations.
  ///
  /// In en, this message translates to:
  /// **'Show nearby metro stations'**
  String get showNearbyStations;

  /// No description provided for @notificationsPermission.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsPermission;

  /// No description provided for @remindersForStreaks.
  ///
  /// In en, this message translates to:
  /// **'Reminders for streaks and quests'**
  String get remindersForStreaks;

  /// No description provided for @youCanChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can change these later in settings'**
  String get youCanChangeLater;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get hindi;

  /// No description provided for @tamil.
  ///
  /// In en, this message translates to:
  /// **'தமிழ்'**
  String get tamil;

  /// No description provided for @telugu.
  ///
  /// In en, this message translates to:
  /// **'తెలుగు'**
  String get telugu;

  /// No description provided for @kannada.
  ///
  /// In en, this message translates to:
  /// **'ಕನ್ನಡ'**
  String get kannada;

  /// No description provided for @marathi.
  ///
  /// In en, this message translates to:
  /// **'मराठी'**
  String get marathi;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;
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
    'bn',
    'en',
    'gu',
    'hi',
    'kn',
    'ml',
    'mr',
    'pa',
    'ta',
    'te',
    'ur',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'gu':
      return AppLocalizationsGu();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'ml':
      return AppLocalizationsMl();
    case 'mr':
      return AppLocalizationsMr();
    case 'pa':
      return AppLocalizationsPa();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
