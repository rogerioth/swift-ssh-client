// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SSHClient",
        platforms: [
        .macOS(.v10_15),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "SSHClient",
            targets: ["SSHClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.5"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "1.1.6"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.61.1"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0")
    ],
    targets: [
        .target(
            name: "SSHClient",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ])
    ]
)
