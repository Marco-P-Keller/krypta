// Neuinstallation soll aussehen wie nach der Notfall-Loeschung.
//
// Auf iOS gehoert der Schluesselbund dem System: Identitaetsschluessel,
// Codes und Tresor-Passwort ueberstehen das Loeschen der App, der Verlauf im
// App-Ordner nicht. Ohne FreshInstallGuard fragt eine frisch geladene App
// nach dem Code eines Kontos, von dem keine einzige Nachricht mehr da ist.
//
// Ein Software-Update darf davon nichts merken - dort bleibt alles stehen.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/constants/storage_keys.dart';
import 'package:kryptaapp/services/emergency/fresh_install_guard.dart';
import 'package:kryptaapp/services/storage/secure_storage_service.dart';

/// Protokolliert, was in welcher Reihenfolge passiert ist.
class _Recorder {
  _Recorder({
    this.markerPresent = false,
    this.appData = false,
    this.residue = false,
    this.keysAfterWipe = false,
    this.markerWriteFails = false,
    this.markerReadThrows,
    this.appDataThrows,
    this.residueThrows,
    this.wipeGate,
  });

  final List<String> steps = [];

  final bool markerPresent;
  final bool appData;
  final bool residue;
  final bool keysAfterWipe;
  final bool markerWriteFails;
  final Object? markerReadThrows;
  final Object? appDataThrows;
  final Object? residueThrows;
  final Completer<void>? wipeGate;

  FreshInstallGuard get guard => FreshInstallGuard(
        installMarkerSet: () async {
          steps.add('read-marker');
          final boom = markerReadThrows;
          if (boom != null) throw boom;
          return markerPresent;
        },
        writeInstallMarker: () async {
          if (markerWriteFails) throw StateError('Ordner nicht beschreibbar');
          steps.add('write-marker');
        },
        appDataPresent: () async {
          steps.add('appdata');
          final boom = appDataThrows;
          if (boom != null) throw boom;
          return appData;
        },
        hasResidue: () async {
          steps.add('residue');
          final boom = residueThrows;
          if (boom != null) throw boom;
          return residue;
        },
        wipe: () async {
          steps.add('wipe');
          final gate = wipeGate;
          if (gate != null) return gate.future;
        },
        identityKeysPresent: () async => keysAfterWipe,
        wipeTimeout: const Duration(milliseconds: 50),
      );
}

