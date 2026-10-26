# AraNotch — Làm việc theo module — Thiết kế

Ngày: 2026-10-26. Chủ dự án duyệt hướng "Gọn ranh giới + sổ module" và thiết kế trong chat cùng ngày.

## Mục tiêu

Chủ dự án bỏ graphify và làm việc theo module: mỗi tính năng là một module có ranh giới rõ, có sổ riêng, có test riêng; khi có lỗi thì sửa trong đúng module đó, không sửa cục bộ chỗ khác để tránh làm hỏng module khác.

Thành công khi:

1. Không còn mã của một tính năng nằm trong nền tảng (`NotchCore`, `NotchShell`) hay trong app (`AraNotch`) ngoài phần lắp ráp.
2. Mỗi module có một sổ trong `docs/modules/` đủ để tìm đường mà không cần đồ thị.
3. Một script chặn việc vượt ranh giới và chạy cùng bộ test.
4. Có lệnh chạy test của riêng một module.
5. Hành vi app và dữ liệu đã lưu (UserDefaults, kho clip) không đổi; toàn bộ test cũ vẫn qua.
6. Graphify của app này bị xoá; các phiên sau làm việc theo sổ module.

Ngoài phạm vi: một giao thức chung để tính năng tự đăng ký (lựa chọn "tái cấu trúc toàn bộ" đã bị loại); đổi giao diện; phát hành bản mới.

## Bản đồ module

| Nhóm | Module (target SPM) | Được import |
|---|---|---|
| Nền tảng | `NotchCore` (logic thuần), `NotchShell` (khung notch, phím tắt chung, bộ thiết kế `Design/`) | Framework hệ thống; `NotchShell` import `NotchCore` |
| Tính năng | `<X>Core` | Chỉ framework không giao diện (Foundation, CoreGraphics, ImageIO, SQLite3, CryptoKit…) |
| Tính năng | `<X>Feature` | `<X>Core` của chính nó, `NotchCore`, `NotchShell`, framework hệ thống |
| Công cụ dòng lệnh | `ClipboardMCP`, `aranotch-mcp`, `aranotch-hook` | Core của tính năng mình |
| App | `AraNotch` | Mọi thứ; chỉ lắp ráp |

Tính năng: Clipboard, Calendar, Media, Timer, Agent, Files, Capture, Translate, Windows, SystemEvents, cùng hai module mới:

- **Overview** (`OverviewCore`, `OverviewFeature`): trang Tổng quan.
- **Tools** (`ToolsFeature`, không có Core vì không có logic thuần): trang Công cụ và widget Công cụ.

## Thay đổi mã

Không đổi hành vi, không đổi khoá lưu.

### Overview thành module riêng

- `OverviewCore` nhận từ `NotchCore/OverviewLayout.swift`: `OverviewWidget`, `OverviewItem`, `OverviewPlacement`, `OverviewGrid`, `OverviewLayout`, `OverviewDrag`. Enum `OverviewFeature` đổi tên thành `OverviewTileGroup` để khỏi trùng tên module `OverviewFeature`.
- `OverviewCore` có `OverviewSettingsStore` đọc ghi bố cục với đúng hai khoá cũ `shell.overviewArrangement` và `shell.hiddenOverviewWidgets` (chuyển từ `ShellSettingsStore`).
- `OverviewFeature` nhận từ app: `OverviewPage`, `OverviewEditButton`, `OverviewEditor`, `OverviewTiles`; thêm `OverviewSettings` (ObservableObject, thay `ShellSettings.overviewArrangement`) và dòng "Bố cục Tổng quan / Đặt lại" của Cài đặt (đang nằm trong `PagesSettingsSection`).
- Test `OverviewLayoutTests` chuyển từ `NotchCoreTests` sang `OverviewCoreTests`; test bố cục của `ShellSettingsStoreTests` (nếu có) chuyển theo.
- `NotchController` không còn gọi `OverviewLayout.orderWithOverview`: nó nhận `leadingPageID: String?` lúc khởi tạo và dùng một hàm chung `PageRegistry.order(_:leading:)` trong `NotchCore` (thứ tự cũ thiếu trang đứng đầu thì đặt trang đó lên trước; thứ tự rỗng giữ nguyên). App truyền `OverviewLayout.pageID`.

### Bộ widget dùng chung ở lại nền tảng

`WidgetPalette`, `WidgetMeasure` ở lại `NotchCore`. Đổi tên cho đúng vai trò dùng chung:

- `OverviewTileSize` → `WidgetSize` (chuyển vào `NotchCore`, cạnh `WidgetMeasure`; giá trị lưu `small`, `wide`, `large` không đổi).
- `OverviewAlert` → `WidgetAlert` (test đổi tên theo).

### Hàng phím số do Clipboard sở hữu

- `NotchCore`: `ShortcutStore` bỏ `quickPaste…`/`recentPaste…`; thêm khái niệm chung `NumberRow` (định danh bằng khoá lưu) với `modifiers(for:)`, `setModifiers(_:for:others:)` (từ chối khi chỉ có Shift hoặc trùng một hàng khác) và `combos(for:)`.
- `NotchShell`: `ShortcutCenter` bỏ mọi tên quick/recent paste; thêm `setNumberRow(_:handler:)`, trạng thái đã đăng ký theo hàng, `isNumberRowCombo`. `ShortcutNumberRowPicker` nhận hàng và khoá chữ hiển thị từ bên gọi.
- `ClipboardFeature`: khai báo hai hàng `ClipboardNumberRows.pinned` (khoá `shortcut.quickPasteModifiers`) và `.recent` (khoá `shortcut.recentPasteModifiers`), gắn handler, và tự truyền khoá chữ của mình cho picker.
- Test: `QuickPasteShortcutTests`/`RecentPasteShortcutTests` thành test `NumberRow` chung trong `NotchCoreTests` (giữ đủ các trường hợp cũ); thêm test trong `ClipboardFeatureTests` khẳng định hai khoá lưu không đổi.

