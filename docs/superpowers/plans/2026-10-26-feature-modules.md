# Làm việc theo module — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gọn ranh giới giữa các module tính năng của AraNotch, viết sổ cho từng module, thêm script chặn vượt ranh giới và chạy test theo module, rồi xoá graphify.

**Architecture:** Package SwiftPM đã chia `<X>Core`/`<X>Feature`. Kế hoạch đưa Overview và Tools thành module riêng, kéo phần còn sót của tính năng (hàng phím số của Clipboard, tên Overview trong `NotchController`) ra khỏi nền tảng, đổi tên bộ widget dùng chung. Không đổi hành vi, không đổi khoá UserDefaults.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, Swift Testing, bash.

**Spec:** `docs/superpowers/specs/2026-10-26-feature-modules-design.md`

## Global Constraints

- Mốc: 1235 test qua hết (commit 823af95). Sau mỗi task `Scripts/test.sh` phải qua hết; tổng số test (cộng các dòng "Test run with N tests") không thấp hơn 1235.
- Khoá lưu giữ nguyên: `shell.overviewArrangement`, `shell.hiddenOverviewWidgets`, `shell.pageOrder`, `shortcut.quickPasteModifiers`, `shortcut.recentPasteModifiers`.
- Giá trị lưu của cỡ ô giữ nguyên: `small`, `wide`, `large`.
- Chữ hiển thị đọc qua `L10n.string` (bundle chính) — không thêm tài nguyên vào target mới.
- Mỗi target mới khai báo trong `Package.swift` cả `products` lẫn `targets`, theo mẫu sẵn có.
- Commit kết thúc bằng hai dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` và `Claude-Session: https://claude.ai/code/session_019Gu6CHqiyaRy1LfvPUHma7`.
- Làm trên nhánh `refactor/feature-modules`; gộp `main` chỉ sau Task 9.

## Review Focus

1. Người dùng đã sắp xếp Tổng quan trước khi nâng cấp: bố cục phải còn nguyên → test đọc `shell.overviewArrangement` qua `OverviewSettingsStore` (Task 4).
2. Thứ tự trang lưu từ trước khi có Tổng quan: Tổng quan vẫn đứng đầu → test `PageRegistry.order(_:leading:)` (Task 3).
3. Người dùng đã bật dán theo số: hai hàng vẫn đọc đúng modifiers cũ và vẫn không được trùng nhau → test `NumberRow` và test khoá của `ClipboardNumberRows` (Task 6).
4. Bấm "Đặt lại" bố cục trong Cài đặt trong lúc notch đang hiện Tổng quan: trang đổi theo ngay → `OverviewEditor` vẫn nghe `OverviewSettings.$arrangement` (Task 4, thử tay ở Task 9).
5. Một lần chạy thử với `--overview-arrangement` không ghi đè bố cục thật → `OverviewEditor` giữ cờ `saves` (Task 4, thử tay ở Task 9).

---

### Task 1: Script ranh giới và chạy test theo module

**Files:**
- Create: `Scripts/check-modules.sh`, `Scripts/test-module.sh`
- Modify: `Scripts/test.sh`

**Interfaces:**
- Produces: `Scripts/check-modules.sh [sources-dir]` (mặc định `Sources`), thoát 0 khi sạch, 1 và in từng dòng `<target>: imports <module> (<rule>)` khi vi phạm. `Scripts/test-module.sh <Module>` với Module ∈ {Platform, App, Clipboard, Calendar, Media, Timer, Agent, Files, Capture, Translate, Windows, SystemEvents, Overview, Tools}.

