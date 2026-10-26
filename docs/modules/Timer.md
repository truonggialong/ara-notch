# Hẹn giờ (TimerCore, TimerFeature)

Sổ của module **Timer**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Hẹn giờ: tối đa bốn bộ đếm ngược có nhãn, mốc đặt sẵn, đếm cạnh notch khi đóng, báo hết giờ có âm thanh, widget Hẹn giờ của Tổng quan.

## Target và thư mục

- `TimerCore` — `Sources/TimerCore/`
- `TimerFeature` — `Sources/TimerFeature/`

## Phụ thuộc và ai dùng

- Dùng: `TimerFeature` dùng `TimerCore`, `NotchShell`, `NotchCore`.
- Được dùng bởi: App (`TimerController`).

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `TimerController.init(settings: TimerSettings, notch: NotchController)`
- `TimerController.makeOverviewTile() -> AnyView`
- `TimerController.makePage() -> NotchPage`
- `TimerController.makeSettingsSection() -> AnyView`
- `TimerController.start(seconds: TimeInterval)`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `timer.presets`, `timer.minutes`, `timer.seconds`, `timer.label`, `timer.sound` (`TimerSettingsStore`). Bộ đếm đang chạy chỉ nằm trong bộ nhớ.

## Quyền hệ thống

Không cần quyền.

## Test

- Chạy: `Scripts/test-module.sh Timer`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/TimerCoreTests/` (7 suite)

## Tệp

- `Sources/TimerCore/CountdownTimer.swift` — A single countdown.
- `Sources/TimerCore/TimerBoard.swift` — The countdowns under way, each with what it is for.
- `Sources/TimerCore/TimerFormat.swift`
- `Sources/TimerCore/TimerSettingsStore.swift` — Reads and writes the timer settings.
- `Sources/TimerFeature/TimerController.swift` — State the timer page renders from.
- `Sources/TimerFeature/TimerPageView.swift` — The timer page of the notch: the choice of a length, one countdown writ large, or several side by side.
- `Sources/TimerFeature/TimerSettings.swift` — Observable timer settings; every change is written through to the store.
- `Sources/TimerFeature/TimerSettingsSection.swift` — The timer's line in Settings › Notices.
- `Sources/TimerFeature/TimerWidget.swift` — The countdowns as a widget of the overview.

## Lỗi và giới hạn đã biết

- Hẹn giờ: tối đa bốn bộ đếm; các bộ đếm mất khi thoát app; phím tắt trên trang chỉ tác động bộ đầu tiên.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`, `WidgetAlert`.
