/// Interface translations.
///
/// Every user-visible English string goes through [tr]. The English text is
/// the key, so a missing translation simply shows English. Placeholders are
/// numbered: `tr('{0} left of {1} budget', [left, limit])`.
library;

import 'translations.dart';

/// A supported interface language.
class AppLanguage {
  const AppLanguage(this.code, this.englishName, this.nativeName);
  final String code;
  final String englishName;
  final String nativeName;
}

const appLanguages = [
  AppLanguage('en', 'English', 'English'),
  AppLanguage('hi', 'Hindi', 'हिन्दी'),
  AppLanguage('kn', 'Kannada', 'ಕನ್ನಡ'),
  AppLanguage('ta', 'Tamil', 'தமிழ்'),
  AppLanguage('te', 'Telugu', 'తెలుగు'),
  AppLanguage('ml', 'Malayalam', 'മലയാളം'),
  AppLanguage('mr', 'Marathi', 'मराठी'),
  AppLanguage('bn', 'Bengali', 'বাংলা'),
  AppLanguage('gu', 'Gujarati', 'ગુજરાતી'),
];

/// Languages that have translations (English always).
List<AppLanguage> get availableLanguages => [
  for (final l in appLanguages)
    if (l.code == 'en' || translations.containsKey(l.code)) l,
];

String _language = 'en';

/// The current interface language code.
String get currentLanguage => _language;

/// Switches the language used by [tr]. Unknown codes fall back to English.
void setCurrentLanguage(String code) {
  _language = translations.containsKey(code) ? code : 'en';
}

/// [english] in the current language, with `{0}`, `{1}`, … replaced by
/// [args].
String tr(String english, [List<Object?> args = const []]) {
  var s = translations[_language]?[english] ?? english;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
