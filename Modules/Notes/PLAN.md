# Ghi chú (Notes): kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trang Ghi chú trên notch và cửa sổ Ghi chú 3 cột, đọc và ghi thẳng Apple Notes, định dạng kiểu Telegram, không bao giờ làm mất dữ liệu của ghi chú.

**Architecture:** `NotesCore` (thuần) giữ mô hình `NoteDocument`, chuyển đổi HTML của AppleScript, giải mã protobuf của `NoteStore.sqlite`, rào chắn `EditSafety` và `SaveGuard`. `NotesFeature` chạy AppleScript (`NotesBridge`), đọc cơ sở dữ liệu (`NoteStoreReader`), dựng trình soạn `NSTextView` dùng chung, trang notch, cửa sổ, cài đặt. App nối mọi lối vào "Ghi chú mới" sang `NotesController`.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI và AppKit (`NSTextView`), `NSAppleScript`, SQLite3 của hệ thống, `Compression`/zlib cho gzip, Swift Testing (`@Test`, `#expect`).

**Spec:** `Modules/Notes/DESIGN.md`

## Global Constraints

- Luật ranh giới của `Modules/README.md`: `NotesCore` chỉ import Foundation và `NotchCore`, không SwiftUI, AppKit, Cocoa; `NotesFeature` chỉ import `NotesCore`, `NotchCore`, `NotchShell`; không Feature nào khác import Notes.
- Không thêm thư viện ngoài (protobuf, gzip, HTML tự viết hoặc dùng framework hệ thống).
- Test chạy bằng `Scripts/test-module.sh Notes`, rồi `Scripts/test.sh`, rồi `swift build`. Không gọi `swift test` trực tiếp.
- Test không bao giờ chạm Notes thật hay `NoteStore.sqlite` thật; dùng `FakeNotesService` và mẫu trong `Modules/Notes/Tests/Core/Fixtures/`.
- Chuỗi giao diện qua `L10n.string("notes.…")`, có cả `App/Resources/en.lproj/Localizable.strings` và `vi.lproj`.
- Khoá UserDefaults: `notes.recentIDs`, `notes.selectedFolderID`, `notes.defaultFolderID`. Case `ShortcutAction.newNote` và khoá lưu phím của nó giữ nguyên.
- Tự lưu sau 1,5 giây ngừng gõ; cache ảnh tối đa 200 MB; không có Full Disk Access thì làm mới mỗi 30 giây khi cửa sổ mở; gộp thay đổi tệp WAL trong 1 giây.
- Phím tắt trình soạn: ⌘B đậm, ⌘I nghiêng, ⌘U gạch chân, ⌘⇧X gạch ngang, ⌘⇧M đơn cách, ⌘K liên kết.
- Tiêu đề do AraNotch ghi: `<b><font face=".AppleSystemUIFontBold"><span style="font-size: 21px">` (cấp 1), `15px` (cấp 2), cấp 3 là chữ đậm `13px`. Đơn cách: `<font face="Courier">`.
- Không dùng hộp thoại hệ thống (`NSAlert`) để xác nhận; xác nhận ngay trong giao diện của app.
- Giao diện theo `NotchShell/Design` (AraPalette, AraSurface, AraControls, AraIcon); cửa sổ nền trắng ngà, thẻ trắng, nút viên đen, một màu cam.
- Commit có tên module ở đầu (`Notes: …`, `Clipboard: …`, `App: …`), tác giả "The Arawo company", kết thúc bằng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Không đẩy lên `origin`.
- Mỗi lần trước khi commit: `git log --oneline -1` và `ListAgents`, dừng nếu một phiên khác đã commit trước.

## Review Focus

1. Ghi chú có ảnh được lưu lại sau khi chỉ sửa chữ: mọi ảnh phải còn đủ và đúng thứ tự (Notes xoá ảnh thiếu). Test ở Task 3 và Task 9.
2. Ghi chú có danh sách việc mở khi không có Full Disk Access: phải chỉ xem, không bao giờ ghi. Test ở Task 5 và Task 9.
3. Ghi chú bị sửa trên iPhone trong lúc đang mở ở AraNotch: lưu không ghi đè, báo xung đột. Test ở Task 5 và Task 9.
4. Chữ tiếng Việt có dấu, emoji, và `&`, `<`, `>` trong nội dung: đi qua HTML rồi về không đổi. Test ở Task 2 và Task 3.
5. Đóng cửa sổ hay notch ngay sau khi gõ (chưa đủ 1,5 giây): nội dung vẫn được lưu. Test ở Task 9.

---

### Task 1: Dựng module và mô hình `NoteDocument`

**Files:**
- Create: `Modules/Notes/Core/NoteDocument.swift`, `Modules/Notes/Tests/Core/NoteDocumentTests.swift`, `Modules/Notes/Feature/NotesFeature.swift` (một dòng `import NotesCore` để target có tệp)
- Modify: `Package.swift` (thêm `core("Notes")`, `feature("Notes")`, `tests("Notes", "Core", dependencies: ["NotesCore"])`, `tests("Notes", "Feature", dependencies: ["NotesFeature"])`, thêm `"Notes"` vào `features`), `Scripts/test-module.sh` (thêm `Notes` vào `MODULES`, case `Notes) suites="NotesCoreTests|NotesFeatureTests"`), `Modules/README.md` (một dòng bảng)

