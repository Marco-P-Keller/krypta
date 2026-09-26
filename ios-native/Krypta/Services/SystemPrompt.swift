import Foundation

/// Fragen des Systems (Face ID, Kamera, Mitteilungen) machen die App kurz
/// inaktiv. Das ist kein Verlassen der App — während Krypta selbst fragt,
/// sperrt sie deshalb nicht.
@MainActor
enum SystemPrompt {
    private(set) static var isShowing = false
    private static var depth = 0

    static func during<T>(_ body: () async -> T) async -> T {
        depth += 1
        isShowing = true
        defer {
            depth -= 1
            isShowing = depth > 0
        }
        return await body()
    }
}
