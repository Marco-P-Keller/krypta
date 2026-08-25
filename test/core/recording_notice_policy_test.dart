import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/recording_notice_policy.dart';

/// Wer erfaehrt wann von einer Bildschirmaufnahme?
///
/// Eine Aufnahme laeuft weiter, waehrend man durch die App navigiert. Der
/// Chat-Bildschirm wird dabei jedes Mal neu gebaut und fragt erneut nach.
/// Ohne Buchhaltung saehe die Gegenseite fuer EINE Aufnahme bei jedem Oeffnen
/// des Chats erneut „Bildschirmaufnahme gestartet".
///
/// Zu wenig melden waere aber schlimmer als zu viel: eine Aufnahme, von der
/// niemand erfaehrt, ist genau der Fall, den der Hinweis verhindern soll.
void main() {
  late RecordingNoticePolicy policy;

  setUp(() => policy = RecordingNoticePolicy());

  test('die erste Meldung einer Aufnahme geht durch', () {
    expect(policy.shouldAnnounce('chat-1', 1), isTrue);
  });

  test('dieselbe Aufnahme wird demselben Chat nur einmal gemeldet', () {
    policy.shouldAnnounce('chat-1', 1);

    expect(policy.shouldAnnounce('chat-1', 1), isFalse);
    expect(policy.shouldAnnounce('chat-1', 1), isFalse);
  });

  test('jeder Chat erfaehrt von derselben Aufnahme', () {
    // Beide Verlaeufe waren auf dem Bildschirm, beide wurden aufgenommen.
    expect(policy.shouldAnnounce('chat-1', 7), isTrue);
    expect(policy.shouldAnnounce('chat-2', 7), isTrue);
  });

  test('eine neue Aufnahme wird wieder gemeldet', () {
    policy.shouldAnnounce('chat-1', 1);

    expect(policy.shouldAnnounce('chat-1', 2), isTrue);
  });

  test('ohne laufende Aufnahme gibt es nichts zu melden', () {
    // 0 heisst: es laeuft gerade keine.
    expect(policy.shouldAnnounce('chat-1', 0), isFalse);
  });

  test('abmelden vergisst alles', () {
    policy.shouldAnnounce('chat-1', 1);

    policy.clear();

    // Nach einem Kontowechsel darf die Buchhaltung des vorigen Kontos nicht
    // dazu fuehren, dass eine laufende Aufnahme stumm bleibt.
    expect(policy.shouldAnnounce('chat-1', 1), isTrue);
  });

  test('die Buchhaltung waechst nicht unbegrenzt', () {
    for (var i = 1; i <= 500; i++) {
      policy.shouldAnnounce('chat-$i', i);
    }

    expect(policy.trackedChats, lessThanOrEqualTo(RecordingNoticePolicy.maxChats));
    // Der zuletzt gesehene Chat muss auf jeden Fall noch bekannt sein.
    expect(policy.shouldAnnounce('chat-500', 500), isFalse);
  });
}
