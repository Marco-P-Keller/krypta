import Foundation
import XCTest
@testable import KryptaBitcoin

/// Transaktionen: Format, Signatur-Hash (BIP143), Signieren, Münzauswahl,
/// Merkle-Beweise.
final class TransactionTests: XCTestCase {
    // BIP143, „Native P2WPKH".
    let unsignedHex = "0100000002fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f0000000000eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac11000000"
    let signedHex = "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000"

    func testBIP143NativeP2WPKH() throws {
        let unsigned = try Transaction.parse(XCTUnwrap([UInt8](hex: unsignedHex)))
        XCTAssertEqual(unsigned.serialized().hex, unsignedHex)
        XCTAssertEqual(unsigned.inputs.count, 2)
        XCTAssertEqual(unsigned.lockTime, 17)

        let privateKey = try XCTUnwrap([UInt8](hex: "619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"))
        let publicKey = try Secp256k1.publicKey(privateKey: privateKey)
        XCTAssertEqual(publicKey.hex, "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357")
        XCTAssertEqual(Transaction.p2wpkhScriptCode(publicKey: publicKey).hex, "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac")

        let sighash = unsigned.segwitSighash(inputIndex: 1, scriptCode: Transaction.p2wpkhScriptCode(publicKey: publicKey), amount: 600_000_000)
        XCTAssertEqual(sighash.hex, "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670")

        // RFC 6979 wie Bitcoin Core damals: dieselbe Signatur wie im BIP.
        let signature = try Secp256k1.signECDSA(digest: sighash, privateKey: privateKey)
        XCTAssertEqual(signature.hex, "304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee")

        let signed = try Transaction.parse(XCTUnwrap([UInt8](hex: signedHex)))
        XCTAssertEqual(signed.serialized().hex, signedHex, "Parsen und Schreiben sind verlustfrei")
        XCTAssertEqual(signed.inputs[1].witness.map(\.hex), [signature.hex + "01", publicKey.hex])
        // Die Kennung hängt nicht an den Zeugen: ohne sie gerechnet.
        var stripped = signed
        for i in stripped.inputs.indices { stripped.inputs[i].witness = [] }
        XCTAssertEqual(signed.txid, stripped.txid)
        XCTAssertEqual(signed.txid, "e8151a2af31c368a35053ddd4bdb285a8595c769a3ad83e0fa02314a602d4609")
        XCTAssertLessThan(signed.weight, signed.serialized().count * 4)
    }

    func testParserRejectsGarbage() throws {
        let good = try XCTUnwrap([UInt8](hex: signedHex))
        XCTAssertThrowsError(try Transaction.parse(good + [0]), "Überhang")
        XCTAssertThrowsError(try Transaction.parse(Array(good.dropLast())), "abgeschnitten")
        var hugeCount = Array(good.prefix(6))
        hugeCount += [0xFE, 0xFF, 0xFF, 0xFF, 0x00]
        XCTAssertThrowsError(try Transaction.parse(hugeCount + Array(repeating: 0, count: 60)), "unmögliche Anzahl")
        var nonCanonical = Array(good.prefix(6))
        nonCanonical += [0xFD, 0x02, 0x00]
        XCTAssertThrowsError(try Transaction.parse(nonCanonical + Array(good.dropFirst(7))), "CompactSize nicht kanonisch")
        for _ in 0..<500 {
            var fuzz = good
            fuzz[Int.random(in: 0..<fuzz.count)] = UInt8.random(in: 0...255)
            _ = try? Transaction.parse(fuzz)
            _ = try? Transaction.parse(Array(fuzz.prefix(Int.random(in: 0..<fuzz.count))))
        }
    }

