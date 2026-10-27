# Notes (NotesCore, NotesFeature)

Sổ của module **Notes**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi. Thiết kế gốc ở [DESIGN.md](DESIGN.md), kế hoạch làm ở [PLAN.md](PLAN.md).

## Vai trò

Ghi chú định dạng chữ kiểu Telegram (bôi chữ là có menu nổi, có phím tắt), và dữ liệu là chính Apple Notes: ghi chú của AraNotch là ghi chú trong Notes, iCloud lo việc đồng bộ. Gồm trang Ghi chú trên notch (bố cục A từ 2026-10-27; trái, 30% bề ngang: ô tìm và nút + màu nhấn, tên thư mục đang xem kèm số ghi chú (bấm để chọn thư mục), danh sách nhóm theo ngày, rê chuột lên dòng thì có nút xoá, chuột phải để mở trong Notes hay xoá; xoá là xoá ngay, kèm dải Hoàn tác 10 giây trên danh sách; phải: một khung gồm hàng đầu (thư mục, giờ sửa, trạng thái lưu, nút Mở trong Notes và Xoá), thanh định dạng khi ghi chú sửa được, rồi trình soạn với dòng đầu cỡ lớn và ảnh rộng bằng khung), tạo ghi chú mới (menu, công cụ, phím tắt, `--new-note`, đều mở notch ở trang Ghi chú), và mục Ghi chú trong Cài đặt. Từ 2026-10-27 không còn cửa sổ Ghi chú riêng: mọi thứ của nó nằm trên trang. Module thay "Ghi chú mới" cũ của Clipboard.

## Target và thư mục

- `NotesCore` — `Modules/Notes/Core/`
- `NotesFeature` — `Modules/Notes/Feature/`
- Test: `Modules/Notes/Tests/Core/` (`NotesCoreTests`, mẫu trong `Fixtures/`), `Modules/Notes/Tests/Feature/` (`NotesFeatureTests`)

## Phụ thuộc và ai dùng

- Dùng: `NotesCore` dùng `NotchCore`. `NotesFeature` dùng `NotesCore`, `NotchCore`, `NotchShell`. Trong ruột có SQLite của hệ thống, `Compression`, `NSAppleScript`; không thêm thư viện.
- Được dùng bởi: App (`AppDelegate` tạo `NotesController`). App nối: trang Ghi chú đăng ký sau trang Lịch, `makePageSettings()` ở Cài đặt › Trang notch, `makeToolSettings()` ở Cài đặt › Công cụ, công cụ `note`, mục menu "Ghi chú mới", phím `.newNote` (`start()` giữ trình xử lý), các tham số dòng lệnh `--new-note`, `--show-notes` (gọi `showPage()`), `--dump-note-data`, `--self-test-notes` (xem `App/README.md`).

## Giao diện công khai

- `NotesController.init(settings: NotesSettings, notch: NotchController)`
- `NotesController.start()`
- `NotesController.makePage() -> NotchPage`
- `NotesController.makePageSettings() -> AnyView`
- `NotesController.makeToolSettings() -> AnyView`
- `NotesController.newNote()` (từ 0.30.0 ghi chú mở ngay dạng nháp, con trỏ sẵn, trước khi Notes tạo xong)
- `NotesController.showPage()` (mở notch ở trang Ghi chú; thay `showWindow(noteID:)` đã bỏ ngày 2026-10-27)
- `NotesController.dumpNoteData(noteID: String, to file: URL) -> Bool`
- `NotesController.saveBeforeQuitting(limit: Duration = .seconds(5)) async -> Bool` (App gọi trong `applicationShouldTerminate`)
- `NotesSettings(store:)` (Feature) và `NotesSettingsStore(defaults:)` với `recentIDs`, `selectedFolderID`, `defaultFolderID` (Core)
- Trong `NotesCore`: `NoteDocument` (và khối, kiểu chữ), `NotesHTMLReader`, `NotesHTMLWriter`, `NoteStoreDecoder` (trả `DecodedNote`), `EditSafety`, `SaveGuard`.

Đổi `newNote()` hay `.newNote` là đụng chỗ App và Platform dùng: báo chủ dự án trước.