**Interfaces:**
- Produces:
  ```swift
  public struct TextStyle: OptionSet, Hashable, Sendable { bold, italic, underline, strikethrough, monospaced }
  public struct TextRun: Hashable, Sendable { public var text: String; public var style: TextStyle; public var link: URL? }
  public enum ListKind: Hashable, Sendable { case bullet, dash, numbered, checklist(done: Bool) }
  public enum NoteBlock: Hashable, Sendable {
      case paragraph([TextRun])
      case heading(level: Int, [TextRun])            // 1 Tiêu đề, 2 Đề mục, 3 Đề mục phụ
      case listItem(ListKind, indent: Int, [TextRun])
      case quote([TextRun])
      case code(String)                              // khối đơn cách cả dòng
      case image(attachmentIndex: Int)               // thứ tự trong các tệp đính kèm của ghi chú
      case table(html: String, cells: [[String]])
      case file(attachmentIndex: Int, name: String, uti: String)
      case drawing(attachmentIndex: Int)
  }
  public struct NoteDocument: Hashable, Sendable {
      public var blocks: [NoteBlock]
      public var plainText: String { get }           // nối các khối bằng "\n", ảnh là "\u{FFFC}"
      public var imageCount: Int { get }
  }
  ```

- [ ] **Step 1:** Viết test `plainTextJoinsBlocksWithObjectReplacementForImages`: tài liệu `[.paragraph([TextRun("Chào")]), .image(attachmentIndex: 0), .listItem(.bullet, indent: 0, [TextRun("a")])]` cho `plainText == "Chào\n\u{FFFC}\na"` và `imageCount == 1`.
- [ ] **Step 2:** `Scripts/test-module.sh Notes` → FAIL (chưa có kiểu).
- [ ] **Step 3:** Viết các kiểu trên, sửa `Package.swift`, `test-module.sh`, `Modules/README.md`.
- [ ] **Step 4:** `Scripts/test-module.sh Notes` → PASS; `Scripts/check-modules.sh` → không lỗi.
- [ ] **Step 5:** Commit `Notes: the module and the note model`.

### Task 2: `NotesHTMLReader`

**Files:**
- Create: `Modules/Notes/Core/NotesHTMLReader.swift`, `Modules/Notes/Tests/Core/NotesHTMLReaderTests.swift`, `Modules/Notes/Tests/Core/Fixtures/probe-read.html` (HTML đọc ra ở thử nghiệm ngày 2026-10-27: phần `read1.html` và phần các kiểu gốc trong `DESIGN.md`, ảnh base64 thay bằng ô trống như Notes trả về), `Modules/Notes/Tests/Core/Fixtures/probe-plaintext.txt`
- Modify: `Package.swift` (resources `.copy("Fixtures")` cho `NotesCoreTests`)

**Interfaces:**
- Consumes: `NoteDocument`, `NoteBlock`, `TextRun`, `TextStyle`, `ListKind` (Task 1)
- Produces: `public enum NotesHTMLReader { public static func read(html: String, plainText: String) -> NoteDocument }`

Tự viết một bộ quét thẻ nhỏ (không dùng `NSAttributedString(html:)`, vì nó cần AppKit và chạy WebKit). Quy tắc:
- Mỗi `<div>` cấp ngoài, `<li>`, `<h1>`/`<h2>`/`<h3>`, `<object>` là một khối.
- `<b>`, `<i>`, `<u>`, `<strike>`, `<tt>`, `<font face="Courier">` cho kiểu; `<a href>` cho liên kết; bỏ `<span style>`.
- Một `<div>` chỉ chứa chữ đậm `.AppleSystemUIFontBold` cỡ 21/15/13 px là `.heading(1/2/3)`. (Sửa 2026-10-27: bộ ghi nay viết tiêu đề đậm 28/24/21 và thân bài 18 px vì Notes ép cỡ nhỏ về 11 px; bộ đọc nhận thêm đậm 24/21/18.)
- `<ul class="Apple-dash-list">` là `.dash`, `<ul>` là `.bullet`, `<ol>` là `.numbered`. `<ul>` lồng nhau tăng `indent`.
- `<div>` toàn chữ Courier (`<tt>`) là `.code`.
- `<object><table>` là `.table`: HTML nguyên văn từ `<object>` tới `</object>`, ô là chữ của từng `<td>`.
- Vị trí ảnh: dòng thứ k của `plainText` chứa `U+FFFC` ứng với `<div>` trống thứ k. Mỗi `U+FFFC` lần lượt là ảnh, trừ chỗ đã là bảng (bảng cũng chiếm một tệp đính kèm, xem `DESIGN.md`).
- Thực thể `&amp; &lt; &gt; &quot; &#39; &nbsp;` và `&#NNNN;` được giải mã.

- [ ] **Step 1:** Viết test:
  - `readsInlineStylesFromProbe`: khối thứ 4 có các run `bold` "bold", `italic` "italic", `underline` "under", `strikethrough` "strike", `monospaced` "mono", link `https://example.com/` "link".
  - `readsHeadingsWrittenAsBoldSizes`: "Probe title" là `.heading(level: 1, …)`, "Heading" là `.heading(level: 2, …)`.
  - `readsNativeHeadingTags`: `<div><h1>Tiêu đề</h1></div>` ra `.heading(level: 1, [TextRun("Tiêu đề")])`.
  - `placesImageAtObjectReplacementLine`: probe có đúng một `.image(attachmentIndex: 0)` nằm giữa khối mã và "end edited".
  - `keepsTableHTMLVerbatim`: `.table` có `html` bắt đầu bằng `<object><table` và `cells == [["Cột 1","Cột 2"],["",""]]`.
  - `decodesEntitiesAndVietnamese`: `<div>A &amp; B &lt;c&gt; Tiếng Việt 😀</div>` ra run `"A & B <c> Tiếng Việt 😀"`.
  - `dashListIsDash`.
