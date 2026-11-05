// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TSBackgroundFetch",
    // iOS 15 is the floor: Xcode 27 refuses any deployment target below it (the podspec says the same).
    platforms: [.iOS(.v15)],
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
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/ios/4.2.0/TSBackgroundFetch.xcframework.zip",
            checksum: "97cacb3b7137cef7ca8a7a7dd491ef3ab2deedf576281a1f01c009414521cf64"
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
