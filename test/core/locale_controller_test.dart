import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/locale/locale_controller.dart';

/// Die App war bis hierher ein Sprachmischmasch: das Tutorial deutsch, der
/// Einrichtungs-Bildschirm direkt danach englisch, die Chat-Einstellungen
/// gemischt. Eine bewusste Sprachwahl gab es nicht — `MaterialApp` hatte gar
/// kein `locale`, es galt einfach die Gerätesprache.
///
/// Diese Tests decken die Wahl selbst ab: welche Sprachen es gibt, wie ein
/// gespeicherter Wert gelesen wird und was bei Unsinn passiert. Die
/// Speicherung ist hineingereicht, damit das ohne Gerät läuft.
void main() {
  /// Ein Speicher im Arbeitsspeicher, der sich wie der echte verhält.
  ({LocaleController controller, Map<String, String> store}) build({
    String? stored,
  }) {
    final store = <String, String>{};
    if (stored != null) store['lang'] = stored;
    final controller = LocaleController(
      read: () async => store['lang'],
      write: (value) async => store['lang'] = value,
    );
    return (controller: controller, store: store);
  }

  group('unterstützte Sprachen', () {
    test('genau die sieben abgesprochenen, Englisch zuerst', () {
      // Englisch oben, weil es die Voreinstellung ist. Danach alphabetisch
      // nach dem Eigennamen — also so, wie die Liste angezeigt wird.
      expect(
        LocaleController.supported.map((l) => l.languageCode).toList(),
        ['en', 'de', 'es', 'fr', 'it', 'nl', 'pt'],
      );
    });

    test('Englisch ist der Rückfall', () {
      expect(LocaleController.fallback, const Locale('en'));
    });

    test('jede Sprache trägt ihren Namen in ihrer eigenen Schreibweise', () {
      // Wer die App auf Spanisch stellen will, sucht „Español" — nicht
      // „Spanisch" und erst recht nicht „Spanish".
      expect(LocaleController.labelFor(const Locale('en')), 'English');
      expect(LocaleController.labelFor(const Locale('de')), 'Deutsch');
      expect(LocaleController.labelFor(const Locale('es')), 'Español');
      expect(LocaleController.labelFor(const Locale('it')), 'Italiano');
      expect(LocaleController.labelFor(const Locale('fr')), 'Français');
      expect(LocaleController.labelFor(const Locale('nl')), 'Nederlands');
      expect(LocaleController.labelFor(const Locale('pt')), 'Português');
    });
  });

  group('einlesen', () {
    test('erkennt jeden unterstützten Code', () {
      for (final locale in LocaleController.supported) {
        expect(LocaleController.parse(locale.languageCode), locale);
      }
    });

    test('Groß- und Kleinschreibung ist egal', () {
      expect(LocaleController.parse('DE'), const Locale('de'));
      expect(LocaleController.parse('Pt'), const Locale('pt'));
    });

    test('Regionszusatz wird abgeschnitten', () {
      // Ein früher gespeicherter Wert oder eine Gerätesprache kann
      // `de_DE` oder `pt-BR` lauten. Die Sprache zählt, nicht die Region.
      expect(LocaleController.parse('de_DE'), const Locale('de'));
      expect(LocaleController.parse('pt-BR'), const Locale('pt'));
    });

    test('unbekannt und leer ergeben nichts', () {
      expect(LocaleController.parse('kl'), isNull);
      expect(LocaleController.parse(''), isNull);
      expect(LocaleController.parse(null), isNull);
    });
  });

  group('laden', () {
    test('ohne gespeicherte Wahl gilt Englisch', () async {
      final t = build();
      await t.controller.load();
      expect(t.controller.locale, const Locale('en'));
      expect(t.controller.hasChosen, isFalse);
    });

    test('eine gespeicherte Wahl wird übernommen', () async {
      final t = build(stored: 'it');
      await t.controller.load();
      expect(t.controller.locale, const Locale('it'));
      expect(t.controller.hasChosen, isTrue);
    });

    test('ein unbrauchbarer Wert fällt still auf Englisch zurück', () async {
      // Lieber Englisch als ein Absturz beim Start, nur weil im Speicher
      // etwas Unerwartetes steht.
      final t = build(stored: 'klingonisch');
      await t.controller.load();
      expect(t.controller.locale, const Locale('en'));
      expect(t.controller.hasChosen, isFalse);
    });
  });

  group('auswählen', () {
    test('setzt die Sprache, speichert sie und meldet die Änderung', () async {
      final t = build();
      var notified = 0;
      t.controller.addListener(() => notified++);

      await t.controller.select(const Locale('fr'));

      expect(t.controller.locale, const Locale('fr'));
      expect(t.controller.hasChosen, isTrue);
      expect(t.store['lang'], 'fr');
      expect(notified, 1);
    });

    test('dieselbe Sprache noch einmal löst keinen Neuaufbau aus', () async {
      final t = build(stored: 'de');
      await t.controller.load();
      var notified = 0;
      t.controller.addListener(() => notified++);

      await t.controller.select(const Locale('de'));

      expect(notified, 0);
    });

    test('eine nicht unterstützte Sprache wird abgelehnt', () async {
      final t = build(stored: 'de');
      await t.controller.load();

      await t.controller.select(const Locale('kl'));

      expect(t.controller.locale, const Locale('de'));
      expect(t.store['lang'], isNot('kl'));
    });

    test('ein Speicherfehler ändert die Sprache trotzdem', () async {
      // Die Anzeige soll umschalten, auch wenn das Merken scheitert. Sonst
      // sieht es aus, als hätte der Tipp nicht funktioniert.
      final controller = LocaleController(
        read: () async => null,
        write: (_) async => throw Exception('Speicher kaputt'),
      );
      await controller.select(const Locale('es'));
      expect(controller.locale, const Locale('es'));
    });
  });
}
