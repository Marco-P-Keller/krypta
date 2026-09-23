import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/chatliste_policy.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/chat_tile.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Was die Chatliste über den Inhalt verrät — und was nicht.
///
/// Bis zum 30.08.2026 stand unter dem Namen der Klartext der letzten
/// Nachricht, und zwar aus einem Feld am Chat: der Text lag damit **zweimal**
/// verschlüsselt auf der Platte, im Nachrichtenspeicher und noch einmal in
/// `chats.enc`.
///
/// Seit dem 22.09.2026 steht dort wieder eine Vorschau — Daniels Liste, „vom
/// Prinzip her wie bei WhatsApp". Der Grund von damals gilt trotzdem weiter,
/// und deshalb gilt jetzt beides:
///
///   * Das **Feld** ist und bleibt weg. Was die Kachel zeigt, reicht ihr der
///     Aufrufer aus dem Verlauf im Speicher; gespeichert wird es nirgends.
///   * Der **Schalter** in den Einstellungen schaltet sie ab. Dann sagt die
///     Liste wieder nur, dass etwas da ist.
///   * Zwei Arten zeigen ihren Inhalt **nie**: die einmalige und die
///     passwortgeschützte Nachricht.
Widget _rahmen(Chat chat) => MaterialApp(
      home: Scaffold(
        body: ChatTile(chat: chat, onTap: () {}),
      ),
    );

void main() {
  /// Ein Chat, wie ihn ein Bestandsgeraet liefert: [preview] steht noch in
  /// der gespeicherten Fassung, das Modell liest ihn nicht mehr.
  Chat chat({int unread = 0, String? preview}) => Chat.fromMap({
        'id': 'c1',
        'recipientId': 'r1',
        'recipientName': 'Marco',
        'lastMessagePreview': ?preview,
        'lastMessageTime': DateTime(2026, 8, 30, 14, 32).millisecondsSinceEpoch,
        'unreadCount': unread,
      });

  testWidgets('der Nachrichtentext steht nicht in der Liste', (tester) async {
    await tester.pumpWidget(_rahmen(chat(preview: 'hey bro')));

    expect(find.text('hey bro'), findsNothing,
        reason: 'die Liste ist von aussen lesbar, der Chat nicht');
    expect(find.text('Marco'), findsOneWidget);
  });

  testWidgets('auch ein alter gespeicherter Text taucht nicht auf',
      (tester) async {
    // Geraete, die schon laufen, haben den Klartext in chats.enc liegen.
    // Bis das Aufraeumen greift, darf die Kachel ihn trotzdem nicht zeigen.
    await tester.pumpWidget(_rahmen(chat(preview: 'Kontonummer DE12 3456')));

    expect(find.textContaining('Kontonummer'), findsNothing);
  });

  testWidgets('der Ballon zeigt die Zahl neuer Nachrichten', (tester) async {
    await tester.pumpWidget(_rahmen(chat(unread: 3)));

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('ohne neue Nachrichten kein Ballon', (tester) async {
    await tester.pumpWidget(_rahmen(chat()));

    expect(find.text('0'), findsNothing);
  });

  testWidgets('viele Nachrichten werden gedeckelt', (tester) async {
    // Die genaue Zahl ab hundert sagt mehr ueber die Nutzung aus, als sie
    // nuetzt — und sprengt den Kreis.
    await tester.pumpWidget(_rahmen(chat(unread: 143)));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('143'), findsNothing);
  });

  // ── Was auch bei eingeschalteter Vorschau nie dasteht ──────────────────

  Message nachricht({
    String? text = 'Kontonummer DE12 3456',
    bool einmalig = false,
    bool passwort = false,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: '',
        decryptedContent: text,
        timestamp: DateTime(2026, 9, 22, 14, 32),
        einmalig: einmalig,
        isPasswordProtected: passwort,
      );

  Future<void> mitVorschau(WidgetTester tester, Vorschau v) =>
      tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatTile(chat: chat(), onTap: () {}, vorschau: v),
        ),
      ));

  testWidgets('die einmalige Nachricht steht nie im Klartext in der Liste',
      (tester) async {
    final v = VorschauPolicy.fuer([nachricht(einmalig: true)],
        eigeneId: 'ich', zeigen: true);
    await mitVorschau(tester, v);

    expect(find.textContaining('Kontonummer'), findsNothing,
        reason: 'sie ist einmal zu oeffnen, nicht einmal zu lesen und '
            'einmal in der Liste');
    final l10n = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.text(l10n.onceOnlyMessage), findsOneWidget);
  });

  testWidgets('die passwortgeschuetzte ebensowenig', (tester) async {
    final v = VorschauPolicy.fuer([nachricht(passwort: true)],
        eigeneId: 'ich', zeigen: true);
    await mitVorschau(tester, v);

    expect(find.textContaining('Kontonummer'), findsNothing);
  });

  testWidgets('und mit abgeschaltetem Schalter gar nichts', (tester) async {
    final v = VorschauPolicy.fuer([nachricht()],
        eigeneId: 'ich', zeigen: false);
    await mitVorschau(tester, v);

    expect(find.textContaining('Kontonummer'), findsNothing);
    expect(find.text('Marco'), findsOneWidget);
  });
}
