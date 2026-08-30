import 'package:flutter/foundation.dart';

/// Was beim Start festgestellt wurde.
enum FreshInstallOutcome {
  /// Der Merker liegt - dieselbe Installation wie beim letzten Start. Das ist
  /// auch der Fall nach einem Software-Update: dort bleibt alles erhalten.
  established,

  /// Erster Start, und es lag nichts mehr herum. Nichts zu tun.
  firstInstall,

  /// Der Merker fehlt, aber der Datenordner dieser Installation ist da: eine
  /// Fassung ohne Merker wurde aktualisiert. Es wird nur nachgetragen.
  migrated,

  /// Krypta wurde geloescht und neu geladen. Reste gefunden und geraeumt.
  reinstallWiped,

  /// Wie [reinstallWiped], aber das Raeumen ist nicht durchgelaufen. Der
  /// Wipe-Merker der Notfall-Loeschung bleibt gesetzt, die Wiederherstellung
  /// beim naechsten Start holt es nach.
  reinstallIncomplete,

  /// Der App-Ordner liess sich nicht beschreiben. Es wurde nichts angefasst.
  skipped,
}

/// Loescht jemand Krypta und laedt es neu, soll es sich verhalten wie nach der
/// Notfall-Loeschung: kein Konto, keine Schluessel, keine Codes, nichts.
///
/// Das ist auf iOS nicht selbstverstaendlich. Der Schluesselbund gehoert dem
/// System, nicht der App - Identitaetsschluessel, Codes, Tresor-Passwort und
/// die Firebase-Sitzung ueberstehen dort das Loeschen der App. Der Verlauf
/// liegt dagegen im App-Ordner und ist weg. Zurueck bliebe ein halber
/// Zustand: die App kennt das Konto und fragt nach dem Code, hat aber keine
/// einzige Nachricht mehr. Wer die App loescht, meint nicht das.
///
/// Unterschieden wird ueber eine Merkerdatei im App-Ordner. Der Ordner
/// verschwindet mit der App und ueberlebt ein Update - genau die Trennung,
/// die hier gebraucht wird. Auf Android faellt der Schluesselbund beim
/// Deinstallieren ohnehin mit weg (`allowBackup="false"`), dort findet der
/// Guard schlicht keine Reste.
///
/// Alle Abhaengigkeiten kommen als Funktionen herein, damit der Ablauf ohne
/// Plattformkanaele pruefbar ist.
class FreshInstallGuard {
  FreshInstallGuard({
    required this.installMarkerSet,
    required this.writeInstallMarker,
    required this.appDataPresent,
    required this.hasResidue,
    required this.wipe,
    required this.identityKeysPresent,
    this.wipeTimeout = const Duration(seconds: 12),
  });

  /// Ob diese Installation schon einmal lief.
  final Future<bool> Function() installMarkerSet;

  /// Setzt den Merker. Darf werfen, wenn der Ordner nicht beschreibbar ist.
  final Future<void> Function() writeInstallMarker;

  /// Ob der Datenordner dieser Installation schon da ist. Er verschwindet mit
  /// der App, ueberlebt aber jedes Update - und ist damit der Beleg, dass eine
  /// Installation aelter ist als der Merker selbst.
  final Future<bool> Function() appDataPresent;

  /// Ob im Schluesselbund noch etwas von frueher liegt.
  final Future<bool> Function() hasResidue;

  /// Die Notfall-Loeschung. Derselbe Weg, denselben Umfang.
  final Future<void> Function() wipe;

  /// Ob nach dem Raeumen noch Identitaetsschluessel da sind.
  final Future<bool> Function() identityKeysPresent;

  /// Frist fuer das Raeumen. Die lokale Haelfte ist in Millisekunden durch;
  /// die Server- und Kontoloeschung braucht Netz und darf den Start nicht
  /// aufhalten. Laeuft die Frist ab, arbeitet sie im Hintergrund weiter.
  final Duration wipeTimeout;

  Future<FreshInstallOutcome> run() async {
    bool marker;
    try {
      marker = await installMarkerSet();
    } catch (_) {
      // Im Zweifel: diese Installation lief schon. Nichts anfassen.
      marker = true;
    }
    if (marker) return FreshInstallOutcome.established;

    // Der Merker fehlt auch jedem, der von einer Fassung aktualisiert, die ihn
    // noch nicht kannte. Diese Installationen sind an ihrem Datenordner zu
    // erkennen: der gehoert zur App und faellt mit ihr weg, eine frisch
    // geladene App kann ihn also nicht haben. Ohne diese Unterscheidung
    // raeumte ausgerechnet das Update auf diese Fassung jedem Bestandsnutzer
    // sein Konto weg.
    bool appData;
    try {
      appData = await appDataPresent();
    } catch (_) {
      appData = true;
    }
    if (appData) return await _markOnly(FreshInstallOutcome.migrated);

    bool residue;
    try {
      residue = await hasResidue();
    } catch (_) {
      residue = false;
    }

    if (!residue) {
      // Der Normalfall auf einem Geraet, das Krypta noch nie hatte.
      return await _markOnly(FreshInstallOutcome.firstInstall);
    }

    // Merker VOR dem Raeumen setzen, aus zwei Gruenden. Erstens ist der
    // erfolgreiche Schreibvorgang der Beweis, dass der Ordner beschreibbar
    // ist - liesse er sich nie setzen, raeumte dieser Guard bei jedem Start
    // erneut, und die App kaeme nie ueber die Einrichtung hinaus. Zweitens
    // braucht ein Abbruch mittendrin ihn nicht: dafuer setzt die
    // Notfall-Loeschung ihren eigenen Merker, und die Wiederherstellung beim
    // naechsten Start raeumt nach.
    try {
      await writeInstallMarker();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Installationsmerker nicht schreibbar - kein Raeumen: $e');
      }
      return FreshInstallOutcome.skipped;
    }

    if (kDebugMode) {
      debugPrint('Neuinstallation erkannt - raeume wie bei der Notfall-Loeschung');
    }

    try {
      await wipe().timeout(wipeTimeout, onTimeout: () {});
    } catch (e) {
      if (kDebugMode) debugPrint('Raeumen gescheitert: $e');
    }

    bool stillThere;
    try {
      stillThere = await identityKeysPresent();
    } catch (_) {
      stillThere = true;
    }

    if (stillThere) {
      if (kDebugMode) {
        debugPrint('Raeumen unvollstaendig - naechster Start holt es nach');
      }
      return FreshInstallOutcome.reinstallIncomplete;
    }
    return FreshInstallOutcome.reinstallWiped;
  }

  Future<FreshInstallOutcome> _markOnly(FreshInstallOutcome outcome) async {
    try {
      await writeInstallMarker();
    } catch (e) {
      if (kDebugMode) debugPrint('Installationsmerker nicht schreibbar: $e');
      return FreshInstallOutcome.skipped;
    }
    return outcome;
  }
}