- [ ] **Step 1:** Viết `check-modules.sh` (bash 3.2 của macOS, không mảng kết hợp). Tên tính năng = tên thư mục có đuôi `Core`/`Feature` bỏ đuôi; module nội bộ = tên thư mục trong `Sources/`. Luật:
  - `*Core`: không import `SwiftUI`, `AppKit`, `NotchShell`, hay module nội bộ nào khác ngoài `NotchCore`.
  - `*Feature` của X: module nội bộ chỉ được là `XCore`, `NotchCore`, `NotchShell`.
  - `NotchCore`, `NotchShell`: không import module nội bộ nào ngoài `NotchCore`.
  - `ClipboardMCP`, `aranotch-mcp`, `aranotch-hook`: chỉ `ClipboardCore`/`ClipboardMCP`/`AgentCore` tương ứng như hiện nay (cho phép mọi `*Core` và `ClipboardMCP`).
  - Chỉ `AraNotch` được import `*Feature`.
- [ ] **Step 2:** Chạy `Scripts/check-modules.sh` → thoát 0 trên mã hiện tại.
- [ ] **Step 3:** Kiểm tra âm: tạo trong scratchpad một bản sao `Sources` có `TimerFeature/X.swift` chứa `import MediaFeature` và `TimerCore/Y.swift` chứa `import SwiftUI`; chạy script với thư mục đó → thoát 1, in đúng hai vi phạm.
- [ ] **Step 4:** `test-module.sh`: chạy `check-modules.sh`, rồi `Scripts/test.sh --filter '<regex>'` với regex là các target test của module (Platform → `NotchCoreTests|NotchShellTests`; Clipboard → `ClipboardCoreTests|ClipboardFeatureTests|ClipboardMCPTests`; Agent → `AgentCoreTests|AgentFeatureTests`; Capture → `CaptureCoreTests|CaptureFeatureTests`; Overview → `OverviewCoreTests`; module không có test thì báo "không có bộ test riêng" và thoát 0; X khác → `XCoreTests`). Tên module lạ → in danh sách hợp lệ, thoát 2.
- [ ] **Step 5:** `test.sh` gọi `check-modules.sh` trước `swift test`. Chạy `Scripts/test-module.sh Timer` → chỉ các suite Timer chạy, qua.
- [ ] **Step 6:** Commit `chore: scripts that check module boundaries and run one module's tests`.

### Task 2: Bộ widget dùng chung mang tên chung

**Files:**
- Create: `Sources/NotchCore/WidgetSize.swift`
- Rename: `Sources/NotchCore/OverviewAlert.swift` → `WidgetAlert.swift`; `Tests/NotchCoreTests/OverviewAlertTests.swift` → `WidgetAlertTests.swift`
- Modify: `Sources/NotchCore/OverviewLayout.swift` (bỏ `OverviewTileSize`), `Sources/NotchShell/Design/AraWidget.swift`, mọi chỗ dùng (`grep -rn 'OverviewTileSize\|OverviewAlert' Sources Tests`)

**Interfaces:**
- Produces: `public enum WidgetSize: String, CaseIterable, Sendable { case small, wide, large; columns; rows; next }` (thân giữ nguyên của `OverviewTileSize`), `public enum WidgetAlert` (thân giữ nguyên của `OverviewAlert`). `EnvironmentValues.araTileSize: WidgetSize`.

- [ ] **Step 1:** Đổi tên kiểu (giữ nguyên thân và chú thích, sửa chú thích đầu cho đúng vai trò dùng chung), sửa mọi chỗ dùng, đổi tên suite test `WidgetAlertTests`.
- [ ] **Step 2:** `Scripts/test.sh` → qua hết, tổng = 1235.
- [ ] **Step 3:** Commit `refactor: the shared widget kit names its size and alert for widgets, not the overview`.

### Task 3: Shell không còn biết tên trang Tổng quan

**Files:**
- Modify: `Sources/NotchCore/PageRegistry.swift`, `Sources/NotchShell/NotchController.swift:98-107`, `Sources/AraNotch/AppDelegate.swift` (chỗ tạo `NotchController`), `Sources/NotchCore/OverviewLayout.swift` (bỏ `orderWithOverview`)
- Test: `Tests/NotchCoreTests/PageRegistryTests.swift`, `Tests/NotchCoreTests/OverviewLayoutTests.swift` (bỏ test `orderWithOverview`)