    func testLowSAndVerify() throws {
        for _ in 0..<50 {
            let key = SecureRandom.bytes(32)
            guard Secp256k1.isValidPrivateKey(key) else { continue }
            let digest = SecureRandom.bytes(32)
            let sig = try Secp256k1.signECDSA(digest: digest, privateKey: key)
            XCTAssertLessThanOrEqual(sig.count, 71)
            // S steht am Ende; kleines S heißt: oberstes Bit 0, höchstens 32 Bytes.
            let sLength = Int(sig[5 + Int(sig[3])])
            XCTAssertLessThanOrEqual(sLength, 32)
            let pub = try Secp256k1.publicKey(privateKey: key)
            XCTAssertTrue(Secp256k1.verifyECDSA(signature: sig, digest: digest, publicKey: pub))
            var other = digest
            other[0] ^= 1
            XCTAssertFalse(Secp256k1.verifyECDSA(signature: sig, digest: other, publicKey: pub))
        }
        XCTAssertFalse(Secp256k1.isValidPrivateKey([UInt8](repeating: 0, count: 32)))
        XCTAssertFalse(Secp256k1.isValidPrivateKey([UInt8](repeating: 0xFF, count: 32)))
    }

    // MARK: - Münzauswahl und Signieren

    struct FixedRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    let seed = Mnemonic.seed(words: KeyTests.abandon).copy

    func coins(_ values: [Int64], confirmed: Bool = true) throws -> [Coin] {
        let account = try WalletKeys.account(seed: seed, network: .regtest)
        return try values.enumerated().map { i, v in
            let address = try WalletKeys.address(account: account, chain: .receive, index: UInt32(i), network: .regtest)
            let txid = Hashes.sha256(Array("coin\(i)".utf8)).hex
            return Coin(outPoint: try OutPoint(txid: txid, vout: UInt32(i % 3)), value: v, scriptPubKey: address.scriptPubKey,
                        path: AddressPath(chain: .receive, index: UInt32(i)), confirmed: confirmed)
        }
    }

    func change() throws -> (script: [UInt8], path: AddressPath) {
        let account = try WalletKeys.account(seed: seed, network: .regtest)
        return (try WalletKeys.address(account: account, chain: .change, index: 0, network: .regtest).scriptPubKey, AddressPath(chain: .change, index: 0))
    }

    let recipient = BitcoinAddress.from(scriptPubKey: [0x00, 0x14] + [UInt8](hex: "751e76e8199196d454941c45d1b3a323f1433bd6")!, network: .regtest)!

    func testPlanWithChangeAndSign() throws {
        var rng = FixedRNG(state: 1)
        let (changeScript, changePath) = try change()
        let plan = try TransactionPlanner.plan(
            coins: try coins([50_000, 120_000, 30_000]), recipient: recipient.scriptPubKey, amount: .exact(100_000),
            feeRate: 5, changeScript: changeScript, changePath: changePath, using: &rng
        )
        XCTAssertEqual(plan.inputs.map(\.value), [120_000], "die größte Münze zuerst")
        XCTAssertNotNil(plan.changeIndex)
        XCTAssertEqual(plan.amount + plan.change + plan.fee, 120_000, "nichts geht verloren")
        XCTAssertEqual(plan.outputs[plan.recipientIndex], TxOutput(value: 100_000, scriptPubKey: recipient.scriptPubKey))
        // 1 Eingang, 2 Ausgänge P2WPKH: 141 vB im ungünstigsten Fall.
        XCTAssertEqual(plan.estimatedVSize, 141)
        XCTAssertEqual(plan.fee, 705)

        let signed = try TransactionSigner.sign(plan.unsignedTransaction(lockTime: 800), inputs: plan.signerInputs, seed: seed, network: .regtest)
        XCTAssertLessThanOrEqual(signed.virtualSize, plan.estimatedVSize)
        XCTAssertGreaterThanOrEqual(Double(plan.fee) / Double(signed.virtualSize), 5, "der echte Satz liegt nie unter dem gewählten")
        XCTAssertEqual(signed.inputs[0].sequence, 0xFFFF_FFFD, "RBF")
        XCTAssertEqual(signed.lockTime, 800)
        XCTAssertNoThrow(try TransactionSigner.verify(signed, inputs: plan.signerInputs))

        // Wer den Betrag der Eingabe fälscht, bekommt eine ungültige Signatur.
        var forged = plan.signerInputs
        forged[0] = .init(outPoint: forged[0].outPoint, value: 130_000, scriptPubKey: forged[0].scriptPubKey, path: forged[0].path)
        XCTAssertThrowsError(try TransactionSigner.verify(signed, inputs: forged))
        // Eine fremde Eingabe wird nicht signiert.
        var foreign = plan.signerInputs
        foreign[0] = .init(outPoint: foreign[0].outPoint, value: foreign[0].value, scriptPubKey: recipient.scriptPubKey, path: foreign[0].path)
        XCTAssertThrowsError(try TransactionSigner.sign(plan.unsignedTransaction(lockTime: 0), inputs: foreign, seed: seed, network: .regtest))
    }