- [ ] **Step 2:** `Scripts/test-module.sh Notes` → FAIL.
- [ ] **Step 3:** Viết `NotesHTMLReader.read(html:plainText:)`.
- [ ] **Step 4:** `Scripts/test-module.sh Notes` → PASS.
- [ ] **Step 5:** Commit `Notes: read a note's HTML from Notes`.

### Task 3: `NotesHTMLWriter` và đi rồi về

**Files:**
- Create: `Modules/Notes/Core/NotesHTMLWriter.swift`, `Modules/Notes/Tests/Core/NotesHTMLWriterTests.swift`

**Interfaces:**
- Consumes: Task 1, `NotesHTMLReader` (Task 2, cho test đi rồi về)
- Produces:
  ```swift
  public struct NoteImageData: Sendable { public var data: Data; public var mimeType: String }  // "image/png", "image/jpeg"…
  public enum NotesHTMLWriter {
      /// images[i] là ảnh có attachmentIndex i. Thiếu ảnh nào thì ném lỗi, không bao giờ ghi thiếu.
      public static func write(_ document: NoteDocument, images: [Int: NoteImageData]) throws -> String
  }
  public enum NotesHTMLWriterError: Error, Equatable { case missingImage(Int), unwritableBlock(String) }
  ```
- Quy tắc: escape `& < > "`; dòng là `<div>…</div>`, dòng trống là `<div><br></div>`. Tiêu đề, đơn cách theo Global Constraints. Danh sách chấm và gạch gộp các mục liền nhau vào một `<ul>` (gạch có `class="Apple-dash-list"`). Ảnh là `<div><img src="data:<mime>;base64,…"></div>`; bảng ghi nguyên `html`. `.listItem(.numbered|.checklist)`, `.quote`, `.file`, `.drawing` ném `unwritableBlock`, vì `EditSafety` đã chặn trước khi tới đây.

- [ ] **Step 1:** Viết test:
  - `roundTripsEveryWritableBlock`: tài liệu có đủ đoạn với mọi kiểu, ba cấp tiêu đề, chấm, gạch, mã, ảnh, bảng. Qua `read(html: write(doc), plainText: doc.plainText)` thì ra lại đúng `doc`.
  - `embedsEveryImageInOrder`: tài liệu 2 ảnh cho đúng hai `<img src="data:image/png;base64,` theo thứ tự 0 rồi 1.
  - `refusesToWriteWithAMissingImage`: thiếu ảnh 1 thì ném `.missingImage(1)`.
  - `refusesChecklist`: ném `.unwritableBlock`.
  - `escapesMarkup`: `"a<b>&"` ra `a&lt;b&gt;&amp;`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết `NotesHTMLWriter`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: write a note back as HTML, every image embedded`.

### Task 4: Bộ đọc protobuf và `NoteStoreDecoder`

**Files:**
- Create: `Modules/Notes/Core/ProtobufReader.swift`, `Modules/Notes/Core/Gzip.swift`, `Modules/Notes/Core/NoteStoreDecoder.swift`, `Modules/Notes/Tests/Core/NoteStoreDecoderTests.swift`, `Modules/Notes/Tests/Core/ProtobufWriter.swift` (chỉ trong test: dựng mẫu)

**Interfaces:**
- Produces:
  ```swift
  struct ProtobufReader { init(_ data: Data); mutating func next() throws -> (field: Int, value: ProtobufValue)? }
  enum ProtobufValue { case varint(UInt64), bytes(Data), fixed32(UInt32), fixed64(UInt64) }
  enum Gzip { static func decompress(_ data: Data) throws -> Data }   // zlib `inflateInit2` với windowBits 31
  public struct NoteStoreAttachment: Hashable, Sendable { public var identifier: String; public var uti: String }
  public enum NoteStoreDecoder {
      /// `data` là ZICNOTEDATA.ZDATA (gzip). Trả tài liệu và danh sách tệp đính kèm theo thứ tự xuất hiện.
      public static func decode(_ data: Data) throws -> (document: NoteDocument, attachments: [NoteStoreAttachment])
  }
  public enum NoteStoreDecoderError: Error { case notGzip, malformed(String) }
  ```
- Sơ đồ protobuf của Notes (theo công trình công khai apple_cloud_notes_parser; kiểm lại ở Task 13 bằng mẫu thật): `NoteStoreProto.document(2) → Document.note(3) → Note { note_text(2): string, attribute_run(5): repeated AttributeRun }`. `AttributeRun { length(1), paragraph_style(2), font_weight(5): 1 đậm, 2 nghiêng, 3 cả hai, underlined(6), strikethrough(7), link(9): string, attachment_info(12) { identifier(1), type_uti(2) } }`. `ParagraphStyle { style_type(1): 0 tiêu đề, 1 đề mục, 2 đề mục phụ, 4 đơn cách, 100 chấm, 101 gạch, 102 số, 103 việc; indent_amount(4); checklist(5) { uuid(1), done(2) }; block_quote(8) }`. `length` đếm theo đơn vị UTF-16.
- Ánh xạ: dòng `style_type` 4 là `.code`; `U+FFFC` có `type_uti` `public.jpeg`/`public.png`/`public.heic`/`public.image` là `.image`, `com.apple.notes.table` là `.table` (với `html` rỗng và `cells` rỗng, được điền từ AppleScript khi hiển thị), `com.apple.drawing*`/`com.apple.paper` là `.drawing`, còn lại là `.file`. `attachmentIndex` đếm chung mọi loại, đúng như thứ tự `attachments` của AppleScript.

- [ ] **Step 1:** Viết test (mẫu dựng bằng `ProtobufWriter` rồi gzip bằng `Process` `/usr/bin/gzip`, hoặc zlib `deflateInit2`):
  - `decodesChecklistWithDoneState`: chữ "việc 1\nviệc 2\n" với hai run `style_type 103`, `done 1` và `done 0` cho `.listItem(.checklist(done: true), …"việc 1")`, rồi `.checklist(done: false)`.
  - `decodesNumberedAndQuote`.
  - `decodesBoldItalicLink`.
  - `countsUTF16ForEmoji`: "😀a" với run độ dài 2 đậm, 1 thường.
  - `mapsAttachmentsByUTI`: một ảnh, một bảng, một PDF cho `.image(0)`, `.table`, `.file(attachmentIndex: 2, …, uti: "com.adobe.pdf")`.
  - `rejectsNonGzip`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết `ProtobufReader`, `Gzip`, `NoteStoreDecoder`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: decode the Notes database's note format`.

