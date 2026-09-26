import FirebaseAuth
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
    func send(from: String, to: String, messageId: String, payload: JSONObject) async throws {
        _ = try await db.collection("messages").document(to).collection("inbox").addDocument(data: [
            "sid": from,
            "mid": messageId,
            "p": payload.anyDictionary,
            "ts": FieldValue.serverTimestamp(),
        ])
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
        for collection in ["publicKeys", "prekeys", "fcmTokens", "deliveryTokens"] {
            batch.deleteDocument(db.collection(collection).document(uid))
        }
        try await batch.commit()
        try? await Auth.auth().currentUser?.delete()
        try? Auth.auth().signOut()
    }
}

/// Firestores Listener-Handle ist nicht Sendable; entfernt wird er nur einmal.
private final class ListenerHandle: @unchecked Sendable {
    private let registration: ListenerRegistration
    init(_ registration: ListenerRegistration) { self.registration = registration }
    func remove() { registration.remove() }
}
