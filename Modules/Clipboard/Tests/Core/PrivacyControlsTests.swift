import Foundation
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct RecordingStateTests {
    @Test func recordsWhenNothingPausesIt() {
        #expect(RecordingState(isPaused: false, pausedUntil: nil, now: date(100)) == .recording)
    }

    @Test func aTimedPauseShowsWhenItEnds() {
        #expect(RecordingState(isPaused: false, pausedUntil: date(700), now: date(100)) == .pausedUntil(date(700)))
    }

    @Test func aTimedPauseThatHasPassedIsRecordingAgain() {
        #expect(RecordingState(isPaused: false, pausedUntil: date(700), now: date(700)) == .recording)
    }

    @Test func anOpenEndedPauseWinsOverATimedOne() {
        #expect(RecordingState(isPaused: true, pausedUntil: date(700), now: date(100)) == .paused)
    }

    @Test func onlyAPauseCanBeResumed() {
        #expect(!RecordingState.recording.isPaused)
        #expect(RecordingState.paused.isPaused)
        #expect(RecordingState.pausedUntil(date(700)).isPaused)
    }
}

@Suite struct CapturePauseTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    @Test func aTimedPauseEndsAfterItsDuration() {
        let start = date(1_000_000)
        #expect(CapturePause.tenMinutes.end(from: start, calendar: calendar) == start.addingTimeInterval(600))
        #expect(CapturePause.oneHour.end(from: start, calendar: calendar) == start.addingTimeInterval(3600))
        #expect(CapturePause.threeHours.end(from: start, calendar: calendar) == start.addingTimeInterval(10_800))
    }

    @Test func untilTomorrowEndsAtTheNextMidnight() {
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 21, minute: 30))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        #expect(CapturePause.untilTomorrow.end(from: evening, calendar: calendar) == midnight)
    }

    @Test func anOpenEndedPauseHasNoEnd() {
        #expect(CapturePause.untilResumed.end(from: date(5), calendar: calendar) == nil)
    }

    @Test func thePauseEndIsRememberedAndRunsOut() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.pausedUntil == nil)
        store.pausedUntil = date(2000)
        #expect(ClipboardSettingsStore(defaults: defaults).pausedUntil == date(2000))
        #expect(store.isPaused(at: date(1999)))
        #expect(!store.isPaused(at: date(2000)))
    }

    @Test func theOldSwitchStillPausesWithNoEnd() {
        let store = ClipboardSettingsStore(defaults: InMemoryDefaults())
        store.isPaused = true
        #expect(store.isPaused(at: date(9_999_999_999)))
    }
}

@Suite struct ClearRangeTests {
    private let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

    private func withStore(_ body: (ClipboardStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-clear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(try ClipboardStore(directory: directory, inMemory: true, maxItems: 500))
    }

    @Test func clearsWhatWasCopiedInTheLastWhile() throws {
        try withStore { store in
            try store.add(.text("cũ"), source: notes, at: date(1000))
            try store.add(.text("vừa chép"), source: notes, at: date(5000))
            let removed = try store.deleteUnpinned(usedSince: date(4000))
            #expect(removed == 1)
            #expect(try store.items().map(\.text) == ["cũ"])
        }
    }

    @Test func pinnedClipsSurviveARecentClear() throws {
        try withStore { store in
            let pinned = try #require(try store.add(.text("ghim"), source: notes, at: date(5000)))
            try store.add(.text("thường"), source: notes, at: date(5001))
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            try store.pin(itemID: pinned.id, toBoard: board.id, at: date(5002))
            _ = try store.deleteUnpinned(usedSince: date(4000))
            // A pinned clip stays in the history as well as on its board.
            #expect(try store.items().map(\.text) == ["ghim"])
            #expect(try store.items(inBoard: board.id).map(\.text) == ["ghim"])
        }
    }

    @Test func aRangeKnowsItsCutoff() {
        let now = date(100_000)
        #expect(ClearRange.lastFifteenMinutes.cutoff(from: now) == date(100_000 - 900))
        #expect(ClearRange.lastHour.cutoff(from: now) == date(100_000 - 3600))
        #expect(ClearRange.olderThanDay.cutoff(from: now) == date(100_000 - 86_400))
        #expect(ClearRange.olderThanWeek.cutoff(from: now) == date(100_000 - 7 * 86_400))
        #expect(ClearRange.lastFifteenMinutes.clearsRecent)
        #expect(!ClearRange.olderThanDay.clearsRecent)
    }
}

@Suite struct SensitiveTextTests {
    @Test func recognisesCommonSecretKeys() {
        #expect(SensitiveText.reason(for: "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD") == .secretKey)
        #expect(SensitiveText.reason(for: "ghp_abcdefghijklmnopqrstuvwxyz0123456789") == .secretKey)
        #expect(SensitiveText.reason(for: "AKIAIOSFODNN7EXAMPLE") == .secretKey)
        // Put together here so GitHub's secret scanning does not take the sample for a real token.
        #expect(SensitiveText.reason(for: "xoxb" + "-123456789012-123456789012-abcdefghijklmnopqrstuvwx") == .secretKey)
        #expect(SensitiveText.reason(for: "  sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789  ") == .secretKey)
    }

    @Test func recognisesAPrivateKeyBlock() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----"
        #expect(SensitiveText.reason(for: pem) == .privateKey)
    }

    @Test func recognisesASignedTokenOfThreeParts() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        #expect(SensitiveText.reason(for: token) == .secretKey)
    }

    @Test func recognisesACardNumber() {
        // A well-known test number; its check digit is right.
        #expect(SensitiveText.reason(for: "4242 4242 4242 4242") == .cardNumber)
        #expect(SensitiveText.reason(for: "4242-4242-4242-4242") == .cardNumber)
        #expect(SensitiveText.reason(for: "4242424242424242") == .cardNumber)
    }

    @Test func aNumberThatFailsTheCheckDigitIsNotACard() {
        #expect(SensitiveText.reason(for: "4242 4242 4242 4243") == nil)
        #expect(SensitiveText.reason(for: "0912 345 678") == nil)
        #expect(SensitiveText.reason(for: "1234567890123456") == nil)
    }

    @Test func ordinaryTextIsNotSensitive() {
        #expect(SensitiveText.reason(for: "Hạn nộp: thứ Sáu") == nil)
        #expect(SensitiveText.reason(for: "https://example.com/a?b=1") == nil)
        #expect(SensitiveText.reason(for: "func greet(_ name: String) -> String { \"hi\" }") == nil)
        // A commit hash and an identifier are long and random-looking, but not secrets.
        #expect(SensitiveText.reason(for: "9fceb02d0ae598e95dc970b74767f19372d61af8") == nil)
        #expect(SensitiveText.reason(for: "01a1126d-8d96-71b0-98d0-fa5eb5c5bfac") == nil)
    }

    @Test func aSecretInsideALongTextIsLeftAlone() {
        // Only a clip that is the secret itself is held back; a document that mentions one is kept.
        let text = "Ghi chú họp: khoá thử là sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD, nhớ đổi trước khi phát hành."
        #expect(SensitiveText.reason(for: text) == nil)
    }

    @Test func theSettingIsOnUntilTurnedOff() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.skipsSensitiveText == true)
        store.skipsSensitiveText = false
        #expect(ClipboardSettingsStore(defaults: defaults).skipsSensitiveText == false)
    }
}
