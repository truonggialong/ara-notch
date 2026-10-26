import ClipboardCore
import Foundation

struct LinkPreviewResult: Sendable {
    var title: String?
    var imageData: Data?
}

/// Downloads a page once to read its title and preview image.
///
/// Deliberately minimal on the network: GET only, no cookies, no cache, no credentials, short
/// timeout, bounded sizes. Every URL it touches — the link, each redirect target, the image —
/// must pass `LinkPreviewPolicy`.
struct LinkPreviewFetcher: Sendable {
    static let timeout: TimeInterval = 6
    static let maxHTMLBytes = 512_000
    static let maxImageBytes = 2_000_000

    let allowLocalHosts: Bool

    /// Never throws: any failure yields an empty result.
    func fetch(_ url: URL) async -> LinkPreviewResult {
        guard isAllowed(url) else { return LinkPreviewResult() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let redirectGuard = RedirectGuard(allowLocalHosts: allowLocalHosts)

        guard let page = await load(url, session: session, delegate: redirectGuard, limit: Self.maxHTMLBytes, typePrefix: "text/html", truncates: true)
        else { return LinkPreviewResult() }

        let metadata = LinkMetadataParser.parse(html: String(decoding: page.data, as: UTF8.self), baseURL: page.url)
        var imageData: Data?
        if let imageURL = metadata.imageURL, isAllowed(imageURL) {
            imageData = await load(imageURL, session: session, delegate: redirectGuard, limit: Self.maxImageBytes, typePrefix: "image/", truncates: false)?.data
        }
        return LinkPreviewResult(title: metadata.title, imageData: imageData)
    }

    private func isAllowed(_ url: URL) -> Bool {
        LinkPreviewPolicy.shouldFetch(url, allowLocalHosts: allowLocalHosts)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout * 2
        configuration.httpAdditionalHeaders = [
            "User-Agent": LinkPreviewPolicy.userAgent(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
            "Accept": "text/html,application/xhtml+xml,image/*;q=0.8",
        ]
        return URLSession(configuration: configuration)
    }

    /// Reads a 200 response of the expected type, up to `limit` bytes.
    /// - Parameter truncates: when true an over-long body is cut at the limit (HTML: the head is
    ///   what matters); when false it is rejected (a cut image is useless).
    private func load(
        _ url: URL, session: URLSession, delegate: RedirectGuard,
        limit: Int, typePrefix: String, truncates: Bool
    ) async -> (data: Data, url: URL)? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let type = http.mimeType?.lowercased(), type.hasPrefix(typePrefix),
                  let finalURL = http.url, isAllowed(finalURL)
            else { return nil }

            var data = Data()
            for try await byte in bytes {
                if data.count >= limit {
                    guard truncates else { return nil }
                    break
                }
                data.append(byte)
            }
            return (data, finalURL)
        } catch {
            return nil
        }
    }
}

/// Stops a redirect before it is followed when its target fails the policy: requesting the
/// target is itself the side effect to avoid.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let allowLocalHosts: Bool

    init(allowLocalHosts: Bool) {
        self.allowLocalHosts = allowLocalHosts
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, LinkPreviewPolicy.shouldFetch(url, allowLocalHosts: allowLocalHosts) else {
            return nil
        }
        return request
    }
}
