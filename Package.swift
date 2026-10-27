// swift-tools-version: 6.0
import PackageDescription

// The app is split by feature. Each feature has one folder in Modules/ holding everything of its own:
//   Modules/<X>/Core       <X>Core, the logic, without interface (tested)
//   Modules/<X>/Feature    <X>Feature, the interface in the notch and in Settings
//   Modules/<X>/Tests/…    <X>CoreTests, <X>FeatureTests
//   Modules/<X>/README.md  the module's guide
// Modules/Platform holds the notch every feature lives in (NotchCore, NotchShell); App/ only puts
// the features together. The boundaries are checked by Scripts/check-modules.sh (Modules/README.md).

/// The logic of a feature: Modules/<feature>/Core.
func core(_ feature: String, dependencies: [Target.Dependency] = []) -> Target {
    .target(name: "\(feature)Core", dependencies: dependencies, path: "Modules/\(feature)/Core")
}

/// The interface of a feature: Modules/<feature>/Feature, on its own Core and the notch.
func feature(_ feature: String, hasCore: Bool = true) -> Target {
    .target(name: "\(feature)Feature",
            dependencies: (hasCore ? [.target(name: "\(feature)Core")] : []) + ["NotchShell"],
            path: "Modules/\(feature)/Feature")
}

/// The tests of one part of a feature: Modules/<feature>/Tests/<part>.
func tests(_ feature: String, _ part: String, dependencies: [Target.Dependency]) -> Target {
    .testTarget(name: "\(feature == "Platform" ? "" : feature)\(part)Tests",
                dependencies: dependencies, path: "Modules/\(feature)/Tests/\(part)")
}

let features = ["Clipboard", "SystemEvents", "Timer", "Media", "Files", "Agent", "Windows", "Translate",
                "Calendar", "Capture", "Overview", "Tools", "Notes"]

let package = Package(
    name: "AraNotch",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AraNotch", targets: ["AraNotch"]),
        .executable(name: "aranotch-mcp", targets: ["aranotch-mcp"]),
        .executable(name: "aranotch-hook", targets: ["aranotch-hook"]),
    ],
    dependencies: [
        // The updater: checks the releases for a newer version, downloads and installs it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // The app: only puts the features together.
        .executableTarget(
            name: "AraNotch",
            dependencies: features.map { .target(name: "\($0)Feature") } + [.product(name: "Sparkle", package: "Sparkle")],
            path: "App/Sources"),

        // Platform: the notch every feature lives in.
        .target(name: "NotchCore", path: "Modules/Platform/NotchCore"),
        .target(name: "NotchShell", dependencies: ["NotchCore"], path: "Modules/Platform/NotchShell"),
        tests("Platform", "NotchCore", dependencies: ["NotchCore"]),
        tests("Platform", "NotchShell", dependencies: ["NotchShell"]),

        // Clipboard, with the server AI agents use to read its history.
        core("Clipboard"),
        feature("Clipboard"),
        .target(name: "ClipboardMCP", dependencies: ["ClipboardCore"], path: "Modules/Clipboard/MCP"),
        .executableTarget(name: "aranotch-mcp", dependencies: ["ClipboardMCP"], path: "Modules/Clipboard/aranotch-mcp"),
        tests("Clipboard", "Core", dependencies: ["ClipboardCore"]),
        tests("Clipboard", "Feature", dependencies: ["ClipboardFeature"]),
        tests("Clipboard", "MCP", dependencies: ["ClipboardMCP", "ClipboardCore"]),

        // Agents (Claude Code, Codex), with the hook Claude Code runs to report its sessions.
        core("Agent"),
        feature("Agent"),
        .executableTarget(name: "aranotch-hook", dependencies: ["AgentCore"], path: "Modules/Agent/aranotch-hook"),
        tests("Agent", "Core", dependencies: ["AgentCore"]),
        tests("Agent", "Feature", dependencies: ["AgentFeature"]),

        core("Calendar"), feature("Calendar"), tests("Calendar", "Core", dependencies: ["CalendarCore"]),
        core("Capture"), feature("Capture"),
        tests("Capture", "Core", dependencies: ["CaptureCore"]), tests("Capture", "Feature", dependencies: ["CaptureFeature"]),
        core("Files"), feature("Files"), tests("Files", "Core", dependencies: ["FilesCore"]),
        core("Media"), feature("Media"), tests("Media", "Core", dependencies: ["MediaCore"]),
        core("Overview", dependencies: ["NotchCore"]), feature("Overview"),
        tests("Overview", "Core", dependencies: ["OverviewCore"]), tests("Overview", "Feature", dependencies: ["OverviewFeature"]),
        core("SystemEvents"), feature("SystemEvents"), tests("SystemEvents", "Core", dependencies: ["SystemEventsCore"]),
        core("Timer"), feature("Timer"), tests("Timer", "Core", dependencies: ["TimerCore"]),
        core("Translate"), feature("Translate"), tests("Translate", "Core", dependencies: ["TranslateCore"]),
        core("Windows"), feature("Windows"), tests("Windows", "Core", dependencies: ["WindowsCore"]),
        core("Notes", dependencies: ["NotchCore"]), feature("Notes"),
        tests("Notes", "Core", dependencies: ["NotesCore"]), tests("Notes", "Feature", dependencies: ["NotesFeature"]),
        feature("Tools", hasCore: false), tests("Tools", "Feature", dependencies: ["ToolsFeature"]),
    ]
)
