# Notes (NotesCore, NotesFeature)

Sổ của module **Notes**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi. Thiết kế gốc ở [DESIGN.md](DESIGN.md), kế hoạch làm ở [PLAN.md](PLAN.md).

## Vai trò

Ghi chú định dạng chữ kiểu Telegram (bôi chữ là có menu nổi, có phím tắt), và dữ liệu là chính Apple Notes: ghi chú của AraNotch là ghi chú trong Notes, iCloud lo việc đồng bộ. Gồm trang Ghi chú trên notch (trái: tìm và danh sách gần đây; phải: trình soạn), cửa sổ Ghi chú ba cột (thư mục, danh sách theo ngày, nội dung kèm thanh định dạng) hiện đủ ảnh, bảng và danh sách việc, tạo ghi chú mới (menu, công cụ, phím tắt, `--new-note`), và mục Ghi chú trong Cài đặt. Module thay "Ghi chú mới" cũ của Clipboard.

## Target và thư mục

- `NotesCore` — `Modules/Notes/Core/`
- `NotesFeature` — `Modules/Notes/Feature/`
- Test: `Modules/Notes/Tests/Core/` (`NotesCoreTests`, mẫu trong `Fixtures/`), `Modules/Notes/Tests/Feature/` (`NotesFeatureTests`)

## Phụ thuộc và ai dùng

- Dùng: `NotesCore` dùng `NotchCore`. `NotesFeature` dùng `NotesCore`, `NotchCore`, `NotchShell`. Trong ruột có SQLite của hệ thống, `Compression`, `NSAppleScript`; không thêm thư viện.
- Được dùng bởi: App (`AppDelegate` tạo `NotesController`). App nối: trang Ghi chú đăng ký sau trang Lịch, `makePageSettings()` ở Cài đặt › Trang notch, `makeToolSettings()` ở Cài đặt › Công cụ, công cụ `note`, mục menu "Ghi chú mới", phím `.newNote` (`start()` giữ trình xử lý), các tham số dòng lệnh `--new-note`, `--show-notes`, `--dump-note-data` (xem `App/README.md`).

## Giao diện công khai

- `NotesController.init(settings: NotesSettings, notch: NotchController)`
- `NotesController.start()`
- `NotesController.makePage() -> NotchPage`
- `NotesController.makePageSettings() -> AnyView`
- `NotesController.makeToolSettings() -> AnyView`
- `NotesController.newNote()`
- `NotesController.showWindow(noteID: String? = nil)`
- `NotesController.dumpNoteData(noteID: String, to file: URL) -> Bool`
- `NotesSettings(store:)` (Feature) và `NotesSettingsStore(defaults:)` với `recentIDs`, `selectedFolderID`, `defaultFolderID` (Core)
- Trong `NotesCore`: `NoteDocument` (và khối, kiểu chữ), `NotesHTMLReader`, `NotesHTMLWriter`, `NoteStoreDecoder`, `EditSafety`, `SaveGuard`.

Đổi `newNote()` hay `.newNote` là đụng chỗ App và Platform dùng: báo chủ dự án trước.

## Ghi chú cho người sửa

