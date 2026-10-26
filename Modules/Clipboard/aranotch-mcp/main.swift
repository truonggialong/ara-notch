import ClipboardMCP
import Foundation

// aranotch-mcp: gives an AI agent read-only access to the AraNotch clipboard history over the
// Model Context Protocol (stdio transport, one JSON message per line).
//
//   aranotch-mcp [--data-dir <path>]
//
// Access is off until the user allows it in AraNotch Settings.

let arguments = CommandLine.arguments
let directory: URL
if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
    directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
} else {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    directory = base.appendingPathComponent("AraNotch/Clipboard", isDirectory: true)
}

// The switch lives in the app's own preferences; it is read again for every call.
let server = ClipboardMCPServer(directory: directory) {
    CFPreferencesAppSynchronize("com.aranotch.app" as CFString)
    return CFPreferencesCopyAppValue("clipboard.mcpEnabled" as CFString, "com.aranotch.app" as CFString) as? Bool ?? false
}

while let line = readLine(strippingNewline: true) {
    if let response = server.handle(line: line) {
        FileHandle.standardOutput.write(Data((response + "\n").utf8))
    }
}
