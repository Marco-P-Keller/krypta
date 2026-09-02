# Einmalige Nachricht Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Absender kann eine Nachricht als einmalig markieren; der Empfaenger oeffnet sie nach einer Bestaetigung in einer eigenen Ansicht, danach ist sie auf beiden Geraeten fort.

**Architecture:** Ein neues Feld `Message.einmalig` reist als `_once` durch den bestehenden Payload. Die Entscheidungen liegen als reine Funktionen in `EinmaligPolicy`, weil der `MessengerProvider` Firebase braucht und im Test nicht laeuft. Verbraucht wird beim Bestaetigen: erst loeschen und melden, dann die Ansicht mit dem Text aus dem Arbeitsspeicher oeffnen. Einzeltimer und Burn after read fallen als Sendeoption weg, ihre Lesepfade bleiben fuer den Bestand.

**Tech Stack:** Flutter 3.47, Dart, flutter_test, provider, Firestore als Relay, gen-l10n mit sieben arb-Dateien.

**Spec:** `docs/superpowers/specs/2026-09-02-einmalige-nachricht-design.md`

## Global Constraints

- **Sprache im Code:** Kommentare und Testnamen auf Deutsch, Umlaute als ae/oe/ue transkribiert.
- **Nutzertexte:** kurze Hauptsaetze, **keine Gedankenstriche**. `test/core/tutorial_texte_test.dart` prueft das fuer alle tut-Schluessel.
- **Sieben Sprachen:** jeder neue Text in app_de, app_en, app_es, app_fr, app_it, app_nl, app_pt. Sonst faellt `test/core/localization_completeness_test.dart` durch. Nach jeder arb-Aenderung `flutter gen-l10n`.
- **Dialoge:** jeder neue AlertDialog mit Inhalt setzt `scrollable: true`. `test/core/dialoge_mit_eingabefeld_test.dart` wacht darueber.
- **Zeilenenden je Datei beibehalten.** chat_screen.dart ist LF, message_bubble.dart ist CRLF. Zeilenweise arbeiten.
- **Rueckwaertskompatibel deserialisieren:** jedes neue Feld braucht einen Standardwert.
- **Nach jeder Aufgabe** `flutter test` und `flutter analyze`. Analyze meldet vier vorbestehende Punkte in fremden Testdateien; mehr heisst, die Aufgabe hat etwas eingeschleppt. Analyze schreibt `analysis_options.yaml` um, vor dem Commit `git checkout -- analysis_options.yaml`.

---

## File Structure

**Neu**

- `lib/features/messenger/logic/einmalig_policy.dart` — die beiden Entscheidungen, ohne Flutter-Abhaengigkeit.
- `lib/features/messenger/presentation/einmalige_nachricht_screen.dart` — die eigene Ansicht, zeigt einen Text und sonst nichts.
- `test/core/einmalig_policy_test.dart`
- `test/core/einmalige_nachricht_ui_test.dart`

**Geaendert**

- `lib/features/messenger/data/models/message_model.dart` — Feld `einmalig`.
- `lib/features/messenger/logic/messenger_provider.dart` — senden, empfangen, verbrauchen.
- `lib/features/messenger/presentation/chat_screen.dart` — Sendemenue, Zustand, Markierung.
- `lib/features/messenger/presentation/widgets/message_bubble.dart` — verborgene Blase, Restzeit raus.
- `lib/l10n/app_*.arb` (sieben) — neue Texte, Tutorialzeile umgewidmet.

---

### Task 1: Die Regel und das Feld

Ohne diese Aufgabe hat keine spaetere etwas, worauf sie sich stuetzen kann.

**Files:**
- Create: `lib/features/messenger/logic/einmalig_policy.dart`
- Create: `test/core/einmalig_policy_test.dart`
- Modify: `lib/features/messenger/data/models/message_model.dart` (Konstruktor Zeile 86, copyWith ab 114, toMap ab 175, fromMap ab 198)
- Test: `test/core/message_persistence_test.dart`

**Interfaces:**
- Consumes: nichts.
- Produces: `EinmaligPolicy.verbergen({required bool einmalig, required String senderId, required String? eigeneId}) -> bool`; `EinmaligPolicy.ausPayload(Map<String, dynamic> payload) -> bool`; `EinmaligPolicy.feldName` (String, Wert `_once`); `Message.einmalig` (bool, Standard false) samt `copyWith(einmalig: ...)`.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

