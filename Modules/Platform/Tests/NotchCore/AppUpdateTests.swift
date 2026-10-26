import Foundation
import Testing
@testable import NotchCore

@Suite struct AppUpdateTests {
    @Test func theUsersOwnAppLooksForUpdates() {
        #expect(AppUpdatePolicy.runsUpdater(isTestRun: false, feedOverride: nil))
    }

    @Test func aCopyStartedForACheckLeavesUpdatesAloneUnlessGivenAFeedToTry() {
        #expect(!AppUpdatePolicy.runsUpdater(isTestRun: true, feedOverride: nil))
        #expect(AppUpdatePolicy.runsUpdater(isTestRun: true, feedOverride: "http://127.0.0.1:8123/appcast.xml"))
        // A feed that cannot be used is no feed.
        #expect(!AppUpdatePolicy.runsUpdater(isTestRun: true, feedOverride: "nonsense"))
    }

    @Test func aFeedGivenByHandIsASecureAddressOrOneOnThisMac() {
        #expect(AppUpdatePolicy.feed(from: "https://example.com/appcast.xml")?.host == "example.com")
        // For trying an update before it is published: a server on this very Mac.
        #expect(AppUpdatePolicy.feed(from: "http://127.0.0.1:8123/appcast.xml")?.port == 8123)
        #expect(AppUpdatePolicy.feed(from: "http://localhost:8123/appcast.xml") != nil)
        // From anywhere else, updates are not fetched in the clear.
        #expect(AppUpdatePolicy.feed(from: "http://example.com/appcast.xml") == nil)
        // The updater reads no files.
        #expect(AppUpdatePolicy.feed(from: "file:///tmp/appcast.xml") == nil)
        #expect(AppUpdatePolicy.feed(from: "nonsense") == nil)
        #expect(AppUpdatePolicy.feed(from: nil) == nil)
    }

    @Test func releasesAreNamedAfterTheirVersion() {
        #expect(AppUpdatePolicy.tag(forVersion: "0.12.0") == "v0.12.0")
        #expect(AppUpdatePolicy.feedAddress(owner: "someone", repository: "an-app")
            == "https://github.com/someone/an-app/releases/latest/download/appcast.xml")
        #expect(AppUpdatePolicy.downloadPrefix(owner: "someone", repository: "an-app", version: "0.12.0")
            == "https://github.com/someone/an-app/releases/download/v0.12.0/")
    }
}
