# Công cụ (ToolsFeature)

Sổ của module **Tools**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Công cụ và widget Công cụ của Tổng quan: các nút lớn cho những việc thường cần phím tắt hay thanh menu (chụp vùng, chụp cuộn, đọc chữ, chọn màu, dịch, panel clipboard, Thư viện, ghi chú mới).

## Target và thư mục

- `ToolsFeature` — `Sources/ToolsFeature/`

## Phụ thuộc và ai dùng

- Dùng: `NotchShell`.
- Được dùng bởi: App (`ToolsController`). App quyết định có công cụ nào và mỗi công cụ gọi tính năng nào; notch đóng trước khi công cụ chạy.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `ToolsController.init(tools: [NotchTool], quickToolIDs: [String])`
- `ToolsController.makePage() -> NotchPage`
- `ToolsController.makeOverviewTile() -> AnyView`

## Ghi chú cho người sửa

- Biểu tượng và màu của mỗi công cụ lấy theo tên trong `NotchTool.looks`; tên không có thì lưới màu cam đào.

## Dữ liệu lưu

- Không lưu gì.

## Quyền hệ thống

Không cần quyền (công cụ được gọi có quyền của nó).

## Test

- Chạy: `Scripts/test-module.sh Tools`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/ToolsFeatureTests/` (1 suite)

## Tệp

- `Sources/ToolsFeature/NotchTool.swift` — One thing the tools page can start.
- `Sources/ToolsFeature/ToolsController.swift` — The tools page and the overview's tools widget: everything that otherwise takes a shortcut or the menu bar.
- `Sources/ToolsFeature/ToolsPage.swift` — The tools page: everything that otherwise takes a shortcut or the menu bar, as buttons large enough to hit without looking twice.
- `Sources/ToolsFeature/ToolsWidget.swift` — The tools as a widget of the overview: round buttons in each tool's colour, named under or beside them.

## Lỗi và giới hạn đã biết

- Chưa có.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): tách từ `Sources/AraNotch/Pages.swift`; thêm `ToolsController` và bộ test đầu tiên.
