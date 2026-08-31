import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/message_bubble.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Wie hoch eine Nachrichtenblase baut.
///
/// Der Anlass: Daniel meldet, die Blasen seien „immer so riesig". Die Ursache
/// war die Uhrzeit — sie stand in einer eigenen Zeile unter dem Text, und ein
/// „ok" wurde dadurch fast doppelt so hoch wie noetig. WhatsApp setzt sie ans
/// Ende der letzten Textzeile und laesst sie nur dann umbrechen, wenn dort
/// wirklich kein Platz mehr ist.
void main() {
  Message nachricht({
    required String text,
    Duration? timer,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'ich',
        recipientId: 'marco',
        encryptedContent: 'x',
        decryptedContent: text,
        timestamp: DateTime(2026, 8, 31, 14, 32),
        status: MessageStatus.read,
        selfDestructDuration: timer,
      );

  Widget rahmen(Message m, {bool isMine = true}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MessageBubble(message: m, isMine: isMine),
        ),
      );

  /// Die Blase selbst, nicht der Bereich, in dem sie sitzt: `Align` nimmt sich
  /// die ganze verfuegbare Flaeche, gemessen werden soll aber der eingefaerbte
  /// Kasten.
  double blasenHoehe(WidgetTester tester) => tester
      .getSize(find
          .descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          )
          .first)
      .height;

  /// Eine Zeile Text plus Innenabstand — mehr darf eine kurze Nachricht nicht
  /// kosten. Alles darueber heisst: die Uhrzeit hat sich eine eigene Zeile
  /// genommen.
  const hoechstensEineZeile = 40.0;

  testWidgets('ein kurzes „ok" bleibt einzeilig', (tester) async {
    await tester.pumpWidget(rahmen(nachricht(text: 'ok')));

    expect(blasenHoehe(tester), lessThan(hoechstensEineZeile),
        reason: 'die Uhrzeit gehoert neben den Text, nicht darunter');
  });

  testWidgets('auch mit Timer-Symbol bleibt es einzeilig', (tester) async {
    await tester.pumpWidget(
      rahmen(nachricht(text: 'ok', timer: const Duration(minutes: 1))),
    );

    expect(blasenHoehe(tester), lessThan(hoechstensEineZeile));
  });

  testWidgets('die Uhrzeit ist trotzdem da', (tester) async {
    await tester.pumpWidget(rahmen(nachricht(text: 'ok')));

    expect(find.text('14:32'), findsOneWidget);
  });

  testWidgets('eine empfangene Nachricht baut genauso flach', (tester) async {
    await tester.pumpWidget(rahmen(nachricht(text: 'ok'), isMine: false));

    expect(blasenHoehe(tester), lessThan(hoechstensEineZeile));
  });

  testWidgets('die Uhrzeit sitzt am Ende des Textes, auch von rechts nach links',
      (tester) async {
    // Der Platzhalter haengt am *logischen* Ende des Textes. Wird die Uhrzeit
    // fest nach visuell rechts gelegt, liegen die beiden bei einer Schrift von
    // rechts nach links auf verschiedenen Seiten — der freigehaltene Platz
    // waere links, die Uhrzeit rechts, und sie schoebe sich ueber den Text.
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: MessageBubble(message: nachricht(text: 'ok'), isMine: true),
        ),
      ),
    ));

    final blase = tester.getRect(find
        .descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Container),
        )
        .first);
    final uhrzeit = tester.getRect(find.text('14:32'));

    // Bei rechts-nach-links endet der Text links — dort gehoert die Uhrzeit hin.
    expect(uhrzeit.left - blase.left, lessThan(blase.right - uhrzeit.right),
        reason: 'die Uhrzeit gehoert ans Ende des Textes, nicht fest nach rechts');
  });

  testWidgets('bei doppelter Schriftgroesse bleibt es einzeilig',
      (tester) async {
    // Die Uhrzeit waechst mit der Systemschrift, die Symbole daneben nicht.
    // Rechnet der freigehaltene Platz das falsch, schiebt sich die Uhrzeit
    // ueber den Text — sichtbar nur bei grosser Schrift, also selten bemerkt.
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: MessageBubble(message: nachricht(text: 'ok'), isMine: true),
          ),
        ),
      ),
    ));

    expect(find.text('14:32'), findsOneWidget);
    // Eine Zeile bei doppelter Schrift: rund vierzig Pixel Text plus Rand.
    expect(blasenHoehe(tester), lessThan(70.0));
  });

  testWidgets('bei doppelter Schrift waechst die Blase nur einfach mit',
      (tester) async {
    // Flutter skaliert den Platzhalter im Text bereits selbst. Wird die
    // Uhrzeit beim Ausmessen ein zweites Mal hochgerechnet, haelt die Blase
    // doppelt so viel Platz frei wie noetig — und genau die Kompaktheit,
    // um die es hier geht, ist bei grosser Systemschrift wieder weg.
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
          body: MessageBubble(message: nachricht(text: 'ok'), isMine: true),
        ),
      ),
    ));

    final breite = tester
        .getSize(find
            .descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            )
            .first)
        .width;
    final uhrzeit = tester.getSize(find.text('14:32')).width;

    // Text + Abstand + Uhrzeit + Haken + Innenabstand. Grosszuegig gerechnet,
    // aber weit unter dem, was doppeltes Hochrechnen ergaebe.
    expect(breite, lessThan(uhrzeit + 140),
        reason: 'die Uhrzeit wird zweimal hochgerechnet');
  });

  testWidgets('die Uhrzeit bleibt in der letzten Zeile, wenn sie umbricht',
      (tester) async {
    // Der Platzhalter haengt am Ende des Textes. Muss er auf eine eigene Zeile
    // ausweichen, darf die Uhrzeit nicht nach oben in den Text hineinragen.
    await tester.pumpWidget(rahmen(nachricht(text: 'Hallo\n')));

    final blase = tester.getRect(find
        .descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Container),
        )
        .first);
    final uhrzeit = tester.getRect(find.text('14:32'));

    // Eine Textzeile ist rund zwanzig Pixel hoch. Die Uhrzeit darf hoechstens
    // in die unterste davon hineinreichen, nie in die darueber.
    expect(uhrzeit.top, greaterThan(blase.bottom - 7 - 20 - 1),
        reason: 'die Uhrzeit ragt in die vorletzte Zeile hinein');
  });

  testWidgets('der freigehaltene Platz folgt der Schrift des Umfelds',
      (tester) async {
    // Die Uhrzeit erbt Schriftart und Laufweite vom Umfeld. Wird beim
    // Ausmessen eine nackte Schrift angenommen statt der tatsaechlichen,
    // faellt der freigehaltene Platz zu klein aus und die Uhrzeit legt sich
    // ueber den Text — je nach Thema und Sprache, also unzuverlaessig.
    Future<double> breiteMit(double laufweite) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DefaultTextStyle(
            style: TextStyle(letterSpacing: laufweite),
            child: MessageBubble(message: nachricht(text: 'ok'), isMine: true),
          ),
        ),
      ));
      return tester
          .getSize(find
              .descendant(
                of: find.byType(MessageBubble),
                matching: find.byType(Container),
              )
              .first)
          .width;
    }

    final schmal = await breiteMit(0);
    final weit = await breiteMit(4);

    // Fuenf Zeichen Uhrzeit mal vier Pixel Laufweite: der freigehaltene Platz
    // muss spuerbar mitwachsen.
    expect(weit - schmal, greaterThan(12),
        reason: 'der Platz wird gegen eine andere Schrift gemessen als gezeichnet');
  });

  testWidgets('ein langer Text bricht weiterhin um und behaelt die Uhrzeit',
      (tester) async {
    await tester.pumpWidget(rahmen(nachricht(
      text: 'Das hier ist bewusst ein laengerer Satz, damit die Blase '
          'ueber mehrere Zeilen laeuft und man sieht, dass die Uhrzeit '
          'dabei nicht verlorengeht.',
    )));

    expect(blasenHoehe(tester), greaterThan(hoechstensEineZeile),
        reason: 'mehrzeilig soll mehrzeilig bleiben');
    expect(find.text('14:32'), findsOneWidget);
  });
}
