// swift-tools-version: 5.9
// This Package.swift documents SPM dependencies.
// Open the .xcodeproj in Xcode to build and run the iOS app.
// To create the project: File → New → Project → "App", name "Stripie",
// then add these packages via: File → Add Package Dependencies

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
