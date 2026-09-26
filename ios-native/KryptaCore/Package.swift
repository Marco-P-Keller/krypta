// swift-tools-version: 5.10
import PackageDescription

// Das Protokoll von Krypta, ohne Oberfläche und ohne Netz.
//
// Alles hier muss Byte für Byte zur Flutter-Fassung passen: ein iPhone mit
// der nativen App chattet mit Geräten, auf denen noch die Flutter-App läuft.
// Den Beweis führen die Vektoren in Tests/KryptaCoreTests/Vectors, siehe
// test/interop/swift_interop_test.dart auf der Dart-Seite.
let package = Package(
    name: "KryptaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KryptaCore", targets: ["KryptaCore"]),
        .library(name: "KryptaMessenger", targets: ["KryptaMessenger"]),
        .library(name: "KryptaBitcoin", targets: ["KryptaBitcoin"]),
        .library(name: "KryptaWallet", targets: ["KryptaWallet"]),
    ],
    dependencies: [
        // libsodium: XChaCha20-Poly1305 und Argon2id. CryptoKit hat beides
        // nicht, und die Flutter-Fassung verwendet genau diese beiden.
        .package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "KryptaCore",
            dependencies: [.product(name: "Clibsodium", package: "swift-sodium")]
        ),
        // libsecp256k1 aus Bitcoin Core, unverändert eingebettet
        // (Sources/Csecp256k1/README.md). Übersetzt über die build_*.c-Hüllen.
        .target(
            name: "Csecp256k1",
            exclude: ["src", "README.md", "COPYING"]
        ),
        // Bitcoin ohne Netz: BIP39/32/84, Adressen, Transaktionen, Signieren
        // (BIP143), Münzauswahl, Merkle-Beweise. Geprüft mit den offiziellen
        // Vektoren (Tests/KryptaBitcoinTests).
        .target(
            name: "KryptaBitcoin",
            dependencies: ["Csecp256k1"]
        ),
        // Die Wallet: Abgleich über Esplora, Adressen je Kontakt, Senden ohne
        // Doppelzahlung, Prüfen von Zahlungen aus dem Chat.
        .target(
            name: "KryptaWallet",
            dependencies: ["KryptaBitcoin"]
        ),
        // Der Messenger ohne Oberfläche und ohne Firebase: Kontakte, Chats,
        // Senden, Empfangen. Der Server steckt hinter dem Protokoll `Relay`.
        .target(
            name: "KryptaMessenger",
            dependencies: ["KryptaCore", "KryptaWallet"]
        ),
        .testTarget(
            name: "KryptaMessengerTests",
            dependencies: ["KryptaMessenger", "KryptaWallet", "KryptaBitcoin"],
            resources: [.copy("Vectors")]
        ),
        .testTarget(
            name: "KryptaBitcoinTests",
            dependencies: ["KryptaBitcoin"],
            resources: [.copy("Vectors")]
        ),
        .testTarget(
            name: "KryptaWalletTests",
            dependencies: ["KryptaWallet"]
        ),
        .testTarget(
            name: "KryptaCoreTests",
            dependencies: ["KryptaCore"],
            resources: [.copy("Vectors")]
        ),
    ]
)
