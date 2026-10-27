# Ghi chú (Notes): thiết kế

Ngày 2026-10-27. Chủ dự án duyệt từng phần trong phiên thiết kế; tệp này là bản viết lại để duyệt lần cuối trước khi lập kế hoạch.

## Mục tiêu

- Ghi chú trong AraNotch, định dạng chữ kiểu Telegram (bôi chữ là có menu, có phím tắt).
- Dữ liệu là chính Apple Notes: AraNotch không có kho riêng, iCloud lo việc đồng bộ sang thiết bị khác.
- Cửa sổ Ghi chú riêng hiển thị đầy đủ như Apple Notes, kể cả ảnh, danh sách việc đã tích, bảng.
- Không bao giờ làm mất hay hỏng một ghi chú của người dùng.

## Những gì đã chốt

| Câu hỏi | Chốt |
|---|---|
| Kiểu đồng bộ | Ghi chú của AraNotch là ghi chú trong Apple Notes (mọi thư mục), đọc và ghi thẳng, không kho riêng |
| Trang trên notch | Sửa được đầy đủ ngay trên notch; ảnh hiện thu nhỏ |
| Đường đọc | Cơ sở dữ liệu của Notes (cần Full Disk Access) để hiển thị đủ; lùi về AppleScript khi thiếu quyền hoặc giải mã hỏng |
| Đường ghi | AppleScript, có rào chắn: ghi chú có thứ không ghi lại được thì chỉ xem |
| Cửa sổ lớn | 3 cột: thư mục, danh sách ghi chú, nội dung |
| Trang notch | Trái: tìm và danh sách gần đây, nút +; phải: nội dung sửa được, nút ⤢ mở cửa sổ lớn |
| Thanh định dạng | Cả hai: thanh cố định ở cửa sổ lớn, menu nổi khi bôi chữ ở cả notch và cửa sổ, cộng phím tắt |
| "Ghi chú mới" cũ | Thay bằng tính năng này (xem mục Thay chức năng cũ) |

## Thử nghiệm đã làm (2026-10-27, macOS 27)

Một ghi chú thử trong thư mục "AraNotch-probe" (đã xoá), tạo qua AppleScript rồi chủ dự án thêm các kiểu gốc của Notes bằng tay.

| Thứ | Đọc qua AppleScript (`body`) | Ghi qua AppleScript (`set body`) |
|---|---|---|
| Đậm `<b>`, nghiêng `<i>`, gạch chân `<u>`, gạch ngang `<strike>`, liên kết `<a>` | Có | Có |
| Đơn cách | `<font face="Courier">`, khối mã ra `<tt>` | Có (thành font Courier) |
| Danh sách chấm `<ul>`, danh sách gạch `<ul class="Apple-dash-list">` | Có | Có |
| Tiêu đề, Đề mục của Notes | `<h1>`, `<h2>` | Không: thành chữ đậm cỡ 21 và 15 px |
| Danh sách việc | Thành `<ul>` thường, mất trạng thái tích | Không |
| Danh sách số | Thành `<ul>` thường | Không (`<ol>` thành `<ul>`) |
| Trích dẫn | Thành `<div>` thường | Không |
| Bảng | `<object><table>…</table></object>` | Có, giữ nguyên khi ghi lại đúng HTML đã đọc |
| Ảnh | Không có trong `body` (chỉ một `<div>` trống); `plaintext` có `U+FFFC` đúng chỗ; `save attachment … in file` lấy ra tệp gốc, không cần Full Disk Access **(sửa 2026-10-27: sai, `save attachment` hỏng trên macOS 27 với lỗi -10000; ảnh lấy từ tệp media trong cơ sở dữ liệu, cần Full Disk Access, hoặc từ cache của app theo id tệp đính kèm)** | `<img src="data:image/png;base64,…">` thành tệp đính kèm thật, hiện trong Notes |

Hệ quả:

1. Ghi lại một ghi chú mà thiếu ảnh thì Notes xoá ảnh đó. Bộ ghi phải nhúng lại mọi ảnh, đúng vị trí `U+FFFC`.
2. Từ HTML không phân biệt được danh sách chấm, danh sách số, danh sách việc. Muốn hiển thị đúng và biết ghi chú nào an toàn để ghi, phải đọc cơ sở dữ liệu của Notes.
3. Bảng được tính là một tệp đính kèm (`count of attachments` tăng 1).
4. Id ghi chú (`x-coredata://…/ICNote/pNN`) không đổi khi ghi lại `body`.
5. `duplicate` không dùng được với ghi chú (lỗi -1717).

## Kiến trúc

Module mới `Notes`, theo mẫu của `Modules/README.md`:

```
Modules/Notes/
  Core/            NotesCore: mô hình, HTML, protobuf, rào chắn (thuần, có test)
  Feature/         NotesFeature: AppleScript, đọc cơ sở dữ liệu, trang notch, cửa sổ, cài đặt
  Tests/Core/      NotesCoreTests (mẫu HTML và protobuf trong Fixtures/)
  Tests/Feature/   NotesFeatureTests
  README.md        sổ của module
  DESIGN.md        tệp này
```

### NotesCore

- `NoteDocument`: một ghi chú là dãy khối. Khối: đoạn, tiêu đề (cấp 1–3), mục danh sách (chấm, gạch, số, việc kèm đã tích hay chưa; có mức thụt), trích dẫn, khối đơn cách, ảnh (id tệp đính kèm), bảng (HTML gốc và lưới ô để hiển thị), tệp khác (tên, loại). Trong khối là các đoạn chữ có kiểu: đậm, nghiêng, gạch chân, gạch ngang, đơn cách, liên kết.
- `NotesHTMLReader`: HTML của `body` cộng thứ tự ảnh từ `plaintext` thành `NoteDocument`. Bỏ qua cỡ chữ và font, trừ: Courier là đơn cách; chữ đậm `.AppleSystemUIFontBold` cỡ 21 hay 15 px đứng riêng một dòng là tiêu đề (vì chính AraNotch ghi tiêu đề ra như vậy). **Sửa 2026-10-27:** Notes ép mọi cỡ dưới 18 px về 11 px, nên AraNotch ghi thân bài 18 px (Notes hiện 15) và tiêu đề đậm 28/24/21 (Notes giữ 24/21/18); bộ đọc nhận cả dạng cũ lẫn chữ đậm 24/21/18 đứng riêng một dòng.
- `NotesHTMLWriter`: `NoteDocument` thành HTML cho `set body`. Tiêu đề ghi thành chữ đậm cỡ to; ảnh nhúng `data:` đúng chỗ; bảng ghi lại nguyên HTML đã đọc.
- `NoteStoreDecoder`: dữ liệu `ZICNOTEDATA.ZDATA` (gzip, rồi protobuf của Notes) thành `NoteDocument` đầy đủ: kiểu đoạn (tiêu đề, đề mục, đề mục phụ, đơn cách, chấm, gạch, số, việc, trích dẫn), trạng thái tích, kiểu chữ, liên kết, vị trí tệp đính kèm và loại của nó. Bộ đọc protobuf tự viết, nhỏ, không thêm thư viện.
- `EditSafety`: từ `NoteDocument` đầy đủ trả về `.editable` hoặc `.readOnly(lý do)`. Chỉ xem khi có: danh sách việc, danh sách số, trích dẫn, tệp đính kèm không phải ảnh hay bảng, bản vẽ, ghi chú bị khoá. Tiêu đề, Đề mục của Notes không chặn sửa, nhưng sổ ghi rõ là sau khi lưu chúng thành chữ đậm cỡ to.
- `EditSafety` khi không có bản đầy đủ (chế độ chỉ AppleScript): mọi ghi chú có `<ul>` không có class đều chỉ xem.
- `SaveGuard`: so ngày sửa lúc mở với ngày sửa hiện tại trước khi ghi; khác thì không ghi, báo xung đột.

### NotesFeature

