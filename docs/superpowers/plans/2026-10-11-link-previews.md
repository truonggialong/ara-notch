# Link Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Liên kết đã sao chép hiện tiêu đề và ảnh đại diện, tải một lần sau khi sao chép, mặc định bật.

**Architecture:** Bộ lọc an toàn và bộ đọc HTML là hàm thuần trong `ClipboardCore`. Kết quả lưu ở ba cột mới (lược đồ 3). `ClipboardFeature` tải bằng `URLSession` tạm thời và nối vào bộ điều khiển.

**Tech Stack:** Swift 6, Foundation `URLSession`, SQLite3, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-link-previews-design.md`

## Global Constraints

- `ClipboardCore` không thực hiện yêu cầu mạng và không import AppKit hay SwiftUI.
- Giới hạn từ spec: HTML 512 000 byte/ký tự; ảnh 2 000 000 byte; thời hạn 6 giây; tiêu đề 200 ký tự; lược đồ phiên bản 3.
- Chỉ GET; không cookie, không bộ nhớ đệm, không thông tin đăng nhập.
- Mọi URL (ban đầu, sau chuyển hướng, ảnh) phải qua `LinkPreviewPolicy.shouldFetch`.
- Test đơn vị không được chạm mạng. Chạy test bằng `Scripts/test.sh`. Mỗi task kết thúc bằng một commit.

## Review Focus

1. **Liên kết dùng một lần:** đường dẫn hoặc tham số có từ nhạy cảm, viết hoa hay thường. Test ở Task 1.
2. **Địa chỉ nội bộ nguỵ trang:** IPv4, IPv6 trong ngoặc vuông, host không có dấu chấm, cổng lạ. Test ở Task 1.
3. **HTML hỏng hoặc bất thường:** thẻ không đóng, thuộc tính đảo thứ tự, nháy đơn, tiêu đề toàn khoảng trắng, không có thẻ nào. Test ở Task 2.
4. **Ảnh có URL nguy hiểm:** `javascript:`, `data:`, `file:` trong `og:image` phải bị bỏ. Test ở Task 2.
5. **Xoá mục có ảnh xem trước:** tệp `.preview` không được sót lại. Test ở Task 3.

---

### Task 1: `LinkPreviewPolicy`

**Files:** Create `Sources/ClipboardCore/LinkPreviewPolicy.swift`; Test `Tests/ClipboardCoreTests/LinkPreviewPolicyTests.swift`

**Interfaces — Produces:** `public enum LinkPreviewPolicy { public static func shouldFetch(_ url: URL, allowLocalHosts: Bool = false) -> Bool }`. `allowLocalHosts` chỉ nới quy tắc về host và cổng, dùng cho kiểm chứng; các quy tắc khác giữ nguyên.

- [ ] **Step 1: Test thất bại.** Cho phép: `https://www.apple.com/vn/macbook-pro/`, `http://example.com`, `https://example.com:443/a?page=2&q=xin+chào`, `https://vnexpress.net/tin-tuc/abc-123.html`. Chặn: `ftp://example.com/a`, `https://user:pass@example.com/`, `http://localhost/a`, `http://printer.local/`, `http://nas/`, `http://192.168.1.1/reboot`, `http://10.0.0.5/`, `http://[::1]/`, `https://8.8.8.8/`, `https://example.com:8443/`, `https://example.com/unsubscribe?u=1`, `https://example.com/Account/Verify/abc`, `https://example.com/reset-password`, `https://example.com/a?token=abc`, `https://example.com/a?access_TOKEN=abc`, `https://example.com/a?sig=1`, `https://example.com/auth/callback`, `https://example.com/invite/xyz`. Với `allowLocalHosts: true`: `http://127.0.0.1:8765/page.html` được phép, nhưng `http://127.0.0.1:8765/login` vẫn bị chặn.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua.
- [ ] **Step 5:** Commit `feat: add link preview safety policy`.

---

### Task 2: `LinkMetadataParser`

**Files:** Create `Sources/ClipboardCore/LinkMetadataParser.swift`; Test `Tests/ClipboardCoreTests/LinkMetadataParserTests.swift`

