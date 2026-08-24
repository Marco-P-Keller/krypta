import 'package:firebase_core/firebase_core.dart';

/// Ob die eigenen Schlüssel auf dem Server liegen.
enum KeyPublishState {
  /// Identity-Key und PreKey-Bundle sind veröffentlicht.
  ok,

  /// Der Server hat den Schreibvorgang abgelehnt. Praktisch immer heißt das:
  /// die Firestore-Rules im Projekt sind älter als der Client. Seit dem
  /// Audit 2026-05 schreibt der Client `updatedAt` mit, und die Regeln
  /// verlangen es — eine ältere Fassung ohne dieses Feld in der Allowlist
  /// lehnt genau diese Schreibvorgänge ab.
  denied,

  /// Netzwerk oder sonstiger Fehler. Geht meist von selbst wieder weg.
  failed,
}

/// Merkt sich, ob das Veröffentlichen der eigenen Schlüssel geklappt hat.
///
/// Ohne Identity-Key im `publicKeys`-Register findet einen niemand; ohne
/// PreKey-Bundle in `prekeys` kommt kein X3DH-Handshake zustande. In beiden
/// Fällen kann niemand eine Session aufbauen und **es kommt keine Nachricht
/// an** — die App verhält sich aber ansonsten völlig normal.
///
/// Genau das lief vorher in `catch (e) { if (kDebugMode) debugPrint(...); }`.
/// In einem Release-Build ist `kDebugMode` false, der Fehlschlag war damit
/// unsichtbar. So konnte der Zustellbug ab Juni monatelang unbemerkt bleiben.
class KeyPublishStatus {
  KeyPublishState _identity = KeyPublishState.ok;
  KeyPublishState _preKeys = KeyPublishState.ok;

  /// Der schlechtere der beiden Teilzustände.
  ///
  /// Eine Ablehnung schlägt einen gewöhnlichen Fehlschlag: beide sind kaputt,
  /// aber nur die Ablehnung sagt einem, wo zu suchen ist.
  KeyPublishState get state {
    if (_identity == KeyPublishState.denied ||
        _preKeys == KeyPublishState.denied) {
      return KeyPublishState.denied;
    }
    if (_identity == KeyPublishState.failed ||
        _preKeys == KeyPublishState.failed) {
      return KeyPublishState.failed;
    }
    return KeyPublishState.ok;
  }

  bool get isHealthy => state == KeyPublishState.ok;

  void recordIdentitySuccess() => _identity = KeyPublishState.ok;
  void recordIdentityFailure(Object error) => _identity = classify(error);

  void recordPreKeySuccess() => _preKeys = KeyPublishState.ok;
  void recordPreKeyFailure(Object error) => _preKeys = classify(error);

  /// Einen Fehler einordnen.
  ///
  /// Die Unterscheidung ist der ganze Punkt: `permission-denied` ist ein
  /// Konfigurationsproblem am Projekt, das von selbst nie weggeht. Alles
  /// andere ist meist vorübergehend.
  static KeyPublishState classify(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return KeyPublishState.denied;
    }
    return KeyPublishState.failed;
  }
}
