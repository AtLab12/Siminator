// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: ["ComposableArchitecture": .staticLibrary],
        baseProductType: .staticLibrary
    )
#endif

let package = Package(
    name: "Siminator",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.42.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.1"),
        .package(url: "https://github.com/AtLab12/swift-composable-architecture.git", branch: "main")
    ]
)
