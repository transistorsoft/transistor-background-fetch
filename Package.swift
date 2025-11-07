// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.5/TSBackgroundFetch.xcframework.zip",
            checksum: "5c81868809c51c3ee7fded211f9fcee7616039289bebc83ae5bfa4e30a96b45c"
        )
    ]
)