## Ghi chú cho người sửa
- Bố cục trang (2026-10-27, phương án A, thiết kế `docs/superpowers/specs/2026-10-27-notes-page-layout-design.md`): `NoteEditorHeader.status(open:state:isReloading:)` quyết định chữ trạng thái (lỗi trước, rồi đang tải, rồi chỉ xem, rồi đã lưu / đang lưu). Thư mục trên hàng đầu lấy từ `NotesStore.folderID(of:)`, nhớ từ mọi lần liệt kê, nên vẫn còn khi danh sách sang thư mục khác. Thanh định dạng chỉ hiện khi ghi chú sửa được (bỏ qua lúc đang tải lại, khi đó nó chỉ mờ đi để chữ không nhảy). Nút đang bật dùng `AraPalette.brand` (cam): trên notch, màu nhấn gần như trùng màu biểu tượng. Nút + dùng kiểu `.accent` của hệ thống, nên trên notch là đĩa trắng.
- Bản nháp (từ 0.30.0, thiết kế `docs/superpowers/specs/2026-10-27-notes-draft-and-undo-design.md`): `newNote(_:in:opened:)` mở ngay một `OpenNote` có id `draft:<uuid>` (`NotesStore.isDraft`), gọi `opened` (trang đặt con trỏ), rồi chờ `finishCreating`: tạo ghi chú, đọc ngày sửa làm mốc SaveGuard, đổi id của `open` và của lần sửa đang chờ (giữ thế hệ, nên trình soạn không dựng lại), rồi ghi phần đã gõ. `startSaving` không ghi bản nháp; `flush` chờ việc tạo xong. Tạo hỏng: bản nháp ở lại với lỗi, sửa tiếp không còn được nhận, dải có nút Chép. `reloadOpenNote` bỏ qua bản nháp. Độ an toàn của bản nháp theo `fullView` và chỗ đặt tạm ảnh.
- Xoá kèm Hoàn tác (từ 0.30.0): `delete(_:started:)` lưu phần đang gõ (`flush`), bỏ ghi chú khỏi danh sách và trình soạn, báo `started` (trang hiện dải ngay), rồi mới bảo Notes xoá (đo: 6 giây; liệt kê lại thêm 15 giây). Notes từ chối thì liệt kê lại và mở lại ghi chú. `undoDelete` chuyển ghi chú từ "Đã xoá gần đây" về thư mục nhớ được (`NotesService.restore`, AppleScript `move note id … to folder id …`, đã thử trên Notes thật: giữ id và nội dung; `container` của ghi chú trong thùng rác báo -1728 nên thư mục phải nhớ từ lần liệt kê), đặt lại dòng của nó vào danh sách, mở lại nếu không có gì đang mở. Trang chờ lần xoá xong rồi mới hoàn tác. Không biết thư mục thì không có nút Hoàn tác.
- Cỡ chữ trình soạn tính theo điểm của chính nó: thân bài 11,2 (đơn cách 10,4), đề mục 17,6/15/12,6, dòng đầu 14 (`NoteAttributedText.leadSize`, đơn cách 13) khi là đoạn thường, giãn dòng 3 pt (`lineSpacing`), lề chữ 12 × 10: chỉ là cách vẽ. Trình soạn được phóng theo cỡ notch (`NSScrollView.magnification` = `araScale`, người dùng không chụm để đổi được), nên ở cỡ mặc định Lớn (×1,25) thân bài hiện 14 pt, nhỏ hơn tên ghi chú trong danh sách một chút. Ảnh vừa cột vì `NoteEditorView.unmagnified` chia bề ngang trang cho tỉ lệ; `NoteTextView.fitClipWidth` giữ bề ngang chữ bằng bounds của clip view (tự co giãn theo frame thì dòng chữ tràn mép phải khi phóng). `fitLeadLine` chạy ở cuối `make` và trong `textStorage(_:didProcessEditing:)` cho đoạn đầu, đoạn thứ hai và các đoạn vừa sửa; chỉ đổi cỡ phông, giữ nét. Bộ đọc lại tài liệu (`document(from:)`) chỉ xem nét đậm, nghiêng, đơn cách và thuộc tính khối, không xem cỡ, nên Notes nhận đúng như trước.

