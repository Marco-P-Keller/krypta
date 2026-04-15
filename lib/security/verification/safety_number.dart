import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Generates and compares safety numbers for identity verification.
///
/// A safety number is a 60-digit string derived from both users' identity
/// public keys + user IDs. Both users compute the same number.
/// Used for QR code verification and manual comparison.
class SafetyNumber {
  static final _sha512 = Sha512();

  /// Generate a 60-digit safety number for a pair of users.
  ///
  /// The number is symmetric: SafetyNumber(A, B) == SafetyNumber(B, A).
  /// This is achieved by sorting the inputs before hashing.
  static Future<String> generate({
    required String localUserId,
    required Uint8List localIdentityPublic,
    required String remoteUserId,
    required Uint8List remoteIdentityPublic,
  }) async {
    // Sort by user ID to ensure symmetry
    final List<(String, Uint8List)> sorted;
    if (localUserId.compareTo(remoteUserId) <= 0) {
      sorted = [(localUserId, localIdentityPublic), (remoteUserId, remoteIdentityPublic)];
    } else {
      sorted = [(remoteUserId, remoteIdentityPublic), (localUserId, localIdentityPublic)];
    }

    // Compute fingerprint for each side: SHA-512(version || userId || pubKey) iterated 5200x
    final fp1 = await _fingerprint(sorted[0].$1, sorted[0].$2);
    final fp2 = await _fingerprint(sorted[1].$1, sorted[1].$2);

    // Take 30 digits from each fingerprint
    return _toDigits(fp1, 30) + _toDigits(fp2, 30);
  }

  /// Format a safety number for display (groups of 5 digits).
  static String formatForDisplay(String safetyNumber) {
    final buf = StringBuffer();
    for (var i = 0; i < safetyNumber.length; i++) {
      if (i > 0 && i % 5 == 0) buf.write(' ');
      buf.write(safetyNumber[i]);
    }
    return buf.toString();
  }

  /// Compute SHA-512 fingerprint, iterated 5200 times.
  static Future<Uint8List> _fingerprint(String userId, Uint8List publicKey) async {
    final version = Uint8List.fromList([0x00, 0x01]); // v1
    final userIdBytes = Uint8List.fromList(utf8.encode(userId));

    // Initial input: version || userId || publicKey
    var data = Uint8List(version.length + userIdBytes.length + publicKey.length);
    data.setRange(0, version.length, version);
    data.setRange(version.length, version.length + userIdBytes.length, userIdBytes);
    data.setRange(
        version.length + userIdBytes.length, data.length, publicKey);

    // Iterate SHA-512 5200 times (Signal uses the same approach)
    for (var i = 0; i < 5200; i++) {
      final hash = await _sha512.hash(data);
      data = Uint8List.fromList(hash.bytes);
    }

    return data;
  }

  /// Convert hash bytes to decimal digit string.
  static String _toDigits(Uint8List hash, int count) {
    final buf = StringBuffer();
    for (var i = 0; i < count && i * 2 + 1 < hash.length; i++) {
      // Take 2 bytes, mod 100000, use last digit
      final val = (hash[i * 2] << 8 | hash[i * 2 + 1]) % 10;
      buf.write(val);
    }
    // Pad if needed
    final result = buf.toString();
    if (result.length >= count) return result.substring(0, count);
    return result.padRight(count, '0');
  }
}
