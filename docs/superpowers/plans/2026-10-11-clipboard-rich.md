# Clipboard Rich Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tô màu code trong bản xem trước và giữ định dạng RTF, HTML của văn bản khi dán lại từ lịch sử.

**Architecture:** Nhận diện và tách token là hàm thuần trong `ClipboardCore`, chạy lúc hiển thị nên không đổi mô hình dữ liệu. Dữ liệu định dạng là tệp trong `blobs/` với hai cột mới ở lược đồ phiên bản 2.

**Tech Stack:** Swift 6, SQLite3, SwiftUI `AttributedString`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-clipboard-rich-design.md`

## Global Constraints

- `ClipboardCore` không import AppKit hay SwiftUI.
- Giới hạn từ spec: nhận diện xét 4 000 ký tự đầu; tô màu tối đa 20 000 ký tự; mỗi phần RTF hoặc HTML tối đa 2 000 000 byte; lược đồ phiên bản 2.
- Bảng màu: từ khoá `#C678DD`, chuỗi `#98C379`, chú thích `#7F848E`, số `#D19A66`, còn lại `#ABB2BF`.
- Không dùng macro SwiftUI (`@State`, `@FocusState`).
- Chạy test bằng `Scripts/test.sh`; test không ghi vào `~/Library`. Mỗi task kết thúc bằng một commit.

## Review Focus

1. **Văn xuôi bị nhận nhầm là code:** câu tiếng Việt có dấu hai chấm, danh sách gạch đầu dòng, địa chỉ nhiều dòng kết thúc bằng dấu phẩy. Test ở Task 1.
2. **Ký tự nhiều byte:** tiếng Việt và emoji trong chuỗi, chú thích và ngoài chúng; token nối lại phải bằng đúng văn bản gốc. Test ở Task 2.
3. **Cấu trúc không đóng:** chuỗi thiếu dấu nháy đóng, `/*` thiếu `*/`, dấu `\` ở cuối văn bản. Test ở Task 2.
4. **Sao chép lại không còn định dạng:** mục từng có RTF, lần sao chép sau chỉ có văn bản thường thì tệp RTF cũ phải bị xoá. Test ở Task 3.
5. **Kho phiên bản 1 có sẵn dữ liệu:** mở lên phải giữ đủ mục và ảnh. Test ở Task 3.

---

### Task 1: `CodeDetector`

**Files:** Create `Sources/ClipboardCore/CodeDetector.swift`; Test `Tests/ClipboardCoreTests/CodeDetectorTests.swift`

**Interfaces — Produces:** `public enum CodeDetector { public static func looksLikeCode(_ text: String) -> Bool }`

- [ ] **Step 1: Test thất bại.** Là code: hàm Swift ba dòng; `def` Python có thụt lề; hàm mũi tên JavaScript nhiều dòng; JSON nhiều dòng; đoạn HTML; câu `SELECT … FROM … WHERE …;` hai dòng; khối CSS ba dòng; một dòng `const total = items.reduce((a, b) => a + b, 0);`. Không phải code: câu tiếng Việt; đoạn tiếng Anh hai câu; "Lịch họp tuần này: thứ Ba 9 giờ, phòng họp tầng 3."; danh sách ba gạch đầu dòng; địa chỉ ba dòng kết thúc bằng dấu phẩy; một liên kết; `#4A90D9`; một từ; chuỗi rỗng; `{` đơn lẻ; "import thuế tăng 5% trong quý này".
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua.
- [ ] **Step 5:** Commit `feat: detect code in copied text`.

---

### Task 2: `CodeTokenizer`

**Files:** Create `Sources/ClipboardCore/CodeTokenizer.swift`; Test `Tests/ClipboardCoreTests/CodeTokenizerTests.swift`

**Interfaces — Produces:**

```swift
public struct CodeToken: Equatable, Sendable {
    public enum Kind: Sendable { case plain, keyword, string, comment, number }
    public let kind: Kind
    public let text: String
}
public enum CodeTokenizer { public static func tokenize(_ text: String) -> [CodeToken] }
```

