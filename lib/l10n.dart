/// Current UI language: 'vi' or 'en'. Set by AppState before the app builds.
String appLang = 'vi';

/// Picks the string for the current language.
String tr(String vi, String en) => appLang == 'en' ? en : vi;

final _stopVi = RegExp(r'^Trạm · (.*) · tuyến (.*)$');
final _stopEn = RegExp(r'^Stop · (.*) · lines (.*)$');

/// Shows a stop description saved in the other language in the current one.
String trStopSubtitle(String s) {
  final m = (appLang == 'en' ? _stopVi : _stopEn).firstMatch(s);
  if (m == null) return s;
  return tr('Trạm · ${m[1]} · tuyến ${m[2]}', 'Stop · ${m[1]} · lines ${m[2]}');
}