- Nguyên tắc số một: không bao giờ làm mất hay hỏng ghi chú của người dùng. Ghi lại bằng AppleScript là thay cả `body`, nên bất cứ thứ gì bộ đọc không hiểu mà bị bỏ rơi là mất dữ liệu. Vì vậy `EditSafety` chặn ghi (ghi chú chỉ xem) mỗi khi có nghi ngờ, kể cả khi bộ đọc dựng lại chữ khác với `plaintext` của ghi chú (lý do `unreadable`).
- Hai đường đọc: cơ sở dữ liệu của Notes (`NoteStoreReader` → `NoteStoreDecoder`, cần Full Disk Access, đầy đủ) và AppleScript (`body` + `plaintext` → `NotesHTMLReader`, thiếu kiểu danh sách). Đường ghi chỉ có AppleScript (`NotesHTMLWriter`).
- Ảnh không lấy được bằng AppleScript: `save attachment` hỏng trên macOS 27 (lỗi -10000). Ảnh đọc từ tệp media trong cơ sở dữ liệu, hoặc từ cache của app (`NoteImageCache`, khoá theo id tệp đính kèm `…/ICAttachment/pNN`; ảnh chưa lưu khoá `new-<uuid>`). Ghi lại một ghi chú thiếu ảnh thì Notes xoá ảnh, nên ghi chú có ảnh không lấy được là chỉ xem.
- Cỡ chữ: Notes đổi cỡ chữ nhận qua HTML (dưới 18 px thành 11 px; 18 px thành 15). Vì vậy bộ ghi viết thân bài 18 px (Notes hiển thị 15) và tiêu đề đậm 28/24/21 (Notes giữ 24/21/18). Bộ đọc nhận cả dạng cũ (đậm hệ thống 21/15/13) lẫn dạng đậm 24/21/18. Test dùng `keptByNotes()` để bắt chước việc Notes đổi cỡ. Đổi các số này thì đổi cả hai phía và thử trên Notes thật.
- Bộ đọc/ghi HTML, bộ giải mã protobuf và `EditSafety` có test trên mẫu thật trong `Tests/Core/Fixtures`. Sửa chúng thì thêm mẫu trước.
- `NotesStore` giữ máy trạng thái lưu (mở, sửa, lưu, xung đột, xoá). Mỗi lần tải có một số thế hệ (`generation`); `edit(_:generation:)` bỏ sửa của thế hệ cũ. Mỗi ghi chú có `writeCount`: lưu sau khi thế hệ khác đã ghi là xung đột, không phụ thuộc ngày giờ. Hai trình soạn (notch và cửa sổ) không bao giờ gửi một sửa có nền khác tài liệu hiện tại của store; chúng bắt kịp trước và hiện "Đã cập nhật từ cửa sổ kia" trong 2 giây.
- Cửa sổ và trang cùng dùng `NoteEditorView`. Dán hay thả ảnh phải thành tệp đính kèm có chỉ số trước khi vào văn bản, để không bao giờ có U+FFFC trần được lưu. Ô con trỏ không được đứng trong phần tiền tố danh sách (• , ☐ , 1. ).
- Notes được mở ở nền (không kích hoạt, ẩn) khi trang Ghi chú hay cửa sổ hiện, hoặc khi bấm Cho phép, nếu Notes chưa chạy. Kiểm tra thụ động không bao giờ hiện hộp hỏi quyền. Người đã thoát Notes sẽ thấy nó mở lại ở nền mỗi lần mở trang.
- Thư mục "Đã xoá gần đây" bị ẩn theo tên (`NotesScripts.trashFolderNames`: tiếng Anh và hai cách viết tiếng Việt), vì Notes không có thuộc tính đánh dấu nó.
- Kịch bản AppleScript nằm cả ở `NotesScripts` (chuỗi thuần, có test không cần Notes). `listNotes` phải dùng dạng `repeat with` đã kiểm trên Notes thật; dạng khác báo -1700.
- Sổ tay của quá trình làm (các phán quyết, ghi chú thử tay) nằm ở `.superpowers/sdd/PLAN/progress.md` trong nhánh làm việc; ý chính đã chép vào mục dưới.

## Dữ liệu lưu

- Không có kho riêng: ghi chú sống trong Notes.
- UserDefaults (`NotesSettingsStore`): `notes.recentIDs` (id ghi chú mở gần đây, tối đa 20), `notes.selectedFolderID` (thư mục đang chọn; notch và cửa sổ dùng chung), `notes.defaultFolderID` (thư mục cho ghi chú mới; không đặt thì dùng thư mục mặc định của Notes). Không có khoá nào khác trong mã. (DESIGN.md nhắc `notes.showsPage`: không có trong mã.)
- Cache ảnh: `~/Library/Caches/<bundle id>/Notes/` (`NoteImageCache`), xoá cái dùng lâu nhất khi vượt 200 MB.
- Đã thêm khoá `NSAppleEventsUsageDescription` (chỉ tiếng Anh: "AraNotch reads and writes your notes in Notes.") vào `App/Resources/Info.plist`.

