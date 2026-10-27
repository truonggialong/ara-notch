# AraNotch

Ứng dụng macOS biến tai thỏ (notch) của MacBook thành một bảng điều khiển nhỏ: clipboard, nhạc đang phát, hẹn giờ, lịch và lời nhắc, ghi chú, thả tệp, chụp màn hình, dịch nhanh và trạng thái của các agent lập trình.

A macOS app that turns the MacBook notch into a small control panel: clipboard, now playing, timers, calendar and reminders, notes, a file shelf, screen capture, quick translate and the state of coding agents.

## Mới trong bản 0.27.0 · New in 0.27.0

- **Ghi chú:** trang Ghi chú mới trên notch và một cửa sổ Ghi chú riêng. Viết và định dạng chữ ngay tại chỗ: đậm, nghiêng, gạch chân, gạch ngang, chữ đơn cách, liên kết, đề mục, danh sách và ảnh. Bôi chữ là có menu định dạng, hoặc dùng phím tắt (⌘B, ⌘I, ⌘U…).
- **Dùng chính Apple Notes:** ghi chú của AraNotch là ghi chú trong app Notes, nên tự đồng bộ qua iCloud sang iPhone và iPad. Ghi chú có danh sách việc, trích dẫn hay hình vẽ vẫn hiện đầy đủ để xem, kèm nút mở trong Notes để sửa.
- **"Ghi chú mới" tạo ghi chú trong Notes:** phím tắt và mục "Ghi chú mới" mở một ghi chú Apple Notes mới trong cửa sổ Ghi chú.
- **Không còn hỏi mật khẩu máy liên tục:** khi bật "Lấy giới hạn từ tài khoản Claude", macOS không còn hỏi mật khẩu sau mỗi lần cập nhật app.

Lần đầu dùng Ghi chú, AraNotch xin quyền điều khiển Notes. Để sửa ghi chú, cấp thêm **Full Disk Access** trong System Settings › Privacy & Security; chưa cấp thì ghi chú chỉ xem được.

---

- **Notes:** a new Notes page on the notch and a Notes window of its own. Write and format right there: bold, italic, underline, strikethrough, monospaced text, links, headings, lists and pictures. Select text for a format menu, or use the shortcuts (⌘B, ⌘I, ⌘U…).
- **It is Apple Notes:** AraNotch's notes are notes in the Notes app, so iCloud syncs them to your iPhone and iPad. Notes with checklists, quotes or drawings still show in full to read, with a button to edit them in Notes.
- **"New note" makes a note in Notes:** the shortcut and the "New note" item open a new Apple Notes note in the Notes window.
- **No more password prompts:** with "Read limits from the Claude account" on, macOS no longer asks for your password after each app update.

The first time you use Notes, AraNotch asks to control Notes. To edit notes, also give it **Full Disk Access** in System Settings › Privacy & Security; without it notes are read only.

## Tính năng · Features

- **Tổng quan:** những gì cần xem nhanh trên một trang, bạn tự chọn ô nào, ở đâu, cỡ nào.
- **Clipboard:** nhớ mọi thứ bạn chép (chữ, liên kết, màu, ảnh, tệp), tìm lại nhanh kể cả chữ trong ảnh, ghim vào board, khoá board bằng mật mã. Cửa sổ Thư viện để xem và sắp xếp tất cả.
- **Nhạc:** bài đang phát, điều khiển phát nhạc, chọn loa hay tai nghe, lời bài hát.
- **Hẹn giờ:** nhiều bộ hẹn giờ cùng lúc, có mức sẵn và nhãn.
- **Lịch và lời nhắc:** ngày của bạn theo giờ, ba ngày tới, thêm sự kiện và lời nhắc, ước tính thời gian làm.
- **Tệp:** thả tệp lên notch để giữ tạm, nén, đổi định dạng hay đổi cỡ ảnh.
- **Ghi chú:** viết và định dạng chữ ngay trên notch (bôi chữ là có menu đậm, nghiêng, gạch chân…), dùng chính ghi chú của Apple Notes nên đồng bộ qua iCloud; thư mục, danh sách theo ngày, thanh định dạng và ảnh đều ngay trên notch.
- **Chụp màn hình:** chụp một vùng, chụp cả trang dài bằng cách cuộn, ghi chú lên ảnh.
- **Dịch nhanh:** chọn chữ trong bất kỳ app nào rồi dịch ngay.
- **Agent lập trình:** xem Claude Code và Codex đang làm gì, khi nào cần bạn, khi nào xong, và còn bao nhiêu giới hạn sử dụng.
- **Thông báo gọn gàng:** pin, Bluetooth, mạng, âm lượng, độ sáng, Caps Lock, bài hát mới và cuộc họp sắp tới hiện ngay cạnh notch.
- **Cửa sổ:** kéo cửa sổ vào mép màn hình hay dùng phím tắt để chia đôi, chia góc.
- Dùng được trên mọi màn hình, kể cả màn hình rời không có tai thỏ; giao diện tiếng Việt và tiếng Anh, chọn trong Cài đặt › Chung › Ngôn ngữ.

