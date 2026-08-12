// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// NOTE: This Package.swift is NOT used for building the app.
// The build is done via run.sh using swiftc directly, because SPM does not
// work with Command Line Tools only (requires full Xcode).
// This file is kept for reference and potential future SPM migration.
// (Issue #22)

import PackageDescription

let package = Package(
    name: "VoiceDictation",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "VoiceDictation",
            path: "VoiceDictation",
            exclude: ["Info.plist"]
        )
    ]
)