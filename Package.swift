// swift-tools-version:5.9
import PackageDescription

// 两个可执行文件：xyzlcu（C 写的轻量客户端，转发给守护进程）和 xyzlcu-core（主程序）。
// 发布用的 universal 版本请用 ./build.sh。
let package = Package(
    name: "xyzlcu",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "IdentityProof", path: "Sources/IdentityProof"),
        .testTarget(name: "IdentityProofTests", dependencies: ["IdentityProof"], path: "Tests/IdentityProofTests"),
        .executableTarget(
            name: "xyzlcu-core",
            dependencies: ["IdentityProof"],
            path: "Sources/xyzlcu",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices"), .linkedFramework("ScreenCaptureKit"),
                             .linkedFramework("CoreMedia"), .linkedFramework("VideoToolbox"), .linkedLibrary("z")]
        ),
        .executableTarget(name: "xyzlcu", path: "Sources/client"),
    ]
)