### Task 5: `EditSafety` và `SaveGuard`

**Files:**
- Create: `Modules/Notes/Core/EditSafety.swift`, `Modules/Notes/Core/SaveGuard.swift`, `Modules/Notes/Tests/Core/EditSafetyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum ReadOnlyReason: Hashable, Sendable { case checklist, numberedList, quote, file, drawing, locked, listsUnknown }
  public enum EditSafety: Hashable, Sendable {
      case editable, readOnly([ReadOnlyReason])
      /// full: tài liệu từ cơ sở dữ liệu (nil khi không có). html: tài liệu đọc qua AppleScript.
      public static func check(full: NoteDocument?, html: NoteDocument, isLocked: Bool) -> EditSafety
  }
  public enum SaveDecision: Equatable, Sendable { case write, conflict }
  public enum SaveGuard { public static func decide(openedAt: Date, currentModification: Date) -> SaveDecision }
  ```
- `check` có `full`: mỗi loại khối không ghi được góp một lý do (không trùng, theo thứ tự trong enum). Tiêu đề không chặn. Không có `full`: có `.listItem(.bullet, …)` thì `.readOnly([.listsUnknown])`. `isLocked` thì `.readOnly([.locked])`.
- `decide`: chênh lệch quá 1 giây là `.conflict` (ngày của AppleScript làm tròn tới giây).

- [ ] **Step 1:** Viết test:
  - `checklistMakesReadOnly`
  - `numberedAndQuoteListBothReasons`: ra `[.numberedList, .quote]`.
  - `imagesTablesHeadingsStayEditable`
  - `withoutDatabaseAnyBulletIsReadOnly`
  - `withoutDatabasePlainTextIsEditable`
  - `lockedIsReadOnly`
  - `sameSecondWrites`
  - `laterModificationConflicts`
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết `EditSafety`, `SaveGuard`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: decide which notes are safe to write`.

### Task 6: `NotesService` và `NotesBridge` (AppleScript)

**Files:**
- Create: `Modules/Notes/Feature/NotesService.swift`, `Modules/Notes/Feature/NotesBridge.swift`, `Modules/Notes/Feature/NotesScripts.swift`, `Modules/Notes/Tests/Feature/NotesScriptsTests.swift`, `Modules/Notes/Tests/Feature/FakeNotesService.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct NoteFolder: Identifiable, Hashable, Sendable { public var id: String; public var name: String; public var account: String; public var noteCount: Int }
  public struct NoteSummary: Identifiable, Hashable, Sendable {
      public var id: String; public var name: String; public var folderID: String
      public var modified: Date; public var snippet: String; public var hasImages: Bool; public var isLocked: Bool
      public var databaseKey: Int? { get }   // số NN trong "…/ICNote/pNN"
  }
  public struct NoteContent: Sendable { public var html: String; public var plainText: String; public var modified: Date; public var attachmentCount: Int }
  public enum NotesAccess: Equatable, Sendable { case unknown, granted, denied }
  public enum NotesServiceError: Error, Equatable { case denied, notFound, script(String) }
  public protocol NotesService: Sendable {
      func access(askIfNeeded: Bool) async -> NotesAccess
      func folders() async throws -> [NoteFolder]
      func notes(in folderID: String?) async throws -> [NoteSummary]        // nil: mọi thư mục
      func content(of noteID: String) async throws -> NoteContent
      func saveAttachment(_ index: Int, of noteID: String, to url: URL) async throws  // Sửa 2026-10-27: đã bỏ, hỏng trên macOS 27 (-10000); xem attachmentIDs(of:)
      func create(in folderID: String, html: String) async throws -> String  // id mới
      func setBody(_ html: String, of noteID: String) async throws -> Date   // ngày sửa mới
      func modification(of noteID: String) async throws -> Date
      func delete(_ noteID: String) async throws
      func createFolder(named: String) async throws -> NoteFolder
      func show(_ noteID: String) async throws                               // mở trong Notes
  }
  public final class NotesBridge: NotesService { public init() }
  enum NotesScripts { static func …(…) -> String }                          // mỗi lệnh một hàm dựng mã AppleScript
  ```
- `access`: `AEDeterminePermissionToAutomateTarget` với bundle `com.apple.Notes`, `askUserIfNeeded` theo tham số; `errAEEventNotPermitted` là `.denied`.
- Chuỗi đưa vào AppleScript được escape `\` và `"`. HTML lớn truyền bằng tệp tạm UTF-8 rồi `read POSIX file … as «class utf8»`, như ở thử nghiệm. Mọi lệnh chạy trên một `DispatchQueue` nối tiếp riêng.
- `notes(in:)` lấy `id, name, modification date, container id, password protected` của mọi ghi chú trong một lệnh (từng thuộc tính dạng danh sách, không lặp từng ghi chú). `snippet` là 120 ký tự đầu của `plaintext`, chỉ lấy cho 50 ghi chú mới nhất; `hasImages` dựa vào `count of attachments`.
- `FakeNotesService` (trong test) giữ ghi chú trong bộ nhớ, đếm số lần `setBody`, đổi được ngày sửa để giả xung đột.

