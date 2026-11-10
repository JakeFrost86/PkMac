// swift-tools-version: 6.2
import PackageDescription

// Resources (sprite form map, icon) are copied into PkMac.app/Contents/Resources by build.sh
// and loaded through Bundle.main, so no SwiftPM resource bundle is needed.
let package = Package(
    name: "PkMac",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "PkMac",
            path: "Sources/PkMac",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
