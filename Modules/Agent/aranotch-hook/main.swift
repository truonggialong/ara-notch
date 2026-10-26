import AgentCore
import Foundation

// aranotch-hook: run by Claude Code as a hook. It reads the hook's JSON from standard input,
// keeps only the event name, session id, folder, tool name and notice text, and appends that
// as one line to the file AraNotch watches. It prints nothing and always succeeds, so it can
// never change what the agent does.
//
//   aranotch-hook [--events-file <path>]

let arguments = CommandLine.arguments
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

// aranotch-hook --statusline [--usage-file <path>]
//
// The same program as Claude Code's status line command. Claude Code hands it the session's
// state on standard input, including the rate limits, which it gives to nothing else. The
// two percentages and their reset times are written to the file AraNotch watches; the folder,
// the session and everything else in the input are dropped. What it prints is the status line.
if arguments.contains("--statusline") {
    let usageFile: URL
    if let index = arguments.firstIndex(of: "--usage-file"), arguments.indices.contains(index + 1) {
        usageFile = URL(fileURLWithPath: arguments[index + 1])
    } else {
        usageFile = support.appendingPathComponent("AraNotch/Agents/claude-usage.json")
    }
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let usage = ClaudeStatusInput.usage(from: input, at: Date())
    if let record = usage?.record {
        try? FileManager.default.createDirectory(at: usageFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((record + "\n").utf8).write(to: usageFile, options: .atomic)
    }
    print(ClaudeStatusLine.text(usage: usage, modelName: ClaudeStatusInput.modelName(from: input)))
    exit(0)
}

let file: URL
if let index = arguments.firstIndex(of: "--events-file"), arguments.indices.contains(index + 1) {
    file = URL(fileURLWithPath: arguments[index + 1])
} else {
    file = support.appendingPathComponent("AraNotch/Agents/events.jsonl")
}

/// The executables of this process's ancestors, nearest first: the agent, its shell, and
/// further up the app whose window it runs in.
func ancestorPaths() -> [String] {
    var paths: [String] = []
    var pid = getppid()
    for _ in 0..<24 where pid > 1 {
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            paths.append(String(cString: buffer))
        }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
        pid = info.kp_eproc.e_ppid
    }
    return paths
}

let input = FileHandle.standardInput.readDataToEndOfFile()
// Only the path of the app the agent runs in is kept, so the notch can bring that app forward.
if let line = AgentHookInput.compact(input, at: Date(), hostApp: AgentHost.appPath(amongAncestors: ancestorPaths())) {
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    // O_APPEND: lines from several agents running at once never overwrite each other.
    let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    if descriptor >= 0 {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
    }
}
exit(0)
