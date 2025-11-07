// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.3/TSBackgroundFetch.xcframework.zip",
            checksum: "607612b8d53951583029cea2f4bb3a14ce8738c07fa3a1062c592b41be9ad9de"
        )
    ]
)