    func testPlanWithoutChange() throws {
        var rng = FixedRNG(state: 2)
        let (changeScript, changePath) = try change()
        // 100 000 + 110 vB · 2 = 100 220; 100 300 passt ohne Wechselgeld.
        let plan = try TransactionPlanner.plan(
            coins: try coins([500_000, 100_300]), recipient: recipient.scriptPubKey, amount: .exact(100_000),
            feeRate: 2, changeScript: changeScript, changePath: changePath, using: &rng
        )
        XCTAssertEqual(plan.inputs.map(\.value), [100_300])
        XCTAssertNil(plan.changeIndex)
        XCTAssertEqual(plan.outputs.count, 1)
        XCTAssertEqual(plan.fee, 300)
    }

    func testSweepAndErrors() throws {
        var rng = FixedRNG(state: 3)
        let (changeScript, changePath) = try change()
        let all = try TransactionPlanner.plan(
            coins: try coins([40_000, 60_000]), recipient: recipient.scriptPubKey, amount: .all,
            feeRate: 10, changeScript: changeScript, changePath: changePath, using: &rng
        )
        XCTAssertEqual(all.inputs.count, 2)
        XCTAssertNil(all.changeIndex)
        XCTAssertEqual(all.amount + all.fee, 100_000)
        XCTAssertEqual(all.estimatedVSize, TransactionPlanner.vsize(inputs: 2, outputScripts: [recipient.scriptPubKey]))

        XCTAssertThrowsError(try TransactionPlanner.plan(
            coins: try coins([40_000]), recipient: recipient.scriptPubKey, amount: .exact(50_000),
            feeRate: 1, changeScript: changeScript, changePath: changePath, using: &rng)) { error in
            guard case .insufficientFunds(let available)? = error as? TransactionPlanner.Failure else { return XCTFail("\(error)") }
            XCTAssertEqual(available, 40_000 - 110)
        }
        XCTAssertThrowsError(try TransactionPlanner.plan(
            coins: try coins([40_000]), recipient: recipient.scriptPubKey, amount: .exact(100),
            feeRate: 1, changeScript: changeScript, changePath: changePath, using: &rng)) {
            XCTAssertEqual($0 as? TransactionPlanner.Failure, .amountBelowDust(minimum: 294))
        }
        for rate in [0.5, 1001, .nan, .infinity] {
            XCTAssertThrowsError(try TransactionPlanner.plan(
                coins: try coins([40_000]), recipient: recipient.scriptPubKey, amount: .exact(1000),
                feeRate: rate, changeScript: changeScript, changePath: changePath, using: &rng)) {
                XCTAssertEqual($0 as? TransactionPlanner.Failure, .feeRateOutOfRange)
            }
        }
    }

