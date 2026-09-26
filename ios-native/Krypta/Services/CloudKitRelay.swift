import CloudKit
import Foundation
import KryptaCore
import KryptaMessenger

/// CloudKit als Relay: die öffentliche Datenbank des Containers
/// `iCloud.com.calcchat.ww`. Kein eigener Server und kein Google mehr —
/// Apple stellt Speicher, Anmeldung (der Apple-Account auf dem iPhone) und
/// Push. Schema und Rechte: ios-native/CloudKit/schema.ckdb.
///
/// Was früher Firestore-Sammlungen waren, sind hier Datensatztypen:
///
/// | Firestore                       | CloudKit                                 |
/// |---------------------------------|------------------------------------------|
/// | publicKeys/{uid}                | `PublicKey`, Name `pk-{uid}`             |
/// | prekeys/{uid}                   | `PreKeyBundle`, Name `pb-{uid}`          |
/// | keyCommitments/{uid}/log/{e}    | `KeyCommitment`, Name `kt-{uid}-{e}`     |
/// | messages/{uid}/inbox/{doc}      | `InboxMessage` mit `recipient == uid`    |
/// | fcmTokens/{uid}, Cloud Function | Abo auf `InboxMessage` (`subscribeToInbox`) |
///
/// Rechte vergibt CloudKit nur je Datensatztyp, nicht je Datensatz wie die
/// Firestore-Regeln. Ändern darf einen Eintrag, wer ihn angelegt hat — so
/// gehört `pk-{uid}` dem iCloud-Konto, das die Kennung zuerst veröffentlicht
/// hat. Nur Posteingänge dürfen alle angemeldeten Geräte löschen, sonst
/// könnte die Empfängerin eine abgeholte Nachricht nicht vom Server nehmen.
/// Inhalte bleiben Ende-zu-Ende-verschlüsselt; was CloudKit anders schützt
/// als Firebase, steht in ios-native/CloudKit/README.md.
final class CloudKitRelay: Relay, @unchecked Sendable {
    static let containerIdentifier = "iCloud.com.calcchat.ww"
    /// Erst beim ersten Gebrauch angelegt: ohne passendes Entitlement bricht
    /// CKContainer mit einer Ausnahme ab, und Demo-Modus und UI-Tests
    /// (`-KryptaDemo`, `-KryptaOffline`) sollen iCloud gar nicht berühren.
    static let container = CKContainer(identifier: containerIdentifier)

    enum RecordType {
        static let publicKey = "PublicKey"
        static let preKeyBundle = "PreKeyBundle"
        static let keyCommitment = "KeyCommitment"
        static let inbox = "InboxMessage"
    }

    /// Nie abgeholte Nachrichten verschwinden nach 24 Stunden (wie früher
    /// `cleanupExpiredMessages` in firebase/functions/index.js).
    static let messageLifetime: TimeInterval = 24 * 3600

    private var db: CKDatabase { Self.container.publicCloudDatabase }

    // MARK: Schlüssel

    func publishPublicKey(uid: String, publicKey: String) async throws {
        let record = CKRecord(recordType: RecordType.publicKey, recordID: Self.publicKeyID(uid))
        record["publicKey"] = publicKey as CKRecordValue
        try await upsert(record)
    }

    func publicKey(uid: String) async throws -> String? {
        try await fetch(Self.publicKeyID(uid), type: RecordType.publicKey)?["publicKey"] as? String
    }

    func publishPreKeyBundle(uid: String, bundle: JSONObject) async throws {
        let record = CKRecord(recordType: RecordType.preKeyBundle, recordID: Self.bundleID(uid))
        record["bundle"] = Data(try bundle.jsonString().utf8) as CKRecordValue
        try await upsert(record)
    }

    /// Wer hier etwas unterschiebt, scheitert an der Signatur: das Bündel ist
    /// mit der Identität signiert und wird gegen den hinterlegten Schlüssel
    /// geprüft (SessionHandshake.outbound).
    func preKeyBundle(uid: String) async throws -> JSONObject? {
        guard let data = try await fetch(Self.bundleID(uid), type: RecordType.preKeyBundle)?["bundle"] as? Data else { return nil }
        return try JSONObject.parse(String(decoding: data, as: UTF8.self))
    }

