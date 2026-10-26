# AraNotch — Bản đồ module

Từ 2026-10-26 dự án làm việc theo module thay cho đồ thị graphify. Mỗi tính năng là một thư mục `Modules/<X>/` chứa mọi thứ của riêng nó: logic, giao diện, test và sổ. Lỗi được sửa trong đúng module chứa nó.

```
Modules/<X>/
  Core/        <X>Core: logic thuần, không giao diện, có test
  Feature/     <X>Feature: giao diện trong notch và trong Settings
  Tests/Core/  <X>CoreTests   (Tests/Feature/: <X>FeatureTests)
  README.md    sổ của module
Modules/Platform/   NotchCore, NotchShell: khung notch mọi tính năng dùng
App/                Sources/ (target AraNotch, chỉ lắp ráp), Resources/ (Info.plist, chuỗi dịch, biểu tượng), README.md
```

Clipboard có thêm `MCP/` (`ClipboardMCP`) và `aranotch-mcp/`; Agent có thêm `aranotch-hook/`. Tên target không đổi theo thư mục, nên `import` vẫn là `ClipboardCore`, `NotchShell`…

## Các module

| Nhóm | Module | Target | Sổ |
|---|---|---|---|
| Nền tảng | Platform | `NotchCore`, `NotchShell` | [Platform/README.md](Platform/README.md) |
| App | App | `AraNotch` | [App/README.md](../App/README.md) |
| Tính năng | Clipboard | `ClipboardCore`, `ClipboardFeature`, `ClipboardMCP`, `aranotch-mcp` | [Clipboard/README.md](Clipboard/README.md) |
| Tính năng | Calendar | `CalendarCore`, `CalendarFeature` | [Calendar/README.md](Calendar/README.md) |
| Tính năng | Media | `MediaCore`, `MediaFeature` | [Media/README.md](Media/README.md) |
| Tính năng | Timer | `TimerCore`, `TimerFeature` | [Timer/README.md](Timer/README.md) |
| Tính năng | Agent | `AgentCore`, `AgentFeature`, `aranotch-hook` | [Agent/README.md](Agent/README.md) |
| Tính năng | Files | `FilesCore`, `FilesFeature` | [Files/README.md](Files/README.md) |
| Tính năng | Capture | `CaptureCore`, `CaptureFeature` | [Capture/README.md](Capture/README.md) |
| Tính năng | Translate | `TranslateCore`, `TranslateFeature` | [Translate/README.md](Translate/README.md) |
| Tính năng | Windows | `WindowsCore`, `WindowsFeature` | [Windows/README.md](Windows/README.md) |
| Tính năng | SystemEvents | `SystemEventsCore`, `SystemEventsFeature` | [SystemEvents/README.md](SystemEvents/README.md) |
| Tính năng | Overview | `OverviewCore`, `OverviewFeature` | [Overview/README.md](Overview/README.md) |
| Tính năng | Tools | `ToolsFeature` | [Tools/README.md](Tools/README.md) |

## Phụ thuộc

```
                AraNotch (app: chỉ lắp ráp)
                   │ import mọi <X>Feature
     ┌─────────────┼──────────────────────────┐
 <X>Feature    <Y>Feature    …            (mỗi Feature)
     │  └─ <X>Core (logic thuần, có test)
     └──── NotchShell (khung notch, Design/) ── NotchCore (logic thuần của khung)
```

Không Feature nào biết Feature khác. Khi hai tính năng cần nhau (Clipboard cần đọc chữ trong ảnh của Capture, tạo lời nhắc của Calendar, viết lại chữ của Translate), app nối chúng bằng một closure trên controller (`clipboard.recognizeText = …`). Tính năng nhận closure không import tính năng kia.

## Luật ranh giới

`Scripts/check-modules.sh` kiểm tra các luật này, chạy tự động trong `Scripts/test.sh`:

