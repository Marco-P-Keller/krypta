import Foundation

/// Hält die Anfragen an einen öffentlichen Server unter dessen Grenze.
///
/// mempool.space nimmt gut zwanzig Anfragen am Stück an, antwortet dann mit
/// 429 und lässt kurz darauf gar keine Verbindung mehr zu. Ein Abgleich
/// braucht schon bei einer neuen Wallet über dreißig (jede Adresse bis zur
/// Lücke einzeln). Deshalb ein Eimer mit Marken: `burst` gehen sofort, danach
/// `perSecond` je Sekunde. Wer keine Marke bekommt, wartet, statt den Server
/// zu verärgern.
public actor RequestPacer {
    private let burst: Double
    private let perSecond: Double
    /// Darf negativ werden: dann stehen so viele schon in der Schlange.
    private var tokens: Double
    private var last: ContinuousClock.Instant
    private let clock = ContinuousClock()

    public init(burst: Int, perSecond: Double) {
        self.burst = Double(max(1, burst))
        self.perSecond = max(0.1, perSecond)
        tokens = Double(max(1, burst))
        last = clock.now
    }

    /// Für mempool.space und andere öffentliche Esplora-Server, gemeinsam für
    /// alle Netze (dieselbe Adresse, dieselbe Grenze). Unter den gemessenen
    /// gut zwanzig am Stück und 200 je Minute.
    public static let publicServer = RequestPacer(burst: 15, perSecond: 3)

    /// Eine Marke nehmen; ist keine da, warten, bis man dran ist.
    public func acquire() async {
        refill()
        tokens -= 1
        if tokens < 0 {
            try? await Task.sleep(for: .seconds(-tokens / perSecond))
        }
    }

    /// Der Server hat gebremst (429): eine Weile gar nichts mehr schicken.
    public func pause(seconds: Double) {
        refill()
        tokens = min(tokens, -seconds * perSecond)
    }

    private func refill() {
        let now = clock.now
        let elapsed = now - last
        last = now
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        tokens = min(burst, tokens + seconds * perSecond)
    }
}
