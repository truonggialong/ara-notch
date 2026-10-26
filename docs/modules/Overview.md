# Tổng quan (OverviewCore, OverviewFeature)

Sổ của module **Overview**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Tổng quan: các widget của tính năng trên lưới 4 cột, 2 đến 4 hàng; người dùng sắp xếp ngay trên notch (thêm, bỏ, đổi cỡ, kéo đổi chỗ); đặt lại bố cục trong Cài đặt › Trang.

## Target và thư mục

- `OverviewCore` — `Sources/OverviewCore/`
- `OverviewFeature` — `Sources/OverviewFeature/`

## Phụ thuộc và ai dùng

- Dùng: `OverviewCore` dùng `NotchCore` (`WidgetSize`). `OverviewFeature` dùng `OverviewCore`, `NotchShell`.
- Được dùng bởi: App (`OverviewController`). Widget của từng ô do tính năng tự vẽ (`makeOverviewTile()`); app trao chúng qua `setTiles`.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `OverviewController.let settings: OverviewSettings`
- `OverviewController.init(settings: OverviewSettings, trialArrangement: [OverviewItem]? = nil)`
- `OverviewController.makePage(notch: NotchController) -> NotchPage`
- `OverviewController.setTiles(_ tiles: [OverviewWidget: AnyView])`
- `OverviewController.makeSettingsRow() -> AnyView`
- `OverviewController.beginEditing()`

## Ghi chú cho người sửa

- Thêm một ô cho tính năng mới: thêm case vào `OverviewWidget` và `OverviewTileGroup`, rồi app trao widget qua `setTiles`.
- `--overview-arrangement <ô:cỡ,…>` (LaunchArguments) chạy thử một bố cục và giữ thay đổi trong bộ nhớ, không lưu. `--edit-overview` chỉ mở sẵn chế độ sửa: dùng một mình thì mọi thay đổi ghi vào bố cục thật (`shell.overviewArrangement`), nên luôn đi kèm `--overview-arrangement` khi thử.

## Dữ liệu lưu

- UserDefaults `shell.overviewArrangement` (danh sách `"<widget>:<size>"`) và `shell.hiddenOverviewWidgets` (chỉ đọc một lần để chuyển dữ liệu cũ) — giữ tên `shell.` từ trước khi tách module (`OverviewSettingsStore`).

## Quyền hệ thống

Không cần quyền.

## Test

- Chạy: `Scripts/test-module.sh Overview`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/OverviewCoreTests/`, `Tests/OverviewFeatureTests/` (chế độ sửa kết thúc khi notch đóng hay trang khác hiện)

## Tệp

- `Sources/OverviewCore/OverviewLayout.swift` — The feature a tile of the overview belongs to.
- `Sources/OverviewCore/OverviewSettingsStore.swift` — Reads and writes the overview's arrangement.
- `Sources/OverviewFeature/OverviewController.swift` — The overview page: the features' widgets on a grid the user arranges on the notch.
- `Sources/OverviewFeature/OverviewEditor.swift` — The overview's arrangement as the page shows it, and the edit mode that changes it on the notch.
- `Sources/OverviewFeature/OverviewPage.swift` — The overview page: the features worth a glance, each on its own tile, on a grid of four columns and two to four rows, in the order and sizes the user chose.
- `Sources/OverviewFeature/OverviewSettings.swift` — The overview's arrangement, kept in the settings as it changes.
- `Sources/OverviewFeature/OverviewSettingsRow.swift` — Settings › Notch pages: the overview's tiles are arranged on the notch itself; here they can only be put back.

## Lỗi và giới hạn đã biết

- Tổng quan chưa có ô ghi chú, phím tắt hay gương như NotchNook. Khi đặt "mở khi rê chuột" (mặc định) thì dòng nói thêm khi chạm notch không hiện, vì notch mở ngay.
- Bộ widget: mỗi tính năng chỉ một ô trên Tổng quan; thẻ luôn tối, không theo giao diện sáng; Bảng màu ở Clipboard lớn chỉ chép lại dạng HEX; pin thiết bị Bluetooth là con số macOS báo, đọc lại mỗi 2 phút khi ô Máy lớn đang hiện; chưa có ô cho Tệp và Dịch.
- Tổng quan: ô kiểu chữ của mỗi tính năng chỉ có một; không để trống được một ô ở giữa lưới (ô luôn dồn vào chỗ trống đầu tiên); tối đa 4 hàng. Ô thêm mới luôn ở cỡ nhỏ, cuối danh sách. Ô Máy chỉ biết thiết bị Bluetooth đang nối khi thông báo Bluetooth đang bật (lúc đó app mới nghe Bluetooth). Ô Hôm nay khi chưa cấp quyền Lịch chỉ báo không có gì, nút xin quyền vẫn ở trang Lịch. Ô hẹn giờ ghi mức sẵn bằng số và dấu phút (5′) cho vừa chỗ.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): tách từ `NotchCore` (`OverviewLayout.swift`), `NotchShell` (`ShellSettings.overviewArrangement`) và app (`OverviewPage`, `OverviewEditor`); thêm `OverviewController`, `OverviewSettings`, `OverviewSettingsStore` (cùng khoá cũ); enum `OverviewFeature` đổi tên `OverviewTileGroup`.
- 2026-10-26 — `OverviewController.makePage(notch:)` gọi hai lần thì chế độ sửa bị nối với notch hai lần. `OverviewEditor.connect` nay thay các liên kết cũ thay vì cộng thêm, và có bản nhận thẳng hai publisher để test được. Bộ test mới `Tests/OverviewFeatureTests/` (`OverviewEditorTests`): kết thúc khi notch đóng, khi trang khác hiện, lần nối sau thay lần trước. Test cuối thất bại khi tạm đổi lại kiểu cộng dồn.
