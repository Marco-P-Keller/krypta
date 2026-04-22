import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/device/device_integrity_policy.dart';
import 'package:kryptaapp/services/platform/platform_security_service.dart';

void main() {
  group('DeviceIntegrityLevel', () {
    test('has exactly three levels', () {
      expect(DeviceIntegrityLevel.values.length, 3);
    });

    test('levels: clean, compromised, unknown', () {
      expect(DeviceIntegrityLevel.values, containsAll([
        DeviceIntegrityLevel.clean,
        DeviceIntegrityLevel.compromised,
        DeviceIntegrityLevel.unknown,
      ]));
    });
  });

  group('DeviceIntegrityPolicy', () {
    test('has exactly three policies', () {
      expect(DeviceIntegrityPolicy.values.length, 3);
    });

    test('policies: block, warnAndDegrade, warnOnly', () {
      expect(DeviceIntegrityPolicy.values, containsAll([
        DeviceIntegrityPolicy.block,
        DeviceIntegrityPolicy.warnAndDegrade,
        DeviceIntegrityPolicy.warnOnly,
      ]));
    });
  });

  group('DeviceIntegrityResult', () {
    test('clean result: isClean=true, isThreat=false', () {
      final result = DeviceIntegrityResult(
        level: DeviceIntegrityLevel.clean,
        checkedAt: DateTime.now(),
      );
      expect(result.isClean, isTrue);
      expect(result.isCompromised, isFalse);
      expect(result.isUnknown, isFalse);
      expect(result.isThreat, isFalse);
    });

    test('compromised result: isCompromised=true, isThreat=true', () {
      final result = DeviceIntegrityResult(
        level: DeviceIntegrityLevel.compromised,
        checkedAt: DateTime.now(),
      );
      expect(result.isClean, isFalse);
      expect(result.isCompromised, isTrue);
      expect(result.isUnknown, isFalse);
      expect(result.isThreat, isTrue);
    });

    test('unknown result: isUnknown=true, isThreat=true', () {
      final result = DeviceIntegrityResult(
        level: DeviceIntegrityLevel.unknown,
        checkedAt: DateTime.now(),
      );
      expect(result.isClean, isFalse);
      expect(result.isCompromised, isFalse);
      expect(result.isUnknown, isTrue);
      expect(result.isThreat, isTrue);
    });

    test('checkedAt is stored', () {
      final now = DateTime(2026, 4, 21, 12, 0);
      final result = DeviceIntegrityResult(
        level: DeviceIntegrityLevel.clean,
        checkedAt: now,
      );
      expect(result.checkedAt, now);
    });
  });

  group('DeviceIntegrityAction', () {
    test('has exactly four actions', () {
      expect(DeviceIntegrityAction.values.length, 4);
    });

    test('actions: allow, block, warnAndDegrade, warnOnly', () {
      expect(DeviceIntegrityAction.values, containsAll([
        DeviceIntegrityAction.allow,
        DeviceIntegrityAction.block,
        DeviceIntegrityAction.warnAndDegrade,
        DeviceIntegrityAction.warnOnly,
      ]));
    });
  });

  group('DeviceIntegrityPolicyService — enforce()', () {
    test('no check yet: returns allow (null result = clean assumed)', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      expect(service.enforce(), DeviceIntegrityAction.allow);
    });

    test('clean device: returns allow regardless of policy', () async {
      for (final policy in DeviceIntegrityPolicy.values) {
        final service = DeviceIntegrityPolicyService(
          platform: _StubPlatform(compromised: false),
          policy: policy,
        );
        await service.checkIntegrity();
        expect(service.enforce(), DeviceIntegrityAction.allow,
            reason: 'Policy $policy should allow clean devices');
      }
    });

    test('compromised device + block policy: returns block', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.block,
      );
      await service.checkIntegrity();
      expect(service.enforce(), DeviceIntegrityAction.block);
    });

    test('compromised device + warnAndDegrade: returns warnAndDegrade',
        () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.warnAndDegrade,
      );
      await service.checkIntegrity();
      expect(service.enforce(), DeviceIntegrityAction.warnAndDegrade);
    });

    test('compromised device + warnOnly: returns warnOnly', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.warnOnly,
      );
      await service.checkIntegrity();
      expect(service.enforce(), DeviceIntegrityAction.warnOnly);
    });

    test('check failure (unknown) + block policy: returns block', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(throwOnCheck: true),
        policy: DeviceIntegrityPolicy.block,
      );
      await service.checkIntegrity();
      expect(service.lastResult!.isUnknown, isTrue);
      expect(service.enforce(), DeviceIntegrityAction.block);
    });

    test('check failure (unknown) + warnAndDegrade: returns warnAndDegrade',
        () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(throwOnCheck: true),
        policy: DeviceIntegrityPolicy.warnAndDegrade,
      );
      await service.checkIntegrity();
      expect(service.enforce(), DeviceIntegrityAction.warnAndDegrade);
    });
  });

  group('DeviceIntegrityPolicyService — hardwareFeaturesAvailable', () {
    test('clean device: hardware available (all policies)', () async {
      for (final policy in DeviceIntegrityPolicy.values) {
        final service = DeviceIntegrityPolicyService(
          platform: _StubPlatform(compromised: false),
          policy: policy,
        );
        await service.checkIntegrity();
        expect(service.hardwareFeaturesAvailable, isTrue,
            reason: 'Policy $policy: hardware should be available on clean');
      }
    });

    test('compromised + block: hardware disabled', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.block,
      );
      await service.checkIntegrity();
      expect(service.hardwareFeaturesAvailable, isFalse);
    });

    test('compromised + warnAndDegrade: hardware disabled', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.warnAndDegrade,
      );
      await service.checkIntegrity();
      expect(service.hardwareFeaturesAvailable, isFalse);
    });

    test('compromised + warnOnly: hardware STILL available', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: true),
        policy: DeviceIntegrityPolicy.warnOnly,
      );
      await service.checkIntegrity();
      expect(service.hardwareFeaturesAvailable, isTrue);
    });
  });

  group('DeviceIntegrityPolicyService — state', () {
    test('default policy is warnAndDegrade', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      expect(service.policy, DeviceIntegrityPolicy.warnAndDegrade);
    });

    test('policy is set at construction and queryable', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
        policy: DeviceIntegrityPolicy.block,
      );
      expect(service.policy, DeviceIntegrityPolicy.block);
    });

    test('lastResult is null before first check', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      expect(service.lastResult, isNull);
    });

    test('lastResult is populated after check', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      await service.checkIntegrity();
      expect(service.lastResult, isNotNull);
      expect(service.lastResult!.isClean, isTrue);
    });

    test('isDeviceClean defaults to false before check', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      // No check → null result → default false (fail-closed)
      expect(service.isDeviceClean, isFalse);
    });

    test('isDeviceThreat defaults to true before check (fail-closed)', () {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(compromised: false),
      );
      expect(service.isDeviceThreat, isTrue);
    });

    test('recheck invalidates cache and re-runs check', () async {
      final platform = _StubPlatform(compromised: false);
      final service = DeviceIntegrityPolicyService(platform: platform);

      await service.checkIntegrity();
      expect(service.isDeviceClean, isTrue);

      // Device becomes compromised while app is in background
      platform.compromised = true;
      await service.recheck();
      expect(service.isDeviceClean, isFalse);
      expect(service.isDeviceThreat, isTrue);
      expect(platform.cacheInvalidated, isTrue);
    });
  });

  group('Fail-closed guarantees', () {
    test('exception during check → level=unknown (worst case)', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(throwOnCheck: true),
      );
      final result = await service.checkIntegrity();
      expect(result.level, DeviceIntegrityLevel.unknown);
      expect(result.isThreat, isTrue);
    });

    test('unknown level triggers policy enforcement', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(throwOnCheck: true),
        policy: DeviceIntegrityPolicy.block,
      );
      await service.checkIntegrity();
      expect(service.enforce(), DeviceIntegrityAction.block);
    });

    test('hardware disabled when check fails (warnAndDegrade)', () async {
      final service = DeviceIntegrityPolicyService(
        platform: _StubPlatform(throwOnCheck: true),
        policy: DeviceIntegrityPolicy.warnAndDegrade,
      );
      await service.checkIntegrity();
      expect(service.hardwareFeaturesAvailable, isFalse);
    });
  });
}

/// Test stub that overrides PlatformSecurityService to control device
/// compromise detection without hitting real platform APIs.
class _StubPlatform extends PlatformSecurityService {
  bool compromised;
  bool throwOnCheck;
  bool cacheInvalidated = false;

  _StubPlatform({
    this.compromised = false,
    this.throwOnCheck = false,
  });

  @override
  Future<bool> isDeviceCompromised() async {
    if (throwOnCheck) throw Exception('Simulated check failure');
    return compromised;
  }

  @override
  void invalidateDeviceCache() {
    cacheInvalidated = true;
    super.invalidateDeviceCache();
  }
}
