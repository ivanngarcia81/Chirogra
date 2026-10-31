// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChirograKit",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "ChirograCore", targets: ["ChirograCore"]),
        .library(name: "ChirograData", targets: ["ChirograData"]),
        .library(name: "ChirograUI", targets: ["ChirograUI"]),
    ],
    targets: [
        // Dominio puro: dinero, doble partida, impuestos y reportes. Sin SwiftUI ni SwiftData.
        .target(name: "ChirograCore"),
        // Persistencia con SwiftData y servicio de contabilización.
        .target(name: "ChirograData", dependencies: ["ChirograCore"]),
        // Vistas SwiftUI y sistema de diseño (tokens del canvas de Claude Design).
        .target(
            name: "ChirograUI",
            dependencies: ["ChirograCore", "ChirograData"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ChirograCoreTests", dependencies: ["ChirograCore"]),
        .testTarget(name: "ChirograDataTests", dependencies: ["ChirograData"]),
        .testTarget(name: "ChirograUITests", dependencies: ["ChirograUI", "ChirograData"]),
    ]
)
