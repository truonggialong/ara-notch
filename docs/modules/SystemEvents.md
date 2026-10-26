# Sự kiện hệ thống (SystemEventsCore, SystemEventsFeature)

Sổ của module **SystemEvents**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Thông báo cạnh notch cho sạc và pin, Caps Lock, mạng, thiết bị Bluetooth; thay khung âm lượng, độ sáng và đèn bàn phím của macOS; widget Máy của Tổng quan (pin máy và thiết bị Bluetooth).

## Target và thư mục

- `SystemEventsCore` — `Sources/SystemEventsCore/`
- `SystemEventsFeature` — `Sources/SystemEventsFeature/`

## Phụ thuộc và ai dùng

- Dùng: `SystemEventsFeature` dùng `SystemEventsCore`, `NotchShell`, `NotchCore`, IOKit, IOBluetooth, CoreBluetooth, Network, CoreAudio.
- Được dùng bởi: App (`SystemEventsController`); app trao dòng âm lượng của Media cho widget Máy.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `SystemEventsController.init(settings: AlertSettings, notch: NotchController)`
- `SystemEventsController.start()`
- `SystemEventsController.makeOverviewTile(volume: AnyView) -> AnyView`
- `SystemEventsController.makeSettingsSection() -> AnyView`
- `SystemEventsController.var isReplacingHUD = false`
- `SystemEventsController.simulate(_ event: SimulatedSystemEvent)`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `alerts.power`, `alerts.capsLock`, `alerts.network`, `alerts.bluetooth`, `alerts.replacesHUD` (`AlertSettingsStore`).

## Quyền hệ thống

Bluetooth (thông báo thiết bị); Trợ năng (bắt phím âm lượng và độ sáng, nghe Caps Lock).

## Test

- Chạy: `Scripts/test-module.sh SystemEvents`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/SystemEventsCoreTests/`

## Tệp

- `Sources/SystemEventsCore/AlertSettingsStore.swift` — Which system alerts appear on the notch.
- `Sources/SystemEventsCore/Bluetooth.swift` — What sort of Bluetooth device this probably is, for choosing an icon.
- `Sources/SystemEventsCore/BluetoothBatteries.swift` — A Bluetooth device connected now, with its battery as the system reports it.
- `Sources/SystemEventsCore/CapsLockDetector.swift` — Reports Caps Lock changes.
- `Sources/SystemEventsCore/ConnectivityDebouncer.swift` — Reports a lost connection only once it has stayed lost for a few seconds, so a flickering Wi-Fi link is not announced.
- `Sources/SystemEventsCore/MediaKeys.swift` — A press or release of one of the keys whose on-screen display the notch can take over.
- `Sources/SystemEventsCore/PowerEventDetector.swift` — The power state of the Mac at one moment.
- `Sources/SystemEventsFeature/ActivityViews.swift` — Builds the notices for system events: each a sign the notch grows into for a moment, naming what speaks on the left and saying what happened on the right.
- `Sources/SystemEventsFeature/AlertSettings.swift` — Observable alert switches; every change is written through to the store.
- `Sources/SystemEventsFeature/AlertSettingsSection.swift` — The system's own notices in Settings › Notices: one chip each.
- `Sources/SystemEventsFeature/BluetoothBatteryReader.swift` — The battery levels of the Bluetooth devices connected now, from the system report.
- `Sources/SystemEventsFeature/BluetoothMonitor.swift` — Reports Bluetooth devices connecting and disconnecting.
- `Sources/SystemEventsFeature/CapsLockMonitor.swift` — Reports the Caps Lock state.
- `Sources/SystemEventsFeature/DeviceWidget.swift` — The battery as the overview shows it.
- `Sources/SystemEventsFeature/HUDControls.swift` — Catches the volume and brightness keys before the system acts on them, so the notch can show the change instead of the system's own display.
- `Sources/SystemEventsFeature/NetworkMonitor.swift` — Reports whether the Mac has a usable network connection.
- `Sources/SystemEventsFeature/PowerMonitor.swift` — Reads the battery and charger state and reports changes.
- `Sources/SystemEventsFeature/SystemEventsController.swift` — Events that can be injected for automated checks, without touching the real system state.

## Lỗi và giới hạn đã biết

- Thông báo Bluetooth chỉ hoạt động sau khi chủ dự án bấm cho phép trong hộp thoại xin quyền Bluetooth của macOS.
- Loại thiết bị Bluetooth được đoán theo tên thiết bị.
- Đèn bàn phím chỉ hiện trên notch khi đổi bằng phím. Bàn phím MacBook đời mới không có phím này; đổi đèn bằng thanh trượt trong Trung tâm điều khiển thì notch không hiện gì. Mức đèn được đọc và chỉnh qua một lớp riêng của macOS (CoreBrightness), có thể đổi ở bản macOS sau; khi lớp đó thiếu, phím được trả lại cho hệ thống.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`, `WidgetAlert`.
