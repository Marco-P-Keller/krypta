import Foundation
import KryptaBitcoin
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AddressStats: Equatable, Codable, Sendable {
    /// Transaktionen insgesamt, bestätigt und im Mempool.
    public let txCount: Int
    /// Davon im Mempool.
    public let pendingCount: Int
    public let funded: Int64
    public let spent: Int64

    public init(txCount: Int, pendingCount: Int, funded: Int64, spent: Int64) {
        self.txCount = txCount
        self.pendingCount = pendingCount
        self.funded = funded
        self.spent = spent
    }

    public var balance: Int64 { funded - spent }
}

public struct ChainUTXO: Equatable, Sendable {
    public let txid: String
    public let vout: UInt32
    public let value: Int64
    public let height: Int?
}

public struct ChainTxOutput: Equatable, Sendable {
    public let script: [UInt8]
    public let value: Int64
}

public struct ChainTx: Equatable, Sendable {
    public let txid: String
    /// Die ausgegebenen Ausgaben (Skript und Wert), in Reihenfolge der Eingänge.
    public let prevouts: [ChainTxOutput]
    public let outputs: [ChainTxOutput]
    public let fee: Int64?
    public let height: Int?
    public let blockTime: Date?
}

public struct TxStatus: Equatable, Sendable {
    public let confirmed: Bool
    public let height: Int?
    public let blockHash: String?
}

public struct MerkleProofData: Equatable, Sendable {
    public let height: Int
    public let siblings: [String]
    public let position: Int
}

public enum ChainError: Error, Equatable, Sendable {
    /// Kein Netz, Zeitüberschreitung: ob der Server etwas bekam, ist offen.
    case unreachable
    case notFound
    /// Der Server lehnt ab (z. B. eine Transaktion): sicher nicht angenommen.
    case rejected(String)
    case invalidResponse
    case rateLimited
}

/// Woher die Wallet ihr Wissen über die Blockchain hat. In der App eine
/// Esplora-Schnittstelle (mempool.space oder ein eigener Server), in Tests
/// eine Kette im Speicher.
///
/// Der Server sieht, welche Adressen abgefragt werden, und kann lügen oder
/// schweigen. Lügen bringt ihm wenig: Beträge stehen in jeder Signatur
/// (BIP143), eingehende Zahlungen prüft die Wallet an der rohen
/// Transaktion, Bestätigungen am Merkle-Beweis samt Blockarbeit.
public protocol ChainSource: Sendable {
    func tipHeight() async throws -> Int
    func addressStats(_ address: String) async throws -> AddressStats
    func utxos(_ address: String) async throws -> [ChainUTXO]
    func transactions(_ address: String) async throws -> [ChainTx]
    func rawTransaction(_ txid: String) async throws -> [UInt8]
    func status(_ txid: String) async throws -> TxStatus
    /// Wer eine Ausgabe ausgegeben hat (`nil`: niemand, auch nicht im Mempool).
    func spender(of outPoint: OutPoint) async throws -> String?
    func merkleProof(_ txid: String) async throws -> MerkleProofData
    func blockHeader(_ hash: String) async throws -> [UInt8]
    func feeEstimates() async throws -> [Int: Double]
    /// Gibt die Kennung zurück, die der Server errechnet hat.
    func broadcast(_ raw: [UInt8]) async throws -> String
    /// Kurse (Währung → Preis je BTC); nur zur Anzeige.
    func prices() async throws -> [String: Double]
}

