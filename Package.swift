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
            checksum: "01fe4fdb5adb9da122bd7d49562a2ceddf3d9b5fa832f59c679add43dd46bc49"
        )
    ]
)
