// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeckReminder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NeckReminder", targets: ["NeckReminder"]),
    ],
    targets: [
        // Pure logic (no AppKit): presence detection, reminder policy, schedule rules, exercise content.
        .target(name: "NeckReminderCore"),
        // The macOS app (AppKit + SwiftUI).
        .executableTarget(
            name: "NeckReminder",
            dependencies: ["NeckReminderCore"]
        ),
        .testTarget(
            name: "NeckReminderCoreTests",
            dependencies: ["NeckReminderCore"]
        ),
    ]
)