**Interfaces:**
- Produces: `PageRegistry.order(_ order: [String], leading pageID: String?) -> [String]` (static); `NotchController.init(settings: ShellSettings, shortcuts: ShortcutCenter? = nil, leadingPageID: String? = nil)`.

- [ ] **Step 1: Test** (chuyển ba khẳng định cũ):
```swift
@Test func aSavedOrderWithoutTheLeadingPageGetsItInFront() {
    #expect(PageRegistry.order(["media", "clipboard"], leading: "overview") == ["overview", "media", "clipboard"])
    #expect(PageRegistry.order([], leading: "overview") == [])
    #expect(PageRegistry.order(["clipboard", "overview"], leading: "overview") == ["clipboard", "overview"])
    #expect(PageRegistry.order(["media"], leading: nil) == ["media"])
}
```
- [ ] **Step 2:** `Scripts/test.sh --filter PageRegistryTests` → FAIL (không có `order`).
- [ ] **Step 3:** Thêm `order(_:leading:)`; `NotchController` dùng nó với `leadingPageID`; app truyền `leadingPageID: OverviewLayout.pageID`; xoá `orderWithOverview` và test cũ của nó.
- [ ] **Step 4:** `Scripts/test.sh` → qua hết, tổng ≥ 1235.
- [ ] **Step 5:** Commit `refactor: the shell is told which page leads instead of knowing the overview`.

### Task 4: Module Overview

**Files:**
- Create: `Sources/OverviewCore/OverviewLayout.swift` (git mv từ `NotchCore`), `Sources/OverviewCore/OverviewSettingsStore.swift`, `Sources/OverviewFeature/OverviewSettings.swift`, `Sources/OverviewFeature/OverviewSettingsRow.swift`, `Tests/OverviewCoreTests/InMemoryDefaults.swift` (bản sao của NotchCoreTests)
- Move: `Sources/AraNotch/OverviewPage.swift`, `Sources/AraNotch/OverviewEditor.swift` → `Sources/OverviewFeature/`; `OverviewTiles` từ `Sources/AraNotch/Pages.swift` → `Sources/OverviewFeature/OverviewTiles.swift`; `Tests/NotchCoreTests/OverviewLayoutTests.swift` → `Tests/OverviewCoreTests/`
- Modify: `Package.swift`, `Sources/NotchCore/ShellSettingsStore.swift` (bỏ hai khoá bố cục), `Sources/NotchShell/ShellSettings.swift` (bỏ `overviewArrangement`), `Sources/AraNotch/SettingsView.swift:408-418` (dùng `OverviewSettingsRow`), `Sources/AraNotch/AppDelegate.swift`

**Interfaces:**
- Consumes: `WidgetSize` (Task 2), `PageRegistry.order` (Task 3).
- Produces:
  - `OverviewCore`: các kiểu cũ, enum `OverviewFeature` đổi tên `OverviewTileGroup`; `public struct OverviewSettingsStore { init(defaults: UserDefaults); var arrangement: [OverviewItem] { get nonmutating set } }` với logic đọc ghi chuyển nguyên từ `ShellSettingsStore.overviewArrangement` (khoá `shell.overviewArrangement`, `shell.hiddenOverviewWidgets`).
  - `OverviewFeature`: `@MainActor public final class OverviewSettings: ObservableObject { init(store: OverviewSettingsStore); @Published var arrangement: [OverviewItem] }`; `public final class OverviewEditor` với `public init(settings: OverviewSettings, trialArrangement: [OverviewItem]? = nil)`, `public func connect(to: NotchController)`, và mọi API app/launch argument đang gọi (`--edit-overview`) thành `public`; `public final class OverviewTiles { public var tiles: [OverviewWidget: AnyView] }`; `public struct OverviewPage`, `public struct OverviewEditButton`; `public struct OverviewSettingsRow: View { init(settings: OverviewSettings) }` (nút "Đặt lại", tắt khi đã là bố cục mặc định).
  - Package: `OverviewCore` (không phụ thuộc gì ngoài `NotchCore`), `OverviewFeature` phụ thuộc `OverviewCore`, `NotchShell`; test target `OverviewCoreTests` phụ thuộc `OverviewCore`; `AraNotch` thêm `OverviewFeature`.

