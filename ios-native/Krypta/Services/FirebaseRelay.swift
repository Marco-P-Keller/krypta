import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore
import Foundation
import KryptaCore
import KryptaMessenger

/// Firestore als Relay — dieselben Sammlungen und Felder wie
/// services/firebase/firestore_service.dart, damit Flutter- und
/// Swift-Geräte über denselben Server sprechen.
///
/// Die Regeln in firebase/firestore.rules verlangen `updatedAt ==
/// request.time`; deshalb überall `FieldValue.serverTimestamp()`.
final class FirebaseRelay: Relay, @unchecked Sendable {
    private let db = Firestore.firestore()

    /// Sealed Sender: eine zweite Firebase-App mit denselben Einstellungen,
    /// bei der sich nie jemand anmeldet. Was über sie geschrieben wird, trägt
    /// kein Konto — der Server sieht nicht, von wem es kommt.
    private static let sealedAppName = "krypta-sealed"

    /// Einmal beim Start, direkt nach `FirebaseApp.configure()`.
    static func configureSealedApp() {
        guard FirebaseApp.app(name: sealedAppName) == nil, let options = FirebaseApp.app()?.options else { return }
        FirebaseApp.configure(name: sealedAppName, options: options)
        guard let app = FirebaseApp.app(name: sealedAppName) else { return }
        let sealed = Firestore.firestore(app: app)
        let settings = sealed.settings
        settings.cacheSettings = MemoryCacheSettings()
        sealed.settings = settings
    }

    private var sealedDb: Firestore? {
        FirebaseApp.app(name: Self.sealedAppName).map { Firestore.firestore(app: $0) }
    }