Datei `test/core/einmalig_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/einmalig_policy.dart';

/// Wann eine einmalige Nachricht verborgen wird und woran sie zu erkennen ist.
void main() {
  group('verbergen', () {
    test('beim Empfaenger wird verborgen', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: true, senderId: 'marco', eigeneId: 'ich'),
        isTrue,
      );
    });

    test('beim Absender nicht: er sieht seinen eigenen Text', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: true, senderId: 'ich', eigeneId: 'ich'),
        isFalse,
      );
    });

    test('eine gewoehnliche Nachricht wird nie verborgen', () {
      expect(
        EinmaligPolicy.verbergen(
            einmalig: false, senderId: 'marco', eigeneId: 'ich'),
        isFalse,
      );
    });
  });

  group('ausPayload', () {
    test('_once wird erkannt', () {
      expect(EinmaligPolicy.ausPayload({'_once': true}), isTrue);
    });

    test('ohne Feld ist die Nachricht gewoehnlich', () {
      expect(EinmaligPolicy.ausPayload({'text': 'hallo'}), isFalse);
    });

    test('_bar eines aelteren Absenders zaehlt NICHT als einmalig', () {
      expect(EinmaligPolicy.ausPayload({'_bar': true}), isFalse);
    });
  });
}
```

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `flutter test test/core/einmalig_policy_test.dart`

Expected: FAIL mit `Error when reading 'lib/features/messenger/logic/einmalig_policy.dart'`

- [ ] **Step 3: Die Regel schreiben**

Datei `lib/features/messenger/logic/einmalig_policy.dart`:

```dart
/// Die einmalige Nachricht: wann sie verborgen wird, und woran sie zu
/// erkennen ist.
///
/// Sie ersetzt seit dem 02.09.2026 den Loeschtimer einzelner Nachrichten und
/// Burn after read. Die Entscheidungen stehen hier und nicht im Provider,
/// weil der Firebase braucht und darum nicht im Test laeuft.
abstract final class EinmaligPolicy {
  /// Das Feld im inneren Payload.
  static const String feldName = '_once';

  /// Ob die Blase den Inhalt verbergen und stattdessen die Schaltflaeche
  /// zeigen muss.
  ///
  /// Beim Absender nie: er sieht seinen eigenen Text, bis die Gegenseite
  /// geoeffnet hat. Danach ist die Nachricht auch bei ihm fort.
  static bool verbergen({
    required bool einmalig,
    required String senderId,
    required String? eigeneId,
  }) =>
      einmalig && senderId != eigeneId;

  /// Ob eine eintreffende Nachricht als einmalig gilt.
  ///
  /// Liest ausschliesslich [feldName]. Das alte `_bar` bleibt bewusst aussen
  /// vor: ein aelterer Absender hat seiner Gegenseite Burn after read
  /// zugesagt. Daraus nachtraeglich eine Nachricht mit Tor und Bestaetigung
  /// zu machen hiesse, seine Zusage im Nachhinein zu aendern.
  static bool ausPayload(Map<String, dynamic> payload) =>
      payload[feldName] == true || payload[feldName] == 'true';
}
```

- [ ] **Step 4: Test laufen lassen, er muss durchgehen**

Run: `flutter test test/core/einmalig_policy_test.dart`

Expected: PASS, sechs Tests

- [ ] **Step 5: Das Feld am Modell ergaenzen**

In `lib/features/messenger/data/models/message_model.dart` direkt nach `final bool burnAfterRead;`:

```dart
  /// Ob diese Nachricht nur einmal geoeffnet werden darf.
  ///
  /// Ersetzt seit dem 02.09.2026 den Einzeltimer und Burn after read. Beim
  /// Empfaenger bleibt der Inhalt verborgen, bis er bestaetigt hat; mit dem
  /// Bestaetigen ist die Nachricht von der Platte fort.
  final bool einmalig;
```

Im Konstruktor nach `this.burnAfterRead = false,` die Zeile `this.einmalig = false,`.

In `copyWith` **kein** neuer Parameter: die Methode nimmt nur fuenf, alles andere wird durchgereicht, und `einmalig` steht beim Anlegen fest. Im Rumpf nach `burnAfterRead: burnAfterRead,` genuegt die Zeile `einmalig: einmalig,`.

In `toMap` nach `'burnAfterRead': burnAfterRead ? 1 : 0,` die Zeile `'einmalig': einmalig ? 1 : 0,`.

In `fromMap` nach `burnAfterRead: (map['burnAfterRead'] as int?) == 1,`:

```dart
      // Bestandsdatensaetze kennen das Feld nicht und sind gewoehnlich.
      einmalig: (map['einmalig'] as int?) == 1,
```

- [ ] **Step 6: Den Modelltest ergaenzen**

