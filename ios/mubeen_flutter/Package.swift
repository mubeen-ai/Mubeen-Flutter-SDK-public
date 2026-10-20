// swift-tools-version: 5.9
//
// Serves Flutter's Swift Package Manager plugin layout. `../mubeen_flutter.podspec` serves
// the CocoaPods resolver. Both compile the same sources; they differ only in how the
// closed-source SDK arrives:
//
//   * SPM        -> the `.binaryTarget(url:checksum:)` below. SwiftPM downloads the
//                   release zip and verifies the checksum itself at resolve time.
//   * CocoaPods  -> the copy committed at `../Frameworks/MubeenDeviceSDK.xcframework`,
//                   produced from the same URL and checksum by `../fetch-xcframework.sh`.
//
// URL and checksum are copied verbatim from Mubeen-IOS-SDK-public/Package.swift. On an
// SDK bump, change all three together: this file, fetch-xcframework.sh, and the committed
// binary.

import PackageDescription

let package = Package(
    name: "mubeen_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        // Flutter's tooling looks for the dashed product name, and the underscored target.
        .library(name: "mubeen-flutter", targets: ["mubeen_flutter"])
    ],
    dependencies: [
        // Injected by the Flutter tool at build time; do not remove.
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "MubeenDeviceSDK",
            url: "https://github.com/mubeen-ai/Mubeen-IOS-SDK-public/releases/download/2.0.0/MubeenDeviceSDK.xcframework.zip",
            checksum: "5d50d72934d9759f025cbfe7e8282ad28a3d15547be5e7bbb9ba65db065147f1"
        ),
        .target(
            name: "mubeen_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "MubeenDeviceSDK"
            ],
            resources: [
                // The SDK reads device identifiers; the plugin's own privacy manifest
                // describes that. Its content is a legal statement to review before release.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
