/// Current UI language: 'vi' or 'en'. Set by AppState before the app builds.
String appLang = 'vi';

/// Picks the string for the current language.
String tr(String vi, String en) => appLang == 'en' ? en : vi;
