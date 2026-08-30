import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/services/storage/legacy_cleanup.dart';

/// Das einmalige Aufräumen der Reste des ausgebauten Tarn-Messengers.
///
/// Den Code zu löschen räumt auf bestehenden Geräten nichts weg. Dort liegen
/// weiter `decoy_chats` mit erfundenen Chats und im Schlüsselbund ein
/// `krypta_code_decoy`. Genau das ist der forensische Hinweis, der weg soll:
/// eine Datei mit erfundenen Chats sagt jemandem, der das Gerät auswertet,
/// dass diese App einen Tarnmodus hatte.
///
/// Deshalb läuft das Aufräumen einmal beim Start — und darf sich dabei nicht
/// selbst im Weg stehen.
void main() {
  late bool merker;
  late List<String> getan;

  setUp(() {
    merker = false;
    getan = [];
  });

  LegacyCleanup baue({
    Future<int> Function()? raeumeDateien,
    Future<void> Function()? loescheSchluessel,
    Future<void> Function()? setzeMerker,
  }) {
    return LegacyCleanup(
      markerSet: () async => merker,
      setMarker: setzeMerker ??
          () async {
            merker = true;
            getan.add('merker');
          },
      purgeFiles: raeumeDateien ??
          () async {
            getan.add('dateien');
            return 2;
          },
      deleteLegacyKeys: loescheSchluessel ??
          () async => getan.add('schluessel'),
    );
  }

  test('mit gesetztem Merker wird nichts angefasst', () async {
    merker = true;

    final ergebnis = await baue().run();

    expect(ergebnis, LegacyCleanupOutcome.alreadyDone);
    expect(getan, isEmpty,
        reason: 'ein zweiter Lauf hat nichts zu tun und darf nichts kosten');
  });

  test('räumt Dateien und Schlüsselbund und merkt es sich', () async {
    final ergebnis = await baue().run();

    expect(ergebnis, LegacyCleanupOutcome.cleaned);
    expect(getan, ['dateien', 'schluessel', 'merker']);
    expect(merker, isTrue);
  });

  test('ohne Reste wird der Merker trotzdem gesetzt', () async {
    // Sonst sucht jeder Start aufs Neue — auf Geräten, die den Tarnmodus nie
    // gesehen haben, wäre das dauerhaft vergebliche Arbeit.
    final ergebnis = await baue(raeumeDateien: () async {
      getan.add('dateien');
      return 0;
    }).run();

    expect(ergebnis, LegacyCleanupOutcome.nothingFound);
    expect(merker, isTrue);
  });

  test('scheitert das Räumen der Dateien, bleibt der Merker aus', () async {
    // Anders als beim FreshInstallGuard, wo der Merker VOR dem Räumen gesetzt
    // wird: dort wäre ein Dauerlauf gefährlich. Hier ist Löschen wiederholbar
    // und folgenlos — ein zweiter Versuch beim nächsten Start ist genau das,
    // was man will. Die Reste dürfen nicht liegen bleiben, nur weil ein Lauf
    // schiefging.
    final ergebnis = await baue(
      raeumeDateien: () async => throw Exception('Ordner nicht lesbar'),
    ).run();

    expect(ergebnis, LegacyCleanupOutcome.failed);
    expect(merker, isFalse);
    expect(getan, isEmpty);
  });

  test('scheitert der Schlüsselbund, bleibt der Merker ebenfalls aus',
      () async {
    final ergebnis = await baue(
      loescheSchluessel: () async => throw Exception('Schluesselbund zu'),
    ).run();

    expect(ergebnis, LegacyCleanupOutcome.failed);
    expect(merker, isFalse,
        reason: 'die Dateien sind weg, der Code noch da — nächster Start holt es nach');
  });

  test('scheitert das Setzen des Merkers, gilt der Lauf als gescheitert',
      () async {
    final ergebnis = await baue(
      setzeMerker: () async => throw Exception('Schluesselbund zu'),
    ).run();

    expect(ergebnis, LegacyCleanupOutcome.failed);
  });
}