- Nguyên tắc số một: không bao giờ làm mất hay hỏng ghi chú của người dùng. Ghi lại bằng AppleScript là thay cả `body`, nên bất cứ thứ gì bộ đọc không hiểu mà bị bỏ rơi là mất dữ liệu. Vì vậy `EditSafety` chặn ghi (ghi chú chỉ xem) mỗi khi có nghi ngờ, kể cả khi bộ đọc dựng lại chữ khác với `plaintext` của ghi chú (lý do `unreadable`).
- Hai đường đọc: cơ sở dữ liệu của Notes (`NoteStoreReader` → `NoteStoreDecoder`, cần Full Disk Access, đầy đủ) và AppleScript (`body` + `plaintext` → `NotesHTMLReader`, thiếu kiểu danh sách). Đường ghi chỉ có AppleScript (`NotesHTMLWriter`).
- Ảnh không lấy được bằng AppleScript: `save attachment` hỏng trên macOS 27 (lỗi -10000). Ảnh đọc từ tệp media trong cơ sở dữ liệu, hoặc từ cache của app (`NoteImageCache`, khoá theo id tệp đính kèm `…/ICAttachment/pNN`; ảnh chưa lưu khoá `new-<uuid>`). Ghi lại một ghi chú thiếu ảnh thì Notes xoá ảnh, nên ghi chú có ảnh không lấy được là chỉ xem.
- Cỡ chữ: Notes đổi cỡ chữ nhận qua HTML (dưới 18 px thành 11 px; 18 px thành 15). Vì vậy bộ ghi viết thân bài 18 px (Notes hiển thị 15) và tiêu đề đậm 28/24/21 (Notes giữ 24/21/18). Bộ đọc nhận cả dạng cũ (đậm hệ thống 21/15/13) lẫn dạng đậm 24/21/18. Test dùng `keptByNotes()` để bắt chước việc Notes đổi cỡ. Đổi các số này thì đổi cả hai phía và thử trên Notes thật.
- Bộ đọc/ghi HTML, bộ giải mã protobuf và `EditSafety` có test trên mẫu thật trong `Tests/Core/Fixtures`. Sửa chúng thì thêm mẫu trước.
- `SaveGuard` chỉ cho ghi khi ngày sửa đúng bằng ngày đã đọc (cả hai qua AppleScript, làm tròn như nhau); khác một giây cũng là xung đột. Notes không tự dời ngày sau `set body` (đã đo).
- Bộ ghi viết mọi span chữ với `white-space: pre-wrap`; thiếu nó Notes gộp dấu cách và bỏ tab, cách đầu dòng.
- Với cơ sở dữ liệu: ngày `ZMODIFICATIONDATE1` của dòng phải trùng giây với ngày AppleScript (lệch thì đọc lại sau 300 ms, vẫn lệch thì `unreadable`); id tệp đính kèm của AppleScript được xếp theo thứ tự trong dữ liệu ghi chú (ZIDENTIFIER → Z_PK), không khớp thì ảnh không có sẵn.
- Trang xin sheet cao 420 pt (`NotesController.sheetHeight`). Notch được giữ mở (`setKeepsOpen`) khi trình soạn có con trỏ, bảng chọn thư mục mở, đang gõ tên thư mục, hay đang chọn ảnh (dải Hoàn tác không giữ notch) (`NotesPageModel.keepsNotchOpen`); rời trang thì mọi thứ đó đóng. Bảng chọn thư mục vẽ ngay trong notch, không dùng `NSPopover`: popover là cửa sổ riêng, con trỏ vào đó thì notch tưởng đã rời và đóng. Bảng chọn ảnh là `NSOpenPanel` riêng (`panel.begin`), không phải sheet trên panel của notch. Esc đóng ô tên thư mục, rồi bảng chọn, rồi dải Hoàn tác, trước khi đóng notch.
- `newNote()` mở trang ngay, trước khi Notes tạo xong. Trong lúc tạo (`isMakingNote`), trang không tự mở ghi chú gần nhất: việc đọc nó qua AppleScript sẽ xếp trước lệnh tạo và làm ghi chú mới chậm thêm hàng chục giây. Trang Ghi chú bị ẩn thì ghi chú mới mở trong Apple Notes. Không có Full Disk Access thì làm mới mỗi 30 giây khi trang đang hiện.
- `NotesStore` giữ máy trạng thái lưu (mở, sửa, lưu, xung đột, xoá). Mỗi lần tải có một số thế hệ (`generation`); `edit(_:generation:)` bỏ sửa của thế hệ cũ. Mỗi ghi chú có `writeCount`: lưu sau khi thế hệ khác đã ghi là xung đột, không phụ thuộc ngày giờ. Hai trình soạn (từ khi bỏ cửa sổ thì chỉ còn một trên trang, nhưng store vẫn giữ luật này) không bao giờ gửi một sửa có nền khác tài liệu hiện tại của store; chúng bắt kịp trước và hiện "Đã cập nhật từ cửa sổ kia" trong 2 giây. Trình soạn không được gõ bắt kịp sau khi bên kia ngừng gõ 0,5 giây. Trong lúc ghi chú đang mở được đọc lại (`isReloading`) thì không sửa được. Một lần tải thay ghi chú đang mở mà thấy lần lưu của nó vừa thành xung đột thì giữ nguyên ghi chú đó (kèm dải xung đột); bấm sang ghi chú kia lần nữa thì rời đi.
- Ảnh ghi vào Notes bằng `<img src="file://…">` trỏ tới tệp đặt tạm trong `~/Library/Group Containers/group.com.apple.notes/AraNotch/` (`NoteImageStaging`), xoá ngay sau khi ghi: Notes chép tệp vào thành ảnh thật, đúng chỗ. Ảnh dạng `data:` thì Notes trên macOS 27 giữ thành ô "File" (`public.data`), nên chỉ dùng trong test của bộ ghi. Ảnh Notes nhận qua HTML trước đây nằm ở loại `public.data` trong tệp không đuôi; bộ đọc nhận ra ảnh qua byte đầu (`NoteImageFormat`).
- Lưu sau 1,5 giây ngừng gõ; ghi chú có ảnh sau 5 giây (mỗi lần ghi gửi lại mọi ảnh lên iCloud). Rời trang, đóng notch, thoát app thì lưu ngay. Đọc ảnh và dựng HTML chạy ngoài main actor; cache giữ ảnh đã ghi dưới id mới bằng liên kết cứng, không ghi lại byte.
- Trang dùng `NoteEditorView` gắn với `NotesPageModel.editor` (`NoteEditorHandle`): thanh định dạng, việc đặt con trỏ khi tạo ghi chú mới (`focus()`, không dùng `focusTextField` của notch vì nó chọn ô tìm) và tự thử đều đi qua đó. Dán hay thả ảnh phải thành tệp đính kèm có chỉ số trước khi vào văn bản, để không bao giờ có U+FFFC trần được lưu. Ô con trỏ không được đứng trong phần tiền tố danh sách (• , ☐ , 1. ).
- Notes được mở ở nền (không kích hoạt, ẩn) khi trang Ghi chú hiện, hoặc khi bấm Cho phép, nếu Notes chưa chạy. Kiểm tra thụ động không bao giờ hiện hộp hỏi quyền. Người đã thoát Notes sẽ thấy nó mở lại ở nền mỗi lần mở trang.
- Thư mục "Đã xoá gần đây" bị ẩn theo tên (`NotesScripts.trashFolderNames`: tiếng Anh và hai cách viết tiếng Việt), vì Notes không có thuộc tính đánh dấu nó.
- Kịch bản AppleScript nằm cả ở `NotesScripts` (chuỗi thuần, có test không cần Notes). `listNotes` phải dùng dạng `repeat with` đã kiểm trên Notes thật; dạng khác báo -1700.

## Dữ liệu lưu

- Không có kho riêng: ghi chú sống trong Notes.
- UserDefaults (`NotesSettingsStore`): `notes.recentIDs` (id ghi chú mở gần đây, tối đa 20), `notes.selectedFolderID` (thư mục đang chọn), `notes.defaultFolderID` (thư mục cho ghi chú mới; không đặt thì dùng thư mục mặc định của Notes). Không có khoá nào khác trong mã. (DESIGN.md nhắc `notes.showsPage`: không có trong mã.)
- Cache ảnh: `~/Library/Caches/<bundle id>/Notes/` (`NoteImageCache`), xoá cái dùng lâu nhất khi vượt 200 MB.
- Đã thêm khoá `NSAppleEventsUsageDescription` (chỉ tiếng Anh: "AraNotch reads and writes your notes in Notes.") vào `App/Resources/Info.plist`.

