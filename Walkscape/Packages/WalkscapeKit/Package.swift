// swift-tools-version: 5.10
import PackageDescription

// WalkscapeKit holds everything that does not need UIKit/SwiftUI:
// domain models, the zone progression engine, the friend-track layout
// engine, mock data sources, the procedural pixel-art renderer and the
// Supabase client.
// It builds and tests on macOS, iOS and Linux (`swift test`).
let package = Package(
    name: "WalkscapeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WalkscapeDomain", targets: ["WalkscapeDomain"]),
        .library(name: "PixelArt", targets: ["PixelArt"]),
        .library(name: "WalkscapeBackend", targets: ["WalkscapeBackend"]),
        .executable(name: "pixel-preview", targets: ["PixelPreview"]),
    ],
    targets: [
        .target(name: "WalkscapeDomain"),
        .target(name: "PixelArt", dependencies: ["WalkscapeDomain"]),
        .target(name: "WalkscapeBackend", dependencies: ["WalkscapeDomain"]),
        .executableTarget(name: "PixelPreview", dependencies: ["PixelArt", "WalkscapeDomain"]),
        .testTarget(name: "WalkscapeDomainTests", dependencies: ["WalkscapeDomain"]),
        .testTarget(name: "PixelArtTests", dependencies: ["PixelArt", "WalkscapeDomain"]),
        .testTarget(name: "WalkscapeBackendTests", dependencies: ["WalkscapeBackend", "WalkscapeDomain"]),
    ]
)