- [ ] **Step 1:** Chuyển `OverviewLayoutTests` sang `OverviewCoreTests`, đổi các khẳng định lưu trữ từ `ShellSettingsStore(...).overviewArrangement` sang `OverviewSettingsStore(...).arrangement`, giữ nguyên chuỗi khoá `"shell.overviewArrangement"` và mọi giá trị mong đợi. Thêm:
```swift
@Test func theShellNoLongerKeepsTheArrangement() {
    let defaults = InMemoryDefaults()
    OverviewSettingsStore(defaults: defaults).arrangement = [item(.timer, .large)]
    #expect(defaults.object(forKey: "shell.overviewArrangement") as? [String] == ["timer:large"])
}
```
- [ ] **Step 2:** Khai báo target trong `Package.swift`, `git mv` các tệp, thêm `OverviewSettingsStore`/`OverviewSettings`/`OverviewSettingsRow`, bỏ phần bố cục khỏi `ShellSettingsStore`/`ShellSettings`, thêm `public` cần thiết, thêm `import OverviewCore` ở các Feature có widget nếu chúng dùng kiểu Overview (theo Task 2 chúng chỉ còn cần `WidgetSize`/`WidgetAlert` của `NotchCore` — nếu Feature nào vẫn cần `OverviewCore` thì đó là vi phạm: sửa cho nó dùng kiểu chung).
- [ ] **Step 3:** App: tạo `OverviewSettings(store: OverviewSettingsStore(defaults: .standard))`, truyền vào `OverviewEditor` và `PagesSettingsSection` (qua `OverviewSettingsRow`).
- [ ] **Step 4:** `Scripts/check-modules.sh` → 0; `Scripts/test-module.sh Overview` → qua; `Scripts/test.sh` → qua hết, tổng ≥ 1236.
- [ ] **Step 5:** Commit `refactor: the overview is a module of its own`.

### Task 5: Module Tools, trang Giới thiệu có tệp riêng

**Files:**
- Create: `Sources/ToolsFeature/NotchTool.swift`, `ToolsPage.swift`, `ToolsWidget.swift`, `ToolsController.swift`; `Sources/AraNotch/AboutPage.swift`
- Delete: `Sources/AraNotch/Pages.swift`
- Modify: `Package.swift`, `Sources/AraNotch/AppDelegate.swift:126-158`

**Interfaces:**
- Produces: `public struct NotchTool: Identifiable { public init(id: String, action: @escaping () -> Void) }` (icon và hue lấy từ bảng `looks` theo `id`, mặc định `(.grid, .peach)` như hiện nay); `@MainActor public final class ToolsController { public init(tools: [NotchTool], quickToolIDs: [String]); public func makePage() -> NotchPage; public func makeOverviewTile() -> AnyView }` — trang id `"tools"`, titleKey `"page.tools.title"`, symbol `"wrench.and.screwdriver"`, quick tools mặc định app truyền `["capture", "text", "color", "translate"]`. Package: `ToolsFeature` phụ thuộc `NotchShell`.

- [ ] **Step 1:** Chuyển mã (thân view giữ nguyên), app tạo danh sách công cụ (việc đóng notch rồi chờ 0,35 s trước khi chạy vẫn ở app, vì nó cần `controller`) và dùng `ToolsController`. `AboutPage` sang tệp riêng.
- [ ] **Step 2:** `Scripts/check-modules.sh` → 0; `Scripts/test.sh` → qua hết, tổng không đổi so với Task 4.
- [ ] **Step 3:** Commit `refactor: the tools page is a module of its own, the about page has its own file`.

### Task 6: Hàng phím số thuộc Clipboard