    /// Flutter-Absender holten sich das Token aus Firestore; mit CloudKit gibt
    /// es keine Flutter-Geräte mehr auf demselben Server.
    func publishDeliveryToken(uid: String, token: String) async throws {}

    /// In Firestore prüfte eine Regel den Zustellschlüssel, weil versiegelte
    /// Nachrichten ohne Anmeldung hineinkamen. In CloudKit ist jedes Schreiben
    /// an ein iCloud-Konto gebunden, und eine Regel je Datensatz gibt es nicht —
    /// also nichts zu veröffentlichen. Der Umschlag bleibt trotzdem versiegelt:
    /// Absender und Kennung stehen nicht im Datensatz.
    func publishSealedAccess(uid: String, keyHash: Data) async throws {}

    // MARK: Posteingang

    /// Absender, Kennung und Nutzlast wie früher `sid`, `mid` und `p` in
    /// Firestore; `alert` und `tag` für das Abo der Empfängerin (`inboxRecord`).
    @discardableResult
    func send(from: String, to: String, messageId: String, payload: JSONObject) async throws -> String {
        let record = Self.inboxRecord(to: to, tag: payload["nt"]?.stringValue)
        record["sender"] = from as CKRecordValue
        record["messageId"] = messageId as CKRecordValue
        record["payload"] = Data(try payload.jsonString().utf8) as CKRecordValue
        try await create(record)
        InboxWake.shared.expectReplies()
        return record.recordID.recordName
    }

    /// Nur Empfängerin, Umschlag und Anhänger — wer schreibt, steht im Umschlag.
    @discardableResult
    func sendSealed(to: String, accessKey: Data, envelope: Data, tag: String?) async throws -> String {
        let record = Self.inboxRecord(to: to, tag: tag)
        record["sealed"] = envelope as CKRecordValue
        try await create(record)
        InboxWake.shared.expectReplies()
        return record.recordID.recordName
    }

    func retractSealed(to: String, docId: String) async throws {
        try await deleteInbox(docId)
    }