An `test/core/message_persistence_test.dart` innerhalb von `main()` anhaengen:

```dart
  test('einmalig ueberlebt Speichern und Laden', () {
    final m = Message(
      id: 'e1',
      chatId: 'c1',
      senderId: 'marco',
      recipientId: 'ich',
      encryptedContent: 'x',
      timestamp: DateTime(2026, 9, 2, 12),
      einmalig: true,
    );
    expect(Message.fromMap(m.toMap()).einmalig, isTrue);
  });

  test('ein Bestandsdatensatz ohne das Feld ist gewoehnlich', () {
    final m = Message(
      id: 'e2',
      chatId: 'c1',
      senderId: 'marco',
      recipientId: 'ich',
      encryptedContent: 'x',
      timestamp: DateTime(2026, 9, 2, 12),
    );
    final karte = Map<String, dynamic>.from(m.toMap())..remove('einmalig');
    expect(Message.fromMap(karte).einmalig, isFalse);
  });
```

- [ ] **Step 7: Alles laufen lassen**

Run: `flutter test` danach `flutter analyze`

Expected: alle Tests gruen, analyze genau vier vorbestehende Punkte

- [ ] **Step 8: Committen**

```bash
git checkout -- analysis_options.yaml
git add lib/features/messenger/logic/einmalig_policy.dart lib/features/messenger/data/models/message_model.dart test/core/einmalig_policy_test.dart test/core/message_persistence_test.dart
git commit -m "feat(einmalig): die Regel und das Feld am Modell"
```

---

### Task 2: Senden und Leitung

Das Sendemenue bietet danach nur noch die einmalige Nachricht, und das Feld reist mit.

**Files:**
- Modify: `lib/features/messenger/presentation/chat_screen.dart` (Zustand ab Zeile 52, `_effectiveTimer` ab 123, `_fristVomChat` ab 133, Senden ab 180, Markierung ab 563, Popup ab 903)
- Modify: `lib/features/messenger/logic/messenger_provider.dart` (sendMessage ab 2379, Payload ab 2579, Empfang bei 3146 und 3398)
- Modify: alle sieben `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: `EinmaligPolicy.feldName`, `EinmaligPolicy.ausPayload`, `Message.einmalig` aus Task 1.
- Produces: `MessengerProvider.sendMessage(..., {bool einmalig = false})`; der l10n-Schluessel `onceOnlyMessage`; eintreffende Nachrichten tragen `einmalig` korrekt.

- [ ] **Step 1: Den Text in sieben Sprachen anlegen**

In jede `lib/l10n/app_XX.arb` den Schluessel `onceOnlyMessage` eintragen. In `app_en.arb` zusaetzlich `"@onceOnlyMessage": {}`.

```text
de  Einmalige Nachricht
en  Once only message
es  Mensaje de una sola vez
fr  Message unique
it  Messaggio usa e getta
nl  Eenmalig bericht
pt  Mensagem de uma vez
```

Run: `flutter gen-l10n` danach `flutter test test/core/localization_completeness_test.dart`

Expected: PASS

- [ ] **Step 2: Den Zustand im Chat-Bildschirm umstellen**

In `lib/features/messenger/presentation/chat_screen.dart` die Felder `_perMessageTimer`, `_burnAfterRead` und `_hasPerMessageOverride` durch ein einziges ersetzen:

```dart
  /// Ob die naechste Nachricht nur einmal geoeffnet werden darf.
  ///
  /// Loeste am 02.09.2026 den Einzeltimer und Burn after read ab. Die Frist
  /// des ganzen Chats bleibt davon unberuehrt und gilt weiterhin fuer jede
  /// Nachricht, die nicht einmalig ist.
  bool _einmalig = false;
```

`_effectiveTimer` und `_fristVomChat` entfallen. Beim Senden wird die Chatfrist immer uebernommen, ausser die Nachricht ist einmalig:

```dart
      selfDestruct: _einmalig ? null : chat?.defaultSelfDestruct,
      selfDestructFromChat: !_einmalig,
      einmalig: _einmalig,
```

- [ ] **Step 3: Das Popup auf einen Eintrag zusammenstreichen**

Die `itemBuilder`-Liste ab Zeile 943 vollstaendig ersetzen. Alle Fristeintraege und der Burn-Eintrag entfallen; der Eintrag fuer die Chat-Vorgabe bleibt, weil er die Frist des Chats anzeigt.

```dart
                itemBuilder: (context) {
                  final chat = context
                      .read<MessengerProvider>()
                      .chatById(widget.chat.id);
                  final hasDefault = chat?.defaultSelfDestruct != null;
                  return [
                    if (hasDefault)
                      PopupMenuItem(
                        value: 'default',
                        child: Text(l10n.chatDefaultWithTimer(
                            _durationLabel(chat!.defaultSelfDestruct, l10n))),
                      ),
                    PopupMenuItem(
                      value: 'once',
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_off_rounded,
                              color: AppColors.destructive, size: 18),
                          const SizedBox(width: 8),
                          Text(l10n.onceOnlyMessage),
                        ],
                      ),
                    ),
                  ];
                },
