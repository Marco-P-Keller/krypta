import Foundation

/// Schutz gegen Wiedereinspielen (`_seq`) und Sitzungs-Rollback (`_psid`)
/// in entschlüsselten v3-Nutzlasten — wie security/ratchet/replay_guard.dart.
public enum ReplayGuard {
    public enum Rejection: String, Error, Equatable {
        case replaySeq = "REPLAY_SEQ"
        case rollbackPsid = "ROLLBACK_PSID"
        case seqTooOld = "SEQ_TOO_OLD"
    }

    public static let seqWindow = 200

    /// Liefert den fortgeschriebenen Zustand oder wirft die Ablehnung.
    /// Nutzlasten ohne `_seq` (alte v3-Absender) laufen unverändert durch.
    public static func validate(state: RatchetState, inner: JSONObject, version: Int) throws -> RatchetState {
        guard version >= 3, case .int(let seq)? = inner["_seq"] else { return state }

        if state.recentRecvSeqs.contains(seq) { throw Rejection.replaySeq }
        if seq < state.highestRecvSeq - seqWindow { throw Rejection.seqTooOld }

        let psid = seq == 0 ? inner["_psid"]?.stringValue : nil
        if let psid, state.peerSeenPsids.contains(psid) { throw Rejection.rollbackPsid }

        var s = state
        let highest = max(seq, state.highestRecvSeq)
        s.highestRecvSeq = highest
        s.recentRecvSeqs = state.recentRecvSeqs.union([seq]).filter { $0 >= highest - seqWindow }
        if let psid { s.peerSeenPsids.insert(psid) }
        return s
    }
}
