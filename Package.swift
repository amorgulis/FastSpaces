// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FastSpaces", platforms: [.macOS("27.0")], products: [.executable(name: "FastSpacesApp", targets: ["FastSpacesApp"]), .executable(name: "GestureProbe", targets: ["GestureProbe"])], targets: [
 .target(name: "FastSpacesCore"),
 .target(name: "GestureBridge", linkerSettings: [.linkedFramework("ApplicationServices")]),
 .executableTarget(name: "FastSpacesApp", dependencies: ["GestureBridge", "FastSpacesCore"]),
 .executableTarget(name: "GestureProbe", dependencies: ["GestureBridge"]),
 .executableTarget(name: "CoreTests", dependencies: ["GestureBridge", "FastSpacesCore"], path: "Tests/CoreTests")
])
