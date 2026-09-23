import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/chatliste_policy.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/chat_tile.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Die Kachel in der Chatliste, so wie Daniel sie am 22.09.2026 bestellt hat:
/// „vom Prinzip her wie bei WhatsApp".
///
/// Name, darunter die letzte Nachricht, rechts die Uhrzeit und der Ballon.
/// Was die Kachel dabei **nicht** zeigt, steht in chat_list_privacy_test.
void main() {
  Chat chat({
    int unread = 0,
    DateTime? zeit,
    bool typing = false,
  }) =>
      Chat(
        id: 'c1',
        recipientId: 'r1',
        recipientName: 'Marco',
        lastMessageTime: zeit ?? DateTime(2026, 9, 22, 14, 32),
        unreadCount: unread,
        isTyping: typing,
      );

  Future<void> zeige(
    WidgetTester tester, {
    required Chat c,
    Vorschau vorschau = (
      art: VorschauArt.keine,
      text: null,
      vonMir: false,
      ereignis: null
    ),
    MessageStatus? stand,
    bool hatInhalt = true,
    DateTime? jetzt,
    String sprache = 'de',
  }) =>
      tester.pumpWidget(MaterialApp(
        locale: Locale(sprache),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatTile(
            chat: c,
            onTap: () {},
            vorschau: vorschau,
            eigenerStand: stand,
            hatInhalt: hatInhalt,
            jetzt: jetzt ?? DateTime(2026, 9, 22, 18, 0),
          ),
        ),
      ));

  Vorschau text(String t, {bool vonMir = false}) =>
      (art: VorschauArt.text, text: t, vonMir: vonMir, ereignis: null);

  testWidgets('die letzte Nachricht steht unter dem Namen', (t) async {
    await zeige(t, c: chat(), vorschau: text('Bin unterwegs'));
    expect(find.text('Bin unterwegs'), findsOneWidget);
    expect(find.text('Marco'), findsOneWidget);
  });

  testWidgets('meine eigene bekommt das Du davor', (t) async {
    await zeige(t, c: chat(), vorschau: text('Bis gleich', vonMir: true));
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.text('${l10n.previewYou}: '), findsOneWidget);
  });

  testWidgets('zu meiner eigenen gehoeren die Haken', (t) async {
    await zeige(t,
        c: chat(),
        vorschau: text('Bis gleich', vonMir: true),
        stand: MessageStatus.read);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('zur Nachricht der Gegenseite nicht', (t) async {
    await zeige(t, c: chat(), vorschau: text('Bin unterwegs'));
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('wer gerade tippt, verdraengt die Vorschau', (t) async {
    // Was geschrieben wird, ist neuer als alles, was dasteht.
    await zeige(t, c: chat(typing: true), vorschau: text('Bin unterwegs'));
    expect(find.text('Bin unterwegs'), findsNothing);
  });

  group('Die Uhrzeit', () {
    testWidgets('heute: die Uhrzeit', (t) async {
      await zeige(t,
          c: chat(zeit: DateTime(2026, 9, 22, 14, 32)),
          jetzt: DateTime(2026, 9, 22, 18, 0));
      expect(find.text('14:32'), findsOneWidget);
    });

    testWidgets('gestern kurz vor Mitternacht, jetzt kurz danach: Gestern',
        (t) async {
      // Der gemeldete Fall: keine vier Stunden dazwischen, und doch ein
      // anderer Tag. Vorher stand hier weiter „23:50".
      await zeige(t,
          c: chat(zeit: DateTime(2026, 9, 21, 23, 50)),
          jetzt: DateTime(2026, 9, 22, 0, 10));
      final l10n = await AppLocalizations.delegate.load(const Locale('de'));
      expect(find.text(l10n.yesterday), findsOneWidget);
      expect(find.text('23:50'), findsNothing);
    });

    testWidgets('und Gestern steht auf Franzoesisch da, nicht auf Englisch',
        (t) async {
      // Hier stand eine feste Liste englischer Kuerzel in einer App mit
      // sieben Sprachen.
      await zeige(t,
          c: chat(zeit: DateTime(2026, 9, 21, 23, 50)),
          jetzt: DateTime(2026, 9, 22, 0, 10),
          sprache: 'fr');
      final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
      expect(find.text(l10n.yesterday), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);
    });

    testWidgets('diese Woche: der Wochentag, nicht Mon oder Tue', (t) async {
      await zeige(t,
          c: chat(zeit: DateTime(2026, 9, 19, 9, 0)),
          jetzt: DateTime(2026, 9, 22, 18, 0));
      expect(find.text('Mon'), findsNothing);
      expect(find.text('Tue'), findsNothing);
      expect(find.text('Sat'), findsNothing);
    });
  });

  testWidgets('ist alles abgelaufen, steht rechts keine Uhrzeit', (t) async {
    // Die Uhrzeit bleibt im Chat gespeichert, damit er seinen Platz in der
    // Liste behaelt — angezeigt wird sie nicht, sie zeigte sonst auf einen
    // Zeitpunkt, zu dem nichts mehr dasteht.
    await zeige(t,
        c: chat(zeit: DateTime(2026, 9, 22, 14, 32)), hatInhalt: false);
    expect(find.text('14:32'), findsNothing);
    expect(find.text('Marco'), findsOneWidget);
  });

  testWidgets('der Ballon steht weiterhin rechts', (t) async {
    await zeige(t, c: chat(unread: 3), vorschau: text('Bin unterwegs'));
    expect(find.text('3'), findsOneWidget);
  });
}
