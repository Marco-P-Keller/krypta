import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Platform security: biometric auth, screenshot protection,
/// root/jailbreak/Frida/debugger detection, screenshot event detection.
///
/// All operations are no-ops on web.
class PlatformSecurityService {
  final LocalAuthentication _localAuth;
  static const _channel = MethodChannel('krypta/security');
  static const _screenshotEventChannel = EventChannel('krypta/screenshot_events');
  static const _captureEventChannel = EventChannel('krypta/capture_events');

  /// Screenshot-Ereignisse von der Plattform. Der Wert ist immer `false` —
  /// blockiert wurde nichts, das Ereignis selbst ist die Aussage.
  Stream<bool>? _screenshotStream;

  /// Zustandswechsel der Bildschirmaufnahme (Aufzeichnung, AirPlay).
  Stream<bool>? _captureStream;

  /// Die durchgehende Beobachtung der Aufnahme.
  ///
  /// Sie laeuft, solange die Erkennung an ist — nicht nur, solange ein Chat
  /// offen ist. Das hat zwei Gruende. Erstens haelt sie den nativen Kanal
  /// offen, sodass ein spaeter hinzukommender Horcher nicht den bereits
  /// bekannten Zustand erneut geliefert bekommt. Zweitens laesst sich nur mit
  /// luekenloser Beobachtung „dieselbe Aufnahme wie eben" von „eine neue
  /// Aufnahme" unterscheiden.
  StreamSubscription<bool>? _captureWatch;
  final _recordingStarted = StreamController<int>.broadcast();
  int _captureCount = 0;
  bool _capturing = false;

  /// Nummer der laufenden Aufnahme, `0` wenn gerade keine laeuft.
  ///
  /// Der Chat-Bildschirm wird beim Wechseln neu gebaut. Ohne diese Nummer
  /// wuerde er fuer EINE Aufnahme mehrfach melden — die Gegenseite saehe
  /// „Bildschirmaufnahme gestartet" bei jedem Oeffnen des Chats erneut.
  int get captureSession => _capturing ? _captureCount : 0;

  /// Meldet den Beginn einer Aufnahme mit ihrer Nummer. Nur den Beginn: das
  /// Ende ist nichts, was die Gegenseite erfahren muesste.
  Stream<int> get onScreenRecordingStarted => _recordingStarted.stream;

  /// Whether screenshot protection is currently enabled.
  bool _screenshotProtectionActive = false;

  bool get isScreenshotProtectionActive => _screenshotProtectionActive;

  /// Cached result of device compromise check.
  /// Call [invalidateDeviceCache] on app resume to re-check periodically.
  bool? _deviceCompromised;

  PlatformSecurityService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  // --- Biometric Authentication ---

  Future<bool> get isBiometricAvailable async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Authenticate to continue'}) async {
    if (kIsWeb) return true;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  // --- Screenshot Protection ---

  /// Enable screenshot/recording protection.
  ///
  /// Returns whether protection is VERIFIED active. On Android FLAG_SECURE
  /// always succeeds; on iOS this reflects whether the OS-level content mask
  /// was actually installed (the platform cannot block the screenshot itself,
  /// only blank its content). Reflects the honest state instead of optimism
  /// so callers/telemetry can react if the mask ever fails to install.
  ///
  /// Blockiert nichts mehr. Auf iOS liess sich ein Screenshot ohnehin nie
  /// verhindern, und der Versuch, den Inhalt zu schwaerzen, beruhte auf
  /// undokumentiertem Verhalten und wirkte ab iOS 26 nicht mehr — die App
  /// behauptete einen Schutz, den sie nicht hatte. Was hier eingeschaltet
  /// wird, ist die **Erkennung**: Screenshots und Bildschirmaufnahmen werden
  /// gemeldet, und beide Seiten erfahren davon.
  ///
  /// Auf Android bleibt FLAG_SECURE aktiv — dort blockiert das System
  /// wirklich, und echter Schutz ist besser als ein Hinweis.
  Future<bool> enableScreenshotProtection() async {
    if (kIsWeb) {
      _screenshotProtectionActive = false;
      return false;
    }
    try {
      final active = await _channel.invokeMethod<bool>('enableSecureFlag');
      _screenshotProtectionActive = active ?? false;
    } catch (_) {
      _screenshotProtectionActive = false;
    }
    if (_screenshotProtectionActive) _watchCapture();
    return _screenshotProtectionActive;
  }

