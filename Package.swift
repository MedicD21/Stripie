// swift-tools-version: 5.9
// This repository is source-only: it contains the Swift files for the Stripie
// iOS app but no .xcodeproj wrapper. This Package.swift documents the SPM
// dependency the app target needs. See README.md → "Getting Started" for how to
// create the Xcode project and add these source files to its target.

import PackageDescription

let package = Package(
    name: "Stripie",
    platforms: [.iOS(.v17)],
    products: [],
    dependencies: [
        // Stripe Terminal SDK — Tap to Pay on iPhone
        // https://github.com/stripe/stripe-terminal-ios
        .package(
            url: "https://github.com/stripe/stripe-terminal-ios",
            .upToNextMinor(from: "4.0.0")
        ),
    ],
    targets: []
)
