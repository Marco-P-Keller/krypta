import Foundation

/// Verweis auf eine Ausgabe: Transaktion und Position.
public struct OutPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Kennung in der Schreibweise von Block-Explorern (umgedrehte Bytes).
    public let txid: String
    public let vout: UInt32

    public init(txid: String, vout: UInt32) throws {
        guard Self.isTxid(txid) else { throw BitcoinError.invalidTransaction("txid") }
        self.txid = txid.lowercased()
        self.vout = vout
    }

    init(internalTxid bytes: [UInt8], vout: UInt32) {
        txid = Array(bytes.reversed()).hex
        self.vout = vout
    }

    /// Die 32 Bytes, wie sie in der Transaktion stehen.
    var internalTxid: [UInt8] { Array([UInt8](hex: txid)!.reversed()) }

    public var description: String { "\(txid):\(vout)" }

    public static func isTxid(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }
    }
}

public struct TxInput: Equatable, Sendable {
    public var outPoint: OutPoint
    public var scriptSig: [UInt8]
    public var sequence: UInt32
    public var witness: [[UInt8]]

    public init(outPoint: OutPoint, scriptSig: [UInt8] = [], sequence: UInt32, witness: [[UInt8]] = []) {
        self.outPoint = outPoint
        self.scriptSig = scriptSig
        self.sequence = sequence
        self.witness = witness
    }
}

public struct TxOutput: Equatable, Hashable, Sendable {
    public var value: Int64
    public var scriptPubKey: [UInt8]

    public init(value: Int64, scriptPubKey: [UInt8]) {
        self.value = value
        self.scriptPubKey = scriptPubKey
    }

    func serialized() -> [UInt8] {
        var out = [UInt8]()
        out.appendLE(value)
        out.appendVarBytes(scriptPubKey)
        return out
    }
}

/// Eine Bitcoin-Transaktion im Format von Bitcoin Core (BIP144 mit Zeugen).
public struct Transaction: Equatable, Sendable {
    public var version: Int32
    public var inputs: [TxInput]
    public var outputs: [TxOutput]
    public var lockTime: UInt32