---

- **Overview:** what you want at a glance on one page; you choose which tiles, where, and how large.
- **Clipboard:** keeps everything you copy (text, links, colours, pictures, files), finds it again (even the text inside pictures), pins it to boards, and locks boards with a passcode. A Library window to browse and sort it all.
- **Music:** what is playing, playback controls, picking speakers or headphones, lyrics.
- **Timers:** several at once, with presets and labels.
- **Calendar and reminders:** your day hour by hour, the next three days, adding events and reminders, time estimates.
- **Files:** drop files on the notch to keep them at hand, compress them, convert them or resize pictures.
- **Notes:** write and format text right on the notch (select text for a menu of bold, italic, underline…), using your Apple Notes notes themselves so they sync through iCloud; folders, notes by date, a format toolbar and pictures, all on the notch.
- **Screen capture:** capture an area, capture a long page by scrolling, and mark up the picture.
- **Quick translate:** select text in any app and translate it at once.
- **Coding agents:** see what Claude Code and Codex are doing, when they need you, when they are done, and how much of their usage limits is left.
- **Tidy notices:** battery, Bluetooth, network, volume, brightness, Caps Lock, a new song and an upcoming meeting show right beside the notch.
- **Windows:** drag a window to a screen edge or use a shortcut to fill half or a corner of the screen.
- Works on every display, external ones without a notch too; in Vietnamese and English, chosen in Settings › General › Language.

## Tải về · Download

