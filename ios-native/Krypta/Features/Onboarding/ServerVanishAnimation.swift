import SwiftUI

/// Die Nachricht reist von deinem iPhone über den Server zu deinem Kontakt —
/// und sobald sie angekommen ist, zerfällt die Kopie auf dem Server.
///
/// Eine Zeitleiste, die sich alle `cycle` Sekunden wiederholt; alles hängt
/// nur von `t` ab, damit die Schleife nahtlos ist. Mit „Bewegung reduzieren"
/// steht das Bild still, im Moment nach dem Löschen.
struct ServerVanishAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cycle: Double = 5.2

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let t = reduceMotion ? 3.6 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            GeometryReader { geo in
                VanishScene(t: t, size: geo.size)
            }
        }
        .frame(height: 190)
        .accessibilityElement()
        .accessibilityLabel("Die Nachricht geht über den Server zu deinem Kontakt. Sobald sie angekommen ist, wird sie auf dem Server gelöscht.")
    }
}

private struct VanishScene: View {
    let t: Double
    let size: CGSize

    // Zeitleiste in Sekunden.
    private let appear = 0.0...0.35
    private let toServer = 0.35...1.35
    private let atServer = 1.35...1.8
    private let toContact = 1.8...2.8
    private let dissolve = 2.95...3.7
    private let fadeOut = 4.7...5.2

    private var a: CGPoint { CGPoint(x: size.width * 0.13, y: size.height * 0.58) }
    private var server: CGPoint { CGPoint(x: size.width * 0.5, y: size.height * 0.36) }
    private var b: CGPoint { CGPoint(x: size.width * 0.87, y: size.height * 0.58) }

    var body: some View {
        let overall = 1 - progress(fadeOut)
        ZStack {
            // Die Wege, gestrichelt.
            Path { p in
                p.move(to: a)
                p.addQuadCurve(to: server, control: CGPoint(x: (a.x + server.x) / 2, y: server.y - 10))
                p.addQuadCurve(to: b, control: CGPoint(x: (server.x + b.x) / 2, y: server.y - 10))
            }
            .stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 6]))

            device(label: "Du", at: a, glow: glow(near: toServer.lowerBound))
            serverNode
            device(label: "Kontakt", at: b, glow: arrived, received: arrived > 0)

            ghost
            particles
            traveller.opacity(overall)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Teile

    private func device(label: LocalizedStringKey, at point: CGPoint, glow: Double, received: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: "iphone")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(received ? 1 : 0.2)
                    .opacity(received ? 1 - progress(fadeOut) : 0)
            }
            .shadow(color: .accentColor.opacity(0.6 * glow), radius: 12 * glow)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .position(x: point.x, y: point.y + 12)
    }

    private var serverNode: some View {
        let deleted = progress(dissolve) > 0.5 && t < fadeOut.lowerBound + 0.25
        let hold = glow(near: atServer.lowerBound)
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "server.rack")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                    .shadow(color: .accentColor.opacity(0.5 * hold), radius: 10 * hold)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white, .green)
                    .background(Circle().fill(Color(.systemBackground)).padding(1))
                    .offset(x: 10, y: -8)
                    .scaleEffect(deleted ? 1 : 0.3)
                    .opacity(deleted ? 1 : 0)
                    .animation(.spring(duration: 0.35, bounce: 0.45), value: deleted)
            }
            ZStack {
                Text("Server").opacity(deleted ? 0 : 1)
                Text("Gelöscht").foregroundStyle(.green).opacity(deleted ? 1 : 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .animation(.easeInOut(duration: 0.25), value: deleted)
        }
        .position(x: server.x, y: server.y - 4)
    }

    /// Die Nachricht selbst: verschlüsselt, mit Schloss.
    private var bubble: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 24)
            .background(Color.accentColor.gradient, in: Capsule())
            .shadow(color: .accentColor.opacity(0.35), radius: 6, y: 2)
    }

    private var traveller: some View {
        let position: CGPoint
        var scale = 1.0
        var opacity = 1.0
        switch t {
        case ..<appear.upperBound:
            position = a
            scale = ease(progress(appear))
        case ..<toServer.upperBound:
            position = arc(from: a, to: server, ease(progress(toServer)))
        case ..<atServer.upperBound:
            position = server
            scale = 1 + 0.12 * sin(.pi * progress(atServer))
        case ..<toContact.upperBound:
            position = arc(from: server, to: b, ease(progress(toContact)))
        default:
            // Angekommen: schlüpft ins Gerät.
            position = b
            let p = progress(toContact.upperBound...toContact.upperBound + 0.3)
            scale = 1 - 0.6 * p
            opacity = 1 - p
        }
        return bubble
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: position.x, y: position.y - 20)
    }

    /// Die Kopie, die auf dem Server liegen bleibt, bis die Nachricht angekommen ist.
    private var ghost: some View {
        let visible = t >= atServer.upperBound && t < dissolve.upperBound
        let d = progress(dissolve)
        return bubble
            .opacity(visible ? 0.55 * (1 - d) : 0)
            .scaleEffect(1 - 0.35 * d)
            .blur(radius: 3 * d)
            .position(x: server.x, y: server.y - 20)
    }

    /// Beim Löschen stiebt sie auseinander.
    private var particles: some View {
        let d = progress(dissolve)
        let active = d > 0 && d < 1
        return ZStack {
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * .pi + 0.4
                let reach = 18 + 26 * ease(d) * (0.7 + 0.3 * Double((i * 7) % 5) / 4)
                Circle()
                    .fill(i.isMultiple(of: 3) ? Color.green : Color.accentColor)
                    .frame(width: 4, height: 4)
                    .scaleEffect(1 - 0.6 * d)
                    .offset(x: cos(angle) * reach, y: sin(angle) * reach * 0.8)
                    .opacity(active ? 1 - d : 0)
            }
        }
        .position(x: server.x, y: server.y - 20)
    }

    // MARK: Zeit

    private var arrived: Double {
        t >= toContact.upperBound ? 1 - progress(fadeOut) : 0
    }

    private func progress(_ range: ClosedRange<Double>) -> Double {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    /// Kurzes Leuchten um einen Zeitpunkt herum.
    private func glow(near moment: Double) -> Double {
        let d = abs(t - moment)
        return d > 0.45 ? 0 : 1 - d / 0.45
    }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private func arc(from p: CGPoint, to q: CGPoint, _ f: Double) -> CGPoint {
        let control = CGPoint(x: (p.x + q.x) / 2, y: min(p.y, q.y) - 10)
        let u = 1 - f
        return CGPoint(
            x: u * u * p.x + 2 * u * f * control.x + f * f * q.x,
            y: u * u * p.y + 2 * u * f * control.y + f * f * q.y
        )
    }
}

#Preview {
    ServerVanishAnimation().padding()
}
