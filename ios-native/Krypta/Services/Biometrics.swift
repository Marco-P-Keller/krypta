import LocalAuthentication

/// Face ID / Touch ID.
enum Biometrics {
    enum Kind { case none, faceID, touchID, opticID }

    static var available: Kind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    static var name: String {
        switch available {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: String(localized: "Biometrie")
        }
    }

    static var symbol: String {
        switch available {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock"
        }
    }

    /// `true` nur bei echtem Erfolg. Abbrechen ist kein Fehlversuch.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        return await SystemPrompt.during {
            (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
        }
    }
}
