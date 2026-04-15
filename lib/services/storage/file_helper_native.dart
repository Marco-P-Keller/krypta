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
