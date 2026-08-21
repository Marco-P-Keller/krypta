import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<String?> getStorageBasePath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'krypta_store');
    await Directory(path).create(recursive: true);
    return path;
  } catch (_) {
    return null;
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
    return file.exists();
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
