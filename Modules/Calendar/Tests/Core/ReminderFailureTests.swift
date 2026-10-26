import Testing
@testable import CalendarCore

@Suite struct ReminderFailureTests {
    @Test func theReasonGivenIsTheFirstThatStoodInTheWay() {
        #expect(ReminderFailure.reason(hasAccess: false, exists: false, isWritable: false, systemMessage: nil) == .noAccess)
        #expect(ReminderFailure.reason(hasAccess: true, exists: false, isWritable: true, systemMessage: nil) == .gone)
        #expect(ReminderFailure.reason(hasAccess: true, exists: true, isWritable: false, systemMessage: "x") == .readOnly)
        #expect(ReminderFailure.reason(hasAccess: true, exists: true, isWritable: true, systemMessage: "Offline") == .system("Offline"))
    }

    @Test func nothingStoodInTheWayIsNoFailure() {
        #expect(ReminderFailure.reason(hasAccess: true, exists: true, isWritable: true, systemMessage: nil) == nil)
    }
}