```

Und `onSelected` entsprechend:

```dart
                onSelected: (value) {
                  setState(() => _einmalig = value == 'once');
                },
```

Das Symbol des Knopfes haengt jetzt an `_einmalig`:

```dart
                icon: Icon(
                  _einmalig
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_off_outlined,
                  color: _einmalig ? AppColors.destructive : dimColor,
                  size: 22,
                ),
```

- [ ] **Step 4: Die Markierung ueber der Eingabezeile**

Der Block ab Zeile 563 zeigt bisher die Frist oder Burn after read. Er zeigt jetzt nur noch die einmalige Nachricht:

```dart
    if (_einmalig) {
      final label = l10n.onceOnlyMessage;
```

Das Zuruecksetzen nach dem Senden bleibt, aus `_burnAfterRead = false;` wird `_einmalig = false;`.

- [ ] **Step 5: Die doppelte Fristbeschriftung aufloesen**

`_durationLabel` in `chat_screen.dart` (Zeile 661) ist eine zweite Fassung derselben Regel, die seit dem 02.09. als `FristLabel` in `lib/features/messenger/logic/frist_stufe.dart` steht. Ersetzen:

```dart
  String _durationLabel(Duration? d, AppLocalizations l10n) =>
      switch (FristLabel.stufe(d)) {
        FristStufe.aus => l10n.off,
        FristStufe.sekunden30 => l10n.seconds30,
        FristStufe.minuten5 => l10n.minutes5,
        FristStufe.minuten30 => l10n.minutes30,
        FristStufe.stunde1 => l10n.hour1,
        FristStufe.tag1 => l10n.day1,
        FristStufe.woche1 => l10n.week1,
      };
```

Import ergaenzen: `import '../logic/frist_stufe.dart';`

- [ ] **Step 6: Provider, Senden**

In `messenger_provider.dart` bekommt `sendMessage` und die innere Sendefunktion den Parameter `bool einmalig = false` anstelle von `bool burnAfterRead = false`. Die Nachricht traegt `einmalig: einmalig`. Im Payload ersetzt

```dart
      if (einmalig) innerPayload[EinmaligPolicy.feldName] = true;
```

die bisherige Zeile `if (burnAfterRead) innerPayload['_bar'] = true;`.

Import ergaenzen: `import 'einmalig_policy.dart';`

- [ ] **Step 7: Provider, Empfang**

An beiden Empfangsstellen (Zeile 3146 und 3398) bleibt das Lesen von `_bar` unveraendert stehen, damit Bestand und aeltere Absender weiter funktionieren. Ergaenzt wird daneben:

```dart
        final einmalig = EinmaligPolicy.ausPayload(innerPayload);
```

und im `Message(...)` das Feld `einmalig: einmalig,`.

- [ ] **Step 8: Alles laufen lassen und committen**

Run: `flutter test` danach `flutter analyze`

Expected: alle Tests gruen, vier vorbestehende Punkte

```bash
git checkout -- analysis_options.yaml
git add lib/ 
git commit -m "feat(einmalig): senden, Leitung, und das Sendemenue auf einen Eintrag"
```

---

### Task 3: Die verborgene Blase

Beim Empfaenger steht kein Inhalt, sondern eine Schaltflaeche.

**Files:**
- Modify: `lib/features/messenger/presentation/widgets/message_bubble.dart` (CRLF beachten)
- Create: `test/core/einmalige_nachricht_ui_test.dart`
- Modify: alle sieben `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: `EinmaligPolicy.verbergen`, `Message.einmalig`.
- Produces: die Blase ruft `onOeffnen` auf, ein `VoidCallback`, den `MessageBubble` neu als optionalen Parameter bekommt. Task 4 haengt den Dialog daran.

- [ ] **Step 1: Die Texte anlegen**

Schluessel `openOnceMessage` in alle sieben arb, in `app_en.arb` zusaetzlich `"@openOnceMessage": {}`.

```text
de  Oeffnen
en  Open
es  Abrir
fr  Ouvrir
it  Apri
nl  Openen
pt  Abrir
```

Dazu `onceOnlyHiddenHint`:

```text
de  Nur einmal zu oeffnen
en  Can be opened once
es  Se puede abrir una vez
fr  Ouvrable une seule fois
it  Apribile una sola volta
nl  Eenmalig te openen
pt  Pode ser aberta uma vez
```

Run: `flutter gen-l10n`

- [ ] **Step 2: Den fehlschlagenden Widget-Test schreiben**

Datei `test/core/einmalige_nachricht_ui_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/presentation/widgets/message_bubble.dart';
import 'package:kryptaapp/l10n/app_localizations.dart';

/// Was der Empfaenger von einer einmaligen Nachricht sieht, bevor er
/// bestaetigt hat: nichts vom Inhalt, nur die Schaltflaeche.
void main() {
  Message nachricht({required String von}) => Message(
        id: 'm1',
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: 'x',
        decryptedContent: 'GEHEIMER TEXT',
        timestamp: DateTime(2026, 9, 2, 14, 32),
        einmalig: true,
      );

  Future<void> zeige(WidgetTester t, Message m, {required bool isMine}) =>
      t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: MessageBubble(message: m, isMine: isMine, onOeffnen: () {}),
        ),
      ));

  testWidgets('beim Empfaenger steht kein Inhalt, sondern Oeffnen', (t) async {
    await zeige(t, nachricht(von: 'marco'), isMine: false);
    expect(find.text('GEHEIMER TEXT'), findsNothing,
        reason: 'der Inhalt darf vor dem Bestaetigen nirgends stehen');
    expect(find.text('Oeffnen'), findsOneWidget);
  });

  testWidgets('beim Absender steht sein eigener Text', (t) async {
    await zeige(t, nachricht(von: 'ich'), isMine: true);
    expect(find.text('GEHEIMER TEXT'), findsOneWidget);
    expect(find.text('Oeffnen'), findsNothing);
  });
}
```

- [ ] **Step 3: Test laufen lassen, er muss fehlschlagen**

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart`

Expected: FAIL, `No named parameter with the name 'onOeffnen'`

- [ ] **Step 4: Den Parameter und den verborgenen Zweig einbauen**

In `MessageBubble` das Feld ergaenzen:

```dart
  /// Wird gerufen, wenn der Empfaenger eine einmalige Nachricht oeffnen will.
  /// Der Dialog haengt beim Aufrufer, nicht an der Blase.
  final VoidCallback? onOeffnen;
```

und im Konstruktor `this.onOeffnen,`.

Im `build`, vor dem gewoehnlichen Inhalt, der neue Zweig:

```dart
    final verbergen = EinmaligPolicy.verbergen(
      einmalig: message.einmalig,
      senderId: message.senderId,
      eigeneId: isMine ? message.senderId : message.recipientId,
    );
```

Ist `verbergen` wahr, tritt an die Stelle des Textes:

```dart
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_rounded,
                  size: 16, color: AppColors.destructive),
              const SizedBox(width: 6),
              Flexible(child: Text(l10n.onceOnlyHiddenHint)),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onOeffnen,
            child: Text(l10n.openOnceMessage),
          ),
        ],
      )
