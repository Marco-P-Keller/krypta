import '../data/models/message_model.dart';

/// Ob diese Nachricht verschwindet, weil [peerId] seinen Chat geleert hat.
///
/// „Chat leeren" nimmt die **eigenen** Nachrichten zurück — auf beiden
/// Geräten. Auf dem eigenen verschwindet alles; auf dem anderen nur das, was
/// man selbst geschrieben hat. Fremde Nachrichten anzufassen wäre kein
/// Aufräumen mehr, sondern ein Eingriff in einen fremden Verlauf: sonst
/// könnte jeder Kontakt jederzeit meine Hälfte des Gesprächs löschen, ohne
/// dass ich zustimme.
///
/// Systemhinweise bleiben ebenfalls stehen, auch die von der Gegenseite
/// ausgelösten. Sonst wäre der Screenshot-Hinweis wertlos: einen Screenshot
/// machen, danach den Chat leeren, Spur weg. Ein Hinweis ist keine Nachricht,
/// die jemandem gehört, sondern eine Feststellung über das Gespräch.
bool removedByPeerClear(Message message, String peerId) {
  if (message.senderId != peerId) return false;
  if (message.isSystemEvent) return false;
  return true;
}
