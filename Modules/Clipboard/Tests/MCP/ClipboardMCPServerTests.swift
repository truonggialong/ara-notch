import ClipboardCore
import Foundation
import Testing
@testable import ClipboardMCP

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

/// A history on disk with five clips and one board locked in the vault.
private func withServer(isEnabled: Bool = true, _ body: (ClipboardMCPServer, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-mcp-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let store = try ClipboardStore(directory: directory)
        let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
        let safari = ClipSource(bundleID: "com.apple.Safari", appName: "Safari")
        try store.add(.image(Data([0x89, 0x50, 1, 2])), source: safari, at: date(10))
        try store.add(.text("https://example.com/"), source: safari, at: date(20))
        try store.add(.text("Lịch họp tuần này: thứ Ba 9 giờ"), source: notes, at: date(30))
        try store.add(.text(String(repeating: "dài ", count: 400)), source: notes, at: date(40))
        let secret = try #require(try store.add(.text("mật khẩu wifi 12345"), source: notes, at: date(50)))
        let board = try store.createBoard(name: "Két", symbolName: "lock", at: date(60))
        try store.pin(itemID: secret.id, toBoard: board.id, at: date(61))
        try store.createVault(passcode: "1234")
        try store.setBoardLocked(id: board.id, true)
    }
    try body(ClipboardMCPServer(directory: directory, isEnabled: { isEnabled }), directory)
}

private func object(_ line: String?) throws -> [String: Any] {
    let line = try #require(line)
    #expect(!line.contains("\n"))
    return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
}

/// Calls a tool and returns the text of its answer and whether it is an error.
private func call(_ server: ClipboardMCPServer, _ name: String, _ arguments: String = "{}") throws -> (text: String, isError: Bool) {
    let request = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
    let response = try object(server.handle(line: request))
    #expect(response["id"] as? Int == 7)
    let result = try #require(response["result"] as? [String: Any])
    let content = try #require(result["content"] as? [[String: Any]])
    return (content.compactMap { $0["text"] as? String }.joined(), result["isError"] as? Bool ?? false)
}

private func rows(_ text: String) throws -> [[String: Any]] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
}

