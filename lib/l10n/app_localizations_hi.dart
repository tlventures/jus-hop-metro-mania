// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'मेट्रो सफर';

  @override
  String get home => 'होम';

  @override
  String get play => 'खेलें';

  @override
  String get learn => 'सीखें';

  @override
  String get wallet => 'वॉलेट';

  @override
  String get profile => 'प्रोफाइल';

  @override
  String goodMorning(Object name) {
    return 'नमस्ते, $name';
  }

  @override
  String get readyToExplore => 'अन्वेषण के लिए तैयार हैं?';

  @override
  String streak(Object days) {
    return '$days दिन की स्ट्रीक';
  }

  @override
  String get tapToClaim => 'क्लेम करने के लिए टैप करें - 20 पॉइंट्स';

  @override
  String get dailyQuests => 'दैनिक कार्य';

  @override
  String get playGame => 'एक गेम खेलें';

  @override
  String get watchVideo => 'वीडियो देखें';

  @override
  String get readArticle => 'लेख पढ़ें';

  @override
  String get yourWallet => 'आपका वॉलेट';

  @override
  String get pointsAvailable => 'उपलब्ध पॉइंट्स';

  @override
  String get silverTier => 'सिल्वर 🥈';

  @override
  String get ptsToGold => 'गोल्ड तक के पॉइंट्स';

  @override
  String get quickEarn => 'जल्दी कमाएं';

  @override
  String ecoImpact(Object kg) {
    return 'आपने $kg किलो CO₂ बचाया';
  }

  @override
  String get thisWeek => 'इस सप्ताह';

  @override
  String get surveys => 'सर्वेक्षण';

  @override
  String get surveysCompleted => 'पूरे किए गए सर्वेक्षण';

  @override
  String get articles => 'लेख';

  @override
  String get articlesRead => 'पढ़े गए लेख';

  @override
  String get stories => 'कहानियाँ';

  @override
  String get storiesCompleted => 'पूरी की गई कहानियाँ';

  @override
  String get learnAndGrow => 'सीखें और बढ़ें';

  @override
  String get playAndEarn => 'खेलें और कमाएं';

  @override
  String get contentLibrary => 'सामग्री पुस्तकालय';

  @override
  String get readAboutMetro =>
      'मेट्रो, स्थायित्व और बहुत कुछ के बारे में पढ़ें';

  @override
  String get shareYourFeedback =>
      'अपनी प्रतिक्रिया साझा करें और पुरस्कार अर्जित करें';

  @override
  String exploreHistory(String cityName) {
    return '$cityName के समृद्ध इतिहास का अन्वेषण करें';
  }

  @override
  String get howToEarn => 'कैसे कमाएं';

  @override
  String get playGames => 'गेम खेलें';

  @override
  String get triviaSubtitle => 'ट्रिविया, सुडोकू, पहेलियाँ';

  @override
  String get watchVideos => 'वीडियो देखें';

  @override
  String get learnAboutMetro => 'मेट्रो और संस्कृति के बारे में जानें';

  @override
  String get readArticles => 'लेख पढ़ें';

  @override
  String get dailyStoriesGuides => 'दैनिक कहानियाँ और गाइड';

  @override
  String get takeSurveys => 'सर्वेक्षण लें';

  @override
  String get redeemRewards => 'पुरस्कार रिडीम करें';

  @override
  String get all => 'सभी';

  @override
  String get food => 'खाना';

  @override
  String get shopping => 'खरीदारी';

  @override
  String get travel => 'यात्रा';

  @override
  String get experiences => 'अनुभव';

  @override
  String get redeem => 'रिडीम करें';

  @override
  String get stationStories => 'स्टेशन की कहानियाँ';

  @override
  String get chapters => 'अध्याय';

  @override
  String chapter(Object current, Object total) {
    return 'अध्याय $current का $total';
  }

  @override
  String get previousButton => '← पिछला';

  @override
  String get nextButton => 'अगला →';

  @override
  String get finishStory => 'कहानी समाप्त करें ✓';

  @override
  String storyCompleted(Object points) {
    return 'कहानी पूरी हुई! +$points पॉइंट्स';
  }

  @override
  String thankYou(Object points) {
    return 'धन्यवाद! आपने +$points पॉइंट्स अर्जित किए';
  }

  @override
  String get onboardingWelcome => 'मेट्रो सफर में आपका स्वागत है';

  @override
  String get onboardingSubtitle => 'पुरस्कार, गेम, सीखें और पॉइंट्स कमाएं';

  @override
  String get getStarted => 'शुरुआत करें';

  @override
  String get skipForNow => 'अभी के लिए छोड़ें';

  @override
  String get playEarnGames => 'खेलें और कमाएं';

  @override
  String get playGameDescription =>
      'दैनिक 5 रोचक गेम खेलें:\n\n🎡 डेली स्पिन\n🧠 ट्रिविया क्विज़\n🎯 सुडोकू\n🧩 शब्द पहेली\n🗺️ सिटी एक्सप्लोरर\n\nहर गेम से पॉइंट्स कमाएं!';

  @override
  String get learnExplore => 'सीखें और अन्वेषण करें';

  @override
  String get learnDescription =>
      'आकर्षक सामग्री की खोज करें:\n\n📖 मेट्रो और संस्कृति के बारे में लेख\n📋 सामुदायिक सर्वेक्षण\n🏛️ समृद्ध इतिहास के साथ स्टेशन की कहानियाँ\n\nहर दिन कुछ नया सीखें!';

  @override
  String get earnRedeem => 'कमाएं और रिडीम करें';

  @override
  String get earnDescription =>
      'सभी गतिविधियों से पॉइंट्स एकत्र करें:\n\n🎮 गेम खेलें\n📚 लेख पढ़ें\n📝 सर्वेक्षण लें\n🔥 दैनिक स्ट्रीक\n\nखाना, खरीदारी और यात्रा वाउचर के लिए रिडीम करें!';

  @override
  String get enableNotifications => 'नोटिफिकेशन सक्षम करें';

  @override
  String get locationAccess => 'स्थान की पहुंच';

  @override
  String get showNearbyStations => 'पास के मेट्रो स्टेशन दिखाएं';

  @override
  String get notificationsPermission => 'नोटिफिकेशन';

  @override
  String get remindersForStreaks => 'स्ट्रीक और कार्यों के लिए अनुस्मारक';

  @override
  String get youCanChangeLater => 'आप बाद में सेटिंग्स में इसे बदल सकते हैं';

  @override
  String get allow => 'अनुमति दें';

  @override
  String get back => 'पिछला';

  @override
  String get done => 'पूर्ण';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get language => 'भाषा';

  @override
  String get selectLanguage => 'भाषा चुनें';

  @override
  String get english => 'English';

  @override
  String get hindi => 'हिन्दी';

  @override
  String get tamil => 'தமிழ்';

  @override
  String get telugu => 'తెలుగు';

  @override
  String get kannada => 'ಕನ್ನಡ';

  @override
  String get marathi => 'मराठी';

  @override
  String get privacyPolicy => 'गोपनीयता नीति';

  @override
  String get termsOfService => 'सेवा की शर्तें';
}
