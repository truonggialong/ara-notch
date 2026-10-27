# Ghi chú chỉ trên notch: bỏ cửa sổ Ghi chú

Ngày 2026-10-27. Chủ dự án duyệt từng phần trong phiên thiết kế. Module: Notes (cộng chỗ nối ở App).

## Mục tiêu

- Bỏ hẳn cửa sổ Ghi chú (`NotesWindowController`, `NotesWindowView`). Không giữ làm tuỳ chọn ẩn.
- Mọi thứ cửa sổ làm được thì trang Ghi chú trên notch làm được.
- Giữ nguyên toàn bộ phần dữ liệu và an toàn: đọc và ghi qua Apple Notes, `EditSafety`, `SaveGuard`, xung đột, `saveBeforeQuitting`.

## Những gì cửa sổ có mà trang chưa có

| Tính năng của cửa sổ | Trên trang sau khi làm |
|---|---|
| Cột thư mục theo tài khoản, "Tất cả ghi chú", số ghi chú | Nút chọn thư mục mở một bảng chọn vẽ trong notch |
| Tạo thư mục mới | Ô "+ Thư mục mới" cuối bảng chọn |
| Danh sách nhóm theo ngày, có đoạn trích | Thay danh sách "mở gần đây lên đầu" |
| Chuột phải: Hiện trong Notes, Xoá (thẻ hỏi lại trong danh sách) | Giống hệt |
| Thanh định dạng cố định (`FormatToolbar`) | Trên đầu cột soạn |
| Ảnh rộng bằng khung soạn | Thay ảnh thu nhỏ |
| Làm mới mỗi 30 giây khi thiếu Full Disk Access | Chạy khi notch mở ở trang Ghi chú |

## Những gì đã chốt

| Câu hỏi | Chốt |
|---|---|
| Bố cục | Hai cột như hiện nay; thư mục là nút chọn ở đầu cột trái |
| Chiều cao | Cố định: trang Ghi chú xin sheet cao 420 pt (`setSheetHeight`), notch tự kẹp tối đa 80% màn hình. Không có cài đặt |
| Danh sách | Nhóm theo ngày sửa như Apple Notes (`NoteListGrouping`); bỏ thứ tự "mở gần đây lên đầu" |
| Cách làm | Tách cửa sổ thành các view nhỏ co giãn theo `araScale`, trang ghép chúng; xoá cửa sổ |

## Bố cục

Notch rộng 640 pt trên sheet (800 pt trên màn hình ở cỡ mặc định), cao 420 pt khi trang Ghi chú đang hiện.

**Cột trái** (khoảng 38% bề ngang):

- Hàng trên: nút **📁 Tên thư mục ▾**, ô tìm, nút **+**.
- Bảng chọn thư mục: "Tất cả ghi chú" kèm tổng số, rồi thư mục theo tài khoản (nhãn tài khoản, tên, số ghi chú), cuối cùng "+ Thư mục mới" (ô nhập ngay trong bảng, Enter tạo, Esc huỷ). Bảng vẽ trong notch, đè lên danh sách, không dùng `NSPopover`: popover là cửa sổ riêng, con trỏ vào đó làm notch tưởng đã rời và đóng.
- Danh sách nhóm theo ngày; mỗi dòng: tên, giờ, đoạn trích, biểu tượng ảnh và khoá.
- Chuột phải một dòng: "Hiện trong Notes", "Xoá". Xoá hiện thẻ hỏi lại ở đầu danh sách (Huỷ, Xoá), không dùng hộp thoại hệ thống.
- Nút **+**: ghi chú mới trong thư mục đang xem; đang ở "Tất cả" thì dùng `defaultFolderID` của Cài đặt (không đặt thì thư mục mặc định của Notes).
- Thẻ mời cấp Full Disk Access (`NotesFullViewCard`) giữ chỗ như hiện nay.

**Cột phải:**

- `FormatToolbar` (nối qua `NoteEditorHandle`), tắt khi ghi chú không sửa được.
- `NoteStatusBanner`.
- `NoteEditorView` với `imageSize: .fitWidth(bề rộng cột trừ lề)`.
- Không còn nút ⤢.

Không có quyền Automation: cả trang là `NotesAccessCard`, như hiện nay.

## Cách hoạt động

### Mở notch thay cho cửa sổ

- `newNote()`: tạo ghi chú, chọn trang Ghi chú (`notch.selectPage`), mở notch (`notch.open`), mở ghi chú mới và đặt con trỏ vào trình soạn.
- Không tạo được (chưa có quyền, Notes không trả lời): vẫn chọn trang và mở notch; trang hiện thẻ quyền. Lệnh không bao giờ im lặng.
- Trang Ghi chú đang bị ẩn (`notch.isPageHidden`): vẫn tạo ghi chú, rồi mở nó trong Apple Notes (`showInNotes`). Không tự bỏ ẩn trang. Không tạo được thì mở Apple Notes.
- `--show-notes`: chọn trang Ghi chú và mở notch.
- Menu "Ghi chú mới", công cụ `note`, phím `.newNote`, `--new-note`: giữ nguyên, đều gọi `newNote()`.

### Giữ notch mở

