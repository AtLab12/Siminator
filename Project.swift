import ProjectDescription

let swiftSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.2",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_NONISOLATEDNONSENDINGBYDEFAULT": "YES",
]

let project = Project(
    name: "Siminator",
    settings: .settings(base: swiftSettings),
    targets: [
        .target(
            name: "Siminator",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.atlab.Siminator",
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true
            ]),
            buildableFolders: [
                "Siminator/Sources",
                "Siminator/Resources",
            ],
            dependencies: [
                .external(name: "NIOCore"),
                .external(name: "NIOHTTP1"),
                .external(name: "NIOHTTP2"),
                .external(name: "NIOPosix"),
            ]
        ),
        .target(
            name: "SiminatorTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.atlab.SiminatorTests",
            infoPlist: .default,
            buildableFolders: [
                "Siminator/Tests"
            ],
            dependencies: [.target(name: "Siminator")]
        ),
    ]
)
