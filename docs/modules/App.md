# App (AraNotch)

Sổ của module **App**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Chương trình chính: tạo và nối các module (`AppDelegate`), cửa sổ Cài đặt, icon thanh menu, cửa sổ chào mừng, trang Giới thiệu, cập nhật (Sparkle), mở khi đăng nhập, gỡ cài đặt, tham số dòng lệnh cho kiểm chứng tự động. Chỉ lắp ráp: logic của tính năng không nằm ở đây.

## Target và thư mục

- `AraNotch` — `Sources/AraNotch/`

## Phụ thuộc và ai dùng

- Dùng: Mọi `<X>Feature`, `<X>Core` khi cần kiểu dữ liệu, `NotchShell`, `NotchCore`, Sparkle.
- Được dùng bởi: Không module nào.

## Giao diện công khai

Xem các kiểu `public` trong mã của module.

## Ghi chú cho người sửa

- Thêm một tính năng mới: tạo `<X>Core`/`<X>Feature`, khai báo trong `Package.swift`, rồi nối ở `AppDelegate.applicationDidFinishLaunching` (tạo controller, `register(page:)`, ô Tổng quan qua `overview.setTiles`, phần Cài đặt qua `SettingsTab`).
- Tham số kiểm chứng: `Sources/AraNotch/LaunchArguments.swift`. Chạy app bằng `open`, không chạy thẳng tệp trong `Contents/MacOS`.

## Dữ liệu lưu

- Thư mục dữ liệu `~/Library/Application Support/AraNotch` (do các tính năng dùng; `--data-dir` thay thế cho lượt chạy thử).
- Khoá cập nhật Sparkle và feed: xem `Scripts/release.sh` và bộ nhớ "Releases and updates".

## Quyền hệ thống

Hỏi và hiển thị trạng thái các quyền (Trợ năng, Lịch, Lời nhắc, Ghi màn hình, Bluetooth) trong cửa sổ chào mừng và Cài đặt › Chung; tự nó không dùng quyền nào.

## Test

- Chạy: `Scripts/test-module.sh App`, rồi `Scripts/test.sh`.
- Không có bộ test riêng: build app (`Scripts/build-app.sh`) và thử tay.

## Tệp

- `Sources/AraNotch/AboutPage.swift` — The app's own card: its icon, its name in the display face, and the facts about this copy and this notch.
- `Sources/AraNotch/AppDelegate.swift`
- `Sources/AraNotch/AppRelauncher.swift` — Opens the app again, for a change that takes effect only at launch (the language).
- `Sources/AraNotch/AppUpdater.swift` — Looks for a newer version of the app among its releases, and downloads and installs it.
- `Sources/AraNotch/KeyScript.swift` — Diagnostics: feeds scripted key presses to the clipboard panel.
- `Sources/AraNotch/LaunchArguments.swift` — Command-line switches, used by automated checks to put the app into a known state.
- `Sources/AraNotch/LoginItem.swift` — Whether the app opens when the user logs in.
- `Sources/AraNotch/MainMenu.swift` — The app's main menu.
- `Sources/AraNotch/SampleClips.swift` — A fixed set of clips covering every kind, for `--seed-clipboard`.
- `Sources/AraNotch/SettingsView.swift` — One tab of the Settings window.
- `Sources/AraNotch/SettingsWindowController.swift` — Owns the single Settings window and brings it to the front on demand.
- `Sources/AraNotch/StatusItemController.swift` — The menu bar icon and its menu.
- `Sources/AraNotch/Uninstaller.swift` — Takes AraNotch off this Mac, after asking: its hooks and status line come out of Claude Code's settings (backed up first), it no longer opens at login, its caches go and, when the user ticks it, its clipboard history, agent data and settings too; then the app goes to the Trash and quits.
- `Sources/AraNotch/WelcomeWindow.swift` — One permission the app can use, and whether macOS has granted it.
- `Sources/AraNotch/WindowSnapshot.swift` — Diagnostics: renders this app's own visible windows to PNG files.
- `Sources/AraNotch/main.swift`

## Giấy phép và ghi công