**Files:**
- Modify: `Sources/NotchCore/Shortcuts.swift` (`ShortcutStore`), `Sources/NotchShell/ShortcutCenter.swift`, `Sources/ClipboardFeature/ClipboardController.swift:250-251`, `Sources/ClipboardFeature/ClipboardSettingsSection.swift:136-140`
- Create: `Sources/ClipboardFeature/ClipboardNumberRows.swift`, `Tests/ClipboardFeatureTests/NumberRowKeyTests.swift`
- Test: `Tests/NotchCoreTests/ShortcutTests.swift` (thay `QuickPasteShortcutTests`, `RecentPasteShortcutTests`)

**Interfaces:**
- Produces:
  - `NotchCore`: `public struct NumberRow: Hashable, Sendable { public let storageKey: String; public init(storageKey: String) }`; trên `ShortcutStore`: `func modifiers(for: NumberRow) -> KeyComboModifiers?`, `func setModifiers(_: KeyComboModifiers?, for: NumberRow, others: [NumberRow])` (nil xoá; từ chối khi không có ⌘/⌃/⌥ hoặc trùng một hàng trong `others`), `func combos(for: NumberRow) -> [KeyCombo]` (9 combo theo `digitKeyCodes`, rỗng khi tắt).
  - `NotchShell`: trên `ShortcutCenter`: `func setNumberRow(_: NumberRow, handler: @escaping (Int) -> Void)`, `@Published private(set) var numberRowModifiers: [NumberRow: KeyComboModifiers]`, `@Published private(set) var refusedNumberRows: Set<NumberRow>`, `func setModifiers(_: KeyComboModifiers?, for: NumberRow)` (others = các hàng đã đăng ký khác), `func isNumberRowCombo(_: KeyCombo) -> Bool` (thay `isQuickPasteCombo`). `ShortcutNumberRowPicker(center:row:other:titleKey:noteKey:)`.
  - `ClipboardFeature`: `public enum ClipboardNumberRows { static let pinned = NumberRow(storageKey: "shortcut.quickPasteModifiers"); static let recent = NumberRow(storageKey: "shortcut.recentPasteModifiers") }`.

- [ ] **Step 1: Test** — viết lại hai suite cũ trên `NumberRow` (`let a = NumberRow(storageKey: "shortcut.quickPasteModifiers"), b = NumberRow(storageKey: "shortcut.recentPasteModifiers")`), giữ mọi khẳng định cũ: lưu và đọc lại `[.control, .option]`; nil tắt; 9 combo, combo đầu `KeyCombo(keyCode: 18, modifiers: ...)`; chỉ Shift bị từ chối; hai hàng không trùng modifiers. Thêm trong `ClipboardFeatureTests`:
```swift
@Test func theNumberRowsKeepTheirStoredKeys() {
    #expect(ClipboardNumberRows.pinned.storageKey == "shortcut.quickPasteModifiers")
    #expect(ClipboardNumberRows.recent.storageKey == "shortcut.recentPasteModifiers")
}
```
- [ ] **Step 2:** `Scripts/test.sh --filter 'ShortcutTests|NumberRowKeyTests'` → FAIL (chưa có `NumberRow`).
- [ ] **Step 3:** Cài đặt API trên; bỏ mọi tên quickPaste/recentPaste khỏi `NotchCore`/`NotchShell` (`grep -rn -i 'quickPaste\|recentPaste' Sources/NotchCore Sources/NotchShell` rỗng); Clipboard đăng ký hai hàng và truyền khoá chữ `settings.shortcuts.quickPaste(.note)` / `settings.shortcuts.recentPaste(.note)`; dòng chọn board chỉ hiện khi `numberRowModifiers[ClipboardNumberRows.pinned] != nil`.
- [ ] **Step 4:** `Scripts/test.sh` → qua hết, tổng ≥ 1237.
- [ ] **Step 5:** Commit `refactor: the clipboard owns its paste-by-number rows; the shell only knows number rows`.

### Task 7: Sổ module và quy trình