    public init(version: Int32 = 2, inputs: [TxInput], outputs: [TxOutput], lockTime: UInt32 = 0) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.lockTime = lockTime
    }

    public var hasWitness: Bool { inputs.contains { !$0.witness.isEmpty } }

    public func serialized(includeWitness: Bool = true) -> [UInt8] {
        let witness = includeWitness && hasWitness
        var out = [UInt8]()
        out.appendLE(version)
        if witness { out.append(contentsOf: [0x00, 0x01]) }
        out.appendVarInt(UInt64(inputs.count))
        for input in inputs {
            out.append(contentsOf: input.outPoint.internalTxid)
            out.appendLE(input.outPoint.vout)
            out.appendVarBytes(input.scriptSig)
            out.appendLE(input.sequence)
        }
        out.appendVarInt(UInt64(outputs.count))
        for output in outputs { out.append(contentsOf: output.serialized()) }
        if witness {
            for input in inputs {
                out.appendVarInt(UInt64(input.witness.count))
                for item in input.witness { out.appendVarBytes(item) }
            }
        }
        out.appendLE(lockTime)
        return out
    }

    /// Kennung wie im Block-Explorer: SHA-256² ohne Zeugen, umgedreht.
    public var txid: String { Array(Hashes.hash256(serialized(includeWitness: false)).reversed()).hex }

    /// Gewicht nach BIP141: Grunddaten vierfach, Zeugen einfach.
    public var weight: Int {
        let base = serialized(includeWitness: false).count
        let total = serialized(includeWitness: true).count
        return base * 3 + total
    }

    public var virtualSize: Int { (weight + 3) / 4 }

    /// Liest eine Transaktion aus dem Netz. Wirft bei allem, was nicht exakt
    /// passt: überzählige Bytes, unmögliche Anzahlen, leere Zeugen-Markierung.
    public static func parse(_ bytes: [UInt8]) throws -> Transaction {
        guard bytes.count >= 10, bytes.count <= 4_000_000 else { throw BitcoinError.invalidTransaction("Größe") }
        var r = ByteReader(bytes)
        let version = Int32(bitPattern: try r.readLE(UInt32.self))
        var inputCount = try r.readVarInt()
        var hasWitness = false
        if inputCount == 0 {
            // Markierung 0x00 0x01: es folgen Zeugen.
            guard try r.readByte() == 0x01 else { throw BitcoinError.invalidTransaction("Markierung") }
            hasWitness = true
            inputCount = try r.readVarInt()
        }
        guard inputCount > 0, inputCount <= UInt64(r.remaining / 41) else { throw BitcoinError.invalidTransaction("Eingänge") }
        var inputs = [TxInput]()
        for _ in 0..<inputCount {
            let txid = try r.read(32)
            let vout = try r.readLE(UInt32.self)
            let script = try r.readVarBytes()
            let sequence = try r.readLE(UInt32.self)
            inputs.append(TxInput(outPoint: OutPoint(internalTxid: txid, vout: vout), scriptSig: script, sequence: sequence))
        }
        let outputCount = try r.readVarInt()
        guard outputCount <= UInt64(r.remaining / 9) else { throw BitcoinError.invalidTransaction("Ausgänge") }
        var outputs = [TxOutput]()
        for _ in 0..<outputCount {
            let value = Int64(bitPattern: try r.readLE(UInt64.self))
            guard value >= 0, value <= BitcoinAmount.maxSats else { throw BitcoinError.invalidTransaction("Betrag") }
            outputs.append(TxOutput(value: value, scriptPubKey: try r.readVarBytes()))
        }
        if hasWitness {
            for i in inputs.indices {
                let n = try r.readVarInt()
                guard n <= UInt64(r.remaining) else { throw BitcoinError.invalidTransaction("Zeugen") }
                for _ in 0..<n { inputs[i].witness.append(try r.readVarBytes()) }
            }
            guard inputs.contains(where: { !$0.witness.isEmpty }) else { throw BitcoinError.invalidTransaction("leere Zeugen") }
        }
        let lockTime = try r.readLE(UInt32.self)
        guard r.isAtEnd else { throw BitcoinError.invalidTransaction("Überhang") }
        return Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
    }

    // MARK: - Signatur-Hash (BIP143)

    /// SIGHASH_ALL für eine Segwit-v0-Eingabe. `scriptCode` ist bei P2WPKH
    /// das P2PKH-Skript des Schlüssels; `amount` der Wert der ausgegebenen
    /// Ausgabe. Weil der Betrag mit unterschrieben wird, kann ein Server,
    /// der über Beträge lügt, keine höhere Gebühr erschleichen: die
    /// Signatur wäre ungültig.
    public func segwitSighash(inputIndex: Int, scriptCode: [UInt8], amount: Int64, sighashType: UInt32 = 1) -> [UInt8] {
        precondition(inputs.indices.contains(inputIndex) && sighashType == 1)
        var prevouts = [UInt8](), sequences = [UInt8](), outs = [UInt8]()
        for input in inputs {
            prevouts.append(contentsOf: input.outPoint.internalTxid)
            prevouts.appendLE(input.outPoint.vout)
            sequences.appendLE(input.sequence)
        }
        for output in outputs { outs.append(contentsOf: output.serialized()) }

        let input = inputs[inputIndex]
        var preimage = [UInt8]()
        preimage.appendLE(version)
        preimage.append(contentsOf: Hashes.hash256(prevouts))
        preimage.append(contentsOf: Hashes.hash256(sequences))
        preimage.append(contentsOf: input.outPoint.internalTxid)
        preimage.appendLE(input.outPoint.vout)
        preimage.appendVarBytes(scriptCode)
        preimage.appendLE(amount)
        preimage.appendLE(input.sequence)
        preimage.append(contentsOf: Hashes.hash256(outs))
        preimage.appendLE(lockTime)
        preimage.appendLE(sighashType)
        return Hashes.hash256(preimage)
    }

    /// Das scriptCode einer P2WPKH-Eingabe: OP_DUP OP_HASH160 <20> OP_EQUALVERIFY OP_CHECKSIG.
    public static func p2wpkhScriptCode(publicKey: [UInt8]) -> [UInt8] {
        [0x76, 0xA9, 0x14] + Hashes.hash160(publicKey) + [0x88, 0xAC]
    }
}
