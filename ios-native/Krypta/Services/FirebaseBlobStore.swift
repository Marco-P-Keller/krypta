import FirebaseAuth
import FirebaseCore
import FirebaseStorage
import Foundation
import KryptaMessenger

/// Anhänge in Firebase Storage unter `att/<Kennung>` (firebase/storage.rules).
///
/// Hochladen und Löschen angemeldet: die Regeln begrenzen die Größe, und nur,
/// wer hochgeladen hat (`o` in den Metadaten), darf löschen. Geholt wird über
/// die Firebase-App ohne Konto (wie Sealed Sender): Firebase sieht nicht,
/// welches Konto einen Anhang abholt. Die Kennung ist zufällig (128 Bit);
/// wer sie kennt, hat die Nachricht bekommen.
final class FirebaseBlobStore: BlobStore, @unchecked Sendable {
    struct NotSignedIn: Error {}

    private var storage: Storage { Storage.storage() }

    private var anonymous: Storage {
        FirebaseApp.app(name: FirebaseRelay.sealedAppName).map { Storage.storage(app: $0) } ?? storage
    }

    private static func path(_ id: String) -> String { "att/\(id)" }

    func upload(_ blob: Data, id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NotSignedIn() }
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = ["o": uid]
        _ = try await storage.reference(withPath: Self.path(id)).putDataAsync(blob, metadata: metadata)
    }

    func download(id: String, maxSize: Int) async throws -> Data {
        try await anonymous.reference(withPath: Self.path(id)).data(maxSize: Int64(maxSize))
    }

    func delete(id: String) async throws {
        try await storage.reference(withPath: Self.path(id)).delete()
    }
}