Bản mới nhất: **[Releases › Latest](https://github.com/truonggialong/ara-notch/releases/latest)** — tải tệp `AraNotch-<phiên bản>.dmg`, mở ra và kéo AraNotch vào thư mục Applications.

The newest version is on the **[latest release](https://github.com/truonggialong/ara-notch/releases/latest)**: download `AraNotch-<version>.dmg`, open it and drag AraNotch into Applications.

## Yêu cầu · Requirements

- macOS 15 trở lên · macOS 15 or later
- Máy Mac dùng chip Apple Silicon · a Mac with Apple Silicon

Đã thử trên macOS 27; chưa thử trên macOS 15 và 26. Máy Mac chạy chip Intel không mở được AraNotch.

Tried on macOS 27; not yet tried on macOS 15 and 26. Macs with Intel chips cannot run AraNotch.

## Lần mở đầu tiên · First launch

AraNotch chưa được ký bằng Apple Developer ID và chưa được Apple chứng nhận (notarize), nên lần đầu macOS sẽ chặn. Mở **System Settings › Privacy & Security**, kéo xuống và bấm **Open Anyway** cho AraNotch. Chỉ cần làm một lần.

AraNotch is not signed with an Apple Developer ID and is not notarized, so macOS blocks its first launch. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** for AraNotch. This is needed once.

## Cập nhật · Updates

Từ bản 0.12.0, AraNotch tự kiểm tra bản mới mỗi ngày một lần và cài khi bạn đồng ý. Kiểm tra bằng tay: trang Thông tin trên notch, hoặc nút Kiểm tra ngay ở Cài đặt › Chung › Tự kiểm tra bản mới.

From 0.12.0 on, AraNotch looks for a newer version once a day and installs it when you agree. To check by hand: the About page on the notch, or Check now in Settings › General › Look for new versions.

## Quyền riêng tư · Privacy

AraNotch không thu thập hay gửi dữ liệu nào về cho người làm ra nó. Những gì rời khỏi máy:

- Khi bạn chép một liên kết, AraNotch mở ngầm liên kết đó một lần để lấy tiêu đề và ảnh (tắt được trong Cài đặt › Clipboard). Liên kết trông như đăng nhập, mã một lần hay token thì bỏ qua.
- Đoạn chữ bạn chọn để dịch được gửi tới Google Translate, chỉ khi bạn bấm dịch.
- Lời bài hát được hỏi từ lrclib.net, chỉ khi bạn bật lời bài hát (mặc định tắt).
- Mỗi ngày một lần, AraNotch hỏi GitHub có bản mới không.

Ghi chú không rời máy qua AraNotch: app đọc và ghi chúng qua app Notes, iCloud đồng bộ như mọi ghi chú khác của bạn. Với Full Disk Access, AraNotch chỉ đọc kho dữ liệu của Notes (để thấy danh sách việc, trích dẫn và ảnh), không sửa nó; khi lưu ghi chú có ảnh, app đặt tạm tệp ảnh trong một thư mục riêng tên `AraNotch` bên trong thư mục của Notes rồi xoá ngay.

Lịch sử clipboard nằm trên máy bạn, trong `~/Library/Application Support/AraNotch`, và mặc định không vào bản sao lưu Time Machine. Board khoá được mã hoá.

AraNotch collects nothing and sends nothing to its maker. What leaves the Mac: a link you copy is opened once in the background for its title and picture (can be turned off in Settings › Clipboard; links that look like sign-ins, one-time codes or tokens are skipped); text you choose to translate goes to Google Translate when you ask; lyrics are asked of lrclib.net when you turn lyrics on (off by default); and once a day AraNotch asks GitHub for a newer version. Notes do not leave the Mac through AraNotch: it reads and writes them through the Notes app, and iCloud syncs them like your other notes. With Full Disk Access, AraNotch only reads Notes' data store (to see checklists, quotes and pictures) and never changes it; when it saves a note with pictures, it puts the picture files for a moment in a folder of its own named `AraNotch` inside Notes' folder, then removes them. The clipboard history stays on your Mac, in `~/Library/Application Support/AraNotch`, out of Time Machine backups by default; locked boards are encrypted.

## Gỡ cài đặt · Removing AraNotch

Cài đặt › Nâng cao › **Gỡ AraNotch**: gỡ hook và dòng trạng thái khỏi Claude Code (có giữ bản sao lưu), thôi mở cùng máy, xoá bộ nhớ đệm và, nếu bạn chọn, cả lịch sử clipboard và cài đặt, rồi chuyển app vào Thùng rác.

Settings › Advanced › **Remove AraNotch** takes its hooks and status line out of Claude Code (keeping a backup), stops it opening at login, removes its caches and, if you tick it, the clipboard history and settings, then moves the app to the Trash.

## Mã nguồn · Source

Mã nguồn nằm trong kho này, chia theo tính năng: mỗi tính năng có một thư mục `Modules/<Tên>/` chứa phần logic có test (`Core/`), giao diện (`Feature/`), test (`Tests/`) và sổ riêng (`README.md`). `App/` chỉ lắp ráp các tính năng. Bắt đầu từ `Modules/README.md`. Dựng bằng `Scripts/build-app.sh`, chạy test bằng `Scripts/test.sh` (macOS 15, Apple Silicon).

The source code is in this repository, split by feature: each feature has one folder `Modules/<Name>/` holding its tested logic (`Core/`), its interface (`Feature/`), its tests (`Tests/`) and its own guide (`README.md`). `App/` only puts the features together. Start at `Modules/README.md`. Build with `Scripts/build-app.sh`, test with `Scripts/test.sh` (macOS 15, Apple Silicon).

## Giấy phép · License

AraNotch là phần mềm tự do theo giấy phép GNU General Public License phiên bản 3 (GPL-3.0). Xem tệp `LICENSE`.

AraNotch is free software under the GNU General Public License, version 3 (GPL-3.0). See the `LICENSE` file.
