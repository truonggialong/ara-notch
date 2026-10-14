# AraNotch

Ứng dụng macOS biến tai thỏ (notch) của MacBook thành một bảng điều khiển nhỏ: clipboard, nhạc đang phát, hẹn giờ, lịch và lời nhắc, thả tệp, chụp màn hình, dịch nhanh và trạng thái của các agent lập trình.

A macOS app that turns the MacBook notch into a small control panel: clipboard, now playing, timers, calendar and reminders, a file shelf, screen capture, quick translate and the state of coding agents.

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

Từ bản 0.12.0, AraNotch tự kiểm tra bản mới mỗi ngày một lần và cài khi bạn đồng ý. Kiểm tra bằng tay: trang Thông tin trên notch, hoặc Cài đặt › Chung › Cập nhật.

From 0.12.0 on, AraNotch looks for a newer version once a day and installs it when you agree. To check by hand: the About page on the notch, or Settings › General › Updates.

## Quyền riêng tư · Privacy

AraNotch không thu thập hay gửi dữ liệu nào về cho người làm ra nó. Những gì rời khỏi máy:

- Khi bạn chép một liên kết, AraNotch mở ngầm liên kết đó một lần để lấy tiêu đề và ảnh (tắt được trong Cài đặt › Clipboard). Liên kết trông như đăng nhập, mã một lần hay token thì bỏ qua.
- Đoạn chữ bạn chọn để dịch được gửi tới Google Translate, chỉ khi bạn bấm dịch.
- Lời bài hát được hỏi từ lrclib.net, chỉ khi bạn bật lời bài hát (mặc định tắt).
- Mỗi ngày một lần, AraNotch hỏi GitHub có bản mới không.

Lịch sử clipboard nằm trên máy bạn, trong `~/Library/Application Support/AraNotch`, và mặc định không vào bản sao lưu Time Machine. Board khoá được mã hoá.

AraNotch collects nothing and sends nothing to its maker. What leaves the Mac: a link you copy is opened once in the background for its title and picture (can be turned off in Settings › Clipboard; links that look like sign-ins, one-time codes or tokens are skipped); text you choose to translate goes to Google Translate when you ask; lyrics are asked of lrclib.net when you turn lyrics on (off by default); and once a day AraNotch asks GitHub for a newer version. The clipboard history stays on your Mac, in `~/Library/Application Support/AraNotch`, out of Time Machine backups by default; locked boards are encrypted.

## Gỡ cài đặt · Removing AraNotch

Cài đặt › Chung › **Gỡ AraNotch…**: gỡ hook và dòng trạng thái khỏi Claude Code (có giữ bản sao lưu), thôi mở cùng máy, xoá bộ nhớ đệm và, nếu bạn chọn, cả lịch sử clipboard và cài đặt, rồi chuyển app vào Thùng rác.

Settings › General › **Remove AraNotch…** takes its hooks and status line out of Claude Code (keeping a backup), stops it opening at login, removes its caches and, if you tick it, the clipboard history and settings, then moves the app to the Trash.

## Mã nguồn · Source

Kho này chỉ chứa các bản phát hành. Mã nguồn chưa được công bố.

This repository holds the releases only. The source code is not published.