```

- [ ] **Step 5: Test laufen lassen, er muss durchgehen**

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart`

Expected: PASS

- [ ] **Step 6: Committen**

```bash
git checkout -- analysis_options.yaml
git add lib/ test/core/einmalige_nachricht_ui_test.dart
git commit -m "feat(einmalig): die verborgene Blase mit Oeffnen"
```

---

### Task 4: Die eigene Ansicht

Zeigt einen Text und sonst nichts. Sie kennt weder Provider noch Nachricht, damit nach dem Verbrauch nichts mehr nachgeladen werden kann.

**Files:**
- Create: `lib/features/messenger/presentation/einmalige_nachricht_screen.dart`
- Modify: `test/core/einmalige_nachricht_ui_test.dart`

**Interfaces:**
- Consumes: nichts. Bekommt den Text als `String`.
- Produces: `EinmaligeNachrichtScreen({required String text})`.

- [ ] **Step 1: Den Test schreiben**

An `test/core/einmalige_nachricht_ui_test.dart` anhaengen:

```dart
  testWidgets('die Ansicht zeigt den Text und einen Schliessen-Knopf',
      (t) async {
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: const EinmaligeNachrichtScreen(text: 'GEHEIMER TEXT'),
    ));
    expect(find.text('GEHEIMER TEXT'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('ein langer Text scrollt, statt ueberzulaufen', (t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(375, 667) * 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: EinmaligeNachrichtScreen(text: List.filled(80, 'Zeile').join(' ')),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
```