- `NotesBridge`: chạy AppleScript qua `NSAppleScript` trên một hàng đợi riêng. Liệt kê tài khoản, thư mục, ghi chú (id, tên, ngày sửa, thư mục, khoá hay không); đọc `body` và `plaintext`; lấy id tệp đính kèm (không lưu được tệp: `save attachment` hỏng trên macOS 27, sửa 2026-10-27); tạo, ghi, xoá ghi chú; tạo thư mục. Có một giao thức để test thay bằng Notes giả.
- `NoteStoreReader`: mở `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` bằng SQLite của hệ thống với `SQLITE_OPEN_READONLY` (không dùng `immutable=1`, vì Notes vẫn đang ghi vào tệp), tìm ghi chú theo id `ZICCLOUDSYNCINGOBJECT` khớp với số `pNN` của id AppleScript, đưa dữ liệu cho `NoteStoreDecoder`. Thiếu quyền hay giải mã hỏng thì trả `nil` và ghi log; nơi gọi lùi về chế độ chỉ AppleScript.
- Theo dõi thay đổi: `DispatchSource` trên `NoteStore.sqlite-wal` (khi có Full Disk Access), gộp các lần đổi trong 1 giây rồi làm mới danh sách. Không có quyền thì làm mới khi mở trang, mở cửa sổ, và mỗi 30 giây khi cửa sổ đang mở.
- `NoteEditor`: `NSTextView` bọc cho SwiftUI, dùng chung ở notch và cửa sổ. `NSAttributedString` qua lại `NoteDocument`. Ảnh là `NSTextAttachment` (thu nhỏ trên notch, vừa chiều rộng ở cửa sổ). Bảng là một attachment vẽ lưới chỉ xem. Ở chế độ chỉ xem, trình soạn không cho sửa và vẽ đủ ô tích, số, trích dẫn.
- Menu nổi khi bôi chữ: Đậm, Nghiêng, Gạch chân, Gạch ngang, Đơn cách, Liên kết, Xoá định dạng.
- Thanh cố định (chỉ ở cửa sổ): như menu nổi, cộng menu kiểu đoạn (Tiêu đề, Đề mục, Đề mục phụ, Thân), Danh sách chấm, Khối mã, Chèn ảnh.
- Phím tắt trong trình soạn: ⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘⇧M, ⌘K.
- Chèn ảnh: dán, kéo thả, hoặc chọn tệp.
- Tự lưu sau 1,5 giây ngừng gõ và khi đóng, qua `SaveGuard`.
- `NotesController`: `makePage()`, `makeSettingsSection()`, `showWindow(noteID:)`, `newNote()`, `start()`; đặt bộ xử lý cho phím tắt `.newNote`.
- Trang notch: chia đôi; trái là ô tìm, nút +, danh sách ghi chú gần đây (tên, giờ, biểu tượng ảnh, ổ khoá); phải là `NoteEditor` của ghi chú đang chọn và nút ⤢.
- Cửa sổ Ghi chú: 3 cột. Cột 1: ô tìm, tài khoản và thư mục kèm số ghi chú, nút + Thư mục. Cột 2: ghi chú nhóm theo ngày (Hôm nay, Hôm qua, 7 ngày trước, tháng…), nút + Ghi chú. Cột 3: thanh định dạng và `NoteEditor`. Chuột phải trên ghi chú: Mở trong Notes, Xoá (xác nhận ngay trong cửa sổ, không dùng hộp thoại hệ thống).
- Ghi chú chỉ xem: dải trên cùng nêu lý do và có nút "Sửa trong Notes" (mở bằng URL của Notes hay AppleScript `show`).
- Giao diện theo hệ thống thiết kế hiện có của app (`NotchShell/Design`): nền trắng ngà, thẻ trắng, nút viên đen, một màu cam.

### App

- `AppDelegate` tạo `NotesController`, thêm trang Ghi chú, mục cài đặt Ghi chú, nối "Ghi chú mới" trên thanh menu, công cụ `note` của trang Công cụ, tham số `--new-note` vào `notes.newNote()`.
- `Info.plist`: thêm `NSAppleEventsUsageDescription`. Kiểm tra `Scripts/build-app.sh`: nếu ký với hardened runtime thì thêm quyền `com.apple.security.automation.apple-events`.
- `Package.swift`: `core("Notes")`, `feature("Notes")`, test Core và Feature, thêm `Notes` vào `features`; `Scripts/test-module.sh` nhận `Notes`; một dòng trong bảng của `Modules/README.md`.

## Thay chức năng cũ

"Ghi chú mới" hiện là trình soạn viết một mục chữ vào clipboard. Chủ dự án chọn thay hẳn nó bằng tính năng này:

- Menu thanh menu "Ghi chú mới", công cụ `note`, tham số `--new-note`, phím tắt `.newNote` đều gọi `NotesController.newNote()`: mở cửa sổ Ghi chú với một ghi chú trống mới trong thư mục mặc định.
- Case `ShortcutAction.newNote` và khoá lưu phím tắt giữ nguyên, nên phím người dùng đã đặt vẫn dùng được. Dòng phím tắt chuyển từ mục cài đặt Clipboard sang mục Ghi chú; chuỗi `settings.clipboard.newNote.note` thay bằng chuỗi mới của Notes; tiền tố tìm kiếm trong Cài đặt cập nhật theo.
- Clipboard: bỏ `ClipboardController.newNote()` (hàm `public`, chủ dự án đã đồng ý bỏ), bỏ `onNewNote` và nút ✎ trên trang Clipboard, bỏ phần "mục chữ mới" trong `ClipEditor` (`newNoteID`, `openNew`) cùng test `aNewNoteStartsWithTheCursorInItsText`. Phần sửa một mục có sẵn giữ nguyên.
- Sổ Clipboard, Platform, Tools, App cập nhật theo.

## Đồng bộ và dữ liệu