    /// Neue Nachrichten, jede einmal je Abfrage-Strom — wie ein Snapshot-
    /// Listener, der nur `.added` meldet.
    ///
    /// CloudKit kennt keine Live-Verbindung. Gefragt wird deshalb, solange die
    /// Engine läuft: alle paar Sekunden, sofort bei einer Mitteilung oder wenn
    /// die App nach vorne kommt, und nach dem Senden eine Weile öfter
    /// (`InboxWake`). Im Hintergrund läuft nichts; dann sagt das Abo Bescheid.
    func inbox(uid: String) -> AsyncThrowingStream<[InboxEnvelope], Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                await collectExpired()
                var seen = Set<String>()
                while !Task.isCancelled {
                    let generation = InboxWake.shared.generation
                    do {
                        let records = try await pending(uid: uid)
                        let fresh = records.filter { !seen.contains($0.recordID.recordName) }
                        // Nur merken, was noch auf dem Server liegt.
                        seen = Set(records.map(\.recordID.recordName))
                        if !fresh.isEmpty {
                            InboxWake.shared.expectReplies()
                            continuation.yield(fresh.map(Self.envelope))
                        }
                    } catch let error as CKError where error.retryAfterSeconds != nil {
                        // Zu viele Anfragen oder Dienst kurz weg: CloudKit sagt, wie lange.
                        try? await Task.sleep(for: .seconds(error.retryAfterSeconds ?? 5))
                        continue
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    await InboxWake.shared.wait(since: generation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func deleteFromInbox(uid: String, docId: String) async throws {
        try await deleteInbox(docId)
    }

    func retract(to: String, docId: String) async throws {
        try await deleteInbox(docId)
    }

    // MARK: Key Transparency — nur anlegen, nie ändern

    func publishKeyCommitment(uid: String, commitment: JSONObject, epoch: Int) async throws {
        let record = CKRecord(recordType: RecordType.keyCommitment, recordID: Self.commitmentID(uid, epoch))
        record["uid"] = uid as CKRecordValue
        record["epoch"] = NSNumber(value: epoch)
        record["commitment"] = Data(try commitment.jsonString().utf8) as CKRecordValue
        // Ohne Änderungsmarke: gibt es die Epoche schon, lehnt CloudKit ab.
        try await create(record)
    }

    /// Einträge nach Epoche sortiert. Zählt nur, was unter seinem eigenen
    /// Namen liegt und vom selben iCloud-Konto stammt wie der öffentliche
    /// Schlüssel — sonst könnte jeder einen Eintrag mit fremder `uid` anlegen
    /// und bei den Kontakten einen Widerspruch vortäuschen. Echte Fälschungen
    /// erkennt die Kette ohnehin an den Signaturen.
    func keyCommitments(uid: String, since: Int?) async throws -> [JSONObject] {
        guard let owner = try await fetch(Self.publicKeyID(uid), type: RecordType.publicKey)?.creatorUserRecordID else { return [] }
        let predicate = since.map { NSPredicate(format: "uid == %@ AND epoch > %@", uid, NSNumber(value: $0)) }
            ?? NSPredicate(format: "uid == %@", uid)
        let query = CKQuery(recordType: RecordType.keyCommitment, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "epoch", ascending: true)]
        return try await records(matching: query, limit: 1000).compactMap { record in
            guard let epoch = record["epoch"] as? Int,
                  record.recordID.recordName == Self.commitmentID(uid, epoch).recordName,
                  record.creatorUserRecordID == owner,
                  let data = record["commitment"] as? Data else { return nil }
            return try? JSONObject.parse(String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: Alles löschen

    /// Alles, was zu `uid` gehört. Der Posteingang wird nur bis zum Start
    /// geleert, damit ein Flut-Angreifer die Löschung nicht endlos am Laufen
    /// hält (siehe Dart: deleteAllUserData). Nachrichten an Kontakte bleiben
    /// liegen: darunter ist die Meldung, dass es dieses Konto nicht mehr gibt.
    func deleteAllUserData(uid: String) async throws {
        let cutoff = Date()
        let inbox = CKQuery(recordType: RecordType.inbox,
                            predicate: NSPredicate(format: "recipient == %@ AND creationDate <= %@", uid, cutoff as NSDate))
        for _ in 0..<50 {
            let page = try await records(matching: inbox, limit: 200, desiredKeys: [])
            if page.isEmpty { break }
            try await delete(page.map(\.recordID))
            if page.count < 200 { break }
        }
        // Fremde Einträge mit derselben `uid` gehören nicht uns und bleiben.
        let log = CKQuery(recordType: RecordType.keyCommitment, predicate: NSPredicate(format: "uid == %@", uid))
        let entries = try await records(matching: log, limit: 1000, desiredKeys: ["epoch"]).filter { record in
            (record["epoch"] as? Int).map { record.recordID.recordName == Self.commitmentID(uid, $0).recordName } ?? false
        }
        try await delete(entries.map(\.recordID), ignoring: [.unknownItem, .permissionFailure])
        try await delete([Self.bundleID(uid), Self.publicKeyID(uid)], ignoring: [.unknownItem, .permissionFailure])
        try? await unsubscribeFromInbox()
    }

    // MARK: Push — statt FCM-Token und Cloud Function

    private static let subscriptionPrefix = "inbox-"
    /// Ändert sich das Abo (Text, Felder), bekommt es eine neue Fassung; das
    /// alte räumt `subscribeToInbox` weg.
    private static let subscriptionVersion = "v1"

    /// Ein Abo auf neue Nachrichten an `uid`, die eine Mitteilung wollen
    /// (`alert == 1`). CloudKit schickt sie selbst über APNs: mit festem Text,
    /// dem Anhänger (`tag`) und `mutable-content`, damit die Notification Service
    /// Extension den Namen einsetzt. Von wem die Nachricht kommt, steht nicht
    /// darin — nur der Anhänger, den nur die Empfängerin zuordnen kann.
    func subscribeToInbox(uid: String) async throws {
        let id = "\(Self.subscriptionPrefix)\(Self.subscriptionVersion)-\(uid)"
        let existing = try await db.allSubscriptions().map(\.subscriptionID)
        let stale = existing.filter { $0.hasPrefix(Self.subscriptionPrefix) && $0 != id }
        if !stale.isEmpty { _ = try await db.modifySubscriptions(saving: [], deleting: stale) }
        guard !existing.contains(id) else { return }

        let subscription = CKQuerySubscription(
            recordType: RecordType.inbox,
            predicate: NSPredicate(format: "recipient == %@ AND alert == 1", uid),
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertLocalizationKey = PushPayload.coverKey
        info.soundName = "default"
        info.shouldSendMutableContent = true
        info.desiredKeys = ["tag"]
        subscription.notificationInfo = info
        _ = try await db.save(subscription)
    }

    func unsubscribeFromInbox() async throws {
        let ids = try await db.allSubscriptions().map(\.subscriptionID).filter { $0.hasPrefix(Self.subscriptionPrefix) }
        if !ids.isEmpty { _ = try await db.modifySubscriptions(saving: [], deleting: ids) }
    }

    // MARK: - Intern

    private static func publicKeyID(_ uid: String) -> CKRecord.ID { CKRecord.ID(recordName: "pk-\(uid)") }
    private static func bundleID(_ uid: String) -> CKRecord.ID { CKRecord.ID(recordName: "pb-\(uid)") }
    private static func commitmentID(_ uid: String, _ epoch: Int) -> CKRecord.ID { CKRecord.ID(recordName: "kt-\(uid)-\(epoch)") }

    /// `alert` entscheidet wie früher `pushPlan` in der Cloud Function, ob
    /// das Abo eine Mitteilung schickt: ein leerer Anhänger (Steuernachricht:
    /// zugestellt, gelesen …) heißt still, ohne Anhänger (Anfrage ohne
    /// Schlüssel) gibt es den neutralen Text. `tag` reist in der Mitteilung mit.
    private static func inboxRecord(to: String, tag: String?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.inbox, recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["recipient"] = to as CKRecordValue
        record["alert"] = NSNumber(value: tag == NotificationTag.quiet ? 0 : 1)
        if let tag, !tag.isEmpty { record["tag"] = tag as CKRecordValue }
        return record
    }

    private static func envelope(_ record: CKRecord) -> InboxEnvelope {
        let docId = record.recordID.recordName
        // Versiegelt: Absender und Kennung stecken im Umschlag.
        if record["sender"] == nil, let sealed = record["sealed"] as? Data {
            return InboxEnvelope(docId: docId, senderId: "", messageId: "", payload: [:], sealed: sealed)
        }
        guard let sid = record["sender"] as? String, let mid = record["messageId"] as? String,
              let data = record["payload"] as? Data,
              let payload = try? JSONObject.parse(String(decoding: data, as: UTF8.self)) else {
            // Unlesbar: trotzdem als leere Nachricht weiterreichen, damit die
            // Engine sie vom Server räumt.
            return InboxEnvelope(docId: docId, senderId: "", messageId: "", payload: [:])
        }
        return InboxEnvelope(docId: docId, senderId: sid, messageId: mid, payload: payload)
    }

    private func pending(uid: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: RecordType.inbox, predicate: NSPredicate(format: "recipient == %@", uid))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return try await records(matching: query, limit: 400)
    }

    /// Was nie abgeholt wurde, verschwindet nach 24 Stunden. Einen Server,
    /// der das stündlich erledigt, gibt es nicht mehr — also räumt jedes Gerät
    /// beim Öffnen des Posteingangs auf, höchstens einmal pro Stunde.
    private func collectExpired() async {
        let key = "cloudkit.expired.last"
        let now = Date().timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: key) > 3600 else { return }
        UserDefaults.standard.set(now, forKey: key)
        let cutoff = Date().addingTimeInterval(-Self.messageLifetime)
        let query = CKQuery(recordType: RecordType.inbox, predicate: NSPredicate(format: "creationDate < %@", cutoff as NSDate))
        guard let expired = try? await records(matching: query, limit: 200, desiredKeys: []), !expired.isEmpty else { return }
        try? await delete(expired.map(\.recordID), ignoring: [.unknownItem, .permissionFailure])
    }

    private func deleteInbox(_ docId: String) async throws {
        guard !docId.isEmpty else { return }
        try await delete([CKRecord.ID(recordName: docId)])
    }

    /// Ein Datensatz nach Name; `nil`, wenn es ihn nicht gibt — oder wenn
    /// unter dem Namen etwas anderes liegt (Namen gelten über alle Typen).
    private func fetch(_ id: CKRecord.ID, type: CKRecord.RecordType) async throws -> CKRecord? {
        do {
            let record = try await db.record(for: id)
            return record.recordType == type ? record : nil
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Anlegen oder überschreiben. Überschreiben darf nur das iCloud-Konto,
    /// das den Eintrag angelegt hat.
    private func upsert(_ record: CKRecord) async throws {
        let result = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
        _ = try result.saveResults[record.recordID]?.get()
    }

    /// Nur anlegen: ein neuer Datensatz ohne Änderungsmarke scheitert, wenn
    /// der Name schon vergeben ist.
    private func create(_ record: CKRecord) async throws {
        _ = try await db.save(record)
    }

    private func delete(_ ids: [CKRecord.ID], ignoring ignored: Set<CKError.Code> = [.unknownItem]) async throws {
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            let result = try await db.modifyRecords(saving: [], deleting: chunk, savePolicy: .ifServerRecordUnchanged, atomically: false)
            for (_, outcome) in result.deleteResults {
                if case .failure(let error) = outcome {
                    if let code = (error as? CKError)?.code, ignored.contains(code) { continue }
                    throw error
                }
            }
        }
    }

    /// Alle Treffer einer Abfrage, höchstens `limit`.
    private func records(matching query: CKQuery, limit: Int, desiredKeys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord] {
        var found: [CKRecord] = []
        var page = try await db.records(matching: query, inZoneWith: nil, desiredKeys: desiredKeys, resultsLimit: min(limit, 200))
        while true {
            for (_, outcome) in page.matchResults {
                if case .success(let record) = outcome { found.append(record) }
            }
            guard let cursor = page.queryCursor, found.count < limit else { return found }
            page = try await db.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys, resultsLimit: min(limit - found.count, 200))
        }
    }
}

/// Weckt die Abfrage des Posteingangs vor der Zeit: eine Mitteilung kam an,
/// die App ist wieder vorne — oder eben ging etwas hin und her, dann kommen
/// gleich Zustell- und Lesemeldungen, und es wird eine Weile öfter gefragt.
final class InboxWake: @unchecked Sendable {
    static let shared = InboxWake()

    static let idleInterval: TimeInterval = 5
    static let busyInterval: TimeInterval = 1.5
    static let busyPeriod: TimeInterval = 20

    private let lock = NSLock()
    private var counter = 0
    private var busyUntil = Date.distantPast

    var generation: Int { lock.withLock { counter } }

    /// Sofort nachsehen.
    func poke() { lock.withLock { counter += 1 } }

    /// Gleich kommt vermutlich etwas zurück.
    func expectReplies() { lock.withLock { busyUntil = Date().addingTimeInterval(Self.busyPeriod) } }

    /// Bis zum nächsten Takt warten, oder bis jemand weckt.
    func wait(since generation: Int) async {
        let busy = lock.withLock { Date() < busyUntil }
        let deadline = Date().addingTimeInterval(busy ? Self.busyInterval : Self.idleInterval)
        while Date() < deadline, self.generation == generation, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