Token mang chuỗi con thay vì khoảng chỉ số, để lớp hiển thị không phải xử lý `String.Index`. Các token `plain` liền nhau được gộp làm một.

- [ ] **Step 1: Test thất bại.** Dùng helper `kinds(_ text:) -> [(Kind, String)]` bỏ token chỉ gồm khoảng trắng.
  - `let x = 42` → keyword `let`, plain `x =`, number `42` (so theo loại và chuỗi đã cắt khoảng trắng).
  - `"a \"b\" c"` là một token string.
  - `// chú thích "không phải chuỗi"` là một token comment.
  - `/* a\nb */ x` → comment rồi plain.
  - `# ghi chú` ở đầu dòng là comment; `color = #fff` không có comment.
  - `-- ghi chú` ở đầu dòng là comment; `a -- b` không có comment.
  - `0xFF`, `3.14`, `1_000` là number; `abc123` là plain.
  - `return` là keyword; `returned` là plain.
  - Chuỗi không đóng `"abc\nnext` → string `"abc`, phần sau không phải string.
  - `/* không đóng` → một comment tới hết.
  - Văn bản kết thúc bằng `"abc\` không crash.
  - Phủ kín: với mười mẫu (gồm tiếng Việt, emoji, văn bản rỗng, chỉ khoảng trắng), nối `text` của mọi token bằng đúng văn bản gốc.
  - Văn bản rỗng cho mảng rỗng.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt (duyệt một lượt theo `Character`), chạy qua.
- [ ] **Step 5:** Commit `feat: tokenize code for highlighting`.

---

### Task 3: Dữ liệu định dạng trong kho, lược đồ phiên bản 2

**Files:** Modify `Sources/ClipboardCore/ClipModels.swift`, `ClipboardStore.swift`; Test `Tests/ClipboardCoreTests/ClipboardStoreRichTests.swift`; Modify `ClipboardStoreTests.swift` (test phiên bản lược đồ)

**Interfaces — Produces:**

```swift
public struct ClipRichData: Equatable, Sendable {
    public var rtf: Data?
    public var html: Data?
    public init(rtf: Data? = nil, html: Data? = nil)
    public var isEmpty: Bool { get }
}
extension ClipItem {            // thêm thuộc tính lưu trữ, tham số init có mặc định nil
    public let rtfBlobName: String?
    public let htmlBlobName: String?
    public var hasRichData: Bool { get }
}
extension ClipboardStore {
    public static let schemaVersion = 2
    public static let maxRichBytes = 2_000_000
    public func add(_ content: ClipContent, rich: ClipRichData?, source: ClipSource, at date: Date) throws -> ClipItem?
    public func richData(for item: ClipItem) -> ClipRichData?
}
```

Hàm `add(_:source:at:)` cũ giữ nguyên chữ ký và gọi bản mới với `rich: nil`.

- [ ] **Step 1: Test thất bại.**
  - `richTextIsStoredAndReturned`: thêm văn bản kèm RTF và HTML; `hasRichData`, `richData(for:)` trả đúng hai phần; `blobs/` có hai tệp `.rtf`, `.html`.
  - `plainTextHasNoRichData`.
  - `richDataIsIgnoredForImagesAndFiles`.
  - `oversizedRichPartIsDropped`: RTF 2 000 001 byte và HTML nhỏ → mục được lưu, chỉ có HTML.
  - `emptyRichDataIsTreatedAsNone`: `ClipRichData(rtf: Data(), html: nil)` → `hasRichData == false`.
  - `duplicateReplacesRichData`: lần hai với RTF khác → trả RTF mới.
  - `duplicateWithoutRichRemovesOldRich` (Review Focus 4): lần hai không có `rich` → `hasRichData == false`, `blobs/` rỗng.
  - `deleteRemovesRichBlobs`, `pruneRemovesRichBlobs`.
  - `missingRichBlobReturnsRemainingPart`: xoá tệp `.rtf` bằng tay → `richData` chỉ còn HTML.
  - `richDataSurvivesReopen` (`inMemory: false`).
  - `migratesVersion1Store` (Review Focus 5): tự tạo tệp SQLite với bảng `items` của phiên bản 1 (không có hai cột mới), một dòng văn bản và một dòng ảnh kèm tệp trong `blobs/`, `user_version = 1`; mở bằng `ClipboardStore`: đủ hai mục, ảnh đọc được, `user_version` là 2, thêm được mục có RTF.
  - Sửa `newerSchemaIsRejected` hiện có: vẫn dùng 99.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua toàn bộ.
- [ ] **Step 5:** Commit `feat: store rich text alongside clips (schema v2)`.

---

### Task 4: Đọc ghi clipboard và hiển thị

**Files:** Modify `Sources/ClipboardFeature/PasteboardIO.swift`, `ClipboardController.swift`, `ClipCardView.swift`, `ClipboardPanelView.swift`, `ClipPresentation.swift`; Create `Sources/ClipboardFeature/CodeText.swift`; Modify `Sources/AraNotch/SampleClips.swift`

- [ ] **Step 1: `PasteboardReader.readRich(_:) -> ClipRichData?`** đọc `.rtf` và `.html`; `PasteboardWriter.write(_:imageData:rich:to:)` ghi thêm hai kiểu đó cho mục văn bản, liên kết, màu.
- [ ] **Step 2: `ClipboardController`:** truyền `rich` khi ghi nhận từ clipboard và khi ghi lại; `capture(_:rich:source:)` công khai có `rich` mặc định `nil`.
- [ ] **Step 3: `CodeText`:** hàm `CodeHighlighter.attributed(_ text: String, fontSize: CGFloat) -> AttributedString` dựng từ `CodeTokenizer` với bảng màu của spec, phông đơn cách. Kết quả được nhớ đệm theo văn bản trong `NSCache`.
- [ ] **Step 4: View:** thẻ notch và khung xem trước của panel dùng `CodeHighlighter` khi `item.kind == .text && CodeDetector.looksLikeCode(item.text)`. Dòng trong danh sách panel dùng biểu tượng `chevron.left.forwardslash.chevron.right` cho code. Dòng metadata của panel thêm nhãn "RTF" hoặc "HTML" khi mục có dữ liệu định dạng.
- [ ] **Step 5: Dữ liệu mẫu:** mẫu code hiện có đủ để kiểm chứng; thêm một mục văn bản kèm RTF.
- [ ] **Step 6:** `swift build` sạch, `Scripts/build-app.sh`. Commit `feat: highlight code and keep rich text when pasting`.

---

### Task 5: Kiểm chứng

Mọi lần chạy dùng `--data-dir` tạm và `--pasteboard-name aranotch.test`.

- [ ] **Step 1:** `Scripts/test.sh` qua toàn bộ.
- [ ] **Step 2:** Ảnh panel với `--send-keys "down,down,down,down"` (mục code): khung xem trước có màu, phông đơn cách. Ảnh trang notch: thẻ code có màu, thẻ văn xuôi thì không.
- [ ] **Step 3:** Script ghi chuỗi kèm RTF vào clipboard riêng; `clipboard.sqlite` có `rtf_blob`, tệp tồn tại và bằng từng byte dữ liệu đã ghi.
- [ ] **Step 4:** Chạy lại app với `--show-clipboard-panel --send-keys "cmd-return"`; clipboard riêng có kiểu `public.rtf` với đúng dữ liệu đó và có cả chuỗi thường.
- [ ] **Step 5:** Tạo một kho phiên bản 1 bằng bản app ở commit `main` hiện tại không khả thi trong bước này; thay vào đó dựa vào test `migratesVersion1Store` và mở lại thư mục dữ liệu `data-live` của vòng 2a (được tạo bởi bản phiên bản 1) bằng bản app mới, xác nhận số mục không đổi và `PRAGMA user_version` là 2.
- [ ] **Step 6:** Commit các sửa đổi phát sinh.
