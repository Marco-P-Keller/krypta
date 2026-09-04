import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/frist_stufe.dart';

/// Jede angebotene Frist bekommt ihre eigene Beschriftung.
///
/// Der Anlass: eine externe Durchsicht bemerkte, dass in der Auswahl zweimal
/// „1 Std." stand. Die Ursache war die Reihenfolge der Vergleiche — dreissig
/// Minuten fielen durch bis zu `inHours <= 1`.
void main() {
  // Genau die Auswahl, die das Einstellungsblatt anbietet.
  const angebotene = <Duration?>[
    null,
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 24),
    Duration(days: 7),
  ];

  test('jede angebotene Frist bekommt eine EIGENE Stufe', () {
    final stufen = angebotene.map(FristLabel.stufe).toList();
    expect(stufen.toSet().length, stufen.length,
        reason: 'zwei Fristen mit derselben Beschriftung — genau der Fehler, '
            'durch den zweimal "1 Std." dastand: $stufen');
  });

  test('„Direkt nach dem Lesen" ist eine eigene Stufe', () {
    // Sie ist keine Frist — es gibt keine Dauer, die sie ausdruecken koennte.
    // Ohne eigene Stufe stuende in der Auswahl „Aus", waehrend der Chat
    // gelesene Nachrichten wegraeumt.
    expect(FristLabel.stufeFuerRegel(nachLesen: true), FristStufe.nachLesen);
    expect(FristLabel.stufeFuerRegel(frist: const Duration(minutes: 5)),
        FristStufe.minuten5);
    expect(FristLabel.stufeFuerRegel(), FristStufe.aus);
  });

  test('die ganze Auswahl bleibt unterscheidbar', () {
    final stufen = [
      ...angebotene.map((d) => FristLabel.stufeFuerRegel(frist: d)),
      FristLabel.stufeFuerRegel(nachLesen: true),
    ];
    expect(stufen.toSet().length, stufen.length);
  });

  test('dreissig Minuten heissen dreissig Minuten', () {
    expect(FristLabel.stufe(const Duration(minutes: 30)),
        FristStufe.minuten30);
  });

  test('die uebrigen Stufen stimmen', () {
    expect(FristLabel.stufe(null), FristStufe.aus);
    expect(FristLabel.stufe(const Duration(seconds: 30)),
        FristStufe.sekunden30);
    expect(FristLabel.stufe(const Duration(minutes: 5)), FristStufe.minuten5);
    expect(FristLabel.stufe(const Duration(hours: 1)), FristStufe.stunde1);
    expect(FristLabel.stufe(const Duration(hours: 24)), FristStufe.tag1);
    expect(FristLabel.stufe(const Duration(days: 7)), FristStufe.woche1);
  });

  test('Zwischenwerte fallen auf die naechste Stufe', () {
    expect(FristLabel.stufe(const Duration(minutes: 6)), FristStufe.minuten30);
    expect(FristLabel.stufe(const Duration(minutes: 31)), FristStufe.stunde1);
    expect(FristLabel.stufe(const Duration(hours: 2)), FristStufe.tag1);
    expect(FristLabel.stufe(const Duration(days: 30)), FristStufe.woche1);
  });
}