## Quyền hệ thống

- Automation (điều khiển Notes): chỉ hỏi khi người dùng bấm Cho phép trên trang hay trong cửa sổ. Đã từ chối thì nút mở Cài đặt hệ thống › Quyền riêng tư › Automation. Không có quyền này thì trang chỉ hiện thẻ giải thích.
- Full Disk Access: không tự hỏi; thẻ mời cấp có nút mở đúng trang Cài đặt hệ thống. Không có thì dùng chế độ chỉ AppleScript (xem giới hạn).
- Cơ sở dữ liệu `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` mở chỉ đọc (không dùng `immutable=1`, vì Notes vẫn ghi vào nó).

## Test

- Chạy: `Scripts/test-module.sh Notes`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Notes/Tests/Core/`, `Modules/Notes/Tests/Feature/`. Feature test dùng Notes giả (`FakeNotesService`) và cơ sở dữ liệu giả; không chạm Notes thật.
- Test bộ giải mã trên ghi chú thật làm ở Notes trên macOS 27: `decodesRealNoteFromMacOS27`.
- Còn nợ thử tay (cần chuột và bàn phím thật): phím định dạng (⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘⇧M), menu nổi khi bôi chữ, ⌘K liên kết, dán ảnh, đóng notch giữa lúc đang lưu, xung đột khi đang sửa ở Notes, độ trễ khi gõ ghi chú dài (trình soạn dựng lại mỗi lần gõ).

## Tệp

- `Modules/Notes/Core/EditSafety.swift` — Why a note may not be written back.
- `Modules/Notes/Core/Gzip.swift` — Gzip decompression with the system Compression framework: the header is parsed here and the
- `Modules/Notes/Core/NoteDocument.swift` — Inline formatting of a run of text.
- `Modules/Notes/Core/NoteStoreDecoder.swift` — An attachment found in a note's data, in order of appearance.
- `Modules/Notes/Core/NotesHTMLReader.swift` — Turns the HTML Notes returns through AppleScript (`body of note`), plus the note's `plaintext`,
- `Modules/Notes/Core/NotesHTMLWriter.swift` — An image's bytes and type, as embedded in a note.
- `Modules/Notes/Core/NotesSettingsStore.swift` — Reads and writes the Notes settings.
- `Modules/Notes/Core/ProtobufReader.swift` — Reads the fields of one protobuf message in order. Every length is bounds-checked, so hostile
- `Modules/Notes/Core/SaveGuard.swift` — Detects a note that changed elsewhere since it was opened.
- `Modules/Notes/Feature/FormatPopover.swift` — What the format menu shows: which styles the selection has, and the link being typed.
- `Modules/Notes/Feature/FormatToolbar.swift` — What the Notes window's toolbar acts on: the window's editor, through the same calls as the floating menu
- `Modules/Notes/Feature/NoteAttachmentCells.swift` — A read-only preview drawn in place of a table, a file or a drawing inside the editor text.
- `Modules/Notes/Feature/NoteAttributedText.swift` — How wide or tall pictures are drawn in the text.
- `Modules/Notes/Feature/NoteEditorView.swift` — The editor of the open note, shared by the notch page and the Notes window.
- `Modules/Notes/Feature/NoteFormatting.swift` — The Telegram-style commands of the editor: a style is removed when the whole selection has it, otherwise added to all of it.
- `Modules/Notes/Feature/NoteImageCache.swift` — AraNotch's own copy of note images, so a note's images can be written back without Full Disk Access
- `Modules/Notes/Feature/NoteListGrouping.swift` — The date groups of the Notes window's list, as Notes shows them: Today, Yesterday, Previous 7 Days,
- `Modules/Notes/Feature/NoteStatusBanner.swift` — The strip above the editor (notch page and window alike) that says why the note cannot be edited
- `Modules/Notes/Feature/NoteStoreReader.swift` — What `NotesStore` reads from Notes' database; `NoteStoreReader` is the real one, tests use a fake.
- `Modules/Notes/Feature/NoteStoreWatcher.swift` — Tells when Notes writes to its database: watches NoteStore.sqlite and its -wal file, and calls `onChange` on the
- `Modules/Notes/Feature/NoteTextView.swift` — What the text view asks of the editor that owns it.
- `Modules/Notes/Feature/NotesAccessCard.swift` — The two System Settings panes Notes needs.
- `Modules/Notes/Feature/NotesBridge.swift` — Talks to the Notes app through AppleScript. Scripts run one at a time on a private queue, because
- `Modules/Notes/Feature/NotesController.swift` — The Notes feature as the app sees it: the notch page, its settings, a new note, and saving whenever the
- `Modules/Notes/Feature/NotesFeature.swift`
- `Modules/Notes/Feature/NotesPageView.swift` — What the Notes page needs beside the store: whether access was looked at yet, and the controller's actions.
- `Modules/Notes/Feature/NotesScripts.swift` — AppleScript source for each Notes command. Pure strings, so they can be tested without Notes.
- `Modules/Notes/Feature/NotesService.swift` — Notes ids look like "x-coredata://UUID/ICNote/p96"; the number is the row key in its database.
- `Modules/Notes/Feature/NotesSettings.swift` — Observable Notes settings; every change is written through to the store.
- `Modules/Notes/Feature/NotesStore.swift` — The note shown in the editor. `images` maps an `.image` block's attachmentIndex to a file holding its bytes.
- `Modules/Notes/Feature/NotesWindowController.swift` — The Notes window, made once and shown again. Says when it closes, so the controller can stop refreshing and save.
- `Modules/Notes/Feature/NotesWindowView.swift` — What the Notes window keeps beside the store: its own search, the folder being named, the note waiting for
- `Modules/Notes/DESIGN.md` — thiết kế (có phần sửa ngày 2026-10-27).
- `Modules/Notes/PLAN.md` — kế hoạch làm (có phần sửa ngày 2026-10-27).

## Lỗi và giới hạn đã biết

- **Không có kho riêng.** Ghi chú của AraNotch chính là ghi chú trong Apple Notes. Notes chưa chạy hay chưa cho Automation thì trang không có gì để hiện. Tài khoản khác iCloud và "Trên máy Mac": có thể chạy, chưa thử.
- **Cần Full Disk Access để hiển thị đủ.** AppleScript chỉ trả HTML, trong đó danh sách việc, danh sách số, trích dẫn thành `<ul>` hay `<div>` thường và ảnh không có. Thiếu quyền thì những thứ đó không biết được, nên ghi chú có danh sách bị coi là chỉ xem; ảnh cũng không lấy được trừ ảnh đã có trong cache của app.
- **Ghi chú chỉ xem, và lý do** (dải trên trình soạn nói rõ, có nút "Sửa trong Notes"): danh sách việc, danh sách số, trích dẫn, bản vẽ, tệp đính kèm hay đính kèm trong dòng (kể cả thẻ #), sửa bảng, ghi chú bị khoá, không đọc được (bộ đọc dựng lại chữ khác với chữ của Notes, hay dữ liệu hỏng), ảnh không có sẵn (ghi lại sẽ làm mất ảnh). Bảng chỉ xem được trọn vẹn, ghi lại giữ nguyên HTML của nó.
- **Ghi bằng AppleScript mất kiểu.** `set body` bằng HTML không tạo được tiêu đề, danh sách việc, danh sách số, trích dẫn của Notes; vì thế các ghi chú có chúng chỉ xem. Tiêu đề do AraNotch viết thành chữ đậm cỡ lớn, Notes đọc lại thành chữ đậm chứ không phải kiểu Tiêu đề của Notes.
- **`save attachment` hỏng trên macOS 27** (lỗi -10000, với mọi tệp đính kèm). Ảnh lấy từ tệp media của cơ sở dữ liệu (cần Full Disk Access) hay cache của app.
- **Cỡ chữ.** Notes đổi cỡ chữ nhận qua HTML (dưới 18 px thành 11 px, 18 px thành 15), không có HTML nào cho đúng cỡ thân bài gốc. Chủ dự án chọn: ghi thân bài 18 px (Notes hiện 15, to hơn chữ Notes gõ một chút) và tiêu đề đậm 28/24/21 (Notes giữ 24/21/18). Hệ quả: chữ trong ghi chú đã lưu từ AraNotch to hơn chữ gõ trong Notes một chút; một dòng toàn chữ đậm cỡ 24/21/18 gõ trong Notes được đọc là tiêu đề.
- **"Đã xoá gần đây" ẩn theo tên** (tiếng Anh và hai cách viết tiếng Việt). Giao diện Notes ngôn ngữ khác thì thư mục đó hiện như thư mục thường.
- **Notes được mở ở nền** khi trang hay cửa sổ hiện, nếu nó chưa chạy.
- **Xung đột.** Ghi chú bị app khác (Notes, máy khác) sửa sau lúc mở thì lần lưu kế là xung đột: không ghi, hiện nút Tải lại và Chép phần của tôi. Đọc lúc chưa ổn định quá giới hạn cũng mở ở trạng thái xung đột, nên đôi khi có dải xung đột thừa khi vừa gõ vừa tải lại.
- **Cơ sở dữ liệu của Notes không có tài liệu.** Bộ giải mã dựng theo thực nghiệm, thử trên ghi chú thật của macOS 27; bản macOS khác có thể đổi. Giải mã hỏng thì lùi về chế độ chỉ AppleScript và ghi log.
- **Chưa có màu riêng cho trang Ghi chú** trên notch: sáu màu của `AraHue` đã dùng hết, nên trang trung tính như Công cụ và Tổng quan. Thêm màu là đổi `NotchCore`, việc của chủ dự án.
- **Nhỏ, còn để lại:** bộ đọc HTML bỏ chữ nằm ngoài khối (chặn ghi bằng `unreadable`); thụt lề sâu hơn danh sách đang mở thì bị làm phẳng; chữ trống/tab đầu đoạn có thể bị Notes gộp; hai khối mã liền nhau gộp một; trình soạn dựng lại mỗi lần gõ (xem độ trễ với ghi chú dài); menu đoạn của cửa sổ có nhãn cố định; "+ Ghi chú" dùng thư mục đang hiện; thư mục mới tạo trong tài khoản mặc định; bắt kịp trình soạn kia thì mất lịch sử hoàn tác và vùng chọn.
- **Chưa thử tay** (xem mục Test): phím định dạng, menu nổi, ⌘K, dán ảnh, đóng notch giữa lúc lưu, xung đột khi sửa ở Notes, độ trễ khi gõ. Cũng chưa có rà soát cuối của cả nhánh.

## Nhật ký sửa lỗi

- 2026-10-27: bộ giải mã chưa từng chạy trên dữ liệu thật; thêm test `decodesRealNoteFromMacOS27` trên một ghi chú tạo trong Notes trên macOS 27. Giải mã đúng ngay lần đầu, ảnh đọc được từ tệp media qua cơ sở dữ liệu (commit 56a9bad).
- 2026-10-27: chữ AraNotch ghi qua HTML bị Notes ép về 11 px, nhỏ hơn chữ gốc, và tiêu đề cũ (đậm hệ thống 21/15/13) đọc lại thành chữ đậm thường. Sửa: thân bài ghi 18 px, tiêu đề đậm 28/24/21; bộ đọc nhận cả dạng cũ và dạng đậm 24/21/18. Test mô phỏng việc Notes đổi cỡ bằng `keptByNotes()` (commit 6c5ef14).
- 2026-10-27: tài liệu sửa: ảnh không lưu được bằng `save attachment` (hỏng trên macOS 27) mà đọc từ cơ sở dữ liệu hay cache; cỡ tiêu đề và thân bài theo cỡ mới. Dọn khoá chuỗi `clipboard.note.new` không còn dùng.