| Target | Được import (trong các module của app) | Không được |
|---|---|---|
| `<X>Core` | `NotchCore` | SwiftUI, AppKit, Cocoa, `NotchShell`, mọi module khác |
| `<X>Feature` | `<X>Core` của chính nó, `NotchCore`, `NotchShell` | Core hay Feature của tính năng khác |
| `NotchCore` | — | SwiftUI, AppKit, Cocoa, mọi module của app |
| `NotchShell` | `NotchCore` | mọi module tính năng |
| `ClipboardMCP`, `aranotch-mcp` | `ClipboardCore`, `ClipboardMCP` | mọi module khác |
| `aranotch-hook` | `AgentCore` | mọi module khác |
| `AraNotch` | tất cả | — |

Framework hệ thống (Foundation, EventKit, Vision…) không bị giới hạn, trừ SwiftUI, AppKit và Cocoa trong Core và `NotchCore`. `Scripts/test-check-modules.sh` (chạy trong `Scripts/test.sh`) kiểm tra chính script này với một cây mã có đủ các kiểu vi phạm.

Ngoại lệ có chủ ý: `ShortcutAction` trong `NotchCore` liệt kê phím tắt toàn cục của mọi tính năng, vì kiểm tra trùng phím cần thấy hết (xem [Platform/README.md](Platform/README.md)).

## Quy trình sửa lỗi

1. **Tìm module.** Đọc bảng trên và sổ của module nghi ngờ (mục "Tệp" và "Giao diện công khai"). Nếu lỗi nằm ở chỗ hai module gặp nhau, module sở hữu là bên có hành vi sai, không phải bên dễ sửa hơn.
2. **Tái hiện bằng test** trong bộ test của module đó (xem mục "Test" của sổ). Module không có bộ test cho phần đó thì đưa phần logic vào `<X>Core` để test được, hoặc ghi rõ cách tái hiện bằng tay.
3. **Sửa trong module đó.** Không sửa vòng ở module khác để che lỗi. Nếu bắt buộc phải đổi giao diện công khai mà module khác đang dùng (một hàm `public`, một khoá lưu, một case của `ShortcutAction`), dừng lại và báo chủ dự án trước.
4. **Kiểm chứng**, theo thứ tự:
   - `Scripts/test-module.sh <Module>`: kiểm tra ranh giới và test của module.
   - `Scripts/test.sh`: kiểm tra ranh giới và toàn bộ test.
   - `swift build`: `swift test` không build target app.
   - Dựng app (`Scripts/build-app.sh`), mở bằng `open`, thử tay đúng chỗ lỗi.
5. **Ghi sổ.** Thêm một dòng vào "Nhật ký sửa lỗi" của sổ module (ngày, lỗi, test đã thêm, commit) và sửa mục "Lỗi và giới hạn đã biết" nếu cần. Thêm một vòng vào `docs/project/HISTORY.md`.

## Thêm hay đổi một module

- Tính năng mới: tạo `Modules/<X>/Core`, `Modules/<X>/Feature`, `Modules/<X>/Tests/Core`, khai báo trong `Package.swift` (`core("<X>")`, `feature("<X>")`, `tests("<X>", "Core", …)` và thêm `<X>` vào `features`), nối ở `AppDelegate`, thêm một dòng vào bảng trên, thêm `<X>` vào `Scripts/test-module.sh`, viết `Modules/<X>/README.md` theo mẫu của các sổ khác.
- Mỗi sổ có các mục: Vai trò; Target và thư mục; Phụ thuộc và ai dùng; Giao diện công khai; Ghi chú cho người sửa; Dữ liệu lưu; Quyền hệ thống; Test; Tệp; Lỗi và giới hạn đã biết; Nhật ký sửa lỗi.
- Đổi tệp, thêm hàm `public`, thêm khoá lưu: cập nhật sổ của module trong cùng commit.
- Không ghi số test hay số suite vào sổ: `Scripts/test-module.sh <Module>` luôn cho con số đúng.

## Tài liệu khác

- `docs/project/FEATURES.md`: tính năng đã làm, lộ trình tính năng còn thiếu.
- `docs/project/HISTORY.md`: nhật ký các vòng làm việc.