## Quyền hệ thống

- Automation (điều khiển Notes): chỉ hỏi khi người dùng bấm Cho phép trên trang. Đã từ chối thì nút mở Cài đặt hệ thống › Quyền riêng tư › Automation. Không có quyền này thì trang chỉ hiện thẻ giải thích.
- Full Disk Access: không tự hỏi; thẻ mời cấp có nút mở đúng trang Cài đặt hệ thống. Không có thì dùng chế độ chỉ AppleScript (xem giới hạn).
- Cơ sở dữ liệu `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` mở chỉ đọc (không dùng `immutable=1`, vì Notes vẫn ghi vào nó).

## Test

- Chạy: `Scripts/test-module.sh Notes`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Notes/Tests/Core/`, `Modules/Notes/Tests/Feature/`. Feature test dùng Notes giả (`FakeNotesService`) và cơ sở dữ liệu giả; không chạm Notes thật.
- Test bộ giải mã trên ghi chú thật làm ở Notes trên macOS 27: `decodesRealNoteFromMacOS27`.
- Tự thử bằng `--self-test-notes` chạy trên trang Ghi chú của notch từ 2026-10-27 (bỏ cửa sổ): qua hết, notch 800×525 trên màn hình ở cỡ mặc định, ghi chú mới mở sau 14–17 giây (bản 0.27.0 trên cùng Notes hôm đó: 13 và 44 giây; Notes chậm với lệnh tạo). Chụp notch: danh sách nhóm theo ngày, thanh định dạng, ảnh rộng, bảng chọn thư mục trong notch với ghim sáng. Chưa thử bằng con trỏ thật: mở menu kiểu đoạn, bảng chọn ảnh, menu chuột phải và thẻ hỏi xoá, Esc (chỉ có test tự động).
- Tự thử bằng `--self-test-notes` (2026-10-27, sự kiện phím và chuột gửi qua app, không phải chuột và bàn phím thật): ⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘⇧M đúng; menu nổi hiện trên vùng chọn (cách 6 pt) và cú bấm đầu tiên ăn; ⌘K thêm liên kết; đề mục và danh sách từ thanh công cụ; ⌘V dán ảnh thành ảnh thật trong Notes; gõ trong ghi chú 1500 dòng tốn tối đa khoảng 6 ms mỗi phím; chữ gõ ngay trước ⌘Q được lưu. Kết quả đã đối chiếu trong Notes. Chưa thử: kéo chuột để chọn chữ, kéo thả ảnh, cuộn bằng con lăn, trang Ghi chú trên notch (đóng notch giữa lúc lưu).

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
- `Modules/Notes/Feature/FormatToolbar.swift` — What the page's toolbar acts on: the page's editor, through the same calls as the floating menu
- `Modules/Notes/Feature/NoteEditorHeader.swift` — The row over the open note: its folder, when it was changed, whether it is saved, Show in Notes and Delete.
- `Modules/Notes/Feature/NoteAttachmentCells.swift` — A read-only preview drawn in place of a table, a file or a drawing inside the editor text.
- `Modules/Notes/Feature/NoteAttributedText.swift` — How wide or tall pictures are drawn in the text.
- `Modules/Notes/Feature/NoteEditorView.swift` — The editor of the open note, on the notch page.
- `Modules/Notes/Feature/NoteFormatting.swift` — The Telegram-style commands of the editor: a style is removed when the whole selection has it, otherwise added to all of it.
- `Modules/Notes/Feature/NoteImageCache.swift` — AraNotch's own copy of note images, so a note's images can be written back without Full Disk Access
- `Modules/Notes/Feature/NoteFolderPicker.swift` — The title of the page's list (folder shown and its count) that opens the folder list; the folder list, drawn inside the notch.
- `Modules/Notes/Feature/NoteListColumn.swift` — The page's list by date and its rows (`NoteListRow`: delete button under the pointer, Show in Notes and Delete on a right click), the delete question in a card.
- `Modules/Notes/Feature/NoteListGrouping.swift` — The date groups of the page's list, as Notes shows them: Today, Yesterday, Previous 7 Days,
- `Modules/Notes/Feature/NoteStatusBanner.swift` — The strip above the editor that says why the note cannot be edited
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
- `docs/superpowers/specs/2026-10-27-notes-draft-and-undo-design.md` — thiết kế bản nháp khi bấm + và xoá kèm Hoàn tác.
- `docs/superpowers/specs/2026-10-27-notes-page-layout-design.md` — thiết kế bố cục A của trang (hai cột tinh gọn).
- `Modules/Notes/DESIGN.md` — thiết kế (có phần sửa ngày 2026-10-27).
- `docs/superpowers/specs/2026-10-27-notes-in-notch-design.md`, `docs/superpowers/plans/2026-10-27-notes-in-notch.md` — thiết kế và kế hoạch bỏ cửa sổ Ghi chú.
- `Modules/Notes/PLAN.md` — kế hoạch làm (có phần sửa ngày 2026-10-27).

## Lỗi và giới hạn đã biết

- **Không có kho riêng.** Ghi chú của AraNotch chính là ghi chú trong Apple Notes. Notes chưa chạy hay chưa cho Automation thì trang không có gì để hiện. Tài khoản khác iCloud và "Trên máy Mac": có thể chạy, chưa thử.
- **Cần Full Disk Access để hiển thị đủ.** AppleScript chỉ trả HTML, trong đó danh sách việc, danh sách số, trích dẫn thành `<ul>` hay `<div>` thường và ảnh không có. Thiếu quyền thì những thứ đó không biết được, nên ghi chú có danh sách bị coi là chỉ xem; ảnh cũng không lấy được trừ ảnh đã có trong cache của app. Thiếu quyền thì trích dẫn, màu, tô sáng, phông, căn lề cũng không thấy được, nên **mọi ghi chú chỉ xem** (lý do "cần Full Disk Access để sửa"; chủ dự án chọn ngày 2026-10-27, thay cho cho sửa kèm cảnh báo), kể cả ghi chú mới tạo. Không có cơ sở dữ liệu thì ảnh xếp theo thứ tự AppleScript trả về.
- **Ghi chú chỉ xem, và lý do** (dải trên trình soạn nói rõ, có nút "Sửa trong Notes"): danh sách việc, danh sách số, trích dẫn, bản vẽ, tệp đính kèm hay đính kèm trong dòng (kể cả thẻ #), định dạng AraNotch không giữ được (phông, chữ trên, màu, tô sáng, căn lề khác trái; chỉ biết được khi có Full Disk Access), sửa bảng, ghi chú bị khoá, không đọc được (bộ đọc dựng lại chữ khác với chữ của Notes, hay dữ liệu hỏng), ảnh không có sẵn (ghi lại sẽ làm mất ảnh). Bảng chỉ xem được trọn vẹn, ghi lại giữ nguyên HTML của nó.
- **Ghi bằng AppleScript mất kiểu.** `set body` bằng HTML không tạo được tiêu đề, danh sách việc, danh sách số, trích dẫn của Notes; vì thế các ghi chú có chúng chỉ xem. Tiêu đề do AraNotch viết thành chữ đậm cỡ lớn, Notes đọc lại thành chữ đậm chứ không phải kiểu Tiêu đề của Notes.
- **`save attachment` hỏng trên macOS 27** (lỗi -10000, với mọi tệp đính kèm). Ảnh lấy từ tệp media của cơ sở dữ liệu (cần Full Disk Access) hay cache của app.
- **Cỡ chữ.** Notes đổi cỡ chữ nhận qua HTML (dưới 18 px thành 11 px, 18 px thành 15), không có HTML nào cho đúng cỡ thân bài gốc. Chủ dự án chọn: ghi thân bài 18 px (Notes hiện 15, to hơn chữ Notes gõ một chút) và tiêu đề đậm 28/24/21 (Notes giữ 24/21/18). Hệ quả: chữ trong ghi chú đã lưu từ AraNotch to hơn chữ gõ trong Notes một chút; một dòng toàn chữ đậm cỡ 24/21/18 gõ trong Notes được đọc là tiêu đề.
- **"Đã xoá gần đây" ẩn theo tên** (tiếng Anh và hai cách viết tiếng Việt). Giao diện Notes ngôn ngữ khác thì thư mục đó hiện như thư mục thường, và ghi chú bị xoá ở Notes trong lúc đang mở thì lần lưu báo lỗi thay vì "đã bị xoá".
- **Ghi chú mới chậm khi Notes đang bận**: thường 3–4 giây từ lúc bấm tới khi mở được; ngay sau khi lưu một ghi chú rất dài (1500 dòng) có lần tới 35 giây, vì các lệnh AppleScript chạy nối nhau sau lần ghi đó.
- **Ghi ảnh cần Full Disk Access**: AraNotch đặt tạm tệp ảnh trong thư mục `AraNotch` của nó bên trong thư mục chứa của Notes (thư mục rỗng còn lại sau khi ghi; tệp bị bỏ lại khi app thoát giữa lúc lưu được dọn sau một giờ). Không đặt được thì ghi chú có ảnh là chỉ xem ("ảnh không có sẵn") và không dán được ảnh, vì ghi ảnh kiểu `data:` sẽ biến ảnh thành ô "File" trong Notes.
- **Cỡ chữ riêng không giữ được**: cỡ chữ người dùng chọn trong Notes (khác cỡ AraNotch ghi) về cỡ thân bài sau một lần lưu từ AraNotch.
- **Lưu ghi chú có ảnh chậm hơn**: 5 giây sau khi ngừng gõ (thay vì 1,5), để mỗi lần ghi không gửi lại mọi ảnh lên iCloud quá thường.
- **Notes được mở ở nền** khi trang hiện, nếu nó chưa chạy.
- **Xung đột.** Ghi chú bị app khác (Notes, máy khác) sửa sau lúc mở thì lần lưu kế là xung đột: không ghi, hiện nút Tải lại và Chép phần của tôi. Đọc lúc chưa ổn định quá giới hạn cũng mở ở trạng thái xung đột, nên đôi khi có dải xung đột thừa khi vừa gõ vừa tải lại.
- **Cơ sở dữ liệu của Notes không có tài liệu.** Bộ giải mã dựng theo thực nghiệm, thử trên ghi chú thật của macOS 27; bản macOS khác có thể đổi. Giải mã hỏng thì lùi về chế độ chỉ AppleScript và ghi log.
- **Chưa có màu riêng cho trang Ghi chú** trên notch: sáu màu của `AraHue` đã dùng hết, nên trang trung tính như Công cụ và Tổng quan. Thêm màu là đổi `NotchCore`, việc của chủ dự án.
- **Nhỏ, còn để lại:** bộ đọc HTML bỏ chữ nằm ngoài khối (chặn ghi bằng `unreadable`); thụt lề sâu hơn danh sách đang mở thì bị làm phẳng; thụt lề danh sách quá 10 cấp (chỉ có ở dữ liệu hỏng) bị coi là 10; hai khối mã liền nhau gộp một; mỗi lần gõ vẫn dựng lại tài liệu từ văn bản và đăng lại ghi chú mở, nên danh sách ghi chú cũng vẽ lại (xem độ trễ với ghi chú dài); menu kiểu đoạn trên thanh định dạng chỉ có biểu tượng (cho vừa cột soạn); "+" dùng thư mục đang hiện (Tất cả: thư mục mặc định); thư mục mới tạo trong tài khoản mặc định; bắt kịp trình soạn kia thì mất lịch sử hoàn tác và vùng chọn.
- **Bản nháp:** thoát app trong lúc Notes còn đang tạo ghi chú chỉ chờ tối đa 5 giây (giới hạn của `saveBeforeQuitting`); quá thì chữ gõ trong bản nháp mất. Tạo hỏng mà đã sang ghi chú khác thì chữ của bản nháp chỉ còn trong log lỗi, không hiện ra.
- **Hoàn tác** chỉ cho lần xoá gần nhất, trong 10 giây, khi trang còn hiện; ghi chú vẫn nằm trong "Đã xoá gần đây" của Notes như trước.
- **Bố cục A chưa thử trên app thật**: trang ở chế độ chỉ xem (thanh định dạng ẩn; chỉ có test). Nút xoá khi rê chuột đã thử bằng con trỏ thật trên bản 0.29.0. Đã thử qua Accessibility trên app thật (2026-10-27): hàng đầu, nút đang bật sáng cam, thẻ hỏi xoá từ hàng đầu và Huỷ, bảng chọn thư mục, đổi thư mục, mở ghi chú khác.
- **Chưa thử tay** (xem mục Test): phím định dạng, menu nổi, ⌘K, dán ảnh, cắt và dán ảnh trong ghi chú, đóng notch giữa lúc lưu, thoát app ngay sau khi gõ, xung đột khi sửa ở Notes, độ trễ khi gõ. Đã kiểm trên Notes thật (2026-10-27): `ZMODIFICATIONDATE1` khớp ngày AppleScript (ghi chú thường sửa được); hai ảnh hiện đúng thứ tự; chữ màu (trường 10) bị khoá đúng; đoạn kiểm "Recently Deleted"; một lần lưu thật qua `--append-note` giữ khoảng trắng, tab và ảnh thật. Chưa kiểm: tô sáng (trường 14), chữ trên (8), căn lề (2) trên ghi chú thật.

## Nhật ký sửa lỗi

- 2026-10-27: chủ dự án thấy thân bài 15 pt hơi to, nhờ giảm chút. Sửa: cả thang nhân 14/15, thân bài hiện 14 pt ở cỡ mặc định. Test `textIsSizedToReadInTheNotch`; chụp trên app thật.

- 2026-10-27: chữ trong trình soạn quá nhỏ (chủ dự án báo): thân bài 13 pt và không theo cỡ notch, nên ở cỡ mặc định chữ ghi chú nhỏ hơn cả chữ danh sách (15). Sửa: trình soạn phóng theo `araScale`, cỡ gốc thân bài 12 (hiện 15 ở cỡ mặc định), đề mục 3 to hơn thân bài. Test `textIsSizedToReadInTheNotch`, `editorFollowsTheNotchsSize`; chụp trang Ghi chú trên app thật ở cỡ mặc định.

- 2026-10-27 (0.30.0, thử trên Notes thật): dải Hoàn tác hiện sau khoảng 21 giây (đợi Notes xoá rồi liệt kê lại), đã quá lúc người ta cần; tên trên dải là tên cũ "New Note". Sửa: ghi chú rời trang và dải hiện ngay (`started`), tên lấy từ dòng đầu đang gõ; nút Hoàn tác không bị cắt chữ, dải 10 giây. Test `aDeleteShowsAtOnceAndARefusalBringsTheNoteBack`.
- 2026-10-27 (bố cục A, thử trên app thật): chip thư mục trên hàng đầu biến mất khi danh sách sang thư mục không chứa ghi chú đang mở, vì nó tìm trong danh sách đang hiện. Sửa: `NotesStore` nhớ thư mục của mọi ghi chú đã liệt kê (`folderID(of:)`). Test `theOpenNotesFolderIsKnownAfterTheListMoves`.

- 2026-10-27: bộ giải mã chưa từng chạy trên dữ liệu thật; thêm test `decodesRealNoteFromMacOS27` trên một ghi chú tạo trong Notes trên macOS 27. Giải mã đúng ngay lần đầu, ảnh đọc được từ tệp media qua cơ sở dữ liệu (commit 56a9bad).
- 2026-10-27: chữ AraNotch ghi qua HTML bị Notes ép về 11 px, nhỏ hơn chữ gốc, và tiêu đề cũ (đậm hệ thống 21/15/13) đọc lại thành chữ đậm thường. Sửa: thân bài ghi 18 px, tiêu đề đậm 28/24/21; bộ đọc nhận cả dạng cũ và dạng đậm 24/21/18. Test mô phỏng việc Notes đổi cỡ bằng `keptByNotes()` (commit 6c5ef14).
- 2026-10-27: tài liệu sửa: ảnh không lưu được bằng `save attachment` (hỏng trên macOS 27) mà đọc từ cơ sở dữ liệu hay cache; cỡ tiêu đề và thân bài theo cỡ mới. Dọn khoá chuỗi `clipboard.note.new` không còn dùng.
- 2026-10-27 (rà soát cuối, I3): `SaveGuard` coi lệch một giây là cùng lúc, nên sửa từ iPhone đồng bộ về ngay sau lần ghi của AraNotch bị ghi đè. Sửa: chỉ ghi khi ngày bằng đúng; điều kiện đọc lại khi danh sách đổi cũng so như vậy. Test `sameDateWrites`, `anyOtherDateConflicts` (commit 74135fe).
- 2026-10-27 (I5): dấu cách liền nhau, tab và cách đầu dòng bị Notes gộp hay bỏ khi ghi, làm phẳng khối mã. Sửa: mọi span chữ có `white-space: pre-wrap` (đã thử trên Notes thật). Test `keepsLeadingSpacesRunsAndTabs`, `keepsTheIndentationOfACodeBlock`, `readsTheSizeBeforeOtherDeclarations` (commit 2396136).
- 2026-10-27 (M1): độ dài run hay thụt lề cực lớn trong dữ liệu hỏng làm tràn số và sập app. Sửa: so trước khi cộng, kẹp thụt lề 0…10 (`NoteDocument.maxListIndent`) ở bộ giải mã, bộ ghi và trình soạn. Test `hugeLengthAndIndentAreClamped`, `writerTakesAHugeIndentAsOneLevelDeeper`, `hugeIndentIsDrawnAtTheDeepestLevel` (commit 5f21ffb).
- 2026-10-27 (I4, phần A): ghi lại làm mất phông, màu, tô sáng, chữ trên, căn lề mà bộ đọc không thấy. Sửa: bộ giải mã đánh dấu (`DecodedNote.hasUnsupportedFormatting`), lý do chỉ xem mới `formatting`. Phần B (trích dẫn khi thiếu Full Disk Access) để nguyên theo quyết định của chủ dự án. Test `flagsFormattingTheWriterCannotKeep`, `plainFormattingIsNotFlagged`, `unsupportedFormattingMakesReadOnly`, `formattingTheWriterCannotKeepMakesReadOnly` (commit 57897c3).
- 2026-10-27 (M3): cơ sở dữ liệu ghi sau AppleScript một chút, nên kiểu khối vừa đổi ở Notes có thể bị ghi lại thành kiểu cũ. Sửa: đọc `ZMODIFICATIONDATE1` cùng `ZDATA`, phải trùng giây với ngày AppleScript; lệch thì đọc lại sau 300 ms, vẫn lệch thì `unreadable`. Test `readsTheRowsModificationDate`, `noDateColumnGivesNoDate`, `databaseRowOlderThanTheNoteIsUnreadable` (commit c017a0b).
- 2026-10-27 (I6): ảnh gán cho id tệp đính kèm theo vị trí, có thể bị đổi chỗ. Sửa: với cơ sở dữ liệu, xếp id của AppleScript theo ZIDENTIFIER → Z_PK của dữ liệu ghi chú; không khớp thì ảnh không có sẵn. Test `imagesFollowTheDatabasesDocumentOrder`, `attachmentsTheDatabaseCannotPlaceMakeImagesUnavailable`, `findsTheRowKeyOfEachAttachment` (commit 5859212).
- 2026-10-27 (I7): mỗi lần lưu ghi chú có ảnh đọc, mã base64 và ghi lại cache mọi ảnh trên main actor, và gửi lại ảnh lên iCloud. Sửa: dựng HTML trong tác vụ tách rời; cache dùng liên kết cứng (qua tên tạm, nên ảnh đổi chỗ không mất); ghi chú có ảnh lưu sau 5 giây. Test `savedImagesAreLinkedNotRewritten`, `aNoteWithImagesSavesAfterALongerPause` (commit 214793e).
- 2026-10-27 (I2): gõ trong lúc tải lại, hay gõ vào ghi chú cũ khi đang mở ghi chú khác, bị bỏ nếu lần lưu thành xung đột. Sửa: không sửa được khi đang tải lại (`isReloading`); lần tải thấy xung đột mới của ghi chú đang mở thì giữ ghi chú đó với dải xung đột. Test `editorIsNotEditableWhileItsNoteIsReloaded`, `editOnTheOldVersionDuringAReloadKeepsItAsAConflict`, `switchingStaysOnANoteWhoseSaveConflicts`, `lateConflictingEditOfTheNoteLeftKeepsItOpen` (commit f701cb7).
- 2026-10-27 (I1): thoát app trong lúc chờ lưu làm mất chữ vừa gõ. Sửa: `saveBeforeQuitting` (tối đa 5 giây), App trả `.terminateLater` rồi trả lời khi lưu xong. Test `quittingSavesWhatWasTyped`, `quittingWaitsForASaveOnlyUpToTheLimit` (commit 575c35f, App 79c049f).
- 2026-10-27 (M2): trạng thái khoá lấy từ lần liệt kê trước, nên ghi chú vừa khoá mở ra thành ghi chú trống sửa được. Sửa: đọc `password protected` cùng nội dung. Test `noteLockedSinceTheListingIsReadOnly`, `contentReadsTheLockState` (commit f063fa3).
- 2026-10-27 (M4): ghi chú bị xoá ở Notes (vào "Đã xoá gần đây") báo lưu hỏng thay vì "đã bị xoá". Sửa: lỗi -10000 khi ghi thì tìm id trong các thư mục rác của từng tài khoản; có thì báo không tìm thấy. Test `trashLookupChecksEveryTrashName`, `onlyAFailedWriteWithMinusTenThousandMayBeADeletedNote` (commit 3ee4bf6).
- 2026-10-27 (M5): "Ghi chú mới" không làm gì khi Notes đóng và chưa liệt kê gì. Sửa: mở Notes ở nền; không tạo được thì vẫn mở cửa sổ (thẻ quyền truy cập). Test `newNoteStartsAClosedNotes` (commit a28cb8e).
- 2026-10-27 (M8): `NoteAttachmentCell` đọc thuộc tính main actor từ `cellSize` (cảnh báo Swift 6). Sửa: hằng `nonisolated`, `content` là `nonisolated(unsafe)`. Kiểm bằng `swift build` không còn cảnh báo (commit cf105a5).
- 2026-10-27: quy tắc `.formatting` khoá mọi ghi chú ghi qua HTML, vì Notes gắn cho chữ đó một phông có cỡ (và tên `Courier`, `.AppleSystemUIFont`, `.AppleSystemUIFontBold`). Sửa: chỉ phông có tên khác những tên này mới tính. Test bằng ba ghi chú thật `realNotesWrittenThroughHTMLAreNotFlagged`, `realColouredWordIsFlagged` (commit 7ba2ed4).
- 2026-10-27: ảnh AraNotch đã ghi đọc lại thành tệp đính kèm (`public.data`, tệp media không đuôi), nên mọi ghi chú có ảnh thành chỉ xem sau lần lưu đầu. Sửa: bộ đọc nhận ảnh qua byte đầu; lấy ảnh lấy đuôi từ byte. Test `publicDataWhoseFileIsAPictureIsAPicture`, `imageInAFileWithoutExtensionLoads`, `NoteImageFormatTests`. `--dump-note-data` ghi thêm loại và tệp của từng đính kèm (commit fc340d0).
- 2026-10-27: mỗi lần lưu ghi chú có ảnh biến ảnh thành ô "File" ngay trong Notes (ảnh `data:` thành `public.data` trên macOS 27). Sửa: ghi ảnh bằng `file://` tới tệp đặt tạm trong thư mục chứa của Notes (`NoteImageStaging`), xoá sau khi ghi; không đặt được thì không ghi. Kiểm trên Notes thật: ảnh vẫn là ảnh, đúng chỗ, sau khi lưu. Test `picturesAreWrittenAsFilesNotesCanReadAndRemovedAfter`, `picturesThatCannotBeStagedFailTheSave`. Thêm `--append-note` để lưu như khi gõ (commit 8920543).
- 2026-10-27: không có Full Disk Access thì trích dẫn đọc ra thành dòng thường và lần lưu làm mất nó. Chủ dự án chọn chỉ xem: lý do mới `needsFullDiskAccess` khi có cơ sở dữ liệu mà không đọc được. Test `everyNoteIsViewOnlyWithoutFullDiskAccess`.
- 2026-10-27 (rà lại N1): với cơ sở dữ liệu, đề mục AraNotch ghi (đậm 24/21/18) và dạng h1–h3 của Notes đọc lại thành đoạn đậm, lần lưu sau ghi chúng về cỡ thân bài; Courier trong dòng mất. Sửa: bộ giải mã đọc tên phông và cỡ của từng đoạn, nhận đề mục như bộ đọc HTML, Courier là đơn cách. Test trên ghi chú thật `realHeadingsReadAsHeadingsFromTheDatabase`, `courierIsMonospaced`; lưu thật qua `--append-note`: đề mục giữ 24/21/18 (commit 38a0ae2).
- 2026-10-27 (rà lại N2–N6): thiếu chỗ đặt tạm ảnh thì ghi chú có ảnh là chỉ xem và không dán được ảnh (trước đó mọi lần lưu thất bại); chỉ tệp media không tên của Notes mới được dò byte (tệp RAW thật vẫn là tệp); GIF, TIFF là ảnh; tệp tạm bị bỏ lại quá một giờ được dọn; đặt tạm ảnh trước khi kiểm ngày. Test `picturesThatCannotBeStagedMakeTheNoteViewOnly`, `stagingRemovesOldLeftovers`, `publicDataWhoseFileIsAPictureIsAPicture` (commit 94851b4).
- 2026-10-27 (M6): cắt rồi dán ảnh trong ghi chú làm mất ảnh. Sửa: chép và cắt ghi thêm kiểu riêng `com.aranotch.notes.fragment` (chữ và byte ảnh theo thứ tự); dán dùng nó trước. Test `cutAndPasteKeepsPictures` (commit 19a9408).
- 2026-10-27 (M7, một phần): trình soạn không được gõ dựng lại cả ghi chú sau mỗi phím gõ ở trình soạn kia. Sửa: bắt kịp sau 0,5 giây ngừng gõ. Test `secondEditorFollowsEditsOfTheFirst` (sửa: ba lần sửa, một lần dựng lại) (commit c4997cc). Chưa làm: đưa tài liệu đang sửa ra khỏi thứ danh sách ghi chú quan sát.
- 2026-10-27 (bỏ cửa sổ): tự thử trên notch thấy ghi chú mới mất 33 giây: trang hiện ra tự mở ghi chú gần nhất, việc đọc nó xếp trước lệnh tạo trong hàng AppleScript. Sửa: không tự mở trong lúc đang tạo (`isMakingNote`). Test `newNoteDoesNotReadAnotherNoteFirst`. Cũng trong vòng này: hai test dựa vào thời gian (`coalescesChangesWithinTheInterval`, `twoEditsOfANoteLeftBehindBothReachNotes`) hỏng khi một test khác giữ main actor gần một giây; sửa test cho không phụ thuộc vào việc main actor trả lời trong 60–100 ms.
- 2026-10-27 (rà soát nhánh bỏ cửa sổ, I-1 và I-2): notch bị giữ mở mãi khi ghi chú đang có con trỏ bị xoá (trình soạn bị gỡ mà không được báo mất con trỏ), hay khi ghi chú đang chờ xác nhận xoá biến mất khỏi danh sách. Sửa: `open` về nil thì bỏ cờ con trỏ; ghi chú rời danh sách thì bỏ câu hỏi xoá. Test `theNotchIsLetGoWhenTheFocusedNoteGoesAway`, `aDeleteQuestionGoesWithItsNote`.