- `build-app.sh` chép `LICENSE` (GPL-3.0 của AraNotch) và `Resources/ThirdPartyNotices.txt` vào `Contents/Resources/` của app. Đó là cách giữ điều kiện của giấy phép MIT mà Sparkle dùng.
- `ThirdPartyNotices.txt` ghi rõ phiên bản Sparkle. Nếu phiên bản trong `Package.resolved` khác, script dừng lại; khi đó chép lại `LICENSE` của Sparkle từ `.build/checkouts/Sparkle/` rồi đổi số phiên bản trong tệp.
- Thêm thư viện bên ngoài nào khác thì cũng chép giấy phép của nó vào tệp này.

## Lỗi và giới hạn đã biết

- Mở khi đăng nhập đăng ký đúng bản app đang chạy; với bản dựng thử nằm trong thư mục dự án thì mục đăng nhập trỏ về đó. Nên bật sau khi app đã nằm ở /Applications.
- Bản `.dmg` ký bằng chứng chỉ tự ký "AraNotch Dev", không phải Developer ID, và không được Apple notarize. Trên máy khác, macOS chặn lần mở đầu; người dùng phải vào Cài đặt hệ thống › Quyền riêng tư & Bảo mật và bấm "Vẫn mở". Bản dựng chỉ chạy trên máy Apple Silicon, macOS 15 trở lên. Không có tự cập nhật: bản mới phải tải và cài lại bằng tay.
- Cửa sổ Cài đặt vẫn dựng trên biểu mẫu chuẩn của macOS (có ô tìm và chú thích một dòng); cửa sổ sửa clip cũng vậy. Nền mờ theo ảnh bìa chỉ có khi app đang phát có gửi ảnh bìa.
- Bản 0.2.0, những gì thấy ở OneNotch mà chưa làm: chọn vùng chia cửa sổ bằng cách kéo cửa sổ lên notch (AraNotch có kéo vào mép màn hình và phím tắt); quay màn hình và GIF; các công cụ chú thích thước đo, kính lúp, cắt ảnh; báo chế độ Tập trung, tắt tiếng micro, khoá màn hình; pin của AirPods; duyệt yêu cầu của agent ngay trên notch; chi phí và token của agent; gương (camera). Một số cần quyền mới hoặc giao diện hệ thống không công khai.
- Nghiên cứu OneNotch: công cụ điều khiển máy không cấp quyền được cho OneNotch (app chạy nền, không hiện trong danh sách), nên chỉ xem được video giới thiệu và tên các tính năng, cài đặt trong gói app; chưa bấm thử trực tiếp cách nó phản hồi thao tác.
- Tự cập nhật: kho `truonggialong/ara-notch` trên GitHub là công khai, chứa mã nguồn (từ 2026-10-26), giấy phép GPL-3.0 và các bản phát hành. Khoá ký là tệp `~/.aranotch/update-signing.key` trên máy chủ dự án, không nằm trong kho mã: mất tệp này thì các bản đã cài không nhận được bản cập nhật nào nữa. App vẫn ký bằng chứng thư tự tạo và chưa được Apple chứng nhận: trên máy khác, lần cài đầu vẫn bị macOS chặn cho tới khi chủ máy cho phép; cập nhật sau đó thì không. Cửa sổ của Sparkle theo ngôn ngữ của máy và không theo giao diện của notch. Chỉ có bản cho máy Apple Silicon.
- Cài đặt, tên menu chính và một số chuỗi kỹ thuật chưa được trau chuốt.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): Overview và Tools chuyển ra module riêng; `AboutPage` có tệp riêng, `Pages.swift` bị bỏ; dòng "Đặt lại bố cục" của Cài đặt › Trang lấy từ `OverviewController.makeSettingsRow()`.
- 2026-10-26 — app chưa kèm giấy phép nào, trong khi giấy phép MIT của Sparkle đòi kèm lời ghi công. `build-app.sh` nay chép `LICENSE` và `Resources/ThirdPartyNotices.txt` vào app, và dừng lại nếu tệp ghi công không đúng phiên bản Sparkle. Không có test tự động: đã dựng app, so tệp, kiểm chữ ký, và thử trường hợp lệch phiên bản.
