import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/erneut_senden_policy.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/message_bubble.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Wann eine gescheiterte Nachricht sich noch einmal schicken laesst.
///
/// Bis zum 25.09.2026 gar nicht: der Text war aus dem Eingabefeld weg, und
/// in der Blase stand nur ein rotes Ausrufezeichen.
void main() {
  Message nachricht({
    String senderId = 'ich',
    MessageStatus status = MessageStatus.failed,
    String? text = 'Bin gleich da',
    bool einmalig = false,
    bool passwort = false,
    SystemEventKind? ereignis,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: senderId,
        recipientId: 'du',
        encryptedContent: '',
        decryptedContent: text,
        timestamp: DateTime(2026, 9, 25, 21),
        status: status,
        einmalig: einmalig,
        isPasswordProtected: passwort,
        passwordUnlocked: !passwort,
        systemEvent: ereignis,
      );

  test('die eigene gescheiterte Nachricht geht noch einmal raus', () {
    expect(ErneutSendenPolicy.moeglich(nachricht(), 'ich'), isTrue);
  });

  test('was rausging, wird nicht noch einmal geschickt', () {
    for (final status in [
      MessageStatus.sending,
      MessageStatus.sent,
      MessageStatus.delivered,
      MessageStatus.read,
    ]) {
      expect(
        ErneutSendenPolicy.moeglich(nachricht(status: status), 'ich'),
        isFalse,
        reason: '$status',
      );
    }
  });

  test('nur die eigene', () {
    expect(
        ErneutSendenPolicy.moeglich(nachricht(senderId: 'du'), 'ich'), isFalse);
  });

  test('ohne bekannte eigene Kennung nichts', () {
    expect(ErneutSendenPolicy.moeglich(nachricht(), null), isFalse);
  });

  test('die einmalige nicht: ihr Klartext liegt beim Absender gar nicht', () {
    expect(
      ErneutSendenPolicy.moeglich(nachricht(einmalig: true, text: null), 'ich'),
      isFalse,
    );
    // Auch dann nicht, wenn aus einem Altbestand doch noch Text daran haengt.
    expect(
        ErneutSendenPolicy.moeglich(nachricht(einmalig: true), 'ich'), isFalse);
  });

  test('die passwortgeschuetzte nicht: sie ginge ungeschuetzt raus', () {
    expect(
        ErneutSendenPolicy.moeglich(nachricht(passwort: true), 'ich'), isFalse);
  });

  test('ohne Text nichts', () {
    expect(ErneutSendenPolicy.moeglich(nachricht(text: null), 'ich'), isFalse);
    expect(ErneutSendenPolicy.moeglich(nachricht(text: ''), 'ich'), isFalse);
  });

  test('ein Hinweis ist keine Nachricht', () {
    expect(
      ErneutSendenPolicy.moeglich(
          nachricht(ereignis: SystemEventKind.values.first), 'ich'),
      isFalse,
    );
  });

  group('die Blase', () {
    Widget rahmen(Message m) => MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(message: m, isMine: true, eigeneId: 'ich'),
          ),
        );

    testWidgets('sagt, dass die Nachricht nicht rausging, und wie weiter',
        (tester) async {
      await tester.pumpWidget(rahmen(nachricht()));
      await tester.pumpAndSettle();
      expect(find.text('Nicht gesendet. Tippen zum erneuten Senden.'),
          findsOneWidget);
    });

    testWidgets('eine zugestellte Nachricht traegt keinen Hinweis',
        (tester) async {
      await tester.pumpWidget(rahmen(nachricht(status: MessageStatus.read)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nicht gesendet'), findsNothing);
    });

  });
}
