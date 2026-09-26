// swift-tools-version: 5.10
import PackageDescription

// Prüft KryptaBitcoin und KryptaWallet gegen einen echten Bitcoin-Core-
// Knoten (Regtest). Nicht Teil der App; Anleitung in README.md.
let package = Package(
    name: "BitcoinRegtest",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../KryptaCore")],
    targets: [
        .executableTarget(
            name: "regtest-signer",
            dependencies: [.product(name: "KryptaBitcoin", package: "KryptaCore")]
        ),
        .executableTarget(
            name: "esplora-e2e",
            dependencies: [
                .product(name: "KryptaBitcoin", package: "KryptaCore"),
                .product(name: "KryptaWallet", package: "KryptaCore"),
            ]
        ),
    ]
)