/// Esplora-REST (Blockstream, mempool.space, eigener Server).
public final class EsploraClient: ChainSource, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let pacer: RequestPacer?
    static let maxResponse = 4_000_000
    /// So oft wird eine mit 429 abgewiesene Anfrage noch einmal geschickt.
    static let rateLimitRetries = 3

    /// `pacer`: für öffentliche Server (`RequestPacer.publicServer`); ein
    /// eigener Knoten braucht keinen.
    public init(baseURL: URL, pacer: RequestPacer? = nil) {
        self.pacer = pacer
        // Relative Pfade brauchen den Schrägstrich am Ende („…/api/").
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/") ?? baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Krypta"]
        session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    /// Wird die Anfrage wegen zu vieler Anfragen abgewiesen (429), kam sie
    /// beim Server nicht an (nginx lehnt vor dem Weiterreichen ab). Also warten
    /// und dieselbe Anfrage noch einmal schicken, auch eine Sendung.
    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var attempt = 0
        while true {
            await pacer?.acquire()
            do {
                return try await send(path, method: method, body: body)
            } catch RateLimited.wait(let hint) where attempt < Self.rateLimitRetries {
                attempt += 1
                let delay = min(15, hint ?? 2 * Double(attempt))
                if let pacer {
                    await pacer.pause(seconds: delay)
                } else {
                    try await Task.sleep(for: .seconds(delay))
                }
            } catch RateLimited.wait {
                throw ChainError.rateLimited
            }
        }
    }

    private enum RateLimited: Error { case wait(Double?) }

    private func send(_ path: String, method: String, body: Data?) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("text/plain", forHTTPHeaderField: "Content-Type") }
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, response, error in
                if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: error ?? ChainError.unreachable)
                }
            }.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw ChainError.invalidResponse }
        guard data.count <= Self.maxResponse else { throw ChainError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw ChainError.notFound
        case 429: throw RateLimited.wait(http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        case 400..<500: throw ChainError.rejected(String(decoding: data.prefix(300), as: UTF8.self))
        default: throw ChainError.unreachable
        }
    }

    private func requestMapped(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        do {
            return try await request(path, method: method, body: body)
        } catch let error as ChainError {
            throw error
        } catch {
            throw ChainError.unreachable
        }
    }

    private func json(_ path: String) async throws -> Any {
        let data = try await requestMapped(path)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw ChainError.invalidResponse }
        return obj
    }

    private func text(_ path: String) async throws -> String {
        String(decoding: try await requestMapped(path), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func checkedAddress(_ address: String) throws -> String {
        guard !address.isEmpty, address.count <= 100, address.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw ChainError.invalidResponse
        }
        return address
    }

    static func checkedTxid(_ txid: String) throws -> String {
        guard OutPoint.isTxid(txid) else { throw ChainError.invalidResponse }
        return txid.lowercased()
    }

    public func tipHeight() async throws -> Int {
        guard let h = Int(try await text("blocks/tip/height")), h >= 0 else { throw ChainError.invalidResponse }
        return h
    }

    public func addressStats(_ address: String) async throws -> AddressStats {
        guard let obj = try await json("address/\(Self.checkedAddress(address))") as? [String: Any],
              let chain = obj["chain_stats"] as? [String: Any], let pool = obj["mempool_stats"] as? [String: Any] else {
            throw ChainError.invalidResponse
        }
        func n(_ m: [String: Any], _ k: String) -> Int64 { (m[k] as? NSNumber)?.int64Value ?? 0 }
        return AddressStats(
            txCount: Int(n(chain, "tx_count") + n(pool, "tx_count")),
            pendingCount: Int(n(pool, "tx_count")),
            funded: n(chain, "funded_txo_sum") + n(pool, "funded_txo_sum"),
            spent: n(chain, "spent_txo_sum") + n(pool, "spent_txo_sum")
        )
    }

    public func utxos(_ address: String) async throws -> [ChainUTXO] {
        guard let list = try await json("address/\(Self.checkedAddress(address))/utxo") as? [[String: Any]] else { throw ChainError.invalidResponse }
        return try list.map { u in
            guard let txid = u["txid"] as? String, OutPoint.isTxid(txid),
                  let vout = (u["vout"] as? NSNumber)?.uint32Value,
                  let value = (u["value"] as? NSNumber)?.int64Value, value > 0, value <= BitcoinAmount.maxSats else {
                throw ChainError.invalidResponse
            }
            let status = u["status"] as? [String: Any]
            let confirmed = (status?["confirmed"] as? Bool) == true
            return ChainUTXO(txid: txid.lowercased(), vout: vout, value: value,
                             height: confirmed ? (status?["block_height"] as? NSNumber)?.intValue : nil)
        }
    }

    public func transactions(_ address: String) async throws -> [ChainTx] {
        guard let list = try await json("address/\(Self.checkedAddress(address))/txs") as? [[String: Any]] else { throw ChainError.invalidResponse }
        return try list.map(Self.parseTx)
    }

    static func parseTx(_ t: [String: Any]) throws -> ChainTx {
        guard let txid = t["txid"] as? String, OutPoint.isTxid(txid),
              let vin = t["vin"] as? [[String: Any]], let vout = t["vout"] as? [[String: Any]] else { throw ChainError.invalidResponse }
        func output(_ o: [String: Any]?) -> ChainTxOutput? {
            guard let o, let hex = o["scriptpubkey"] as? String, let script = [UInt8](hex: hex),
                  let value = (o["value"] as? NSNumber)?.int64Value else { return nil }
            return ChainTxOutput(script: script, value: value)
        }
        let status = t["status"] as? [String: Any]
        let confirmed = (status?["confirmed"] as? Bool) == true
        return ChainTx(
            txid: txid.lowercased(),
            prevouts: vin.map { output($0["prevout"] as? [String: Any]) ?? ChainTxOutput(script: [], value: 0) },
            outputs: try vout.map { guard let o = output($0) else { throw ChainError.invalidResponse }; return o },
            fee: (t["fee"] as? NSNumber)?.int64Value,
            height: confirmed ? (status?["block_height"] as? NSNumber)?.intValue : nil,
            blockTime: confirmed ? ((status?["block_time"] as? NSNumber)?.doubleValue).map(Date.init(timeIntervalSince1970:)) : nil
        )
    }

    public func rawTransaction(_ txid: String) async throws -> [UInt8] {
        guard let raw = [UInt8](hex: try await text("tx/\(Self.checkedTxid(txid))/hex")) else { throw ChainError.invalidResponse }
        return raw
    }

    public func status(_ txid: String) async throws -> TxStatus {
        guard let s = try await json("tx/\(Self.checkedTxid(txid))/status") as? [String: Any] else { throw ChainError.invalidResponse }
        let confirmed = (s["confirmed"] as? Bool) == true
        return TxStatus(confirmed: confirmed, height: (s["block_height"] as? NSNumber)?.intValue, blockHash: s["block_hash"] as? String)
    }

    public func spender(of outPoint: OutPoint) async throws -> String? {
        guard let o = try await json("tx/\(Self.checkedTxid(outPoint.txid))/outspend/\(outPoint.vout)") as? [String: Any] else {
            throw ChainError.invalidResponse
        }
        guard (o["spent"] as? Bool) == true else { return nil }
        guard let txid = o["txid"] as? String, OutPoint.isTxid(txid) else { throw ChainError.invalidResponse }
        return txid.lowercased()
    }

    public func merkleProof(_ txid: String) async throws -> MerkleProofData {
        guard let p = try await json("tx/\(Self.checkedTxid(txid))/merkle-proof") as? [String: Any],
              let height = (p["block_height"] as? NSNumber)?.intValue, let merkle = p["merkle"] as? [String],
              let pos = (p["pos"] as? NSNumber)?.intValue else { throw ChainError.invalidResponse }
        return MerkleProofData(height: height, siblings: merkle, position: pos)
    }

    public func blockHeader(_ hash: String) async throws -> [UInt8] {
        guard let raw = [UInt8](hex: try await text("block/\(Self.checkedTxid(hash))/header")), raw.count == 80 else { throw ChainError.invalidResponse }
        return raw
    }

    public func feeEstimates() async throws -> [Int: Double] {
        guard let map = try await json("fee-estimates") as? [String: Any] else { throw ChainError.invalidResponse }
        var out: [Int: Double] = [:]
        for (k, v) in map {
            if let target = Int(k), let rate = (v as? NSNumber)?.doubleValue { out[target] = rate }
        }
        return out
    }

    public func broadcast(_ raw: [UInt8]) async throws -> String {
        let txid = try await text("tx", method: "POST", body: Data(raw.hex.utf8))
        guard OutPoint.isTxid(txid) else { throw ChainError.invalidResponse }
        return txid.lowercased()
    }

    private func text(_ path: String, method: String, body: Data) async throws -> String {
        String(decoding: try await requestMapped(path, method: method, body: body), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// mempool.space: `/api/v1/prices`. Andere Esplora-Server haben das nicht.
    public func prices() async throws -> [String: Double] {
        guard let map = try await json("v1/prices") as? [String: Any] else { throw ChainError.invalidResponse }
        var out: [String: Double] = [:]
        for (k, v) in map where k.count == 3 && k != "time" {
            if let price = (v as? NSNumber)?.doubleValue, price > 0 { out[k] = price }
        }
        return out
    }
}
