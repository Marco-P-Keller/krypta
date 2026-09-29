import Foundation
import XCTest
@testable import KryptaWallet

/// Die Drosselung für öffentliche Esplora-Server (mempool.space sperrt nach
/// gut zwanzig schnellen Anfragen).
final class RequestPacerTests: XCTestCase {
    private func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// Der Vorrat geht sofort, danach je Marke 1/perSecond.
    func testBurstThenPaced() async {
        let pacer = RequestPacer(burst: 3, perSecond: 20)
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<3 { await pacer.acquire() }
        XCTAssertLessThan(seconds(clock.now - start), 0.05)
        for _ in 0..<4 { await pacer.acquire() }
        // Vier über dem Vorrat: mindestens 4/20 s.
        XCTAssertGreaterThanOrEqual(seconds(clock.now - start), 0.18)
    }

    /// Gleichzeitige Anfragen stellen sich an, statt gemeinsam loszulaufen.
    func testConcurrentCallersQueue() async {
        let pacer = RequestPacer(burst: 1, perSecond: 20)
        let clock = ContinuousClock()
        let start = clock.now
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { await pacer.acquire() } }
        }
        XCTAssertGreaterThanOrEqual(seconds(clock.now - start), 0.18)
    }

    /// Nach einem 429 geht eine Weile nichts mehr hinaus.
    func testPauseHoldsBack() async {
        let pacer = RequestPacer(burst: 10, perSecond: 20)
        let clock = ContinuousClock()
        await pacer.pause(seconds: 0.3)
        let start = clock.now
        await pacer.acquire()
        XCTAssertGreaterThanOrEqual(seconds(clock.now - start), 0.28)
    }
}
