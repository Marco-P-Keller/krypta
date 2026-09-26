import CloudKit
import Foundation
import KryptaCore

/// Das iCloud-Konto auf dem iPhone — an Stelle der anonymen Anmeldung bei
/// Firebase.
///
/// Die Krypta-Kennung hängt nicht daran: 28 Zufallszeichen, erzeugt auf dem
/// Gerät, im selben Format wie früher die von Firebase. Kontakte erfahren so
/// nie etwas über den Apple-Account. Apple dagegen weiß, welcher Account die
/// Einträge schreibt — das ist der Preis dafür, keinen eigenen Server zu
/// brauchen (siehe ios-native/CloudKit/README.md).
enum CloudAccount {
    enum Failure: Error, Equatable {
        /// Kein Apple-Account angemeldet, oder iCloud für Krypta aus.
        case noAccount
        /// Bildschirmzeit oder ein Profil verbieten iCloud.
        case restricted
        /// Gerade nicht feststellbar (Anmeldung läuft, kein Netz).
        case unavailable
    }

    static func requireAvailable() async throws {
        let status: CKAccountStatus
        do {
            status = try await CloudKitRelay.container.accountStatus()
        } catch {
            throw Failure.unavailable
        }
        switch status {
        case .available: return
        case .noAccount: throw Failure.noAccount
        case .restricted: throw Failure.restricted
        case .couldNotDetermine, .temporarilyUnavailable: throw Failure.unavailable
        @unknown default: throw Failure.unavailable
        }
    }

    /// Eine neue Kennung: 28 Zeichen aus A–Z, a–z und 0–9, wie Firebase Auth
    /// sie vergab — so passt sie überall, wo Kennungen geprüft werden
    /// (`QRPayload.isValidUserId`). Rund 166 Bit Zufall.
    static func newUserId() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var id = ""
        while id.count < 28 {
            // 248 = 4 × 62: darüber verworfen, damit jedes Zeichen gleich oft vorkommt.
            for byte in Data.random(count: 32) where byte < 248 && id.count < 28 {
                id.append(alphabet[Int(byte) % alphabet.count])
            }
        }
        return id
    }
}