**Interfaces — Produces:**

```swift
public struct LinkMetadata: Equatable, Sendable {
    public var title: String?
    public var imageURL: URL?
    public init(title: String? = nil, imageURL: URL? = nil)
}
public enum LinkMetadataParser {
    public static func parse(html: String, baseURL: URL) -> LinkMetadata
}
```

- [ ] **Step 1: Test thất bại.**
  - `ogTitleWinsOverTitleTag`; `twitterTitleIsSecondChoice`; `titleTagIsTheFallback`.
  - `entitiesAreDecoded`: `Tom &amp; Jerry &#8211; &quot;Phim&quot; &#x1F600;&nbsp;hay` → `Tom & Jerry – "Phim" 😀 hay`.
  - `whitespaceIsCollapsed`: tiêu đề nhiều dòng thụt lề thành một dòng.
  - `titleIsTruncatedTo200Characters`.
  - `blankTitleIsNil`; `noTagsGivesEmptyMetadata`.
  - `ogImageIsResolvedAgainstBase`: `/img/a.png` với base `https://example.com/tin/bai.html` → `https://example.com/img/a.png`; URL tuyệt đối giữ nguyên; `//cdn.example.com/a.png` → `https://cdn.example.com/a.png`.
  - `twitterImageIsSecondChoice`.
  - `dangerousImageSchemesAreRejected`: `javascript:alert(1)`, `data:image/png;base64,AAAA`, `file:///etc/passwd` → `imageURL == nil`.
  - `attributeOrderAndQuotesDoNotMatter`: `<meta content='Tiêu đề' property='og:title'>` và `<meta name="og:title" content="X">`.
  - `tagsAreCaseInsensitive`: `<TITLE>`, `<META PROPERTY="OG:TITLE" …>`.
  - `unclosedTitleTagIsIgnored`: `<title>abc` không có thẻ đóng → `title == nil`.
  - `onlyTheBeginningIsExamined`: thẻ `og:title` nằm sau 600 000 ký tự đệm → không thấy.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt (quét chuỗi bằng tìm kiếm không phân biệt hoa thường, không dùng biểu thức chính quy phức tạp), chạy qua.
- [ ] **Step 5:** Commit `feat: parse link titles and preview images from HTML`.

---

### Task 3: Kho lược đồ 3 và cài đặt

**Files:** Modify `Sources/ClipboardCore/ClipModels.swift`, `ClipboardStore.swift`, `ClipboardSettingsStore.swift`; Test `Tests/ClipboardCoreTests/ClipboardStoreLinkTests.swift`; bổ sung `ClipboardSettingsStoreTests.swift`; sửa `migratesVersion1Store` để mong đợi phiên bản 3

**Interfaces — Produces:**

```swift
extension ClipItem {      // thuộc tính lưu trữ mới, tham số init mặc định nil
    public let linkTitle: String?
    public let linkImageBlobName: String?
    public let linkCheckedAt: Date?
}
extension ClipboardStore {
    public static let schemaVersion = 3
    public static let maxLinkImageBytes = 2_000_000
    public func setLinkPreview(id: Int64, title: String?, imageData: Data?, at date: Date) throws
    public func linkImageData(for item: ClipItem) -> Data?
    public func item(id: Int64) throws -> ClipItem?      // đổi từ private sang public
}
extension ClipboardSettingsStore { public var linkPreviews: Bool { get nonmutating set } }  // "clipboard.linkPreviews", mặc định true
```

- [ ] **Step 1: Test thất bại.** `newLinkHasNoPreview` (`linkCheckedAt == nil`); `setLinkPreviewStoresTitleAndImage`; `emptyResultStillMarksChecked`; `oversizedLinkImageIsDropped` (tiêu đề vẫn lưu); `recopyingKeepsThePreview`; `deleteRemovesPreviewBlob`; `pruneRemovesPreviewBlob`; `deleteAllRemovesPreviewBlob`; `setLinkPreviewOnMissingItemDoesNothing`; `previewSurvivesReopen`; `migratesVersion2Store` (tự tạo bảng phiên bản 2 có `rtf_blob`, `html_blob`, một dòng liên kết; mở lên được phiên bản 3, mục còn nguyên, ghi được bản xem trước). Cài đặt: mặc định bật, ghi tắt đọc tắt, sai kiểu trả bật.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt (nâng cấp theo từng bước 1→2→3), chạy qua toàn bộ.
- [ ] **Step 5:** Commit `feat: store link previews (schema v3)`.

