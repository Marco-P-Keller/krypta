import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/device/device_integrity_policy.dart';
import 'package:kryptaapp/security/hardware/hardware_security_binding.dart';
import 'package:kryptaapp/services/platform/platform_security_service.dart';

void main() {
  group('HardwareSecurityLevel', () {
    test('has exactly three levels', () {
      expect(HardwareSecurityLevel.values.length, 3);
    });

    test('levels: hardwareEnclave, trustedExecution, softwareOnly', () {
      expect(HardwareSecurityLevel.values, containsAll([
        HardwareSecurityLevel.hardwareEnclave,
        HardwareSecurityLevel.trustedExecution,
        HardwareSecurityLevel.softwareOnly,
      ]));
    });
  });

  group('HardwareSecurityBinding — initial state', () {
    test('level defaults to softwareOnly before init', () {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);
      expect(binding.level, HardwareSecurityLevel.softwareOnly);
    });

    test('isHardwareBindingAvailable is false before init', () {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);
      expect(binding.isHardwareBindingAvailable, isFalse);
    });

    test('isHardwareKeyReady is false before init', () {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);
      expect(binding.isHardwareKeyReady, isFalse);
    });
  });

  group('HardwareSecurityBinding — integration with DeviceIntegrity', () {
    test('hardware binding disabled when device is compromised (warnAndDegrade)',
        () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CompromisedPlatform(),
        policy: DeviceIntegrityPolicy.warnAndDegrade,
      );
      await integrity.checkIntegrity();

      final binding = HardwareSecurityBinding(integrity: integrity);
      // Even if hardware were detected, compromised device = disabled
      expect(binding.isHardwareBindingAvailable, isFalse);
    });

    test('hardware binding disabled when device is compromised (block)',
        () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CompromisedPlatform(),
        policy: DeviceIntegrityPolicy.block,
      );
      await integrity.checkIntegrity();

      final binding = HardwareSecurityBinding(integrity: integrity);
      expect(binding.isHardwareBindingAvailable, isFalse);
    });

    test('hardware features available with warnOnly policy even if compromised',
        () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CompromisedPlatform(),
        policy: DeviceIntegrityPolicy.warnOnly,
      );
      await integrity.checkIntegrity();

      // hardwareFeaturesAvailable is true for warnOnly
      expect(integrity.hardwareFeaturesAvailable, isTrue);
    });
  });

  group('HardwareSecurityBinding — levelDescription', () {
    test('provides German descriptions for each level', () {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);

      // Before init — null level
      expect(binding.levelDescription, contains('Nicht initialisiert'));
    });
  });

  group('HardwareSecurityBinding — wrapKey/unwrapKey without hardware', () {
    test('wrapKey returns null when hardware not ready', () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);

      final result = await binding.wrapKey(Uint8List(32));
      expect(result, isNull);
    });

    test('unwrapKey returns null when hardware not ready', () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);

      final result = await binding.unwrapKey(Uint8List(48));
      expect(result, isNull);
    });

    test('createHardwareKey returns false when not available', () async {
      final integrity = DeviceIntegrityPolicyService(
        platform: _CleanPlatform(),
      );
      final binding = HardwareSecurityBinding(integrity: integrity);

      final result = await binding.createHardwareKey();
      expect(result, isFalse);
    });
  });
}

/// Test stub: clean device (no compromise detected).
class _CleanPlatform extends PlatformSecurityService {
  @override
  Future<bool> isDeviceCompromised() async => false;
}

/// Test stub: compromised device.
class _CompromisedPlatform extends PlatformSecurityService {
  @override
  Future<bool> isDeviceCompromised() async => true;
}
