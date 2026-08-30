import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

const _storeDirName = 'krypta_store';

Future<String?> getStorageBasePath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _storeDirName);
    await Directory(path).create(recursive: true);
    return path;
  } catch (_) {
    return null;
  }
}

/// Ob der Datenordner dieser Installation schon da ist - ohne ihn dabei
/// anzulegen.
///
/// Er verschwindet mit der App und ist deshalb der zweite Beleg dafuer, dass
/// eine Installation nicht neu ist. Gebraucht wird er fuer Bestandsnutzer:
/// deren Fassung kannte den Installationsmerker noch nicht, also fehlt er
/// ihnen nach dem Update. Ohne diese Ruecksicht raeumte genau dieses Update
/// jedem von ihnen das Konto weg.
///
/// Bei einem Fehler `true` - im Zweifel wird nichts geraeumt.
Future<bool> localStoreExists() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return await Directory(p.join(dir.path, _storeDirName)).exists();
  } catch (_) {
    return true;
  }
}

Future<void> createDir(String path) async {
  await Directory(path).create(recursive: true);
}

Future<void> writeFileBytes(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<Uint8List?> readFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return Uint8List.fromList(await file.readAsBytes());
}

Future<List<String>> listEncFiles(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return [];
  final entities = await dir.list().toList();
  return entities
      .whereType<File>()
      .where((f) => f.path.endsWith('.enc'))
      .map((f) => f.path)
      .toList();
}

Future<void> deleteFileAt(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

Future<void> deleteDirRecursive(String path) async {
  final dir = Directory(path);
  if (await dir.exists()) await dir.delete(recursive: true);
}

// --- H3: Wipe-in-progress marker ---
//
// A 0-byte file in the app-support directory that survives across app
// restarts but is visible to us at startup. It is deliberately placed
// OUTSIDE the encrypted store and secure-storage backends so a wipe that
// crashes mid-way still leaves the marker behind.

Future<File> _wipeMarkerFile() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return File(p.join(dir.path, '.krypta_wipe_in_progress'));
}

Future<void> setWipeMarker() async {
  final file = await _wipeMarkerFile();
  await file.create(recursive: true);
}

Future<bool> isWipeMarkerSet() async {
  try {
    final file = await _wipeMarkerFile();
    return await file.exists();
  } catch (_) {
    return false;
  }
}

Future<void> clearWipeMarker() async {
  try {
    final file = await _wipeMarkerFile();
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

// --- Merker: diese Installation lief schon einmal ---
//
// Eine 0-Byte-Datei neben dem Wipe-Merker, im App-Support-Ordner. Der Ordner
// gehoert zur Installation: er verschwindet, wenn jemand Krypta loescht, und
// er bleibt stehen, wenn nur die App aktualisiert wird. Genau diese
// Unterscheidung braucht der FreshInstallGuard.
//
// Der Schluesselbund taugt dafuer nicht - auf iOS ueberlebt er beides.

Future<File> _installMarkerFile() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return File(p.join(dir.path, '.krypta_installed'));
}

/// Ob der Merker liegt. Bei einem Fehler `true` - dann passiert nichts.
/// Ein falsches `false` wuerde Daten loeschen, die es noch geben soll; ein
/// falsches `true` laesst nur Reste liegen. Der Irrtum in diese Richtung ist
/// der billigere.
Future<bool> isInstallMarkerSet() async {
  try {
    final file = await _installMarkerFile();
    return await file.exists();
  } catch (_) {
    return true;
  }
}

/// Setzt den Merker. Wirft, wenn der Ordner nicht beschreibbar ist - der
/// Aufrufer raeumt dann nicht, sonst raeumte er bei jedem Start erneut.
Future<void> setInstallMarker() async {
  final file = await _installMarkerFile();
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
}

/// Wipe all application cache and temp directories.
/// Covers: image cache, HTTP cache, temp files, notification payloads.
Future<void> wipeCacheAndTemp() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (await Directory(tempDir.path).exists()) {
      await for (final entity in Directory(tempDir.path).list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}

  try {
    final cacheDir = await getApplicationCacheDirectory();
    if (await Directory(cacheDir.path).exists()) {
      await for (final entity in Directory(cacheDir.path).list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}
}