- [ ] **Step 1:** Viết test:
  - `escapesQuotesInNames`: `NotesScripts.createFolder(named: "A \"b\" \\")` chứa `"A \"b\" \\\\"`.
  - `setBodyReadsHTMLFromFile`: chứa `read POSIX file "/tmp/x.html" as «class utf8»` và `set body of`.
  - `databaseKeyFromID`: `"x-coredata://AA/ICNote/p96"` cho 96.
  - `listingFetchesPropertiesAsLists`: chứa `id of notes`, `modification date of notes`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết các tệp trên.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: talk to Notes through AppleScript`.

### Task 7: `NoteStoreReader` và theo dõi thay đổi

**Files:**
- Create: `Modules/Notes/Feature/NoteStoreReader.swift`, `Modules/Notes/Feature/NoteStoreWatcher.swift`, `Modules/Notes/Tests/Feature/NoteStoreReaderTests.swift`

**Interfaces:**
- Consumes: `NoteStoreDecoder` (Task 4), `NoteSummary.databaseKey` (Task 6)
- Produces:
  ```swift
  public final class NoteStoreReader: Sendable {
      public static let defaultURL: URL   // ~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
      public init(url: URL = defaultURL)
      public var isReadable: Bool { get }                 // có Full Disk Access
      public func rawData(forNoteKey key: Int) -> Data?   // ZICNOTEDATA.ZDATA
      public func document(forNoteKey key: Int) -> (document: NoteDocument, attachments: [NoteStoreAttachment])?  // nil khi không đọc hay giải mã được, có ghi log
  }
  public final class NoteStoreWatcher { public init(url: URL, onChange: @escaping @MainActor () -> Void); public func stop() }
  ```
- Truy vấn: `SELECT d.ZDATA FROM ZICCLOUDSYNCINGOBJECT n JOIN ZICNOTEDATA d ON d.Z_PK = n.ZNOTEDATA WHERE n.Z_PK = ?`. Mở bằng `sqlite3_open_v2(…, SQLITE_OPEN_READONLY)`, mỗi lần đọc mở rồi đóng. Log qua `os.Logger(subsystem: "AraNotch", category: "Notes")`.
- Watcher: `DispatchSource.makeFileSystemObjectSource` trên `NoteStore.sqlite-wal`, gộp trong 1 giây; tệp WAL bị thay thì mở lại.

- [ ] **Step 1:** Viết test với một SQLite tạm, có hai bảng tối giản đúng tên cột, một dòng mang dữ liệu gzip của Task 4:
  - `readsNoteDataByKey`
  - `missingKeyIsNil`
  - `unreadableFileIsNotReadable`: đường dẫn không tồn tại.
  - `corruptDataIsNil`
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết `NoteStoreReader`, `NoteStoreWatcher`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: read the Notes database, read only`.

### Task 8: Chuyển đổi `NSAttributedString` và lệnh định dạng

**Files:**
- Create: `Modules/Notes/Feature/NoteAttributedText.swift`, `Modules/Notes/Feature/NoteFormatting.swift`, `Modules/Notes/Tests/Feature/NoteAttributedTextTests.swift`

**Interfaces:**
- Consumes: Task 1
- Produces:
  ```swift
  public enum NoteImageSize { case thumbnail, fitWidth(CGFloat) }   // thumbnail: cao tối đa 64 pt
  enum NoteAttributedText {
      static func make(_ doc: NoteDocument, images: [Int: NSImage], imageSize: NoteImageSize) -> NSAttributedString
      static func document(from text: NSAttributedString, original: NoteDocument) -> NoteDocument
  }
  enum NoteFormat: CaseIterable { case bold, italic, underline, strikethrough, monospaced, link, clear }
  enum BlockFormat { case title, heading, subheading, body, bulletList, codeBlock }
  enum NoteFormatting {
      static func apply(_ f: NoteFormat, to text: NSTextStorage, range: NSRange, link: URL?)
      static func apply(_ f: BlockFormat, to text: NSTextStorage, range: NSRange)
      static func isActive(_ f: NoteFormat, in text: NSAttributedString, range: NSRange) -> Bool
  }
  ```
- Kiểu khối lưu trong thuộc tính riêng `NSAttributedString.Key("AraNotesBlock")` trên cả đoạn; ảnh, bảng, tệp là `NSTextAttachment` có thuộc tính `"AraNotesAttachmentIndex"`, để `document(from:original:)` lấy lại đúng khối gốc. Bảng, tệp, bản vẽ được vẽ bằng một `NSTextAttachmentCell` riêng. Ô tích vẽ ☐/☑ và số vẽ "1." dưới dạng tiền tố chỉ hiển thị.
- `apply` bật tắt kiểu: cả vùng đã có kiểu thì bỏ, chưa có thì thêm (như Telegram). Đơn cách dùng `NSFont.monospacedSystemFont`.