Import ergaenzen: `import 'package:kryptaapp/features/messenger/presentation/einmalige_nachricht_screen.dart';`

- [ ] **Step 2: Test laufen lassen, er muss fehlschlagen**

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart`

Expected: FAIL, Datei nicht gefunden

- [ ] **Step 3: Die Ansicht schreiben**

Datei `lib/features/messenger/presentation/einmalige_nachricht_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Die Ansicht einer einmaligen Nachricht.
///
/// Sie bekommt den Text als Zeichenkette und kennt weder Provider noch
/// Nachricht. Das ist Absicht: zu dem Zeitpunkt, an dem sie erscheint, ist
/// die Nachricht bereits von der Platte fort. Es gibt nichts mehr
/// nachzuladen, und niemand kann sie versehentlich ein zweites Mal holen.
class EinmaligeNachrichtScreen extends StatelessWidget {
  final String text;

  const EinmaligeNachrichtScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.onceOnlyConfirmTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding, vertical: 24),
          child: SingleChildScrollView(
            child: SelectionContainer.disabled(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Test laufen lassen und committen**

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart` danach `flutter test` und `flutter analyze`

```bash
git checkout -- analysis_options.yaml
git add lib/features/messenger/presentation/einmalige_nachricht_screen.dart test/core/einmalige_nachricht_ui_test.dart
git commit -m "feat(einmalig): die eigene Ansicht"
```

---

### Task 5: Bestaetigen und verbrauchen

Der schwerste Teil. Reihenfolge: erst loeschen und melden, dann anzeigen.

**Files:**
- Modify: `lib/features/messenger/logic/messenger_provider.dart`
- Modify: `lib/features/messenger/presentation/chat_screen.dart`
- Modify: alle sieben `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: `Message.einmalig` und `onOeffnen` aus Task 3, `EinmaligeNachrichtScreen` aus Task 4. **Diese Aufgabe setzt Task 4 voraus**, sonst kompiliert der Schritt mit dem Navigator nicht.
- Produces: `MessengerProvider.verbraucheEinmalige(String chatId, String messageId) -> Future<String?>` — gibt den Klartext zurueck und loescht die Nachricht; `null`, wenn sie nicht mehr da ist.

- [ ] **Step 1: Die Texte anlegen**

Vier Schluessel in alle sieben arb, in `app_en.arb` je ein leeres `@`-Gegenstueck.

`onceOnlyConfirmTitle`

```text
de  Nur einmal zu oeffnen
en  Can be opened once
es  Se puede abrir una vez
fr  Ouvrable une seule fois
it  Apribile una sola volta
nl  Eenmalig te openen
pt  Pode ser aberta uma vez
```

`onceOnlyConfirmBody`

```text
de  Diese Nachricht kann nur einmal geoeffnet werden. Sobald du sie schliesst, wird sie dauerhaft entfernt. Das gilt auch, wenn etwas dazwischenkommt.
en  This message can be opened once. As soon as you close it, it is removed for good. That also applies if something interrupts you.
es  Este mensaje solo se puede abrir una vez. En cuanto lo cierres, se elimina para siempre. Tambien si algo te interrumpe.
fr  Ce message ne peut etre ouvert qu une fois. Des que tu le fermes, il est supprime definitivement. Cela vaut aussi si quelque chose t interrompt.
it  Questo messaggio si puo aprire una sola volta. Appena lo chiudi, viene rimosso per sempre. Vale anche se qualcosa ti interrompe.
nl  Dit bericht kan een keer worden geopend. Zodra je het sluit, is het definitief weg. Dat geldt ook als er iets tussenkomt.
pt  Esta mensagem so pode ser aberta uma vez. Assim que a fechares, e removida para sempre. Isso tambem vale se algo te interromper.
```

`onceOnlyScreenshotHint`

```text
de  Ein Screenshot laesst sich nicht verhindern. Du erfaehrst davon.
en  A screenshot cannot be prevented. You will be told about it.
es  No se puede impedir una captura. Se te avisara.
fr  Une capture ne peut pas etre empechee. Tu en seras informe.
it  Uno screenshot non si puo impedire. Ne verrai informato.
nl  Een schermafbeelding is niet te voorkomen. Je hoort ervan.
pt  Uma captura nao pode ser impedida. Vais saber dela.
```

`onceOnlyConfirmAction`

```text
de  Bestaetigen und oeffnen
en  Confirm and open
es  Confirmar y abrir
fr  Confirmer et ouvrir
it  Conferma e apri
nl  Bevestigen en openen
pt  Confirmar e abrir
```

Run: `flutter gen-l10n` danach `flutter test test/core/localization_completeness_test.dart`

- [ ] **Step 2: Den Verbrauch im Provider schreiben**

In `messenger_provider.dart` neben `burnReadMessages`:

```dart
  /// Eine einmalige Nachricht verbrauchen und ihren Klartext herausgeben.
  ///
  /// Die Reihenfolge ist die eigentliche Aussage: erst von der Platte
  /// entfernen und der Gegenseite Bescheid sagen, dann den Text
  /// zurueckgeben. Wer danach abstuerzt, hat sie trotzdem verbraucht, und
  /// genau das ist zugesagt. Wuerde erst beim Schliessen geloescht, koennte
  /// man die App im richtigen Moment abschiessen.
  ///
  /// Gibt `null` zurueck, wenn die Nachricht nicht mehr da ist.
  Future<String?> verbraucheEinmalige(String chatId, String messageId) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return null;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return null;

    final m = messages[idx];
    final text = m.decryptedContent;
    if (text == null) return null;

    messages.removeAt(idx);
    await _localStore.saveMessages(chatId, messages);
    _meldeAblauf(chatId, messageId);
    _standNachrechnen(chatId);
    notifyListeners();
    return text;
  }
```

- [ ] **Step 3: Den Dialog im Chat-Bildschirm**

In `chat_screen.dart` eine Methode ergaenzen und sie als `onOeffnen` an die Blase haengen:

```dart
  Future<void> _oeffneEinmalige(Message m) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Sonst legt sich der Inhalt bei grosser Systemschrift ueber die
        // Knopfzeile, siehe die Dialogarbeit vom 02.09.
        scrollable: true,
        title: Text(l10n.onceOnlyConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.onceOnlyConfirmBody),
            const SizedBox(height: 12),
            Text(
              l10n.onceOnlyScreenshotHint,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.onceOnlyConfirmAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final text = await context
        .read<MessengerProvider>()
        .verbraucheEinmalige(widget.chat.id, m.id);
    if (text == null || !mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EinmaligeNachrichtScreen(text: text),
    ));
  }
```

- [ ] **Step 4: Den Dialog in allen sieben Sprachen pruefen**

Die Spec verlangt, dass der Bestaetigungsdialog auf dem kleinsten Geraet bei
maximaler Systemschrift in allen sieben Sprachen haelt. An
`test/core/einmalige_nachricht_ui_test.dart` anhaengen:

```dart
  for (final sprache in const ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt']) {
    testWidgets('der Bestaetigungsdialog passt, Sprache $sprache', (t) async {
      t.view.devicePixelRatio = 2.0;
      t.view.physicalSize = const Size(375, 667) * 2.0;
      addTearDown(t.view.reset);

      late AppLocalizations l10n;
      await t.pumpWidget(MaterialApp(
        locale: Locale(sprache),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: Builder(builder: (ctx) {
          l10n = AppLocalizations.of(ctx)!;
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    scrollable: true,
                    title: Text(l10n.onceOnlyConfirmTitle),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.onceOnlyConfirmBody),
                        const SizedBox(height: 12),
                        Text(l10n.onceOnlyScreenshotHint),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () {}, child: Text(l10n.cancel)),
                      FilledButton(
                          onPressed: () {},
                          child: Text(l10n.onceOnlyConfirmAction)),
                    ],
                  ),
                ),
                child: const Text('auf'),
              ),
            ),
          );
        }),
      ));
      await t.tap(find.text('auf'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
```

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart`

Expected: PASS, sieben zusaetzliche Faelle

- [ ] **Step 5: Die neuen Texte gegen die Stilregel pruefen**

`tutorial_texte_test.dart` deckt nur Schluessel ab, die mit `tut` beginnen.
Die Texte dieser Funktion tun das nicht. Deshalb eine eigene Pruefung, in
derselben Datei `test/core/einmalige_nachricht_ui_test.dart`, ausserhalb der
Widget-Tests:

```dart
  test('die Texte der einmaligen Nachricht sind kurz und ohne Gedankenstriche',
      () async {
    for (final sprache in const ['de', 'en', 'es', 'fr', 'it', 'nl', 'pt']) {
      final l = await AppLocalizations.delegate.load(Locale(sprache));
      final texte = <String, String>{
        'onceOnlyMessage': l.onceOnlyMessage,
        'openOnceMessage': l.openOnceMessage,
        'onceOnlyHiddenHint': l.onceOnlyHiddenHint,
        'onceOnlyConfirmTitle': l.onceOnlyConfirmTitle,
        'onceOnlyConfirmBody': l.onceOnlyConfirmBody,
        'onceOnlyScreenshotHint': l.onceOnlyScreenshotHint,
        'onceOnlyConfirmAction': l.onceOnlyConfirmAction,
      };
      texte.forEach((k, v) {
        expect(v.trim(), isNotEmpty, reason: '$k ist leer in $sprache');
        expect(v.contains('—'), isFalse, reason: '$k in $sprache');
        expect(v.contains('–'), isFalse, reason: '$k in $sprache');
        expect(v.length, lessThanOrEqualTo(160), reason: '$k in $sprache');
      });
    }
  });
```

Run: `flutter test test/core/einmalige_nachricht_ui_test.dart`

Expected: PASS

- [ ] **Step 6: Alles laufen lassen und committen**

Run: `flutter test` danach `flutter analyze`

```bash
git checkout -- analysis_options.yaml
git add lib/ test/core/einmalige_nachricht_ui_test.dart
git commit -m "feat(einmalig): bestaetigen, verbrauchen, melden"
```

---

### Task 6: Aufraeumen

Was der Einzeltimer hinterlaesst.

**Files:**
- Modify: `lib/features/messenger/presentation/widgets/message_bubble.dart` (Restzeit ab Zeile 197)
- Modify: `lib/features/auth/presentation/tutorial_screen.dart` (Seite Nachrichten)
- Modify: alle sieben `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: alles aus Task 1 bis 5.
- Produces: nichts Neues.

- [ ] **Step 1: Die Restzeit unter der Blase entfernen**

Der Block in `message_bubble.dart` ab Zeile 197 mit `Icons.timer_outlined` und dem eigenen Sekundentakt gehoerte ausschliesslich zum Einzeltimer; beim Chat-Timer stand dort nie etwas. Der Block und der zugehoerige `Timer` entfallen vollstaendig, samt `dispose`.

- [ ] **Step 2: Die Tutorialzeile umwidmen**

Auf der Seite Nachrichten (`_PageMessages`) entfaellt die Zeile mit `tutTRemaining` und `tutDRemaining`. Die Zeile mit `burnAfterRead` wird zur Zeile fuer die einmalige Nachricht:

```dart
        _FeatureRow(
          isDark: isDark,
          icon: Icons.visibility_off_rounded,
          color: AppColors.destructive,
          title: l10n.onceOnlyMessage,
          description: l10n.tutDOnceOnly,
        ),
```

Neuer Schluessel `tutDOnceOnly` in sieben Sprachen:

```text
de  Nur einmal zu oeffnen. Danach ist sie bei euch beiden fort.
en  Can be opened once. After that it is gone on both sides.
es  Se abre una sola vez. Despues desaparece para los dos.
fr  Ouvrable une seule fois. Ensuite elle est partie des deux cotes.
it  Si apre una sola volta. Poi sparisce da entrambe le parti.
nl  Eenmalig te openen. Daarna is het bij jullie allebei weg.
pt  Abre se uma vez. Depois desaparece dos dois lados.
```

Die Schluessel `tutTRemaining` und `tutDRemaining` aus allen sieben arb entfernen, ebenso `burnAfterRead` als Tutorialzeile.

- [ ] **Step 3: Alles laufen lassen**

Run: `flutter gen-l10n` danach `flutter test` und `flutter analyze`

Expected: alle Tests gruen. `tutorial_texte_test` prueft die neuen Texte auf Gedankenstriche und Laenge, `tutorial_seiten_test` prueft die Seiten auf Ueberlauf.

- [ ] **Step 4: Committen**

```bash
git checkout -- analysis_options.yaml
git add lib/
git commit -m "feat(einmalig): Restzeit und Tutorialzeile aufgeraeumt"
```

---

## Testprotokoll

Nach der letzten Aufgabe, nicht zwischendurch. Betroffen sind **1.27**, **3.9**, **5.14** und **3.11**: alle vier beschreiben Verhalten, das es danach nicht mehr gibt. Sie werden **umgeschrieben statt geloescht**, weil Daniels Haekchen an den `data-id` haengen. Dazu ein neuer Punkt fuer die einmalige Nachricht mit diesen Proben:

- Absender sieht seinen Text, bis geoeffnet wurde.
- Empfaenger sieht keinen Inhalt, nur die Schaltflaeche.
- Abbrechen laesst alles stehen.
- Nach dem Bestaetigen ist sie bei **beiden** fort.
- App im richtigen Moment abschiessen: sie bleibt trotzdem fort.
- Eine gewoehnliche Nachricht daneben bleibt stehen.
