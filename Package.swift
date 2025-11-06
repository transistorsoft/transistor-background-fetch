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
            checksum: "68cf602ebd8712816ffaa14a62dbfc89b1f4454481830fc77bff855bfd106764"
        )
    ]
)
