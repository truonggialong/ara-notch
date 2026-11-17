# Sự kiện hệ thống (SystemEventsCore, SystemEventsFeature)

Sổ của module **SystemEvents**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Thông báo cạnh notch cho sạc và pin, Caps Lock, mạng, thiết bị Bluetooth; thay khung âm lượng, độ sáng và đèn bàn phím của macOS; widget Máy của Tổng quan (pin máy và thiết bị Bluetooth).

## Target và thư mục

- `SystemEventsCore` — `Modules/SystemEvents/Core/`
- `SystemEventsFeature` — `Modules/SystemEvents/Feature/`

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
- Bộ test: `Modules/SystemEvents/Tests/Core/`

## Tệp

- `Modules/SystemEvents/Core/AlertSettingsStore.swift` — Which system alerts appear on the notch.
- `Modules/SystemEvents/Core/Bluetooth.swift` — What sort of Bluetooth device this probably is, for choosing an icon.
- `Modules/SystemEvents/Core/BluetoothBatteries.swift` — A Bluetooth device connected now, with its battery as the system reports it.
- `Modules/SystemEvents/Core/CapsLockDetector.swift` — Reports Caps Lock changes.
- `Modules/SystemEvents/Core/ConnectivityDebouncer.swift` — Reports a lost connection only once it has stayed lost for a few seconds, so a flickering Wi-Fi link is not announced.
- `Modules/SystemEvents/Core/MediaKeys.swift` — A press or release of one of the keys whose on-screen display the notch can take over.
- `Modules/SystemEvents/Core/PowerEventDetector.swift` — The power state of the Mac at one moment.
- `Modules/SystemEvents/Feature/ActivityViews.swift` — Builds the notices for system events: each a sign the notch grows into for a moment, naming what speaks on the left and saying what happened on the right.
- `Modules/SystemEvents/Feature/AlertSettings.swift` — Observable alert switches; every change is written through to the store.
- `Modules/SystemEvents/Feature/AlertSettingsSection.swift` — The system's own notices in Settings › Notices: one chip each.
- `Modules/SystemEvents/Feature/BluetoothBatteryReader.swift` — The battery levels of the Bluetooth devices connected now, from the system report.
- `Modules/SystemEvents/Feature/BluetoothMonitor.swift` — Reports Bluetooth devices connecting and disconnecting.
- `Modules/SystemEvents/Feature/CapsLockMonitor.swift` — Reports the Caps Lock state.
- `Modules/SystemEvents/Feature/DeviceWidget.swift` — The battery as the overview shows it.
- `Modules/SystemEvents/Feature/HUDControls.swift` — Catches the volume and brightness keys before the system acts on them, so the notch can show the change instead of the system's own display.
- `Modules/SystemEvents/Feature/NetworkMonitor.swift` — Reports whether the Mac has a usable network connection.
- `Modules/SystemEvents/Feature/PowerMonitor.swift` — Reads the battery and charger state and reports changes.
- `Modules/SystemEvents/Feature/SystemEventsController.swift` — Events that can be injected for automated checks, without touching the real system state.
- `Modules/SystemEvents/Core/KeepAwake.swift` — Một phiên giữ máy thức: các mức 30 phút, 1 giờ, 2 giờ, vô hạn, và thời gian còn lại (`KeepAwakeSession`).
- `Modules/SystemEvents/Core/KeepAwakeRules.swift` — Cài đặt giữ máy thức (`KeepAwakeSettingsStore`), khi nào phiên tự dừng, nhắc trước khi hết, và Trigger tự bật (`KeepAwakeRules`).
- `Modules/SystemEvents/Feature/KeepAwakeSettings.swift` — Cài đặt giữ máy thức quan sát được (`KeepAwakeSettings`), mục Cài đặt › Công cụ, và bảng chọn kiểu phiên khi bấm giữ nút (`makeChooser`).
- `Modules/SystemEvents/Feature/KeepAwakeController.swift` — Giữ máy và màn hình thức bằng `IOPMAssertion`, đặt cốc vàng và giờ còn lại cạnh notch.

## Lỗi và giới hạn đã biết

- Thông báo Bluetooth chỉ hoạt động sau khi chủ dự án bấm cho phép trong hộp thoại xin quyền Bluetooth của macOS.
- Loại thiết bị Bluetooth được đoán theo tên thiết bị.
- Đèn bàn phím chỉ hiện trên notch khi đổi bằng phím. Bàn phím MacBook đời mới không có phím này; đổi đèn bằng thanh trượt trong Trung tâm điều khiển thì notch không hiện gì. Mức đèn được đọc và chỉnh qua một lớp riêng của macOS (CoreBrightness), có thể đổi ở bản macOS sau; khi lớp đó thiếu, phím được trả lại cho hệ thống.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`, `WidgetAlert`.
- 2026-11-16 — N2: giữ máy thức (`KeepAwakeSession`, `KeepAwakeController`): mỗi lần bấm nút trên trang Công cụ đi qua 30 phút, 1 giờ, 2 giờ, vô hạn rồi tắt; giữ cả màn hình thức bằng `IOPMAssertion`; cốc vàng và giờ còn lại nằm cạnh notch (id `keepAwake`, ưu tiên 1) — `KeepAwakeTests`, thử tay bằng chuột giả lập và `pmset -g assertions`.
- 2026-11-16 — thông báo hệ thống bằng hình: sạc, rút sạc, pin đầy là năm ô pin (`BatteryCells`); pin yếu và mất mạng có chữ đỏ; Caps Lock là phím và đèn cam; Bluetooth là hình thiết bị và tên; các mức là thanh không số (`SystemActivities.Level`); giữ máy thức là cốc vàng và vòng thời gian còn lại (`KeepAwakeSession.remaining`) — `BatteryCellsTests`, `KeepAwakeTests`.
- 2026-11-17 — giữ máy thức nâng cao theo Amphetamine 5.3.2 (chủ dự án duyệt K1–K5): chỉ giữ máy, cho màn hình tắt (`kIOPMAssertionTypePreventUserIdleSystemSleep`); kiểu phiên đến một giờ, khi một app còn mở, đến khi tải xong (`KeepAwakeSession.Until`); tự dừng khi pin dưới mức chọn, khi rút sạc, khi máy bị cho ngủ; nhắc 5 phút trước khi hết với nút +30′, +1 giờ dưới notch; Trigger tự bật theo app, cắm sạc kèm màn hình ngoài, giờ làm việc (`KeepAwakeRules`, `KeepAwakeSettingsStore`, khoá `keepAwake.*`); Trigger bị tắt bằng tay không tự bật lại cho tới khi điều kiện hết một lần — `KeepAwakeRulesTests`; thử tay: bảng chọn khi bấm giữ, phiên theo Finder, kiểu chỉ máy (pmset), mục Cài đặt.