    func publishPublicKey(uid: String, publicKey: String) async throws {
        try await db.collection("publicKeys").document(uid).setData([
            "publicKey": publicKey,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    func publicKey(uid: String) async throws -> String? {
        try await db.collection("publicKeys").document(uid).getDocument().data()?["publicKey"] as? String
    }

    func publishPreKeyBundle(uid: String, bundle: JSONObject) async throws {
        var data = bundle.anyDictionary
        data["updatedAt"] = FieldValue.serverTimestamp()
        try await db.collection("prekeys").document(uid).setData(data)
    }

    func preKeyBundle(uid: String) async throws -> JSONObject? {
        guard var data = try await db.collection("prekeys").document(uid).getDocument().data() else { return nil }
        data.removeValue(forKey: "updatedAt")
        return JSONObject(any: data)
    }

    func publishDeliveryToken(uid: String, token: String) async throws {
        try await db.collection("deliveryTokens").document(uid).setData([
            "token": token,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Nur `sid`, `mid`, `p` und `ts` — alles Weitere steckt verschlüsselt in `p`.
    @discardableResult
    func send(from: String, to: String, messageId: String, payload: JSONObject) async throws -> String {
        try await db.collection("messages").document(to).collection("inbox").addDocument(data: [
            "sid": from,
            "mid": messageId,
            "p": payload.anyDictionary,
            "ts": FieldValue.serverTimestamp(),
        ]).documentID
    }

    // MARK: Sealed Sender — siehe firestore.rules und Engine+Sealed

    /// Nur der Hash; der Schlüssel selbst reist verschlüsselt zu den Kontakten.
    func publishSealedAccess(uid: String, keyHash: Data) async throws {
        try await db.collection("sealedAccess").document(uid).setData([
            "h": keyHash,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Ohne Anmeldung: `p.s` ist der Umschlag, `p.nt` der Anhänger für die
    /// Mitteilung (die Cloud Function liest ihn wie bisher aus `p`), `ak` der
    /// Zustellschlüssel, den die Regel gegen den Hash prüft.
    @discardableResult
    func sendSealed(to: String, accessKey: Data, envelope: Data, tag: String?) async throws -> String {
        guard let sealedDb else { throw RelayError.accessDenied }
        var p: [String: Any] = ["s": envelope.base64EncodedString()]
        if let tag { p["nt"] = tag }
        do {
            return try await sealedDb.collection("messages").document(to).collection("inbox").addDocument(data: [
                "p": p,
                "ts": FieldValue.serverTimestamp(),
                "ak": accessKey,
            ]).documentID
        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            throw RelayError.accessDenied
        }
    }

    /// Versiegelte Dokumente darf löschen, wer ihren Pfad kennt — also nur
    /// Absender und Empfängerin. Auch das ohne Anmeldung.
    func retractSealed(to: String, docId: String) async throws {
        guard let sealedDb else { return }
        try await sealedDb.collection("messages").document(to).collection("inbox").document(docId).delete()
    }

    func inbox(uid: String) -> AsyncThrowingStream<[InboxEnvelope], Error> {
        AsyncThrowingStream { continuation in
            let registration = db.collection("messages").document(uid).collection("inbox")
                .order(by: "ts")
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let snapshot else { return }
                    let batch = snapshot.documentChanges.compactMap { change -> InboxEnvelope? in
                        guard change.type == .added else { return nil }
                        let data = change.document.data()
                        // Versiegelt: Absender und Kennung stecken im Umschlag.
                        if data["sid"] == nil, let p = data["p"] as? [String: Any], let s = p["s"] as? String {
                            return InboxEnvelope(docId: change.document.documentID, senderId: "", messageId: "", payload: [:],
                                                 sealed: Data(base64Encoded: s) ?? Data())
                        }
                        guard let sid = data["sid"] as? String, let mid = data["mid"] as? String,
                              let p = data["p"] as? [String: Any] else {
                            // Unlesbar: trotzdem als leere Nachricht weiterreichen,
                            // damit die Engine sie vom Server räumt.
                            return InboxEnvelope(docId: change.document.documentID, senderId: "", messageId: "", payload: [:])
                        }
                        return InboxEnvelope(docId: change.document.documentID, senderId: sid, messageId: mid, payload: JSONObject(any: p))
                    }
                    if !batch.isEmpty { continuation.yield(batch) }
                }
            let handle = ListenerHandle(registration)
            continuation.onTermination = { _ in handle.remove() }
        }
    }

    func deleteFromInbox(uid: String, docId: String) async throws {
        try await db.collection("messages").document(uid).collection("inbox").document(docId).delete()
    }

    /// Erlaubt, solange `sid` der eigene ist (firestore.rules). Ist die
    /// Nachricht schon weg, lehnt der Server ab — dann ist nichts zu tun.
    func retract(to: String, docId: String) async throws {
        try await db.collection("messages").document(to).collection("inbox").document(docId).delete()
    }

    // MARK: Key Transparency — nur anlegen, nie ändern (siehe firestore.rules)

    func publishKeyCommitment(uid: String, commitment: JSONObject, epoch: Int) async throws {
        try await db.collection("keyCommitments").document(uid).collection("log").document(String(epoch))
            .setData(commitment.anyDictionary)
    }

    func keyCommitments(uid: String, since: Int?) async throws -> [JSONObject] {
        var query: Query = db.collection("keyCommitments").document(uid).collection("log")
        if let since { query = query.whereField("e", isGreaterThan: since) }
        let snapshot = try await query.order(by: "e").getDocuments()
        return snapshot.documents.map { JSONObject(any: $0.data()) }
    }

    // MARK: Push

    /// Das FCM-Token, an das die Cloud Function die Mitteilungen schickt.
    func registerPushToken(uid: String, token: String) async throws {
        try await db.collection("fcmTokens").document(uid).setData([
            "token": token,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    func deletePushToken(uid: String) async throws {
        try await db.collection("fcmTokens").document(uid).delete()
    }

    /// Alles auf dem Server löschen, dann das Konto. Der Posteingang wird nur
    /// bis zum Start geleert, damit ein Flut-Angreifer die Löschung nicht
    /// endlos am Laufen hält (siehe Dart: deleteAllUserData).
    func deleteAllUserData(uid: String) async throws {
        let cutoff = Timestamp(date: Date())
        let inbox = db.collection("messages").document(uid).collection("inbox")
        for _ in 0..<1000 {
            let page = try await inbox.whereField("ts", isLessThanOrEqualTo: cutoff).order(by: "ts").limit(to: 500).getDocuments()
            if page.documents.isEmpty { break }
            let batch = db.batch()
            page.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            if page.documents.count < 500 { break }
        }
        let log = db.collection("keyCommitments").document(uid).collection("log")
        for _ in 0..<1000 {
            let page = try await log.order(by: FieldPath.documentID()).limit(to: 500).getDocuments()
            if page.documents.isEmpty { break }
            let batch = db.batch()
            page.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            if page.documents.count < 500 { break }
        }
        let batch = db.batch()
        for collection in ["publicKeys", "prekeys", "fcmTokens", "deliveryTokens", "sealedAccess"] {
            batch.deleteDocument(db.collection(collection).document(uid))
        }
        try await batch.commit()
        // Nur das eigene Konto — falls inzwischen schon ein neues angemeldet ist.
        if let user = Auth.auth().currentUser, user.uid == uid {
            try? await user.delete()
            try? Auth.auth().signOut()
        }
    }
}

/// Firestores Listener-Handle ist nicht Sendable; entfernt wird er nur einmal.
private final class ListenerHandle: @unchecked Sendable {
    private let registration: ListenerRegistration
    init(_ registration: ListenerRegistration) { self.registration = registration }
    func remove() { registration.remove() }
}
