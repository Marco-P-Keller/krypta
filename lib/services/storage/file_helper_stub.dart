import 'dart:typed_data';

/// Web/stub: no file system access, all operations are no-ops.
Future<String?> getStorageBasePath() async => null;
Future<void> createDir(String path) async {}
Future<void> writeFileBytes(String path, Uint8List bytes) async {}
Future<Uint8List?> readFileBytes(String path) async => null;
Future<List<String>> listEncFiles(String dirPath) async => [];
Future<void> deleteFileAt(String path) async {}
Future<void> deleteDirRecursive(String path) async {}
Future<void> setWipeMarker() async {}
Future<bool> isWipeMarkerSet() async => false;
Future<void> clearWipeMarker() async {}
Future<void> wipeCacheAndTemp() async {}
