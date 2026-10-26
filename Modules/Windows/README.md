# Cửa sổ (WindowsCore, WindowsFeature)

Sổ của module **Windows**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Chia cửa sổ: phím tắt ⌃⌥ + mũi tên đưa cửa sổ đang dùng về nửa, phần tư, giữa, toàn màn hình; kéo cửa sổ vào mép màn hình để chia, có khung xem trước.

## Target và thư mục

- `WindowsCore` — `Modules/Windows/Core/`
- `WindowsFeature` — `Modules/Windows/Feature/`

## Phụ thuộc và ai dùng

- Dùng: `WindowsFeature` dùng `WindowsCore`, `NotchShell`.
- Được dùng bởi: App (`WindowsController`).

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `WindowsController.init(store: WindowSettingsStore)`
- `WindowsController.init(settings: WindowSettings)`
- `WindowsController.start()`
- `WindowsController.makeSettingsSection() -> AnyView`
- `WindowsController.snap(zoneNamed name: String) -> Bool`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `windows.snapEnabled`, `windows.edgeSnapEnabled` (`WindowSettingsStore`).

## Quyền hệ thống

Trợ năng (di chuyển cửa sổ của app khác).

## Test

- Chạy: `Scripts/test-module.sh Windows`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Windows/Tests/Core/`

## Tệp

- `Modules/Windows/Core/EdgeSnap.swift` — Decides where a window snaps when it is dragged to an edge of the display.
- `Modules/Windows/Core/SnapZone.swift` — A place on the display a window can be snapped to.
- `Modules/Windows/Feature/EdgeSnapMonitor.swift` — Watches for a window being dragged to an edge of the display, shows where it would snap, and snaps it when the mouse button is released there.
- `Modules/Windows/Feature/WindowMover.swift` — Moves and resizes the front window of whatever app the user is working in, through the Accessibility interface.
- `Modules/Windows/Feature/WindowsController.swift` — Observable window settings; every change is written through to the store.

## Lỗi và giới hạn đã biết

- Phím chia cửa sổ (⌃⌥ và mũi tên) và ⌘1–9 trong panel chưa đổi được; chỉ tám lệnh trong mục Phím tắt đổi được. Phím fn không dùng làm phím tắt được (giới hạn của macOS). Trong lúc đang ghi một phím tắt, mọi phím tắt của app tạm ngừng.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- Chưa có.