- Notes là nguồn duy nhất. AraNotch lưu trong UserDefaults: `notes.recentIDs` (id ghi chú mở gần đây), `notes.selectedFolderID`, `notes.defaultFolderID` (thư mục cho ghi chú mới; mặc định là thư mục mặc định của Notes), `notes.showsPage`.
- Ảnh (sửa 2026-10-27: lấy từ tệp media của cơ sở dữ liệu, không bằng AppleScript) được giữ trong `~/Library/Caches/<bundle id>/Notes/<id ghi chú>/`, xoá khi ghi chú bị xoá hay khi cache quá 200 MB (xoá cái cũ nhất trước).
- Danh sách chỉ đọc tên, dòng đầu, ngày sửa, có ảnh không, khoá không; nội dung đọc khi mở ghi chú.
- Lưu: đọc ngày sửa hiện tại; trùng ngày sửa lúc mở thì `set body`, rồi đọc lại ngày sửa mới làm mốc. Khác thì báo "Ghi chú đã đổi ở nơi khác" với nút Tải lại và Chép phần của tôi; không ghi.

## Quyền hệ thống

- Automation (điều khiển Notes): chỉ hỏi khi người dùng bấm nút trên trang Ghi chú hay trong cửa sổ. Đã từ chối thì nút mở Cài đặt hệ thống > Quyền riêng tư > Automation.
- Full Disk Access: không tự hỏi; thẻ "Cấp Full Disk Access để xem đủ" có nút mở đúng trang Cài đặt hệ thống. Không có quyền thì vẫn dùng được ở chế độ chỉ AppleScript.

## Lỗi và tình huống biên

| Tình huống | Hành vi |
|---|---|
| Notes chưa chạy | AppleScript mở Notes ở nền; trang hiện vòng chờ trong lúc đọc |
| Chưa có hay bị từ chối Automation | Thẻ giải thích, nút Cho phép hoặc mở Cài đặt hệ thống |
| Thiếu Full Disk Access | Chế độ chỉ AppleScript; thẻ nhỏ mời cấp quyền |
| Giải mã cơ sở dữ liệu hỏng | Như thiếu Full Disk Access cho ghi chú đó; ghi log |
| Lưu thất bại | Giữ nội dung đang soạn, báo lỗi, nút Chép nội dung |
| Ghi chú đổi ở nơi khác giữa chừng | Không ghi; nút Tải lại, Chép phần của tôi |
| Ghi chú bị khoá | Hiện tên và ổ khoá; bấm vào thì mở bằng Notes |
| Ghi chú bị xoá ở nơi khác khi đang mở | Báo "Ghi chú đã bị xoá", nút Chép nội dung, Tạo lại |
| Xoá ghi chú | Xác nhận trong cửa sổ; Notes đưa vào Đã xoá gần đây |

## Kiểm thử

- `NotesCoreTests`:
  - `NotesHTMLReader` và `NotesHTMLWriter` trên mẫu HTML thật của thử nghiệm.
  - Đi rồi về (HTML → mô hình → HTML → mô hình) ra giống hệt.
  - Ảnh được nhúng lại đúng vị trí `U+FFFC`.
  - Bảng giữ nguyên HTML.
  - `NoteStoreDecoder` trên mẫu protobuf thật lấy từ một ghi chú thử, làm sạch, không chứa nội dung thật của người dùng.
  - `EditSafety` cho từng loại khối, ở cả hai chế độ.
  - `SaveGuard`.
- `NotesFeatureTests`:
  - Đổi kiểu chữ trong `NoteEditor` (bôi chữ, ⌘B…).
  - `NSAttributedString` qua lại `NoteDocument`.
  - `NotesController` với Notes giả: tạo, lưu, xung đột, chỉ xem.
- Thử thật trong một thư mục thử của Notes, xoá sau khi xong:
  - Tạo, sửa, chèn ảnh, lưu; đối chiếu trong Notes bằng ảnh chụp.
  - Sửa ở Notes giữa chừng thì AraNotch báo xung đột.
  - Ghi chú có ô tích mở chỉ xem và hiện đúng trạng thái tích.
  - Có và không có Full Disk Access.
  - Phím tắt "Ghi chú mới" mở cửa sổ với ghi chú trống.
- Phần cần chuột thật mà công cụ không làm được thì ghi vào danh sách thử tay còn nợ.

## Ngoài phạm vi

- Tạo hay sửa bảng, danh sách việc, danh sách số, trích dẫn từ AraNotch (AppleScript không ghi được).
- Spoiler (Notes không có).
- Ghi chú bị khoá.
- Thư mục chia sẻ, cộng tác.
- Đính kèm tệp không phải ảnh từ AraNotch.
- Tài khoản Notes khác iCloud và "Trên máy Mac": có thể chạy, chưa thử.
