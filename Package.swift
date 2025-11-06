// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.0/TSBackgroundFetch.xcframework.zip",
            checksum: "86ce01ecd4f67775f8227765672833699c86df0a9f154b19efb0e3d1f3dd380c"
        )
    ]
)
