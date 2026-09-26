import Foundation

/// Die Schlüssel einer Wallet nach BIP84 (native Segwit, bc1q…):
/// m/84'/c'/0'/k/i mit c = 0 (Bitcoin) oder 1 (Testnetze), k = 0 für
/// Empfang und 1 für Wechselgeld.
public enum WalletKeys {
    public enum Chain: UInt32, Codable, Sendable {
        case receive = 0
        case change = 1
    }

    public static func accountPath(_ network: BitcoinNetwork) -> [UInt32] {
        [84 | HD.hardened, network.coinType | HD.hardened, HD.hardened]
    }

    /// Öffentlicher Kontoschlüssel. Braucht den Seed nur einmal (beim
    /// Anlegen); danach entstehen alle Adressen ohne Geheimnis.
    public static func account(seed: [UInt8], network: BitcoinNetwork) throws -> ExtendedPublicKey {
        try ExtendedPrivateKey.master(seed: seed).derive(accountPath(network)).publicKey
    }

    public static func address(account: ExtendedPublicKey, chain: Chain, index: UInt32, network: BitcoinNetwork) throws -> BitcoinAddress {
        let key = try account.child(chain.rawValue).child(index)
        return BitcoinAddress.p2wpkh(publicKey: key.publicKey, network: network)
    }

    /// Öffentlicher Schlüssel einer Adresse (für den Zeugen beim Signieren).
    public static func publicKey(account: ExtendedPublicKey, chain: Chain, index: UInt32) throws -> [UInt8] {
        try account.child(chain.rawValue).child(index).publicKey
    }
}

/// Wo eine eigene Adresse im Baum hängt.
public struct AddressPath: Hashable, Codable, Sendable {
    public let chain: WalletKeys.Chain
    public let index: UInt32

    public init(chain: WalletKeys.Chain, index: UInt32) {
        self.chain = chain
        self.index = index
    }
}

/// Signiert eine fertig geplante Transaktion.
///
/// Prüft vorher, dass jede Eingabe wirklich zu dieser Wallet gehört (das
/// Ausgabeskript passt zum abgeleiteten Schlüssel), und nachher jede
/// Signatur einzeln. Ein Fehler irgendwo heißt: gar nichts wird signiert.
public enum TransactionSigner {
    public struct Input: Sendable {
        public let outPoint: OutPoint
        public let value: Int64
        public let scriptPubKey: [UInt8]
        public let path: AddressPath

        public init(outPoint: OutPoint, value: Int64, scriptPubKey: [UInt8], path: AddressPath) {
            self.outPoint = outPoint
            self.value = value
            self.scriptPubKey = scriptPubKey
            self.path = path
        }
    }

    public static func sign(_ unsigned: Transaction, inputs: [Input], seed: [UInt8], network: BitcoinNetwork) throws -> Transaction {
        guard unsigned.inputs.count == inputs.count,
              zip(unsigned.inputs, inputs).allSatisfy({ $0.outPoint == $1.outPoint }) else { throw BitcoinError.signingFailed }
        let account = try ExtendedPrivateKey.master(seed: seed).derive(WalletKeys.accountPath(network))
        let chains: [WalletKeys.Chain: ExtendedPrivateKey] = [
            .receive: try account.child(WalletKeys.Chain.receive.rawValue),
            .change: try account.child(WalletKeys.Chain.change.rawValue),
        ]
        var tx = unsigned
        for (i, input) in inputs.enumerated() {
            guard let chain = chains[input.path.chain] else { throw BitcoinError.signingFailed }
            let node = try chain.child(input.path.index)
            let publicKey = try node.publicKey.publicKey
            guard input.scriptPubKey == [0x00, 0x14] + Hashes.hash160(publicKey) else { throw BitcoinError.signingFailed }
            let digest = tx.segwitSighash(inputIndex: i, scriptCode: Transaction.p2wpkhScriptCode(publicKey: publicKey), amount: input.value)
            let signature = try node.withPrivateKey { try Secp256k1.signECDSA(digest: digest, privateKey: $0) }
            tx.inputs[i].scriptSig = []
            tx.inputs[i].witness = [signature + [0x01], publicKey]
        }
        try verify(tx, inputs: inputs)
        return tx
    }

    /// Jede Eingabe: Zeuge hat die erwartete Form, Signatur passt zum
    /// Schlüssel und zum Sighash, Schlüssel passt zum Skript.
    public static func verify(_ tx: Transaction, inputs: [Input]) throws {
        guard tx.inputs.count == inputs.count else { throw BitcoinError.signingFailed }
        for (i, input) in inputs.enumerated() {
            let witness = tx.inputs[i].witness
            guard witness.count == 2, witness[1].count == 33, let last = witness[0].last, last == 0x01,
                  input.scriptPubKey == [0x00, 0x14] + Hashes.hash160(witness[1]),
                  tx.inputs[i].scriptSig.isEmpty else { throw BitcoinError.signingFailed }
            let digest = tx.segwitSighash(inputIndex: i, scriptCode: Transaction.p2wpkhScriptCode(publicKey: witness[1]), amount: input.value)
            guard Secp256k1.verifyECDSA(signature: Array(witness[0].dropLast()), digest: digest, publicKey: witness[1]) else {
                throw BitcoinError.signingFailed
            }
        }
    }
}