    /// Viele Zufallsfälle: die Summen stimmen immer, Staub entsteht nie, der
    /// echte Gebührensatz liegt nie unter dem gewählten.
    func testPlannerInvariants() throws {
        var rng = FixedRNG(state: 42)
        let (changeScript, changePath) = try change()
        let pool = try coins((0..<12).map { _ in Int64.random(in: 1_000...2_000_000, using: &rng) })
        for _ in 0..<300 {
            let subset = pool.filter { _ in Bool.random(using: &rng) }
            guard !subset.isEmpty else { continue }
            let rate = Double(Int.random(in: 1...300, using: &rng))
            let amount = Int64.random(in: 294...3_000_000, using: &rng)
            do {
                let plan = try TransactionPlanner.plan(coins: subset, recipient: recipient.scriptPubKey, amount: .exact(amount),
                                                       feeRate: rate, changeScript: changeScript, changePath: changePath, using: &rng)
                let inSum = plan.inputs.reduce(0) { $0 + $1.value }
                XCTAssertEqual(inSum, plan.outputs.reduce(0) { $0 + $1.value } + plan.fee)
                XCTAssertEqual(plan.amount, amount)
                XCTAssertTrue(plan.outputs.allSatisfy { $0.value >= BitcoinAddress.dustLimit(scriptPubKey: $0.scriptPubKey) })
                XCTAssertGreaterThanOrEqual(Double(plan.fee), Double(plan.estimatedVSize) * rate)
                XCTAssertEqual(Set(plan.inputs.map(\.outPoint)).count, plan.inputs.count)
            } catch let failure as TransactionPlanner.Failure {
                guard case .insufficientFunds = failure else { return XCTFail("\(failure)") }
                // Nur wenn es wirklich nicht reicht: alle lohnenden Münzen
                // zusammen decken Betrag und Gebühr nicht.
                let worth = subset.filter { $0.value > TransactionPlanner.fee(vsize: TransactionPlanner.inputWeight / 4, rate: rate) }
                let total = worth.reduce(0) { $0 + $1.value }
                XCTAssertLessThan(total, amount + TransactionPlanner.fee(vsize: TransactionPlanner.vsize(inputs: max(1, worth.count), outputScripts: [recipient.scriptPubKey]), rate: rate))
            }
        }
    }

    // MARK: - Merkle und Arbeit

    /// Block 100 000: vier Transaktionen, Kopf und Kennung aus der Blockchain.
    func testMerkleProofAndHeader() throws {
        let txids = [
            "8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87",
            "fff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4",
            "6359f0868171b1d194cbee1af2f16ea598ae8fad666d9b012c8ed2b79a236ec4",
            "e9a66845e05d5abc0ad04ec80f774a7e585c6e8db975962d069a522137b80c1d",
        ]
        var header = [UInt8]()
        header.appendLE(Int32(1))
        header += Array([UInt8](hex: "000000000002d01c1fccc21636b607dfd930d31d01c3a62104612a1719011250")!.reversed())
        header += Array([UInt8](hex: "f3e94742aca4b5ef85488dc37c06c3282295ffec960994b2c0d5ac2a25a95766")!.reversed())
        header.appendLE(UInt32(1_293_623_863))
        header.appendLE(UInt32(0x1B04_864C))
        header.appendLE(UInt32(274_148_111))
        let block = try BlockHeader(header)
        XCTAssertEqual(block.hash, "000000000003ba27aa200b1cecaad478d2b00432346c3f1f3986da1afd33e506")

        // Beweis für die dritte Transaktion: Nachbar 4, dann Hash(1,2).
        func node(_ a: String, _ b: String) -> String {
            Array(Hashes.hash256(Array([UInt8](hex: a)!.reversed()) + Array([UInt8](hex: b)!.reversed())).reversed()).hex
        }
        let siblings = [txids[3], node(txids[0], txids[1])]
        XCTAssertEqual(MerkleProof.root(txid: txids[2], siblings: siblings, position: 2), block.merkleRoot)
        XCTAssertTrue(MerkleProof.verify(txid: txids[2], siblings: siblings, position: 2, header: block, network: .regtest))
        XCTAssertFalse(MerkleProof.verify(txid: txids[2], siblings: siblings, position: 3, header: block, network: .regtest), "falsche Position")
        XCTAssertFalse(MerkleProof.verify(txid: txids[1], siblings: siblings, position: 2, header: block, network: .regtest), "falsche Transaktion")
        // 2010 war die Schwierigkeit 14 484; als Bestätigung für echtes Geld zu billig.
        XCTAssertFalse(MerkleProof.verify(txid: txids[2], siblings: siblings, position: 2, header: block, network: .mainnet))

        // Ein Kopf ohne Arbeit fällt überall durch.
        var lazy = header
        lazy[76] ^= 1
        XCTAssertFalse(try BlockHeader(lazy).hasProofOfWork(maximumTarget: BlockHeader.maximumTarget(for: .regtest)))
        XCTAssertNotNil(BlockHeader.target(bits: 0x1705_A121))
        XCTAssertNil(BlockHeader.target(bits: 0x0480_0001), "negatives Ziel")
    }
}