`notch.setKeepsOpen(true, forPage:)` khi một trong các điều sau đúng; bỏ khi không còn điều nào:

- trình soạn có con trỏ (đã có);
- bảng chọn thư mục đang mở;
- đang gõ tên thư mục mới;
- đang có thẻ hỏi xoá.

Esc: đóng bảng chọn thư mục hoặc thẻ hỏi xoá trước; không có gì thì để notch xử lý như thường.

### Làm mới và lưu

- Có Full Disk Access: `NoteStoreWatcher` như hiện nay.
- Không có: bộ đếm 30 giây (`windowRefreshInterval`, đổi tên thành `refreshInterval`) chạy khi notch mở và trang Ghi chú đang hiện; dừng khi đóng notch hay rời trang.
- Lưu khi rời trang, đóng notch, thoát app: giữ nguyên. Bỏ các đường gắn với cửa sổ (`windowShowingChanged`, `windowMiniaturizedChanged`, `onClose`, `onMiniaturize`).
- Cửa sổ có tìm kiếm riêng; trang dùng `store.searchText` như hiện nay. Đổi thư mục không xoá ô tìm.
- `selectedFolderID` vẫn lưu ở `notes.selectedFolderID`.

## Giao diện công khai (chủ dự án đã duyệt ngày 2026-10-27)

- Bỏ `NotesController.showWindow(noteID:)`.
- `NotesController.newNote()` giữ chữ ký, đổi hành vi như trên.
- App: `--show-notes` gọi hàm mới `NotesController.showPage()` (chọn trang và mở notch).
- Platform không đổi: `selectPage`, `open`, `isPageHidden`, `setSheetHeight`, `setKeepsOpen` đã có.
- Khoá lưu: không thêm, không bỏ. `notes.recentIDs` vẫn ghi khi mở ghi chú và dùng để chọn ghi chú mở sẵn khi vào trang, chỉ không còn xếp danh sách.

## Tệp

- Xoá: `Feature/NotesWindowController.swift`, `Feature/NotesWindowView.swift`, `Tests/Feature/NotesWindowTests.swift` (test còn ý nghĩa chuyển sang test của trang).
- Thêm: `Feature/NoteFolderPicker.swift` (nút và bảng chọn thư mục, tạo thư mục), `Feature/NoteListColumn.swift` (danh sách nhóm theo ngày, dòng, menu chuột phải, thẻ hỏi xoá).
- Viết lại: `Feature/NotesPageView.swift` (bố cục, `NotesPageModel` mang thêm trạng thái bảng chọn, thư mục mới, thẻ xoá và `NoteEditorHandle`).
- Sửa: `Feature/NotesController.swift` (`newNote`, `showPage`, chiều cao, giữ mở, bộ đếm), `Feature/NotesSelfTest.swift` (điều khiển trang trên notch), `App/Sources/AppDelegate.swift`, `App/Sources/LaunchArguments.swift` (chú thích `--show-notes`).
- Chuỗi: khoá `notes.window.*` còn dùng đổi thành `notes.*` (ví dụ `notes.allNotes`, `notes.newFolder`, `notes.delete`); khoá không còn dùng (`notes.window.title`, `notes.openWindow`, `notes.window.none.detail`…) xoá ở `vi.lproj` và `en.lproj`.

## Test

Logic quyết định nằm trong model có closure, để test không cần notch thật. Trong `NotesFeatureTests`, dùng `FakeNotesService`:

- lọc danh sách theo thư mục và tìm kiếm;
- nút + chọn thư mục đang xem, hoặc `defaultFolderID` khi ở "Tất cả";
- thẻ hỏi xoá: Huỷ không xoá, Xoá gọi `delete` rồi làm mới;
- `newNote()`: trang hiện (chọn trang, mở notch, mở ghi chú); trang ẩn (mở trong Notes); không tạo được (vẫn mở trang);
- bộ đếm 30 giây chỉ chạy khi notch mở ở trang Ghi chú và không có Full Disk Access;
- giữ mở đúng với từng điều kiện trong bốn điều kiện;
- tạo thư mục: tên rỗng không tạo.

Kiểm chứng: `Scripts/test-module.sh Notes`, `Scripts/test.sh`, `swift build`, `Scripts/build-app.sh`, `open build/AraNotch.app`, `--self-test-notes` trên notch. Thử tay: chọn thư mục, tạo thư mục, xoá ghi chú, ảnh rộng bằng khung, notch không đóng khi đang dùng bảng chọn hay thẻ xoá, "Ghi chú mới" từ menu và phím tắt.

## Ghi sổ

`Modules/Notes/README.md` (vai trò, giao diện công khai, ghi chú cho người sửa, tệp, giới hạn, test), ghi chú sửa ở `Modules/Notes/DESIGN.md`, `App/README.md` (`--show-notes`), `docs/project/FEATURES.md`, một vòng trong `docs/project/HISTORY.md`.

## Ngoài phạm vi

- Không đổi bộ đọc, bộ ghi, `EditSafety`, `SaveGuard`, `NotesStore`, trừ chỗ cần cho các view mới.
- Không thêm màu riêng cho trang (giới hạn `AraHue` vẫn như cũ).
- Không thêm cài đặt chiều cao.
