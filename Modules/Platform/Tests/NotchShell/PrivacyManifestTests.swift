import Foundation
import Testing

/// The privacy manifest that ships in the app: no tracking, nothing collected, and a reason
/// for each kind of API Apple asks a reason for that the code uses.
@Suite struct PrivacyManifestTests {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/PrivacyInfo.xcprivacy"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theAppTracksNobodyAndCollectsNothing() throws {
        let plist = try manifest()
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    @Test func everyAPIThatNeedsAReasonHasOne() throws {
        let declared = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: declared.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
        #expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"])
    }

    @Test func theBuildPutsTheManifestInTheApp() throws {
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("PrivacyInfo.xcprivacy"))
    }
}