- [ ] **Step 1:** Viết test:
  - `roundTripsThroughAttributedString`: tài liệu của Task 3 qua `make` rồi `document(from:original:)` ra lại đúng.
  - `boldTogglesOnAndOff`
  - `boldOnMixedRangeMakesAllBold`
  - `clearRemovesEveryInlineStyle`
  - `typingAfterImageKeepsImageIndex`: chèn chữ sau ảnh thì `document(from:)` vẫn có `.image(attachmentIndex: 0)`.
  - `checklistRendersDoneMark`: tài liệu chỉ xem có `.checklist(done: true)` thì chuỗi hiển thị chứa "☑".
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết các tệp.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: the editor's text and its formatting commands`.

### Task 9: `NotesStore` (mô hình của trang và cửa sổ)

**Files:**
- Create: `Modules/Notes/Feature/NotesStore.swift`, `Modules/Notes/Feature/NoteImageCache.swift`, `Modules/Notes/Feature/NotesSettings.swift`, `Modules/Notes/Core/NotesSettingsStore.swift`, `Modules/Notes/Tests/Feature/NotesStoreTests.swift`

**Interfaces:**
- Consumes: `NotesService`, `FakeNotesService` (Task 6), `NoteStoreReader` (Task 7), `NotesHTMLReader`, `NotesHTMLWriter`, `EditSafety`, `SaveGuard`, `NoteStoreDecoder`
- Produces:
  ```swift
  public struct NotesSettingsStore { public enum Key { recentIDs = "notes.recentIDs", selectedFolderID = "notes.selectedFolderID", defaultFolderID = "notes.defaultFolderID" }; public init(defaults: UserDefaults); public var recentIDs: [String]; public var selectedFolderID: String?; public var defaultFolderID: String? }
  @MainActor public final class NotesSettings: ObservableObject { public init(store: NotesSettingsStore) /* @Published cho ba khoá */ }
  public struct OpenNote: Equatable { public var id: String; public var document: NoteDocument; public var safety: EditSafety; public var openedAt: Date; public var images: [Int: URL] }
  public enum NoteSaveState: Equatable { case saved, pending, saving, conflict, failed(String), deleted }
  @MainActor final class NotesStore: ObservableObject {
      init(service: NotesService, database: NoteStoreReader?, cache: NoteImageCache, settings: NotesSettings, debounce: Duration = .milliseconds(1500))
      @Published private(set) var access: NotesAccess
      @Published private(set) var fullView: Bool               // đọc được cơ sở dữ liệu
      @Published private(set) var folders: [NoteFolder]
      @Published private(set) var notes: [NoteSummary]          // của thư mục đang chọn, mới nhất trước
      @Published var selectedFolderID: String?                  // nil: mọi thư mục
      @Published var searchText: String                         // lọc tên và snippet, không phân biệt dấu (dùng folding .diacriticInsensitive, .caseInsensitive)
      @Published private(set) var open: OpenNote?
      @Published private(set) var saveState: NoteSaveState
      func requestAccess() async
      func refresh() async
      func openNote(_ id: String) async
      func edit(_ document: NoteDocument)                        // đặt pending, hẹn lưu sau debounce
      func flush() async                                         // lưu ngay nếu đang pending
      func newNote(_ document: NoteDocument? = nil) async        // tạo trong defaultFolderID (hoặc thư mục đầu), mở nó; document dùng cho "Tạo lại"
      func reloadOpenNote() async                                // sau xung đột
      func delete(_ id: String) async
  }
  final class NoteImageCache { init(root: URL, limitBytes: Int = 200_000_000); func url(noteID: String, index: Int) -> URL; func trim(); func remove(noteID: String) }
  ```
- `openNote`: lấy `content`, đọc `full` từ cơ sở dữ liệu nếu có. Tài liệu hiển thị là `full` khi có (bảng lấy `html` và `cells` từ tài liệu HTML theo `attachmentIndex`), không thì là tài liệu HTML. `safety = EditSafety.check(...)`. Ảnh được lấy từ tệp media của cơ sở dữ liệu (hay cache của app) khi chưa có. (Sửa 2026-10-27: `saveAttachment` đã bỏ vì `save attachment` hỏng trên macOS 27, lỗi -10000; `NotesService` có `attachmentIDs(of:)` thay thế, cache khoá theo id tệp đính kèm.) Thêm id vào `recentIDs` (tối đa 20).
- Lưu: `modification` → `SaveGuard.decide`; `.conflict` thì `saveState = .conflict` và không ghi. `.write` thì đọc ảnh từ cache, `NotesHTMLWriter.write`, `setBody`, đặt `openedAt` bằng ngày trả về. Lỗi `.notFound` thì `.deleted`. Ghi chú `.readOnly` không bao giờ gọi `setBody`.

- [ ] **Step 1:** Viết test với `FakeNotesService` và `debounce: .milliseconds(10)`:
  - `savesAfterTypingStops`: hai lần `edit` liên tiếp gây đúng một `setBody`.
  - `flushSavesImmediately`
  - `keepsImagesWhenOnlyTextChanged`: ghi chú hai ảnh, sửa chữ, HTML đã ghi có đúng hai `<img`.
  - `readOnlyWithoutDatabaseNeverWrites`: ghi chú có `<ul>`, `database == nil`, `edit` rồi `flush` thì `setBody` được gọi 0 lần.
  - `conflictDoesNotOverwrite`: đổi ngày sửa trong fake sau `openNote` thì `saveState == .conflict`, 0 lần ghi.
  - `deletedElsewhereReportsDeleted`
  - `searchIgnoresDiacritics`: tìm "viec" thấy "Việc nhà".
  - `newNoteGoesToDefaultFolder`
  - `recentIDsCapAtTwenty`
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết các tệp.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `Notes: open, save and guard notes`.

