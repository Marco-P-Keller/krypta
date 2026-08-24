import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Die vom Nutzer gewählte Anzeigesprache.
///
/// Vorher hatte `MaterialApp` gar kein `locale`: es galt die Gerätesprache,
/// und weil ein guter Teil der Oberfläche fest verdrahtete Texte trug, ergab
/// das einen Mischmasch — Tutorial deutsch, Einrichtung englisch, Chat-
/// Einstellungen gemischt. Die Sprache ist jetzt eine bewusste Entscheidung,
/// beim Einrichten getroffen und in den Einstellungen änderbar.
///
/// Das Lesen und Schreiben ist hineingereicht statt fest an den
/// `SecureStorageService` gebunden — so lässt sich das hier ohne Gerät und
/// ohne Plattformkanal testen.
class LocaleController extends ChangeNotifier {
  LocaleController({
    required Future<String?> Function() read,
    required Future<void> Function(String) write,
  })  : _read = read,
        _write = write;

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;

  /// Die angebotenen Sprachen, in der Reihenfolge der Auswahlliste.
  ///
  /// Englisch steht bewusst oben und ist die Voreinstellung; der Rest folgt
  /// alphabetisch nach dem Eigennamen, so wie er in der Liste erscheint.
  static const List<Locale> supported = [
    Locale('en'), // English
    Locale('de'), // Deutsch
    Locale('es'), // Español
    Locale('fr'), // Français
    Locale('it'), // Italiano
    Locale('nl'), // Nederlands
    Locale('pt'), // Português
  ];

  static const Locale fallback = Locale('en');

  /// Der Name der Sprache in ihrer eigenen Schreibweise.
  ///
  /// Wer die App auf Spanisch stellen will, sucht „Español" — nicht
  /// „Spanisch" und erst recht nicht „Spanish". Deshalb steht diese Liste
  /// bewusst NICHT in den `.arb`-Dateien: sie wird nicht übersetzt.
  static String labelFor(Locale locale) {
    switch (locale.languageCode) {
      case 'de':
        return 'Deutsch';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'it':
        return 'Italiano';
      case 'nl':
        return 'Nederlands';
      case 'pt':
        return 'Português';
      case 'en':
      default:
        return 'English';
    }
  }

  /// Einen gespeicherten oder vom System gemeldeten Code einlesen.
  ///
  /// Verträgt `de_DE` und `pt-BR`: die Sprache zählt, die Region nicht.
  /// Gibt `null` zurück, wenn nichts Brauchbares dasteht — der Aufrufer
  /// entscheidet dann über den Rückfall.
  static Locale? parse(String? code) {
    if (code == null) return null;
    final normalized =
        code.trim().split(RegExp('[-_]')).first.toLowerCase();
    if (normalized.isEmpty) return null;
    for (final locale in supported) {
      if (locale.languageCode == normalized) return locale;
    }
    return null;
  }

  Locale _locale = fallback;
  Locale get locale => _locale;

  /// Ob je eine gültige Sprache gespeichert war.
  ///
  /// Unterscheidet „Englisch, weil so gewählt" von „Englisch, weil noch
  /// nichts gewählt wurde" — nur im zweiten Fall gehört die Auswahl ins
  /// Einrichten.
  bool _hasChosen = false;
  bool get hasChosen => _hasChosen;

  /// Die gespeicherte Wahl übernehmen. Beim Start einmal aufzurufen.
  Future<void> load() async {
    String? stored;
    try {
      stored = await _read();
    } catch (_) {
      // Ein unlesbarer Speicher darf den Start nicht verhindern.
      stored = null;
    }
    final parsed = parse(stored);
    if (parsed != null) {
      _locale = parsed;
      _hasChosen = true;
    } else {
      _locale = fallback;
      _hasChosen = false;
    }
  }

  /// Eine Sprache wählen. Wirkt sofort, ohne Neustart.
  Future<void> select(Locale locale) async {
    if (!supported.contains(locale)) return;
    if (_locale == locale && _hasChosen) return;

    _locale = locale;
    _hasChosen = true;
    notifyListeners();

    try {
      await _write(locale.languageCode);
    } catch (e) {
      // Die Anzeige hat schon umgeschaltet — das soll auch so bleiben, sonst
      // sieht es aus, als hätte der Tipp nicht funktioniert. Gemerkt wird die
      // Wahl dann eben erst beim nächsten Mal.
      if (kDebugMode) debugPrint('Sprachwahl konnte nicht gespeichert werden');
    }
  }
}
