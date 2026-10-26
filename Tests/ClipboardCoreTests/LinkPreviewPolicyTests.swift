import Foundation
import Testing
@testable import ClipboardCore

@Suite struct LinkPreviewPolicyTests {
    @Test(arguments: [
        "https://www.apple.com/vn/macbook-pro/",
        "http://example.com",
        "https://example.com:443/a?page=2&q=xin+ch%C3%A0o",
        "https://vnexpress.net/tin-tuc/abc-123.html",
        "http://example.com:80/",
        "https://example.com/authors/nguyen-van-a",
    ])
    func ordinaryPagesMayBeFetched(_ string: String) throws {
        #expect(LinkPreviewPolicy.shouldFetch(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "ftp://example.com/a",
        "file:///etc/hosts",
        "https://user:pass@example.com/",
        "https://user@example.com/",
    ])
    func unsupportedSchemesAndCredentialsAreBlocked(_ string: String) throws {
        #expect(!LinkPreviewPolicy.shouldFetch(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "http://localhost/a", "http://LOCALHOST/a", "http://printer.local/", "http://nas/",
        "http://192.168.1.1/reboot", "http://10.0.0.5/", "http://[::1]/", "https://8.8.8.8/",
        "http://router.lan/", "http://db.internal/", "https://example.com:8443/", "http://example.com:8080/",
    ])
    func localAndUnusualHostsAreBlocked(_ string: String) throws {
        #expect(!LinkPreviewPolicy.shouldFetch(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "https://example.com/unsubscribe?u=1", "https://example.com/Account/Verify/abc",
        "https://example.com/reset-password", "https://example.com/auth/callback",
        "https://example.com/invite/xyz", "https://example.com/users/5/delete",
        "https://example.com/magic-link/abc", "https://example.com/LOGIN",
    ])
    func actionLookingPathsAreBlocked(_ string: String) throws {
        #expect(!LinkPreviewPolicy.shouldFetch(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "https://example.com/a?token=abc", "https://example.com/a?access_TOKEN=abc",
        "https://example.com/a?sig=1", "https://example.com/a?x=1&session_id=9",
        "https://example.com/a?otp=123456", "https://example.com/a?api_key=k",
    ])
    func secretLookingQueriesAreBlocked(_ string: String) throws {
        #expect(!LinkPreviewPolicy.shouldFetch(try #require(URL(string: string))))
    }

    @Test func allowLocalHostsOnlyRelaxesHostAndPort() throws {
        let page = try #require(URL(string: "http://127.0.0.1:8765/bai-viet.html"))
        let login = try #require(URL(string: "http://127.0.0.1:8765/login.html"))
        #expect(!LinkPreviewPolicy.shouldFetch(page))
        #expect(LinkPreviewPolicy.shouldFetch(page, allowLocalHosts: true))
        #expect(!LinkPreviewPolicy.shouldFetch(login, allowLocalHosts: true))
    }
}

@Suite struct LinkPreviewUserAgentTests {
    @Test func theAppNamesItsOwnVersionWhenItFetchesAPreview() {
        #expect(LinkPreviewPolicy.userAgent(appVersion: "0.17.3") == "Mozilla/5.0 (Macintosh) AraNotch/0.17.3 link-preview")
        // A copy that cannot read its version still says what it is.
        #expect(LinkPreviewPolicy.userAgent(appVersion: nil) == "Mozilla/5.0 (Macintosh) AraNotch link-preview")
    }
}