---

### Task 4: Tải và hiển thị

**Files:** Create `Sources/ClipboardFeature/LinkPreviewFetcher.swift`; Modify `ClipboardSettings.swift`, `ClipboardController.swift`, `ClipboardViewModel.swift`, `ClipCardView.swift`, `ClipboardPanelView.swift`, `ClipPresentation.swift`, `ClipboardSettingsSection.swift`; `Sources/AraNotch/LaunchArguments.swift`, `AppDelegate.swift`; hai file `Localizable.strings`

**Interfaces — Produces:**

```swift
struct LinkPreviewResult: Sendable { var title: String?; var imageData: Data? }
struct LinkPreviewFetcher: Sendable {
    init(allowLocalHosts: Bool)
    func fetch(_ url: URL) async -> LinkPreviewResult      // không ném lỗi; lỗi cho kết quả rỗng
}
extension ClipboardController { public var allowsLocalLinkPreviews: Bool { get set } }
```

- [ ] **Step 1: `LinkPreviewFetcher`** theo mục "Tải" của spec; đọc thân bằng `URLSession.bytes(for:)` và dừng ở giới hạn.
- [ ] **Step 2: `ClipboardController`:** sau khi ghi nhận từ clipboard một mục `link` chưa kiểm tra, nếu `settings.linkPreviews` bật và bộ lọc cho phép thì chạy `Task` tải, rồi `setLinkPreview` và tải lại danh sách. Dữ liệu mẫu và `capture` công khai không kích hoạt tải.
- [ ] **Step 3: View:** thẻ notch của liên kết hiện ảnh nhỏ (nếu có), tiêu đề, host. Dòng panel dùng tiêu đề làm dòng chính và host làm dòng phụ. Khung xem trước hiện ảnh, tiêu đề, URL.
- [ ] **Step 4: Cài đặt và chuỗi:** `Toggle` với khoá `settings.clipboard.linkPreviews`, kèm dòng chú thích `settings.clipboard.linkPreviews.note`.
- [ ] **Step 5: Tham số** `--allow-local-link-previews`.
- [ ] **Step 6:** `Scripts/build-app.sh` sạch. Commit `feat: fetch and show link previews`.

---

### Task 5: Kiểm chứng

- [ ] **Step 1:** `Scripts/test.sh` qua toàn bộ.
- [ ] **Step 2:** Máy chủ `python3 -m http.server` trên `127.0.0.1` phục vụ `bai-viet.html` (có `og:title`, `og:image` trỏ tới `anh.png`) và `login.html`. App chạy với `--allow-local-link-previews`, thư mục dữ liệu tạm, clipboard riêng. Ghi URL `bai-viet.html`: kho có `link_title` đúng, có tệp `.preview` bằng từng byte `anh.png`; nhật ký máy chủ có đúng hai dòng GET.
- [ ] **Step 3:** Ghi URL `login.html`: không có dòng nhật ký mới, `link_checked_at` vẫn rỗng.
- [ ] **Step 4:** Chạy app không có `--allow-local-link-previews`, ghi URL `bai-viet.html` khác tham số: không có dòng nhật ký mới (bộ lọc chặn địa chỉ nội bộ).
- [ ] **Step 5:** Tắt cài đặt bằng `defaults` tạm, chạy với `--allow-local-link-previews`, ghi một URL mới: không có dòng nhật ký mới. Xoá khoá `defaults`.
- [ ] **Step 6:** Ảnh panel và trang notch có tiêu đề và ảnh xem trước.
- [ ] **Step 7:** Mở bản sao thư mục dữ liệu phiên bản 2 của vòng trước: lên phiên bản 3, số mục không đổi.
- [ ] **Step 8:** Commit các sửa đổi phát sinh.
