import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/transport/privacy_polling.dart';

void main() {
  group('PrivacyPolling Configuration', () {
    test('base interval is 10 seconds', () {
      expect(PrivacyPolling.baseInterval, const Duration(seconds: 10));
    });

    test('max jitter is 20 seconds', () {
      expect(PrivacyPolling.maxJitter, const Duration(seconds: 20));
    });

    test('minimum poll interval is 10 seconds (base, no jitter)', () {
      final minInterval = PrivacyPolling.baseInterval;
      expect(minInterval.inSeconds, 10);
    });

    test('maximum poll interval is 30 seconds (base + full jitter)', () {
      final maxInterval = PrivacyPolling.baseInterval + PrivacyPolling.maxJitter;
      expect(maxInterval.inSeconds, 30);
    });

    test('jitter range prevents timing correlation', () {
      // The jitter window (20s) is 2x the base interval (10s).
      // This makes it infeasible for a network observer to correlate
      // poll timing with message delivery events.
      final jitterRatio = PrivacyPolling.maxJitter.inMilliseconds /
          PrivacyPolling.baseInterval.inMilliseconds;
      expect(jitterRatio, greaterThanOrEqualTo(1.0));
    });

    test('base interval is short enough for reasonable UX', () {
      // Max delivery latency = baseInterval + maxJitter = 30s
      // This is acceptable for a privacy-focused messenger.
      final maxLatency = PrivacyPolling.baseInterval + PrivacyPolling.maxJitter;
      expect(maxLatency.inSeconds, lessThanOrEqualTo(60));
    });
  });
}
