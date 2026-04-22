import 'dart:typed_data';

/// A byte buffer that zeros its contents when disposed.
///
/// Dart's GC does not guarantee memory zeroing. This class provides
/// best-effort defense-in-depth:
/// 1. Explicit [dispose] zeros all bytes and marks the buffer as dead
/// 2. The finalizer API is not used (unreliable in Dart)
/// 3. Callers MUST call [dispose] when done — this is enforced by usage pattern
///
/// Usage:
/// ```dart
/// final buf = SensitiveBuffer(derivedKey);
/// try {
///   // use buf.bytes
/// } finally {
///   buf.dispose();
/// }
/// ```
///
/// Limitations:
/// - Dart JIT/AOT may copy bytes during optimization
/// - String representations (base64) cannot be zeroed (immutable)
/// - GC may retain copies of the original Uint8List
/// - This is BEST EFFORT, not a guarantee
class SensitiveBuffer {
  Uint8List _bytes;
  bool _disposed = false;

  SensitiveBuffer(this._bytes);

  /// Create from a copy of the source bytes.
  factory SensitiveBuffer.copy(Uint8List source) {
    return SensitiveBuffer(Uint8List.fromList(source));
  }

  /// The raw bytes. Throws if disposed.
  Uint8List get bytes {
    if (_disposed) {
      throw StateError('SensitiveBuffer already disposed');
    }
    return _bytes;
  }

  int get length => _bytes.length;

  /// Whether this buffer has been disposed (zeroed).
  bool get isDisposed => _disposed;

  /// Zero all bytes and mark as disposed.
  ///
  /// Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    zeroBytes(_bytes);
    _disposed = true;
  }

  /// Best-effort zero of a byte array.
  ///
  /// Public static so other code can use it without creating a SensitiveBuffer.
  static void zeroBytes(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  /// Zero multiple byte arrays at once.
  static void zeroAll(List<Uint8List> buffers) {
    for (final buf in buffers) {
      zeroBytes(buf);
    }
  }

  /// Zero a byte array and return an empty replacement.
  /// Useful for inline zeroing: `key = SensitiveBuffer.zeroAndReplace(key);`
  static Uint8List zeroAndReplace(Uint8List bytes) {
    zeroBytes(bytes);
    return Uint8List(0);
  }
}