`ShortcutAction` (danh mục phím tắt toàn cục) ở lại nền tảng: việc kiểm tra trùng phím cần thấy mọi phím. Đây là ngoại lệ được ghi trong sổ.

### Tools thành module riêng

`ToolsFeature` nhận từ `Pages.swift`: `NotchTool` (kèm bảng `looks`), `ToolsPage`, `ToolsWidget`. Nó có `ToolsController(tools:)` với `makePage()` và `makeOverviewTile()`. App vẫn quyết định có công cụ nào và mỗi công cụ gọi tính năng nào (vì đó là lắp ráp).

### Trang Giới thiệu

`AboutPage` sang tệp riêng `Sources/AraNotch/AboutPage.swift`; `Pages.swift` bị xoá.

## Sổ module

- `docs/modules/README.md`: bảng module, sơ đồ phụ thuộc, luật ranh giới, quy trình sửa lỗi, cách chạy script.
- Một tệp cho mỗi module: `Platform.md` (NotchCore + NotchShell), `App.md`, `Clipboard.md`, `Calendar.md`, `Media.md`, `Timer.md`, `Agent.md`, `Files.md`, `Capture.md`, `Translate.md`, `Windows.md`, `SystemEvents.md`, `Overview.md`, `Tools.md`.
- Mỗi sổ có các mục: Vai trò; Target và thư mục; Tệp chính (một dòng mỗi tệp); Giao diện công khai (những gì app gọi); Phụ thuộc và ai dùng; Dữ liệu lưu (khoá UserDefaults, tệp trên đĩa); Quyền hệ thống; Test (lệnh và bộ test); Lỗi và giới hạn đã biết (lấy từ `FEATURES.md`); Nhật ký sửa lỗi.
- `FEATURES.md` vẫn là sổ tính năng và lộ trình; `HISTORY.md` vẫn là nhật ký các vòng. Sổ module là nơi tìm đường trong mã.

## Công cụ

- `Scripts/check-modules.sh`: đọc dòng `import` của từng target trong `Sources/` và báo lỗi (mã thoát khác 0) khi:
  - `<X>Core` import SwiftUI, AppKit, `NotchShell` hoặc module của tính năng khác;
  - `<X>Feature` import Core hay Feature của tính năng khác;
  - `NotchCore`/`NotchShell` import bất kỳ module tính năng nào;
  - một target ngoài `AraNotch` import một `…Feature`.
  
  `Scripts/test.sh` chạy nó trước `swift test`.
- `Scripts/test-module.sh <Module>`: chạy `swift test --filter` cho các bộ test của module (ví dụ `Clipboard` → `ClipboardCoreTests`, `ClipboardFeatureTests`, `ClipboardMCPTests`), sau khi chạy `check-modules.sh`.

## Quy trình sửa lỗi theo module

1. Xác định module chứa lỗi (sổ module).
2. Viết test tái hiện lỗi trong bộ test của module đó.
3. Chỉ sửa trong module đó. Nếu bắt buộc phải đổi giao diện công khai mà module khác đang dùng: dừng, báo chủ dự án trước.
4. `Scripts/test-module.sh <Module>`, rồi `Scripts/test.sh` (gồm `check-modules.sh`), rồi build app và thử tay.
5. Ghi một dòng vào "Nhật ký sửa lỗi" của sổ module và cập nhật mục lỗi/giới hạn.

Quy trình được ghi trong `CLAUDE.md` ở gốc repo và trong bộ nhớ của Claude.

## Xoá graphify

- Xoá: `graphify-out/`, `.graphifyignore`, `Scripts/graph-update.py`, `Scripts/graph-docs.py`, `Scripts/graph-refresh.sh`, dòng `graphify-out/` trong `.gitignore`.
- Sửa câu hướng dẫn graphify ở đầu `FEATURES.md` và `HISTORY.md` thành hướng dẫn theo sổ module; các mục lịch sử cũ giữ nguyên.
- Bộ nhớ `aranotch-project-memory-workflow` viết lại theo cách làm mới.
- Không động tới `~/.claude/settings.json` và `~/CLAUDE.md` (dự án khác còn dùng); các hook đó chỉ chạy khi có `graph.json`, kiểm tra lại sau khi xoá.

## Lỗi và trường hợp biên

- Dữ liệu cũ: bố cục Tổng quan, thứ tự trang, hai hàng phím số đọc từ đúng khoá cũ; có test cho từng khoá.
- Thứ tự trang lưu từ trước khi có Tổng quan vẫn được đặt Tổng quan lên đầu (test của `orderWithOverview` chuyển thành test của `PageRegistry.order(_:leading:)`).
- Lượt chạy thử với `--overview-arrangement` vẫn không lưu.

## Kiểm thử

- Mốc trước khi làm (2026-10-26, commit 823af95): 1235 test, tất cả qua.
- Sau khi làm: `Scripts/test.sh` qua hết, số test không ít hơn mốc (test chuyển chỗ vẫn được đếm); `Scripts/check-modules.sh` qua; `Scripts/test-module.sh Overview` chạy đúng các bộ test của Overview.
- Thử tay trên app thật (bản dựng mới, mở bằng `open`): Tổng quan giữ bố cục đang dùng, vào chế độ sửa, đổi cỡ và kéo một ô rồi đặt lại; trang Công cụ mở được một công cụ; Cài đặt > Clipboard có hai hàng phím số với giá trị cũ; trang Giới thiệu hiện phiên bản.
