import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/chatliste_policy.dart';

/// Welche Form die Uhrzeit rechts in der Chatliste annimmt.
///
/// Der Anlass: dort stand eine eigene Rechnung mit
/// `now.difference(time).inDays`. Das ist um zehn nach Mitternacht fuer eine
/// Nachricht von gestern 23:50 immer noch null — in der Liste stand deshalb
/// `23:50`, als waere sie von heute. Eine Stufe hoeher derselbe Fehler:
/// „Dienstag" blieb bis Mittwochabend stehen.
///
/// Gerechnet wird darum in **Kalendertagen**. Die Woerter selbst kommen aus
/// der Uebersetzung und aus `intl`; vorher standen dort feste englische
/// Kuerzel (`Yesterday`, `Mon`, `Tue`) in einer App mit sieben Sprachen.
void main() {
  group('Der Tageswechsel', () {
    test('heute frueh ist eine Uhrzeit', () {
      expect(
        ChatlistZeit.form(
            DateTime(2026, 9, 22, 8, 5), DateTime(2026, 9, 22, 23, 0)),
        ZeitForm.uhrzeit,
      );
    });

    test('gestern 23:50, gelesen um 00:10, ist Gestern', () {
      // Genau der gemeldete Fall. Keine vier Stunden dazwischen, und doch
      // ein anderer Tag.
      expect(
        ChatlistZeit.form(
            DateTime(2026, 9, 21, 23, 50), DateTime(2026, 9, 22, 0, 10)),
        ZeitForm.gestern,
      );
    });

    test('vor 23 Stunden am selben Tag bleibt eine Uhrzeit', () {
      expect(
        ChatlistZeit.form(
            DateTime(2026, 9, 22, 0, 30), DateTime(2026, 9, 22, 23, 30)),
        ZeitForm.uhrzeit,
      );
    });
  });

  group('Die weiteren Stufen', () {
    test('zwei bis sechs Tage sind ein Wochentag', () {
      for (final tage in [2, 3, 6]) {
        expect(
          ChatlistZeit.form(
              DateTime(2026, 9, 22).subtract(Duration(days: tage)),
              DateTime(2026, 9, 22, 12)),
          ZeitForm.wochentag,
          reason: 'vor $tage Tagen',
        );
      }
    });

    test('ab sieben Tagen ein Datum', () {
      expect(
        ChatlistZeit.form(DateTime(2026, 9, 15, 12), DateTime(2026, 9, 22, 12)),
        ZeitForm.datum,
      );
    });

    test('der siebte Tag ist die Grenze, nicht der achte', () {
      // Sonst stuende eine Woche spaeter derselbe Wochentag da wie heute.
      expect(
        ChatlistZeit.form(DateTime(2026, 9, 16, 12), DateTime(2026, 9, 22, 12)),
        ZeitForm.wochentag,
      );
    });
  });

  test('eine Uhr, die vorgeht, macht daraus kein Datum von morgen', () {
    // Der Zeitstempel kommt von der Gegenseite. Geht ihre Uhr vor, ist die
    // Nachricht in der Zukunft — eine Uhrzeit ist dann immer noch die beste
    // Antwort.
    expect(
      ChatlistZeit.form(DateTime(2026, 9, 23, 9), DateTime(2026, 9, 22, 23)),
      ZeitForm.uhrzeit,
    );
  });
}
