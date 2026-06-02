import ProjectDescription

let project = Project(
    name: "Siminator",
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
            dependencies: []
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
