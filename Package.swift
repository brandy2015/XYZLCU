// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "xyzlcu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "xyzlcu",
            path: "Sources/xyzlcu",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices"), .linkedFramework("ScreenCaptureKit")]
        )
    ]
)
