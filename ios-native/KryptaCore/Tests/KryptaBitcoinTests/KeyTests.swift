import Foundation
import XCTest
@testable import KryptaBitcoin

/// Schlüssel und Adressen gegen die offiziellen Vektoren: BIP39 (Trezor),
/// BIP32, BIP84, BIP173/BIP350. Stimmt hier ein Byte nicht, landet Geld
/// an einer Adresse, die niemand ausgeben kann.
final class KeyTests: XCTestCase {
    func vectors(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: - Hashes

    func testRIPEMD160() {
        let cases: [(String, String)] = [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            ("abcdefghijklmnopqrstuvwxyz", "f71c27109c692c1b56bbdceb5b9d2865b3708dbc"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "12a053384a9c0c88e405a06c27dcf49ada62eb2b"),
            (String(repeating: "1234567890", count: 8), "9b752e45573d4b39f4dbd3323cab82bf63326bfb"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(RIPEMD160.hash(Array(input.utf8)).hex, expected, input)
        }
        XCTAssertEqual(RIPEMD160.hash([UInt8](repeating: 0x61, count: 1_000_000)).hex, "52783243c1697bdbe16d37f97f68f08325dc1528")
    }

    func testWordlistIsTheOfficialOne() {
        XCTAssertEqual(Mnemonic.wordlist.count, 2048)
        let file = Mnemonic.wordlist.joined(separator: "\n") + "\n"
        XCTAssertEqual(Hashes.sha256(Array(file.utf8)).hex, "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda")
        XCTAssertEqual(Set(Mnemonic.wordlist.map { $0.prefix(4) }).count, 2048, "die ersten vier Buchstaben sind eindeutig")
    }

    // MARK: - BIP39

    func testBIP39TrezorVectors() throws {
        let list = try XCTUnwrap(vectors("bip39_trezor")["english"] as? [[String]])
        XCTAssertEqual(list.count, 24)
        for v in list {
            let entropy = try XCTUnwrap([UInt8](hex: v[0]))
            let words = try Mnemonic.words(entropy: entropy)
            XCTAssertEqual(words.joined(separator: " "), v[1])
            XCTAssertEqual(try Mnemonic.entropy(words: words).copy, entropy)
            let seed = Mnemonic.seed(words: words, passphrase: "TREZOR")
            XCTAssertEqual(seed.copy.hex, v[2])
            XCTAssertEqual(try ExtendedPrivateKey.master(seed: seed.copy).serialized(version: 0x0488_ADE4), v[3])
        }
    }

    func testMnemonicRejectsBadInput() {
        var words = Array(repeating: "abandon", count: 12)
        XCTAssertThrowsError(try Mnemonic.entropy(words: words)) { XCTAssertEqual($0 as? Mnemonic.Failure, .checksum) }
        words[11] = "about"
        XCTAssertNoThrow(try Mnemonic.entropy(words: words))
        XCTAssertNoThrow(try Mnemonic.entropy(words: words.map { " \($0.uppercased()) " }), "Groß/klein und Leerraum egal")
        words[3] = "bitcoinx"
        XCTAssertThrowsError(try Mnemonic.entropy(words: words)) { XCTAssertEqual($0 as? Mnemonic.Failure, .unknownWord(3)) }
        XCTAssertThrowsError(try Mnemonic.entropy(words: Array(words.prefix(11)))) { XCTAssertEqual($0 as? Mnemonic.Failure, .wordCount) }
        XCTAssertEqual(Mnemonic.suggestions(for: "zo"), ["zone", "zoo"])
    }

    func testGeneratedEntropyRoundTrips() throws {
        for _ in 0..<50 {
            let entropy = Mnemonic.generateEntropy()
            XCTAssertEqual(entropy.count, 16)
            let words = try Mnemonic.words(entropy: entropy.copy)
            XCTAssertEqual(words.count, 12)
            XCTAssertEqual(try Mnemonic.entropy(words: words).copy, entropy.copy)
        }
    }

    // MARK: - BIP32

    func testBIP32Vectors() throws {
        let data = try vectors("bip32")
        let list = try XCTUnwrap(data["vectors"] as? [[String: Any]])
        XCTAssertEqual(list.count, 4)
        for v in list {
            let seed = try XCTUnwrap([UInt8](hex: v["seed"] as! String))
            let master = try ExtendedPrivateKey.master(seed: seed)
            for chain in v["chains"] as! [[String: String]] {
                let node = try master.derive(HD.parsePath(chain["path"]!))
                XCTAssertEqual(node.serialized(version: 0x0488_ADE4), chain["xprv"], chain["path"]!)
                XCTAssertEqual(try node.publicKey.serialized(version: 0x0488_B21E), chain["xpub"], chain["path"]!)
                // Öffentlich weiterleiten muss dasselbe ergeben wie privat.
                let pub = try ExtendedPublicKey.parse(chain["xpub"]!, version: 0x0488_B21E)
                XCTAssertEqual(try pub.child(7), try node.child(7).publicKey)
            }
        }
        // Ungültige öffentliche Schlüssel werden abgewiesen.
        for bad in try XCTUnwrap(data["invalid"] as? [String]) where bad.hasPrefix("xpub") {
            XCTAssertThrowsError(try ExtendedPublicKey.parse(bad, version: 0x0488_B21E), bad)
        }
    }

    // MARK: - BIP84

    static let abandon = Array(repeating: "abandon", count: 11) + ["about"]

    func testBIP84Vectors() throws {
        let seed = Mnemonic.seed(words: Self.abandon).copy
        let master = try ExtendedPrivateKey.master(seed: seed)
        XCTAssertEqual(master.serialized(version: 0x04B2_430C), "zprvAWgYBBk7JR8Gjrh4UJQ2uJdG1r3WNRRfURiABBE3RvMXYSrRJL62XuezvGdPvG6GFBZduosCc1YP5wixPox7zhZLfiUm8aunE96BBa4Kei5")
        let accountPriv = try master.derive(WalletKeys.accountPath(.mainnet))
        XCTAssertEqual(accountPriv.serialized(version: 0x04B2_430C), "zprvAdG4iTXWBoARxkkzNpNh8r6Qag3irQB8PzEMkAFeTRXxHpbF9z4QgEvBRmfvqWvGp42t42nvgGpNgYSJA9iefm1yYNZKEm7z6qUWCroSQnE")
        let account = try WalletKeys.account(seed: seed, network: .mainnet)
        XCTAssertEqual(account.serialized(version: 0x04B2_4746), "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs")

        let cases: [(WalletKeys.Chain, UInt32, String, String, String)] = [
            (.receive, 0, "KyZpNDKnfs94vbrwhJneDi77V6jF64PWPF8x5cdJb8ifgg2DUc9d", "0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c", "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"),
            (.receive, 1, "Kxpf5b8p3qX56DKEe5NqWbNUP9MnqoRFzZwHRtsFqhzuvUJsYZCy", "03e775fd51f0dfb8cd865d9ff1cca2a158cf651fe997fdc9fee9c1d3b5e995ea77", "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"),
            (.change, 0, "KxuoxufJL5csa1Wieb2kp29VNdn92Us8CoaUG3aGtPtcF3AzeXvF", "03025324888e429ab8e3dbaf1f7802648b9cd01e9b418485c5fa4c1b9b5700e1a6", "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"),
        ]
        for (chain, index, wif, pubkey, address) in cases {
            XCTAssertEqual(try WalletKeys.publicKey(account: account, chain: chain, index: index).hex, pubkey)
            XCTAssertEqual(try WalletKeys.address(account: account, chain: chain, index: index, network: .mainnet).string, address)
            let priv = try accountPriv.child(chain.rawValue).child(index)
            let payload = try XCTUnwrap(Base58.decodeCheck(wif))
            XCTAssertEqual(payload.count, 34)
            priv.withPrivateKey { XCTAssertEqual($0, Array(payload[1..<33])) }
        }
        // Testnetze: Münztyp 1, tb1…
        let test = try WalletKeys.address(account: WalletKeys.account(seed: seed, network: .testnet4), chain: .receive, index: 0, network: .testnet4)
        XCTAssertTrue(test.string.hasPrefix("tb1q"))
        XCTAssertEqual(test.string, "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl", "m/84'/1'/0'/0/0 wie in Sparrow und Electrum")
    }

    // MARK: - Adressen

    func testBIP350AddressVectors() throws {
        let data = try vectors("bip350")
        for v in try XCTUnwrap(data["valid"] as? [[String: String]]) {
            let address = v["address"]!, script = v["script"]!
            let hrp = address.lowercased().hasPrefix("bc") ? "bc" : "tb"
            let decoded = try XCTUnwrap(SegwitAddress.decode(hrp: hrp, address), address)
            let version = decoded.version == 0 ? [UInt8(0)] : [UInt8(0x50 + decoded.version)]
            XCTAssertEqual((version + [UInt8(decoded.program.count)] + decoded.program).hex, script, address)
            XCTAssertEqual(SegwitAddress.encode(hrp: hrp, version: decoded.version, program: decoded.program), address.lowercased())
        }
        for bad in try XCTUnwrap(data["invalid"] as? [String]) {
            XCTAssertNil(SegwitAddress.decode(hrp: "bc", bad), bad)
            XCTAssertNil(SegwitAddress.decode(hrp: "tb", bad), bad)
        }
        for s in try XCTUnwrap(data["bech32m_valid"] as? [String]) {
            XCTAssertEqual(Bech32.decode(s)?.variant, .bech32m, s)
        }
        for s in try XCTUnwrap(data["bech32_valid"] as? [String]) {
            XCTAssertEqual(Bech32.decode(s)?.variant, .bech32, s)
        }
        for s in try XCTUnwrap(data["bech32m_invalid"] as? [String]) {
            XCTAssertNil(Bech32.decode(s), s)
        }
    }

    func testAddressParsing() throws {
        let p2wpkh = try BitcoinAddress("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4", network: .mainnet)
        XCTAssertEqual(p2wpkh.kind, .p2wpkh)
        XCTAssertEqual(p2wpkh.string, "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
        XCTAssertEqual(p2wpkh.dustLimit, 294)

        let p2tr = try BitcoinAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", network: .mainnet)
        XCTAssertEqual(p2tr.kind, .p2tr)
        XCTAssertEqual(p2tr.dustLimit, 330)

        let p2pkh = try BitcoinAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", network: .mainnet)
        XCTAssertEqual(p2pkh.kind, .p2pkh)
        XCTAssertEqual(p2pkh.scriptPubKey.hex, "76a91462e907b15cbf27d5425399ebf6f0fb50ebb88f1888ac")
        XCTAssertEqual(p2pkh.dustLimit, 546)
        XCTAssertEqual(BitcoinAddress.from(scriptPubKey: p2pkh.scriptPubKey, network: .mainnet)?.string, p2pkh.string)

        let p2sh = try BitcoinAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", network: .mainnet)
        XCTAssertEqual(p2sh.kind, .p2sh)
        XCTAssertEqual(p2sh.dustLimit, 540)
        XCTAssertEqual(BitcoinAddress.from(scriptPubKey: p2sh.scriptPubKey, network: .mainnet)?.string, p2sh.string)

        // Falsches Netz wird als solches erkannt, Kaputtes als kaputt.
        XCTAssertThrowsError(try BitcoinAddress("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", network: .mainnet)) {
            XCTAssertEqual($0 as? BitcoinError, .wrongNetwork)
        }
        XCTAssertThrowsError(try BitcoinAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", network: .testnet4)) {
            XCTAssertEqual($0 as? BitcoinError, .wrongNetwork)
        }
        XCTAssertThrowsError(try BitcoinAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", network: .mainnet)) {
            XCTAssertEqual($0 as? BitcoinError, .invalidAddress)
        }
        // Künftige Segwit-Versionen: gültig, aber Krypta schickt nichts hin.
        XCTAssertThrowsError(try BitcoinAddress("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", network: .mainnet)) {
            XCTAssertEqual($0 as? BitcoinError, .unsupportedAddress)
        }
        XCTAssertThrowsError(try BitcoinAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 ; drop", network: .mainnet))
    }

    func testPaymentRequests() throws {
        let r = try PaymentRequest.parse("bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0.0012&label=Lena%20M", network: .mainnet)
        XCTAssertEqual(r.address.string, "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
        XCTAssertEqual(r.amount, 120_000)
        XCTAssertEqual(r.label, "Lena M")
        XCTAssertEqual(r.uri, "bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0.0012")
        XCTAssertEqual(try PaymentRequest.parse("BITCOIN:BC1QCR8TE4KR609GCAWUTMRZA0J4XV80JY8Z306FYU", network: .mainnet).address.string, r.address.string)
        XCTAssertThrowsError(try PaymentRequest.parse("bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?req-somethingnew=1", network: .mainnet))
        XCTAssertThrowsError(try PaymentRequest.parse("bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=1e3", network: .mainnet))
        XCTAssertThrowsError(try PaymentRequest.parse("bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0,5", network: .mainnet))
    }

    func testAmounts() {
        XCTAssertEqual(BitcoinAmount.parse("0.001"), 100_000)
        XCTAssertEqual(BitcoinAmount.parse("0,001"), 100_000)
        XCTAssertEqual(BitcoinAmount.parse(".5"), 50_000_000)
        XCTAssertEqual(BitcoinAmount.parse("12"), 1_200_000_000)
        XCTAssertEqual(BitcoinAmount.parse("0.00000001"), 1)
        XCTAssertEqual(BitcoinAmount.parse("21000000"), BitcoinAmount.maxSats)
        XCTAssertNil(BitcoinAmount.parse("21000000.00000001"))
        XCTAssertNil(BitcoinAmount.parse("0.000000001"), "neun Nachkommastellen")
        XCTAssertNil(BitcoinAmount.parse("1.000,5"))
        XCTAssertNil(BitcoinAmount.parse("-1"))
        XCTAssertNil(BitcoinAmount.parse("1e3"))
        XCTAssertNil(BitcoinAmount.parse(""))
        XCTAssertNil(BitcoinAmount.parse("."))
        XCTAssertNil(BitcoinAmount.parse("١"), "nur ASCII-Ziffern")
        XCTAssertEqual(BitcoinAmount.parseSats("12'500"), 12_500)
        XCTAssertEqual(BitcoinAmount.plainBTC(120_000), "0.0012")
        XCTAssertEqual(BitcoinAmount.plainBTC(100_000_000), "1")
        XCTAssertEqual(BitcoinAmount.formatBTC(123_456), "0.00\u{2009}123\u{2009}456")
        XCTAssertEqual(BitcoinAmount.formatBTC(-2_100_000_000, decimalSeparator: ","), "-21,00\u{2009}000\u{2009}000")
    }
}