void main() {
  group('FreshInstallGuard', () {
    test('Merker liegt: dieselbe Installation, nichts wird angefasst', () async {
      final r = _Recorder(markerPresent: true, residue: true);

      expect(await r.guard.run(), FreshInstallOutcome.established);
      expect(r.steps, ['read-marker']);
    });

    test('Software-Update aendert nichts - der Merker ueberlebt es', () async {
      // Ein Update laesst den App-Ordner stehen. Aus Sicht des Guards ist das
      // exakt derselbe Fall wie ein gewoehnlicher Neustart.
      final r = _Recorder(
        markerPresent: true,
        residue: true,
        keysAfterWipe: true,
      );

      expect(await r.guard.run(), FreshInstallOutcome.established);
      expect(r.steps.contains('wipe'), isFalse);
    });

    test('erster Start ohne Reste: nur der Merker wird gesetzt', () async {
      final r = _Recorder(residue: false);

      expect(await r.guard.run(), FreshInstallOutcome.firstInstall);
      expect(r.steps, ['read-marker', 'appdata', 'residue', 'write-marker']);
    });

    test('geloescht und neu geladen: Reste werden geraeumt', () async {
      final r = _Recorder(residue: true, keysAfterWipe: false);

      expect(await r.guard.run(), FreshInstallOutcome.reinstallWiped);
      expect(r.steps.contains('wipe'), isTrue);
    });

    test('der Merker steht VOR dem Raeumen', () async {
      // Andersherum liefe der Guard nach einem gescheiterten Schreibvorgang
      // bei jedem Start erneut - die App kaeme nie ueber die Einrichtung
      // hinaus, weil jeder Start die frischen Codes wieder mitnaehme.
      final r = _Recorder(residue: true);

      await r.guard.run();
      expect(r.steps.indexOf('write-marker') < r.steps.indexOf('wipe'), isTrue);
    });

    test('Merker nicht schreibbar: es wird nichts geraeumt', () async {
      final r = _Recorder(residue: true, markerWriteFails: true);

      expect(await r.guard.run(), FreshInstallOutcome.skipped);
      expect(r.steps.contains('wipe'), isFalse);
    });

    test('Raeumen unvollstaendig wird gemeldet, nicht verschwiegen', () async {
      // Der Wipe-Merker der Notfall-Loeschung bleibt dann gesetzt; die
      // Wiederherstellung beim naechsten Start holt es nach.
      final r = _Recorder(residue: true, keysAfterWipe: true);

      expect(await r.guard.run(), FreshInstallOutcome.reinstallIncomplete);
    });

    test('haengendes Raeumen haelt den Start nicht auf', () async {
      final gate = Completer<void>();
      final r = _Recorder(residue: true, wipeGate: gate);

      expect(
        await r.guard.run().timeout(const Duration(seconds: 5)),
        FreshInstallOutcome.reinstallWiped,
      );
      gate.complete();
    });

    test('Merkerabfrage wirft: im Zweifel nichts anfassen', () async {
      final r = _Recorder(residue: true, markerReadThrows: StateError('io'));

      expect(await r.guard.run(), FreshInstallOutcome.established);
      expect(r.steps.contains('wipe'), isFalse);
    });

    test('Bestandsnutzer beim Update: Datenordner da, es wird nichts geraeumt',
        () async {
      // Der schlimmste denkbare Fehler dieser Aenderung: das Update auf die
      // erste Fassung mit Merker raeumt jedem Tester das Konto weg. Vor dem
      // Update gab es den Merker nicht, also fehlt er - aber der Datenordner
      // ist da, und den kann eine frisch geladene App nicht haben.
      final r = _Recorder(appData: true, residue: true, keysAfterWipe: true);

      expect(await r.guard.run(), FreshInstallOutcome.migrated);
      expect(r.steps, ['read-marker', 'appdata', 'write-marker']);
    });

    test('Ordnerpruefung wirft: als Bestand behandeln', () async {
      final r = _Recorder(residue: true, appDataThrows: StateError('io'));

      expect(await r.guard.run(), FreshInstallOutcome.migrated);
      expect(r.steps.contains('wipe'), isFalse);
    });

    test('Restepruefung wirft: lieber liegen lassen als loeschen', () async {
      final r = _Recorder(residueThrows: StateError('keychain'));

      expect(await r.guard.run(), FreshInstallOutcome.firstInstall);
      expect(r.steps.contains('wipe'), isFalse);
    });
  });

  group('SecureStorageService.hasResidualData', () {
    test('leerer Schluesselbund: keine Reste', () async {
      final service = SecureStorageService(storage: _FakeStorage({}));
      expect(await service.hasResidualData(), isFalse);
    });

    test('fremde Eintraege zaehlen nicht', () async {
      final service = SecureStorageService(
        storage: _FakeStorage({'irgendwas_anderes': 'x'}),
      );
      expect(await service.hasResidualData(), isFalse);
    });

    test('ein einziger Krypta-Eintrag genuegt', () async {
      final service = SecureStorageService(
        storage: _FakeStorage({StorageKeys.setupComplete: 'true'}),
      );
      expect(await service.hasResidualData(), isTrue);
    });

    test('readAll scheitert: einzeln nachsehen', () async {
      final service = SecureStorageService(
        storage: _FakeStorage(
          {StorageKeys.identityPrivateKey: 'k'},
          readAllThrows: true,
        ),
      );
      expect(await service.hasResidualData(), isTrue);
    });

    test('readAll scheitert und nichts liegt da: keine Reste', () async {
      final service = SecureStorageService(
        storage: _FakeStorage({}, readAllThrows: true),
      );
      expect(await service.hasResidualData(), isFalse);
    });
  });
}

class _FakeStorage implements FlutterSecureStorage {
  _FakeStorage(this._data, {this.readAllThrows = false});

  final Map<String, String> _data;
  final bool readAllThrows;

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readAllThrows) throw StateError('Eintrag unlesbar');
    return Map<String, String>.from(_data);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('hier nicht gebraucht');
  }
}