@Suite struct MCPProtocolTests {
    @Test func initializeAnswersWithToolsCapability() throws {
        try withServer { server, _ in
            let response = try object(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#))
            #expect(response["jsonrpc"] as? String == "2.0")
            #expect(response["id"] as? Int == 1)
            let result = try #require(response["result"] as? [String: Any])
            #expect(result["protocolVersion"] as? String == "2025-06-18")
            #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
            #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "aranotch-clipboard")
        }
    }

    @Test func anUnknownProtocolVersionGetsTheServersOwn() throws {
        try withServer { server, _ in
            let response = try object(server.handle(line: #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#))
            #expect(response["id"] as? String == "a")
            #expect((response["result"] as? [String: Any])?["protocolVersion"] as? String == ClipboardMCPServer.protocolVersions[0])
        }
    }

    @Test func notificationsGetNoAnswer() throws {
        try withServer { server, _ in
            #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
            #expect(server.handle(line: "   ") == nil)
        }
    }

    @Test func pingAnswersWithAnEmptyResult() throws {
        try withServer { server, _ in
            let response = try object(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#))
            #expect((response["result"] as? [String: Any])?.isEmpty == true)
        }
    }

    @Test func listsThreeReadOnlyTools() throws {
        try withServer { server, _ in
            let response = try object(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
            let tools = try #require((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
            #expect(tools.compactMap { $0["name"] as? String } == ["clipboard_list", "clipboard_search", "clipboard_get"])
            for tool in tools {
                #expect((tool["description"] as? String)?.isEmpty == false)
                #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
            }
        }
    }

    @Test func errorsFollowJSONRPC() throws {
        try withServer { server, _ in
            let unknown = try object(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#))
            #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
            let garbage = try object(server.handle(line: "{not json"))
            #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
            #expect(garbage["id"] is NSNull)
            let noTool = try object(server.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"clipboard_erase"}}"#))
            #expect((noTool["error"] as? [String: Any])?["code"] as? Int == -32602)
        }
    }
}

@Suite struct MCPClipboardToolTests {
    @Test func listReturnsTheNewestClipsWithoutTheVault() throws {
        try withServer { server, _ in
            let answer = try call(server, "clipboard_list")
            #expect(!answer.isError)
            let rows = try rows(answer.text)
            #expect(rows.compactMap { $0["kind"] as? String } == ["text", "text", "link", "image"])
            #expect(!answer.text.contains("mật khẩu"))
            #expect(rows[1]["text"] as? String == "Lịch họp tuần này: thứ Ba 9 giờ")
            #expect(rows[1]["source_app"] as? String == "Notes")
            #expect(rows[1]["last_used_at"] as? String == "1970-01-01T00:00:30Z")
            #expect(rows[1]["id"] is Int)
        }
    }

    @Test func longTextIsCutInListsAndWholeInGet() throws {
        try withServer { server, _ in
            let long = try #require(try rows(call(server, "clipboard_list").text).first)
            #expect((long["text"] as? String)?.count == 500)
            #expect(long["truncated"] as? Bool == true)
            let id = try #require(long["id"] as? Int)
            let whole = try call(server, "clipboard_get", #"{"id":\#(id)}"#)
            #expect(whole.text == String(repeating: "dài ", count: 400))
        }
    }

    @Test func listTakesALimitAndAKind() throws {
        try withServer { server, _ in
            try #expect(rows(call(server, "clipboard_list", #"{"limit":2}"#).text).count == 2)
            let links = try rows(call(server, "clipboard_list", #"{"kind":"link"}"#).text)
            #expect(links.compactMap { $0["text"] as? String } == ["https://example.com/"])
            #expect(try call(server, "clipboard_list", #"{"kind":"hologram"}"#).isError)
        }
    }

    @Test func searchUsesTheAppsOwnMatching() throws {
        try withServer { server, _ in
            let found = try rows(call(server, "clipboard_search", #"{"query":"lich hop"}"#).text)
            #expect(found.count == 1)
            let fromSafari = try rows(call(server, "clipboard_search", #"{"query":"@safari"}"#).text)
            #expect(fromSafari.count == 2)
            try #expect(rows(call(server, "clipboard_search", #"{"query":"mật khẩu"}"#).text).isEmpty)
            #expect(try call(server, "clipboard_search", #"{}"#).isError)
        }
    }

    @Test func getDescribesAnImageInsteadOfReturningItsBytes() throws {
        try withServer { server, _ in
            let image = try #require(try rows(call(server, "clipboard_list", #"{"kind":"image"}"#).text).first)
            let id = try #require(image["id"] as? Int)
            let answer = try call(server, "clipboard_get", #"{"id":\#(id)}"#)
            #expect(answer.text.contains("image"))
            #expect(answer.text.contains("4"))
        }
    }

    @Test func getRefusesVaultClipsAndUnknownIds() throws {
        try withServer { server, directory in
            let store = try ClipboardStore(directory: directory)
            try store.unlockVault(passcode: "1234")
            let board = try #require(try store.boards().first)
            let secretID = try #require(try store.items(inBoard: board.id).first?.id)
            #expect(try call(server, "clipboard_get", #"{"id":\#(secretID)}"#).isError)
            #expect(try call(server, "clipboard_get", #"{"id":99999}"#).isError)
            #expect(try call(server, "clipboard_get", #"{}"#).isError)
        }
    }

    @Test func everyToolIsRefusedWhileTheSettingIsOff() throws {
        try withServer(isEnabled: false) { server, _ in
            for tool in ["clipboard_list", "clipboard_search", "clipboard_get"] {
                let answer = try call(server, tool, #"{"query":"a","id":1}"#)
                #expect(answer.isError)
                // Where the switch is since 0.23.0: the Agents section.
                #expect(answer.text.contains("Settings, Agents"))
            }
        }
    }

    @Test func aMissingHistoryIsAnErrorNotACrash() throws {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("aranotch-mcp-none-\(UUID().uuidString)")
        let server = ClipboardMCPServer(directory: nowhere, isEnabled: { true })
        #expect(try call(server, "clipboard_list").isError)
        #expect(!FileManager.default.fileExists(atPath: nowhere.path))
    }

    @Test func readingNeverChangesTheHistoryFile() throws {
        try withServer { server, directory in
            let file = directory.appendingPathComponent("clipboard.sqlite")
            let before = try Data(contentsOf: file)
            _ = try call(server, "clipboard_list")
            _ = try call(server, "clipboard_search", #"{"query":"a"}"#)
            #expect(try Data(contentsOf: file) == before)
        }
    }
}