**Files:**
- Create: `docs/modules/README.md`, `docs/modules/{Platform,App,Clipboard,Calendar,Media,Timer,Agent,Files,Capture,Translate,Windows,SystemEvents,Overview,Tools}.md`, `CLAUDE.md` (gốc repo)

- [ ] **Step 1:** README: bảng module (nhóm, target, thư mục, phụ thuộc), luật ranh giới (đúng như `check-modules.sh`), ngoại lệ `ShortcutAction`, quy trình sửa lỗi 5 bước của spec, cách dùng hai script.
- [ ] **Step 2:** Mỗi sổ module theo đúng các mục của spec (Vai trò; Target và thư mục; Tệp chính; Giao diện công khai; Phụ thuộc và ai dùng; Dữ liệu lưu; Quyền hệ thống; Test; Lỗi và giới hạn đã biết; Nhật ký sửa lỗi). Dữ liệu lưu lấy từ các `Key` trong `*SettingsStore` và đường dẫn tệp; lỗi/giới hạn lấy từ `docs/project/FEATURES.md`. Nhật ký sửa lỗi mở đầu bằng dòng 2026-10-26 của lần tái cấu trúc này nếu module bị chạm.
- [ ] **Step 3:** `CLAUDE.md`: một trang ngắn: đọc `docs/modules/README.md` trước; sửa lỗi theo quy trình; không sửa ngoài module; chạy `test-module.sh` rồi `test.sh`; cập nhật sổ module, `FEATURES.md`, `HISTORY.md` sau mỗi việc; không dùng graphify cho repo này.
- [ ] **Step 4:** Kiểm tra: mỗi đường dẫn tệp nêu trong sổ tồn tại (script nhỏ trong scratchpad lấy mọi `Sources/...swift` trong `docs/modules` và `test -f`).
- [ ] **Step 5:** Commit `docs: a guide for every module and the way we fix bugs by module`.

### Task 8: Xoá graphify

**Files:**
- Delete: `graphify-out/` (không theo git), `.graphifyignore`, `Scripts/graph-update.py`, `Scripts/graph-docs.py`, `Scripts/graph-refresh.sh`
- Modify: `.gitignore`, `docs/project/FEATURES.md:3`, `docs/project/HISTORY.md:3`; bộ nhớ `aranotch-project-memory-workflow.md` và `MEMORY.md`

- [ ] **Step 1:** Xoá; sửa hai câu đầu tài liệu thành "cập nhật sổ module trong `docs/modules/`".
- [ ] **Step 2:** `grep -rn -i graphify . --exclude-dir=.build --exclude-dir=build --exclude-dir=.claude --exclude-dir=.git` chỉ còn trong các mục lịch sử của `HISTORY.md` và các plan/spec cũ.
- [ ] **Step 3:** Chạy một lệnh `grep` bất kỳ qua Bash: hook graphify không còn chèn nhắc "MANDATORY: graphify-out/graph.json exists".
- [ ] **Step 4:** Commit `chore: graphify is gone; the module guides replace it`.

### Task 9: Kiểm chứng toàn bộ, thử tay, gộp

- [ ] **Step 1:** `Scripts/test.sh` → qua hết; ghi tổng số test.
- [ ] **Step 2:** `Scripts/build-app.sh`, thay bản trong `/Applications` bằng `ditto` theo bộ nhớ launch, mở bằng `open`.
- [ ] **Step 3:** Thử tay: Tổng quan còn bố cục đang dùng; vào sửa, đổi cỡ một ô, kéo một ô, rồi trả lại như cũ; trang Công cụ hiện 8 công cụ, bấm "Bảng màu" mở được bộ chọn màu (Esc thoát); Cài đặt > Clipboard có hai hàng phím số với giá trị cũ; Cài đặt > Trang có nút Đặt lại bố cục; trang Giới thiệu hiện phiên bản. Chụp ảnh làm bằng chứng.
- [ ] **Step 4:** Thêm một vòng vào `HISTORY.md`; gộp `refactor/feature-modules` vào `main` (fast-forward); xoá nhánh.