  void _watchCapture() {
    _captureWatch ??= onScreenCaptureChanged.listen((laeuft) {
      if (laeuft == _capturing) return;
      _capturing = laeuft;
      if (laeuft) {
        _captureCount++;
        _recordingStarted.add(_captureCount);
      }
    });
  }

  Future<void> disableScreenshotProtection() async {
    _screenshotProtectionActive = false;
    // Aus heisst aus: keine Beobachtung, keine laufende Sitzung, und damit
    // erfaehrt auch die Gegenseite nichts mehr.
    _captureWatch?.cancel();
    _captureWatch = null;
    _capturing = false;
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('disableSecureFlag');
    } catch (_) {}
  }

  /// Meldet, dass ein Screenshot gemacht wurde.
  ///
  /// Der Wert ist immer `false`: verhindert wurde nichts, iOS meldet den
  /// Screenshot erst danach. Der Strom selbst ist das Ereignis.
  /// Der native Kanal wird geoeffnet, sobald ein Chat zuhoert — unabhaengig
  /// davon, ob der Hinweis eingeschaltet ist. Deshalb wird hier gefiltert:
  /// „aus" ist eine Zusage an den Nutzer, und ohne diese Sperre bekaeme die
  /// Gegenseite eine Meldung, obwohl er den Hinweis abgeschaltet hat.
  Stream<bool> get onScreenshotDetected {
    _screenshotStream ??= _screenshotEventChannel
        .receiveBroadcastStream()
        .where((_) => _screenshotProtectionActive)
        .map((event) => event == true)
        .handleError((_) {});
    return _screenshotStream!;
  }

  // --- Bildschirmaufnahme und Spiegelung ---

  /// Ob der Bildschirm gerade aufgezeichnet oder gespiegelt wird.
  ///
  /// Auf iOS aus `UIScreen.isCaptured` — dokumentiert und von Apple
  /// unterstützt, anders als der Layer-Trick für Screenshots. Auf Android
  /// immer `false`: dort blockiert FLAG_SECURE die Aufnahme bereits.
  Future<bool> isScreenCaptured() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('isScreenCaptured') ?? false;
    } catch (_) {
      // Ohne Antwort keine Aufnahme behaupten — die sichere Richtung ist hier
      // die andere als beim Schutzzustand: eine erfundene Aufnahme würde die
      // App grundlos schwarz schalten.
      return false;
    }
  }

  /// Meldet den Beginn und das Ende einer Bildschirmaufnahme oder Spiegelung.
  Stream<bool> get onScreenCaptureChanged {
    _captureStream ??= _captureEventChannel
        .receiveBroadcastStream()
        .map((event) => event == true)
        .handleError((_) {});
    return _captureStream!;
  }

  // --- Device Integrity Check ---

  /// Comprehensive device compromise detection.
  ///
  /// Checks for:
  /// - Root (Android) / Jailbreak (iOS) indicators
  /// - Frida instrumentation framework
  /// - Debugger attachment
  /// - Tampered runtime environment
  ///
  /// Returns true if the device appears compromised.
  /// Result is cached after first check.
  Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    if (_deviceCompromised != null) return _deviceCompromised!;

    try {
      bool compromised = false;

      if (Platform.isAndroid) {
        compromised = _checkAndroidRoot() ||
            _checkFridaAndroid() ||
            _checkDebugger();
      } else if (Platform.isIOS) {
        compromised = _checkIOSJailbreak() ||
            _checkFridaIOS() ||
            _checkDebugger();
      }

      _deviceCompromised = compromised;
      return compromised;
    } catch (_) {
      // Fail-closed: if we can't check, assume compromised
      _deviceCompromised = true;
      return true;
    }
  }

  /// Hard block: call on app start to prevent use on compromised devices.
  /// Returns true if device is safe.
  Future<bool> enforceDeviceIntegrity() async {
    final compromised = await isDeviceCompromised();
    if (compromised) {
      if (kDebugMode) debugPrint('Device integrity check FAILED — app blocked');
    }
    return !compromised;
  }

  /// Invalidate the cached device integrity result.
  ///
  /// Call this on `AppLifecycleState.resumed` to re-check on each app resume.
  /// Prevents bypassing integrity checks if the device is rooted while
  /// the app is in the background.
  void invalidateDeviceCache() {
    _deviceCompromised = null;
  }

  // --- Root Detection (Android) ---

  bool _checkAndroidRoot() {
    const rootIndicators = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/sbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/data/local/su',
      '/system/bin/failsafe/su',
      '/system/sd/xbin/su',
      '/system/app/SuperSU.apk',
      '/data/data/com.noshufou.android.su',
      '/data/data/eu.chainfire.supersu',
      '/data/data/com.topjohnwu.magisk',
    ];
    for (final path in rootIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }
    // Check for Magisk
    try {
      if (File('/sbin/.magisk').existsSync()) return true;
    } catch (_) {}
    return false;
  }

  // --- Jailbreak Detection (iOS) ---

  bool _checkIOSJailbreak() {
    const jailbreakIndicators = [
      '/Applications/Cydia.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
      '/usr/bin/ssh',
      '/private/var/stash',
      '/Applications/Sileo.app',
      '/var/binpack',
      '/Library/PreferenceBundles/LibertyPref.bundle',
      '/Library/PreferenceBundles/ShadowPreferences.bundle',
      '/usr/lib/libhooker.dylib',
      '/usr/lib/libsubstitute.dylib',
    ];
    for (final path in jailbreakIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }

    // Check if app can write to system paths (sandboxing broken)
    try {
      final testFile = File('/private/jailbreak_test');
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      return true; // Should not be writable on non-jailbroken device
    } catch (_) {
      // Expected — cannot write to system paths
    }

    return false;
  }

  // --- Frida Detection ---

  bool _checkFridaAndroid() {
    // Check for Frida server process indicators
    const fridaIndicators = [
      '/data/local/tmp/frida-server',
      '/data/local/tmp/re.frida.server',
    ];
    for (final path in fridaIndicators) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }

    // Check for Frida-related libraries loaded in memory
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      if (maps.contains('frida') || maps.contains('gadget')) return true;
    } catch (_) {}

    return false;
  }

  bool _checkFridaIOS() {
    // Check for Frida dylibs
    const fridaLibs = [
      '/usr/lib/frida',
      '/usr/lib/FridaGadget.dylib',
      '/Library/Frameworks/FridaGadget.framework',
    ];
    for (final path in fridaLibs) {
      try {
        if (File(path).existsSync()) return true;
      } catch (_) {}
    }
    return false;
  }

  // --- Debugger Detection ---

  bool _checkDebugger() {
    // Check if running in debug/profile mode
    if (kDebugMode || kProfileMode) return false; // Allow during development

    // On release builds, check for debugger attachment
    try {
      if (Platform.isAndroid) {
        // Check TracerPid in /proc/self/status
        final status = File('/proc/self/status').readAsStringSync();
        final tracerLine = status.split('\n').firstWhere(
          (line) => line.startsWith('TracerPid:'),
          orElse: () => 'TracerPid:\t0',
        );
        final pid = int.tryParse(tracerLine.split('\t').last.trim()) ?? 0;
        if (pid != 0) return true; // Debugger attached
      }
    } catch (_) {}

    return false;
  }
}