### Task 10: Trình soạn, menu định dạng nổi và trang notch

**Files:**
- Create: `Modules/Notes/Feature/NoteEditorView.swift` (`NSViewRepresentable` bọc `NSTextView`), `Modules/Notes/Feature/FormatPopover.swift`, `Modules/Notes/Feature/NotesPageView.swift`, `Modules/Notes/Feature/NotesAccessCard.swift`, `Modules/Notes/Feature/NotesController.swift`
- Modify: `App/Resources/en.lproj/Localizable.strings`, `App/Resources/vi.lproj/Localizable.strings` (khoá `notes.*`)

**Interfaces:**
- Consumes: `NotesStore` (Task 9), `NoteAttributedText`, `NoteFormatting` (Task 8)
- Produces:
  ```swift
  struct NoteEditorView: NSViewRepresentable { init(store: NotesStore, imageSize: NoteImageSize) }
  @MainActor public final class NotesController {
      public init(settings: NotesSettings, notch: NotchController)
      public func makePage() -> NotchPage          // id "notes", titleKey "notes.page.title", symbolName "note.text", hue theo AraHue chưa dùng
      public func makeToolSettings() -> AnyView     // dòng phím tắt .newNote
      public func makePageSettings() -> AnyView     // thư mục mặc định, trạng thái hai quyền
      public func newNote()
      public func showWindow(noteID: String? = nil) // Task 11
      public func start()                           // đặt handler .newNote, bật watcher
  }
  ```
- Trình soạn: `NSTextView` cho phép ảnh (`importsGraphics`, dán và kéo thả ảnh thì thêm khối ảnh và lưu ảnh vào cache dưới chỉ số mới), `isEditable = (safety == .editable)`. Phím tắt theo Global Constraints, qua `performKeyEquivalent`. Bôi chữ thì hiện `FormatPopover` (một `NSPanel` nhỏ không lấy focus, đặt trên vùng chọn) với Đậm, Nghiêng, Gạch chân, Gạch ngang, Đơn cách, Liên kết, Xoá định dạng. Nút đang bật được tô màu.
- Trang notch: trái 38% có ô tìm, nút +, danh sách `recent` (tên, giờ, biểu tượng ảnh, ổ khoá). Phải là `NoteEditorView(imageSize: .thumbnail)`, nút ⤢ gọi `showWindow(noteID:)`. Trên cùng là dải chỉ xem hoặc xung đột khi có. Chưa có quyền thì cả trang là `NotesAccessCard`. Notch giữ mở khi trình soạn có focus (`notch.setKeepsOpen(_, forPage: "notes")`). Đóng notch thì gọi `flush()`.
- Dải chỉ xem: lý do ghép từ `notes.readOnly.<reason>`, nút "Sửa trong Notes" gọi `service.show`. Dải xung đột: nút Tải lại (`reloadOpenNote`) và Chép phần của tôi (đưa `plainText` lên clipboard). Dải `.deleted`: Chép nội dung, Tạo lại (`newNote` với tài liệu đang soạn). Dải `.failed`: thông báo lỗi và Chép nội dung. Bấm ghi chú bị khoá thì gọi `service.show`, không mở trong trình soạn.

- [ ] **Step 1:** Viết test (`NotesFeatureTests`):
  - `commandBTogglesBoldInEditor`: tạo `NSTextView` qua coordinator của `NoteEditorView`, chọn chữ, gửi ⌘B, chữ thành đậm và `store.saveState == .pending`.
  - `readOnlyEditorIsNotEditable`
  - `pageHasNotesID`: `makePage().id == "notes"`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết các tệp và chuỗi dịch.
- [ ] **Step 4:** PASS, rồi `swift build`.
- [ ] **Step 5:** Commit `Notes: the notch page and the editor`.

### Task 11: Cửa sổ Ghi chú 3 cột

**Files:**
- Create: `Modules/Notes/Feature/NotesWindowController.swift`, `Modules/Notes/Feature/NotesWindowView.swift`, `Modules/Notes/Feature/FormatToolbar.swift`, `Modules/Notes/Feature/NoteListGrouping.swift`
- Modify: `Modules/Notes/Feature/NotesController.swift` (`showWindow`), chuỗi dịch
- Test: `Modules/Notes/Tests/Feature/NoteListGroupingTests.swift`

**Interfaces:**
- Consumes: `NotesStore`, `NoteEditorView(imageSize: .fitWidth)`
- Produces: `enum NoteListGrouping { static func groups(_ notes: [NoteSummary], now: Date, calendar: Calendar) -> [(titleKey: String, notes: [NoteSummary])] }`, nhóm theo Hôm nay, Hôm qua, 7 ngày trước, 30 ngày trước, rồi từng tháng (`notes.group.month` với tên tháng).
- Cửa sổ: theo mẫu `LibraryWindowController` của Clipboard, tự `setHiddenFromCapture` theo `notch.settings.hidesFromCapture`, cỡ mặc định 1000×640, nhớ khung bằng `setFrameAutosaveName("AraNotesWindow")`.
- Cột 1: tìm, thư mục kèm số ghi chú theo tài khoản, nút + Thư mục (ô nhập ngay trong cột).
- Cột 2: nhóm ngày, nút + Ghi chú. Chuột phải: Mở trong Notes, Xoá. Xoá hiện dải xác nhận trong cột.
- Cột 3: `FormatToolbar` (các nút của menu nổi, cộng menu Tiêu đề / Đề mục / Đề mục phụ / Thân, Danh sách chấm, Khối mã, Chèn ảnh qua `NSOpenPanel`), rồi trình soạn.
- Đóng cửa sổ hay đổi ghi chú thì gọi `flush()`. Không có Full Disk Access thì làm mới mỗi 30 giây khi cửa sổ mở.

