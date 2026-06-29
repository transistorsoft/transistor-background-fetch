// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TSBackgroundFetch",
    // iOS 13 is required by the Swift overlay (async/await + BGTaskScheduler).
    // The Objective-C binary itself still supports iOS 12 via CocoaPods (see the podspec).
    platforms: [.iOS(.v13)],
    products: [
        // Objective-C binary framework.
        // Consumed by the plugin bridges (React Native, Cordova, Capacitor, Flutter)
        // and by the background-geolocation Swift overlay.
        .library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"]),

        // Swift overlay for pure-native Swift apps:  `import BackgroundFetch`
        // exposes the `BackgroundFetch.shared` convenience API.
        .library(name: "BackgroundFetch", targets: ["BackgroundFetch"])
    ],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.1.1/TSBackgroundFetch.xcframework.zip",
            checksum: "05702e657d4f307082ade707d8d0ae1eda55e112f42bf38febcb0230034c4860"
        ),

        // Swift convenience layer that re-exports the binary.  The sources are the
        // same SwiftInterface files shared with the iOS DemoApp — single source of truth.
        .target(
            name: "BackgroundFetch",
            dependencies: ["TSBackgroundFetch"],
            path: "ios/TSBackgroundFetch/SwiftInterface"
        )
    ]
)