- [ ] **Step 1:** Viết test `groupsByDay`: ghi chú lúc 9:00 hôm nay, hôm qua, 3 ngày trước, 2 tháng trước ra 4 nhóm đúng thứ tự.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Viết các tệp.
- [ ] **Step 4:** PASS, rồi `swift build`.
- [ ] **Step 5:** Commit `Notes: the notes window`.

### Task 12: Nối vào app, thay "Ghi chú mới" cũ

**Files:**
- Modify:
  - `App/Sources/AppDelegate.swift`: tạo `NotesController`; `register(page: notes.makePage())` sau calendar; công cụ `tool("note") { notes?.newNote() }`; `onNewNote: { notes?.newNote() }`; `--new-note`; mục `notes.makePageSettings()` trong "Tuỳ chọn trang"; `notes.makeToolSettings()` cạnh `clipboard.makeToolSettings()`; `notes.start()`; tiền tố tìm `settings.notes`, bỏ `settings.clipboard.newNote`.
  - `App/Sources/LaunchArguments.swift`: `--dump-note-data <id> <file>` ghi `rawData` ra tệp, dùng ở Task 13.
  - `App/Resources/Info.plist`: `NSAppleEventsUsageDescription`.
  - Chuỗi: `settings.notes.*` mới. `settings.clipboard.newNote.note` bỏ; `menu.newNote`, `shortcut.newNote`, `icon.newNote` giữ nhưng đổi nghĩa thành ghi chú Notes.
  - Clipboard: bỏ `ClipboardController.newNote()`, dòng `setHandler(.newNote)`, `viewModel.onNewNote`, `ClipboardViewModel.onNewNote`, nút `AraIconButton(.newNote…)` ở `ClipboardPageView.swift:35`, `ShortcutRow(… .newNote …)` ở `ClipboardSettingsSection.swift:183`, `ClipEditor.newNoteID`/`openNew`, test `aNewNoteStartsWithTheCursorInItsText`.
  - Sổ: `Modules/Clipboard/README.md`, `Modules/Tools/README.md`, `App/README.md`.
- Test: chạy toàn bộ.

- [ ] **Step 1:** `grep -rn "newNote\|onNewNote\|openNew" Modules App` chỉ còn các chỗ thuộc Notes, `ShortcutAction`, `AraIcon`, `NotchTool`, `StatusItemController`, `LaunchArguments`, `AppDelegate`.
- [ ] **Step 2:** `Scripts/test.sh` → PASS; `swift build` → không lỗi; `Scripts/check-modules.sh` → không vi phạm.
- [ ] **Step 3:** Commit `App: Notes in the notch and its window; "New note" now makes an Apple Note`.

### Task 13: Thử thật, mẫu protobuf thật, sổ

**Files:**
- Create: `Modules/Notes/Tests/Core/Fixtures/real-checklist.notedata` (lấy bằng `--dump-note-data` từ một ghi chú thử chỉ có chữ mẫu), `Modules/Notes/README.md`
- Modify: `Modules/Notes/Tests/Core/NoteStoreDecoderTests.swift`, `docs/project/FEATURES.md`, `docs/project/HISTORY.md`, `Modules/README.md`, `README.md` ở gốc (một dòng tính năng)

- [ ] **Step 1:** `Scripts/build-app.sh`, rồi `open build/AraNotch.app`. Nhờ chủ dự án cấp Automation và Full Disk Access cho AraNotch; không tự bấm hộp hỏi của hệ thống.
- [ ] **Step 2:** Tạo thư mục "AraNotch-test" qua AraNotch. Nhờ chủ dự án thêm trong Notes một ghi chú có danh sách việc (một dòng đã tích), danh sách số, trích dẫn, một ảnh. Chạy `--dump-note-data` lấy mẫu, thêm test `decodesRealNoteFromMacOS27`. Nếu sơ đồ protobuf ở Task 4 lệch thì sửa `NoteStoreDecoder` theo mẫu thật, test trước.
- [ ] **Step 3:** Thử thật, chụp ảnh từng bước và đối chiếu với Notes:
  - Tạo ghi chú từ notch, gõ chữ có ⌘B, ⌘I, liên kết, dán một ảnh, đóng notch ngay: Notes có đủ.
  - Mở ghi chú đó ở cửa sổ, đổi đề mục, thêm danh sách chấm: Notes có đủ, ảnh còn.
  - Ghi chú của chủ dự án ở bước 2: chỉ xem, ô tích hiện ☑ đúng dòng.
  - Sửa ghi chú trong Notes khi AraNotch đang mở nó, rồi gõ ở AraNotch: báo xung đột, Notes không bị ghi đè.
  - Tắt Full Disk Access (nhờ chủ dự án), mở lại: ghi chú có danh sách chỉ xem, có thẻ mời cấp quyền.
  - Phím tắt và mục "Ghi chú mới" trên thanh menu mở cửa sổ với ghi chú trống.
  - Xoá thư mục thử.
- [ ] **Step 4:** Viết `Modules/Notes/README.md` đủ các mục của mẫu sổ. Thêm dòng vào `FEATURES.md`, nêu rõ phần đã thử tay và chưa thử. Thêm một vòng vào `HISTORY.md`. Phần cần chuột thật chưa làm được thì ghi vào danh sách thử tay còn nợ.
- [ ] **Step 5:** `Scripts/test.sh`, `swift build` → PASS. Commit `Notes: real-note fixture, module guide, ledger and history`.
