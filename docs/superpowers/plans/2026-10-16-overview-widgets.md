# Tổng quan kiểu widget — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trang Tổng quan thành lưới 4 cột mà chủ dự án tự sắp xếp ngay trên notch: bỏ, thêm, đổi cỡ (nhỏ, rộng, lớn), kéo đổi chỗ; notch dài thêm hàng khi cần.

**Architecture:** Bố cục là một danh sách có thứ tự `[OverviewItem]` lưu trong `ShellSettingsStore`; `OverviewGrid` (NotchCore, logic thuần) đặt từng ô vào chỗ trống đầu tiên vừa nó và tính số hàng. `OverviewPage` (AraNotch) vẽ lưới theo kết quả đó, truyền cỡ xuống từng ô qua environment `\.araTileSize`; mỗi tính năng tự vẽ ba dạng của ô mình. Chế độ sửa do `OverviewEditor` giữ, nút bút chì nằm trên hàng tab qua một chỗ mới `NotchPage.headerAccessory`.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 15, Swift Testing (`Scripts/test.sh`).

**Spec:** `docs/superpowers/specs/2026-10-16-overview-widgets-design.md`

## Global Constraints

- Lưới 4 cột; ít nhất 2 hàng, nhiều nhất 4 hàng (16 ô nhỏ).
- Ba cỡ: `small` 1×1, `wide` 2×1, `large` 2×2; nút cỡ đổi vòng nhỏ → rộng → lớn → nhỏ.
- Mỗi `OverviewWidget` nhiều nhất một lần trong bố cục.
- Khoá lưu: `shell.overviewArrangement`, mảng chuỗi `"<widget>:<size>"`.
- Bố cục mặc định: `media:wide, calendar:wide, timer:small, agents:small, clipboard:small, device:small`; `tools` mặc định tắt.
- `shell.hiddenOverviewWidgets` chỉ được đọc để chuyển một lần, không ghi nữa.
- Chiều rộng notch không bao giờ đổi; trần 80% chiều cao màn hình của `PageHeight` giữ nguyên.
- Mọi chữ hiện ra có cả `Resources/en.lproj/Localizable.strings` và `Resources/vi.lproj/Localizable.strings`.
- Thao tác bằng chuột là chính, không thêm phím tắt mới (hướng giao diện của chủ dự án).
- Chạy test bằng `Scripts/test.sh`; build app bằng `Scripts/build-app.sh`; cập nhật bản cài ở `/Applications` bằng `ditto` và mở bằng `open` (không chạy trực tiếp tệp thực thi).
- Sau mỗi việc có sửa code: `graphify update .`.

## Review Focus

1. **Notch bị trần 80% cắt (cỡ 150%, 4 hàng, màn hình 13 inch):** các hàng phải cùng thấp lại cho vừa, không ô nào bị cắt hay tràn. → Việc 4 chia chiều cao thật của trang cho số hàng, không dùng chiều cao hàng cố định; kiểm bằng ảnh chụp ở 150%.
2. **Kéo dở rồi thả ra ngoài notch, hoặc notch đóng giữa lúc kéo:** ô về chỗ cũ, không có gì được lưu. → Việc 9: `OverviewDrag` giữ bố cục xem trước, `drop(inside: false)` trả `nil`; test `aDragShowsTheNewOrderAndIsSavedOnlyWhenDroppedOnTheGrid`.
3. **Ô Clipboard cỡ nhỏ khi clip mới nhất nằm trong bảng khoá:** không được lộ nội dung; lấy clip mới nhất không mã hoá như ô hiện nay. → Việc 6 giữ bộ lọc `!isEncrypted` cho mọi cỡ.
4. **Lịch và Lời nhắc chưa cấp quyền:** ô Hôm nay ở cỡ nào cũng còn nút xin quyền như hiện nay, không phải ô trống. → Việc 6 giữ nhánh xin quyền cho cả ba cỡ; kiểm bằng đọc mã, không đổi quyền thật và không bấm hộp thoại hệ thống.
5. **Ghi cài đặt liên tục trong lúc kéo, hoặc ghi khi kéo về chỗ cũ:** chỉ một lần ghi khi thả, không ghi nếu không đổi. → Việc 9: chỗ ghi duy nhất là kết quả của `OverviewDrag.drop`; test `aDragBackToWhereItStartedSavesNothing`.

---

## Bản đồ tệp

| Tệp | Việc | Trách nhiệm |
|---|---|---|
| `Sources/NotchCore/OverviewLayout.swift` | 1, 2, 3 | `OverviewWidget`, `OverviewTileSize`, `OverviewItem`, `OverviewPlacement`, `OverviewGrid`; giữ `OverviewLayout.pageID`, `orderWithOverview` |
| `Sources/NotchCore/ShellSettingsStore.swift` | 3 | Đọc, ghi, chuyển bố cục |
| `Sources/NotchShell/ShellSettings.swift` | 3 | `@Published overviewArrangement` |
| `Tests/NotchCoreTests/OverviewLayoutTests.swift` | 1, 2, 3 | Viết lại cho mô hình mới |
| `Sources/NotchShell/Design/AraOverviewTile.swift` | 4 | `\.araTileSize`; dòng tên chỉ có icon ở cỡ nhỏ |
| `Sources/AraNotch/Pages.swift` | 4, 7, 8, 9 | `OverviewPage` vẽ lưới; ô Công cụ và Máy ba cỡ; lớp phủ chế độ sửa |
| `Sources/AraNotch/OverviewEditor.swift` (mới) | 8, 9 | Trạng thái chế độ sửa, bố cục xem trước khi kéo |
| `Sources/NotchShell/NotchPage.swift`, `NotchRootView.swift`, `NotchController.swift` | 8 | `headerAccessory`, `selectedPagePublisher` |
| Tệp ô của từng tính năng | 5, 6, 7 | Ba dạng của từng ô |
| `Sources/SystemEventsFeature/BluetoothMonitor.swift`, `SystemEventsController.swift` | 7 | Tên thiết bị Bluetooth đang nối |
| `Sources/AraNotch/SettingsView.swift`, `AppDelegate.swift` | 4, 8, 10 | Nối dây; Cài đặt › Trang notch |
| `Resources/*/Localizable.strings` | 4, 8, 10 | Chữ mới |
| `docs/project/FEATURES.md`, `docs/project/HISTORY.md` | 11 | Sổ tính năng và lịch sử |

---

### Việc 1: Mô hình ô và cách xếp

**Files:**
- Modify: `Sources/NotchCore/OverviewLayout.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Produces:
  - `public enum OverviewTileSize: String, CaseIterable, Sendable { case small, wide, large }` với `var columns: Int` (1, 2, 2), `var rows: Int` (1, 1, 2), `var next: OverviewTileSize`.
  - `public struct OverviewItem: Equatable, Sendable { public var widget: OverviewWidget; public var size: OverviewTileSize }`.
  - `public struct OverviewPlacement: Equatable, Sendable { public let item: OverviewItem; public let column: Int; public let row: Int }`.
  - `public enum OverviewGrid` với `static let columns = 4`, `static let minimumRows = 2`, `static let maximumRows = 4`, `static func place(_ items: [OverviewItem]) -> (placements: [OverviewPlacement], rows: Int)`, `static func fits(_ items: [OverviewItem]) -> Bool`.

- [ ] **Bước 1: Viết test hỏng**

Giữ nguyên các test cũ (Việc 4 mới bỏ API cũ, để mỗi commit đều build được cả app). Thêm:

```swift
private func item(_ widget: OverviewWidget, _ size: OverviewTileSize) -> OverviewItem { OverviewItem(widget: widget, size: size) }

@Test func sizesCycleSmallWideLarge() {
    #expect(OverviewTileSize.small.next == .wide)
    #expect(OverviewTileSize.wide.next == .large)
    #expect(OverviewTileSize.large.next == .small)
}

@Test func theDefaultFillsTwoRows() {
    let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small),
                 item(.agents, .small), item(.clipboard, .small), item(.device, .small)]
    let result = OverviewGrid.place(items)
    #expect(result.rows == 2)
    #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1], [3, 1]])
}

@Test func aSmallTileFillsTheGapAWideOneLeaves() {
    // The second wide tile does not fit in the one column left on row 0, so it starts row 1;
    // the small tile after it goes back up into that column.
    let result = OverviewGrid.place([item(.timer, .small), item(.media, .wide), item(.calendar, .wide), item(.agents, .small)])
    #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [1, 0], [0, 1], [3, 0]])
}

@Test func aLargeTileTakesTwoRows() {
    let result = OverviewGrid.place([item(.media, .large), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)])
    #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [2, 0], [2, 1], [3, 1]])
    #expect(result.rows == 2)
}

@Test func thePageNeverHasFewerThanTwoRows() {
    #expect(OverviewGrid.place([]).rows == 2)
    #expect(OverviewGrid.place([item(.timer, .small)]).rows == 2)
}

@Test func moreThanFourRowsDoesNotFit() {
    let four = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .large)]
    #expect(OverviewGrid.fits(four))
    #expect(OverviewGrid.place(four).rows == 4)
    #expect(!OverviewGrid.fits(four + [item(.device, .small)]))
}
```

- [ ] **Bước 2: Chạy, thấy hỏng**

Run: `Scripts/test.sh --filter OverviewLayoutTests`
Expected: lỗi biên dịch, `OverviewTileSize` chưa có.

- [ ] **Bước 3: Viết mã**

Thêm các kiểu ở trên vào `OverviewLayout.swift`, chưa bỏ gì. `place` dùng lưới chiếm chỗ mở rộng dần, không giới hạn hàng (để `fits` biết khi quá 4):

```swift
var taken: [[Bool]] = []
for item in items {
    var row = 0
    search: while true {
        while taken.count < row + item.size.rows { taken.append(Array(repeating: false, count: columns)) }
        for column in 0...(columns - item.size.columns) where free(column, row, item.size) { mark; record; break search }
        row += 1
    }
}
rows = max(minimumRows, taken.count with trailing empty rows dropped)
```

`fits` là `place(items).rows <= maximumRows`.

- [ ] **Bước 4: Chạy, thấy qua**

Run: `Scripts/test.sh --filter OverviewLayoutTests`
Expected: mọi test qua.

- [ ] **Bước 5: Commit**

```bash
git add Sources/NotchCore/OverviewLayout.swift Tests/NotchCoreTests/OverviewLayoutTests.swift
git commit -m "feat: the overview's tiles are placed on a four-column grid, each in the first gap it fits"
```

---

### Việc 2: Các phép sửa bố cục và chiều cao

**Files:**
- Modify: `Sources/NotchCore/OverviewLayout.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Consumes: Việc 1.
- Produces (đều là `static func` của `OverviewGrid`, trả bố cục mới hoặc `nil` khi không làm được):
  - `resized(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem]?`
  - `moved(_ items: [OverviewItem], widget: OverviewWidget, to index: Int) -> [OverviewItem]`
  - `adding(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem]?`
  - `removing(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem]`
  - `index(atColumn column: Int, row: Int, in items: [OverviewItem]) -> Int?` — vị trí trong danh sách của ô đang chiếm ô lưới đó; `nil` cho ô trống.
  - `sheetHeight(rows: Int) -> CGFloat?` — `nil` khi `rows <= 2`; ngược lại `NotchGeometry.defaultOpenSize.height + CGFloat(rows - 2) * rowStep`, với `static let rowStep: CGFloat = 84` (một hàng 78 cộng khoảng cách 6, đo trên tờ 640 × 200; Việc 4 kiểm lại bằng ảnh chụp và sửa hằng này nếu lệch).

- [ ] **Bước 1: Viết test hỏng**

```swift
@Test func resizingTakesTheNextSizeThatFits() {
    let full = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .wide), item(.device, .small)]
    // agents wide → large would need a fifth row; it goes on to small instead.
    #expect(OverviewGrid.resized(full, widget: .agents)?.first { $0.widget == .agents }?.size == .small)
    // device small → wide fits (row 4 has room for it beside agents).
    #expect(OverviewGrid.resized(full, widget: .device)?.first { $0.widget == .device }?.size == .wide)
}

@Test func resizingWithNoOtherSizeThatFitsGivesNil() {
    // Sixteen cells taken: a small tile can neither widen nor grow.
    let full = [item(.media, .large), item(.calendar, .large), item(.timer, .large),
                item(.agents, .wide), item(.device, .small), item(.tools, .small)]
    #expect(OverviewGrid.resized(full, widget: .tools) == nil)
    // A tile that is not on the page has nothing to resize.
    #expect(OverviewGrid.resized([item(.media, .small)], widget: .tools) == nil)
}

@Test func movingPutsATileAtAnIndex() {
    let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small)]
    #expect(OverviewGrid.moved(items, widget: .timer, to: 0).map(\.widget) == [.timer, .media, .calendar])
    #expect(OverviewGrid.moved(items, widget: .media, to: 9).map(\.widget) == [.calendar, .timer, .media])
}

@Test func addingIsSmallAtTheEndOnceAndOnlyWithRoom() {
    let items = [item(.media, .wide)]
    #expect(OverviewGrid.adding(items, widget: .tools) == items + [item(.tools, .small)])
    #expect(OverviewGrid.adding(items, widget: .media) == nil)
    let four = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .large)]
    #expect(OverviewGrid.adding(four, widget: .device) == nil)
}

@Test func removingTakesTheTileOut() {
    #expect(OverviewGrid.removing([item(.media, .wide), item(.timer, .small)], widget: .media) == [item(.timer, .small)])
}

@Test func aCellIsFoundByTheTileOnIt() {
    let items = [item(.media, .large), item(.calendar, .wide)]
    #expect(OverviewGrid.index(atColumn: 1, row: 1, in: items) == 0)
    #expect(OverviewGrid.index(atColumn: 3, row: 0, in: items) == 1)
    #expect(OverviewGrid.index(atColumn: 3, row: 1, in: items) == nil)
}

@Test func eachRowPastTwoMakesTheSheetTaller() {
    #expect(OverviewGrid.sheetHeight(rows: 2) == nil)
    #expect(OverviewGrid.sheetHeight(rows: 3) == 284)
    #expect(OverviewGrid.sheetHeight(rows: 4) == 368)
}
```

- [ ] **Bước 2: Chạy, thấy hỏng** — `Scripts/test.sh --filter OverviewLayoutTests`, lỗi biên dịch.

- [ ] **Bước 3: Viết mã** trong `OverviewGrid`. `resized` thử lần lượt `size.next`, `size.next.next` và dừng khi quay về cỡ cũ; trả bố cục đầu tiên `fits`; `nil` khi không có hoặc không tìm được cỡ khác. `moved` bỏ ô khỏi danh sách rồi chèn lại ở `index` kẹp vào `0...(số ô còn lại)`.

- [ ] **Bước 4: Chạy, thấy qua.**

- [ ] **Bước 5: Commit** — `feat: the overview's arrangement can be resized, reordered, added to and taken from`.

---

### Việc 3: Lưu bố cục và chuyển từ bản cũ

**Files:**
- Modify: `Sources/NotchCore/ShellSettingsStore.swift`, `Sources/NotchShell/ShellSettings.swift`, `Sources/NotchCore/OverviewLayout.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Consumes: Việc 1.
- Produces:
  - `OverviewGrid.defaultArrangement: [OverviewItem]` (theo Global Constraints).
  - `ShellSettingsStore.Key.overviewArrangement = "shell.overviewArrangement"`.
  - `ShellSettingsStore.overviewArrangement: [OverviewItem] { get nonmutating set }`.
  - `ShellSettings.overviewArrangement: [OverviewItem]` (`@Published`, ghi xuống store trong `didSet`). `hiddenOverviewWidgets` ở store và `ShellSettings` còn giữ tới Việc 4.

- [ ] **Bước 1: Viết test hỏng**

```swift
@Test func anArrangementIsRemembered() {
    let defaults = InMemoryDefaults()
    let store = ShellSettingsStore(defaults: defaults)
    store.overviewArrangement = [item(.timer, .large), item(.media, .small)]
    #expect(defaults.object(forKey: "shell.overviewArrangement") as? [String] == ["timer:large", "media:small"])
    #expect(ShellSettingsStore(defaults: defaults).overviewArrangement == [item(.timer, .large), item(.media, .small)])
}

@Test func withNothingSavedTheDefaultIsUsed() {
    #expect(ShellSettingsStore(defaults: InMemoryDefaults()).overviewArrangement == OverviewGrid.defaultArrangement)
    #expect(OverviewGrid.place(OverviewGrid.defaultArrangement).rows == 2)
}

@Test func tilesHiddenBeforeStayHidden() {
    let defaults = InMemoryDefaults()
    defaults.set(["timer", "media"], forKey: "shell.hiddenOverviewWidgets")
    #expect(ShellSettingsStore(defaults: defaults).overviewArrangement.map(\.widget) == [.calendar, .agents, .clipboard, .device])
}

@Test func damagedEntriesAreDropped() {
    let defaults = InMemoryDefaults()
    defaults.set(["media:wide", "weather:small", "timer:huge", "media:small", "nonsense", "agents:large"], forKey: "shell.overviewArrangement")
    #expect(ShellSettingsStore(defaults: defaults).overviewArrangement == [item(.media, .wide), item(.agents, .large)])
}

@Test func anArrangementTooTallLosesItsLastTiles() {
    let defaults = InMemoryDefaults()
    defaults.set(["media:large", "calendar:large", "timer:large", "agents:large", "device:small"], forKey: "shell.overviewArrangement")
    #expect(ShellSettingsStore(defaults: defaults).overviewArrangement.map(\.widget) == [.media, .calendar, .timer, .agents])
}

@Test func anEmptyArrangementStaysEmpty() {
    let defaults = InMemoryDefaults()
    defaults.set([String](), forKey: "shell.overviewArrangement")
    #expect(ShellSettingsStore(defaults: defaults).overviewArrangement.isEmpty)
}
```

- [ ] **Bước 2: Chạy, thấy hỏng.**

- [ ] **Bước 3: Viết mã.** Đọc: không có khoá mới → mặc định trừ các ô trong khoá cũ; có → tách mỗi chuỗi ở dấu `:` thành `OverviewWidget` và `OverviewTileSize`, bỏ chuỗi hỏng và widget trùng, rồi bỏ ô cuối cho tới khi `OverviewGrid.fits`. Ghi: chỉ khoá mới.

- [ ] **Bước 4: Chạy, thấy qua** — `Scripts/test.sh --filter OverviewLayoutTests` rồi `Scripts/test.sh` (cả bộ).

- [ ] **Bước 5: Commit** — `feat: the overview's arrangement is saved, starting from the tiles that were hidden before`.

---

### Việc 4: Trang vẽ lưới và báo chiều cao

**Files:**
- Modify: `Sources/NotchShell/Design/AraOverviewTile.swift`, `Sources/AraNotch/Pages.swift` (`OverviewPage`), `Sources/AraNotch/AppDelegate.swift`, `Sources/AraNotch/LaunchArguments.swift`, `Sources/AraNotch/SettingsView.swift` (bỏ hàng chip `settings.overview`; Việc 10 thay chỗ đó), `Sources/NotchCore/OverviewLayout.swift`, `Sources/NotchCore/ShellSettingsStore.swift`, `Sources/NotchShell/ShellSettings.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Consumes: Việc 1–3; `NotchController.setSheetHeight(_:forPage:)`.
- Produces:
  - `public extension EnvironmentValues { var araTileSize: OverviewTileSize }` (mặc định `.wide`) trong `AraOverviewTile.swift`. Ở `.small`, dòng tên của `AraOverviewTile` chỉ có icon (vẫn là nút mở trang, có chú giải là tên).
  - `OverviewPage(settings: ShellSettings, tiles: [OverviewWidget: AnyView], onRowsChange: @escaping (Int) -> Void)`.
  - Tham số chạy thử `--overview-arrangement <list>` (ví dụ `media:large,timer:small`): dùng bố cục này cho lần chạy đó, không ghi vào cài đặt. Mọi ảnh chụp từ đây dùng nó cùng `--open-on-launch --select-page overview --snapshot-dir <dir>`, để không đổi cài đặt thật của chủ dự án.

- [ ] **Bước 0: Bỏ API cũ.** Xoá `OverviewLayout.widgets(hidden:)`, `arrangement`, `columns(hidden:)`, `growing`, `fills(_:in:)`, `ShellSettings.hiddenOverviewWidgets`; `ShellSettingsStore.hiddenOverviewWidgets` thành `private` chỉ đọc (dùng cho chuyển ở Việc 3); xoá các test cũ tương ứng (`everyWidgetShowsUnlessHidden`, `aNameThatIsNoWidgetHidesNothing`, `theWidgetsStandInThreeColumns`, `aColumnLeftEmptyIsNotKept`, `oneWidgetInEachColumnTakesTheRoomLeftOver`, `theHiddenWidgetsAreRemembered`).

- [ ] **Bước 1: Viết mã `OverviewPage`.** Dùng `GeometryReader`: bề rộng ô = (rộng − 3 × khoảng cách) / 4, chiều cao hàng = (cao − (số hàng − 1) × khoảng cách) / số hàng, nên khi notch bị trần 80% các hàng cùng thấp lại (Review Focus 1). Đặt mỗi ô bằng `.frame` và `.position` theo `OverviewPlacement`, gắn `.environment(\.araTileSize, placement.item.size)`. Gọi `onRowsChange` trong `.onChange(of: rows, initial: true)`. Một ô có trong bố cục mà `tiles` không có view: vẽ `AraOverviewTile` trống với icon và tên tính năng, giữ chỗ để bố cục không nhảy. Bố cục rỗng: giữ `AraEmptyState` (Việc 8 thêm nút).
- [ ] **Bước 2: Nối dây trong `AppDelegate`:** `onRowsChange: { [weak controller] rows in controller?.setSheetHeight(OverviewGrid.sheetHeight(rows: rows), forPage: OverviewLayout.pageID) }`.
- [ ] **Bước 3: Build và chạy test** — `Scripts/test.sh` rồi `Scripts/build-app.sh`; Expected: không lỗi.
- [ ] **Bước 4: Kiểm bằng ảnh chụp.** Cài vào `/Applications` (`ditto`), mở bằng `open` kèm các tham số chạy thử ở trên. Bố cục mặc định ở cỡ 120%: notch cao đúng như bản 0.24.0. Một bố cục 3 hàng: hàng thứ ba cao bằng hai hàng đầu; nếu lệch, sửa `OverviewGrid.rowStep` và test của nó. Cỡ 150% với 4 hàng: không ô nào bị cắt (cỡ notch là cài đặt thật; ghi lại giá trị trước khi đổi và trả lại ngay sau khi chụp).
- [ ] **Bước 5: Commit** — `feat: the overview page lays its tiles on the grid and grows a row at a time`.

---

### Việc 5: Ba cỡ cho Nhạc và Hẹn giờ

**Files:**
- Modify: `Sources/MediaFeature/MediaOverviewTile.swift`, `Sources/TimerFeature/TimerOverviewTile.swift`

**Interfaces:**
- Consumes: `\.araTileSize` (Việc 4). Mỗi ô đọc `@Environment(\.araTileSize) private var size` và `switch size`.

Nội dung (từ spec, không đổi):

| Ô | small | wide | large |
|---|---|---|---|
| Nhạc | Ảnh bìa, tên bài, nút phát/tạm dừng | Như nay | Ảnh lớn, tên, ca sĩ, thanh tiến độ (chỉ xem), ba nút, dòng lời bài hát đang hát khi `MediaSettings.showsLyrics` bật |
| Hẹn giờ | Bộ đếm sắp hết nhất, bấm để tạm dừng/tiếp tục; chưa có thì một mức sẵn đầu tiên | Như nay | Tới bốn bộ đếm của `TimerBoard`, mỗi bộ có +1′ và tạm dừng; chưa có thì các mức sẵn |

- [ ] **Bước 1: Viết ba dạng của ô Nhạc**, dùng lại các view con có trong `MediaOverviewTile.swift` và trang Nhạc (thanh tiến độ, dòng lời bài hát) thay vì vẽ lại.
- [ ] **Bước 2: Viết ba dạng của ô Hẹn giờ**, dùng lại các hàng bộ đếm của trang Hẹn giờ.
- [ ] **Bước 3: Build, chụp ba cỡ** của mỗi ô bằng tiếng Anh và tiếng Việt, khi có và khi không có nhạc/bộ đếm. Dùng `--overview-arrangement` để đặt ô ở cỡ cần chụp, `--simulate-now-playing <json>` cho bài hát và `--timer <seconds>` cho bộ đếm. Không bấm nút phát hay chuyển bài trên ứng dụng nhạc thật của chủ dự án.
- [ ] **Bước 4: Commit** — `feat: the music and timer tiles come in small, wide and large`.

---

### Việc 6: Ba cỡ cho Hôm nay và Clipboard

**Files:**
- Modify: `Sources/CalendarFeature/CalendarOverviewTile.swift`, `Sources/ClipboardFeature/ClipboardOverviewTile.swift`

| Ô | small | wide | large |
|---|---|---|---|
| Hôm nay | Việc kế tiếp và thời gian còn lại ("còn 12′" / "in 12′") | Ba dòng (như nay) | Sáu dòng; nút Tham gia cho sự kiện có link họp; bấm vòng tròn để xong lời nhắc |
| Clipboard | Clip mới nhất không mã hoá, bấm để dán | Ba thẻ (như nay) | Sáu thẻ, hai hàng ba thẻ |

- [ ] **Bước 1: Ô Hôm nay.** Đổi hằng `lines` thành hàm theo cỡ (1, 3, 6). Dùng lại nút Tham gia và vòng tròn xong của trang Lịch. Khi chưa có quyền, mọi cỡ hiện nút xin quyền như ô hiện nay (Review Focus 4). Thêm chuỗi `overview.calendar.in` ("in %@" / "còn %@") vào hai tệp chuỗi.
- [ ] **Bước 2: Ô Clipboard.** Đổi `count` thành hàm theo cỡ (1, 3, 6); giữ bộ lọc `!$0.isEncrypted` cho mọi cỡ (Review Focus 3); lỗi lịch sử hỏng vẫn hiện như nay ở mọi cỡ.
- [ ] **Bước 3: Chụp ba cỡ** hai thứ tiếng với `--simulate-agenda` và kho clipboard thử (`--data-dir <thư mục tạm> --seed-clipboard`); một lần với `--seed-boards --seed-vault <mật mã thử>` và clip mới nhất nằm trong bảng khoá. Không đụng lịch sử thật. Trường hợp chưa có quyền Lịch: không đổi quyền thật của máy; kiểm bằng cách đọc mã rằng nhánh xin quyền của ô hiện nay được giữ cho cả ba cỡ.
- [ ] **Bước 4: Commit** — `feat: the today and clipboard tiles come in small, wide and large`.

---

### Việc 7: Ba cỡ cho Agent, Máy và Công cụ

**Files:**
- Modify: `Sources/AgentFeature/AgentOverviewTile.swift`, `Sources/AraNotch/Pages.swift` (`DeviceOverviewTile`, `ToolsOverviewTile`), `Sources/AraNotch/AppDelegate.swift`, `Sources/SystemEventsFeature/BluetoothMonitor.swift`, `Sources/SystemEventsFeature/SystemEventsController.swift`, `Sources/MediaFeature/MediaController.swift`

**Interfaces:**
- Produces:
  - `SystemEventsController.makeBluetoothRow() -> AnyView` — tên các thiết bị Bluetooth đang nối, một dòng; trống thì không vẽ gì.
  - `MediaController.makeOutputRow() -> AnyView` — đầu ra âm thanh đang dùng.
  - `DeviceOverviewTile(battery: AnyView, volume: AnyView, output: AnyView, bluetooth: AnyView)`.
  - `ToolsOverviewTile(quickTools: [NotchTool], allTools: [NotchTool])`.

| Ô | small | wide | large |
|---|---|---|---|
| Agent | Một chấm gộp và một dòng ("1 waiting for you" / "1 chờ bạn", "2 running" / "2 đang chạy") | Hai phiên (như nay) | Năm phiên và vạch giới hạn Claude, Codex (dùng lại `usageStrip` của trang Agent) |
| Máy | Pin phần trăm và mức âm lượng | Như nay | Pin, âm lượng, đầu ra âm thanh, thiết bị Bluetooth đang nối |
| Công cụ | Bốn nút nhanh, 2 × 2 | Bốn nút một hàng (như nay) | Tám công cụ, hai hàng |

- [ ] **Bước 1: Bluetooth.** `BluetoothMonitor` đã theo dõi nối/ngắt (`disconnectTokens` theo thiết bị); thêm danh sách tên thiết bị đang nối, cập nhật ở hai sự kiện đó, chỉ sau khi quyền Bluetooth đã có (không gây hộp thoại mới). Nếu không lấy được mà không cần quyền mới, bỏ `makeBluetoothRow` và ghi giới hạn ở Việc 11.
- [ ] **Bước 2: Ba dạng của ba ô.** Chuỗi mới cho dòng gộp của Agent ở hai tệp chuỗi, dùng dạng số ít/số nhiều như các chuỗi agent hiện có.
- [ ] **Bước 3: Chụp ba cỡ** hai thứ tiếng: pin và thiết bị Bluetooth thật của máy; agent bằng `--agent-events-file` và `--claude-usage-file` với tệp thử (năm phiên, có một phiên chờ).
- [ ] **Bước 4: Commit** — `feat: the agents, device and tools tiles come in small, wide and large`.

---

### Việc 8: Chế độ sửa — bỏ, đổi cỡ, thêm

**Files:**
- Create: `Sources/AraNotch/OverviewEditor.swift`
- Modify: `Sources/NotchShell/NotchPage.swift`, `Sources/NotchShell/NotchRootView.swift`, `Sources/NotchShell/NotchController.swift`, `Sources/AraNotch/Pages.swift`, `Sources/AraNotch/AppDelegate.swift`, `Resources/*/Localizable.strings`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`. Target AraNotch không có test, nên mọi phép tính của chế độ sửa nằm trong `OverviewGrid`; `OverviewEditor` chỉ giữ trạng thái và gọi chúng.

**Interfaces:**
- Consumes: Việc 2 (`resized`, `adding`, `removing`), Việc 3 (`ShellSettings.overviewArrangement`).
- Produces:
  - `NotchPage.headerAccessory: (@MainActor () -> AnyView)?` — `NotchRootView` vẽ nó trên hàng tab ngay trước nút ghim, chỉ khi trang đó đang hiện.
  - `NotchController.selectedPagePublisher: AnyPublisher<String?, Never>`.
  - `@MainActor final class OverviewEditor: ObservableObject` với `@Published private(set) var isEditing: Bool`, `@Published var isChoosingTile: Bool`, `@Published private(set) var refusedWidget: OverviewWidget?` (ô vừa bị từ chối đổi cỡ, tự xoá sau 1,2 giây), `func begin()`, `func end()`, `func remove(_:)`, `func resize(_:)`, `func add(_:)`, `var hiddenWidgets: [OverviewWidget]`. Khởi tạo với `ShellSettings`, `keepOpen: (Bool) -> Void`.

  - `OverviewGrid.showsAddTile(_ items: [OverviewItem]) -> Bool` — còn ít nhất một tính năng chưa có và `adding` làm được với nó; `OverviewGrid.editingRows(_ items: [OverviewItem]) -> Int` — số hàng khi sửa, tính cả ô "+" như một ô nhỏ ở cuối khi `showsAddTile`.

- [ ] **Bước 0: Test hỏng cho hai hàm trên**

```swift
@Test func theAddTileShowsWhileATileIsMissingAndThereIsRoom() {
    #expect(OverviewGrid.showsAddTile(OverviewGrid.defaultArrangement)) // tools is missing
    let everyTile = OverviewWidget.allCases.map { item($0, .small) }
    #expect(!OverviewGrid.showsAddTile(everyTile))
}

@Test func theAddTileCanTakeARowOfItsOwn() {
    // The default fills two rows; the add tile needs a third while editing.
    #expect(OverviewGrid.editingRows(OverviewGrid.defaultArrangement) == 3)
    #expect(OverviewGrid.editingRows([item(.media, .wide)]) == 2)
}
```

Chạy `Scripts/test.sh --filter OverviewLayoutTests` (hỏng), viết hai hàm, chạy lại (qua).

- [ ] **Bước 1: `headerAccessory` và `selectedPagePublisher`** trong NotchShell; trang không đặt nó thì hàng tab như cũ.
- [ ] **Bước 2: `OverviewEditor`.** `begin()` đặt `isEditing` và gọi `keepOpen(true)` (nối tới `setKeepsOpen(_:forPage: "overview")`); `end()` ngược lại và đóng danh sách chip. Đăng ký `isOpenPublisher` (đóng → `end()`) và `selectedPagePublisher` (khác `"overview"` → `end()`). `resize` gọi `OverviewGrid.resized`; `nil` thì đặt `refusedWidget`.
- [ ] **Bước 3: Nút trên hàng tab.** Bút chì (`AraIcon.edit` hoặc icon bút có sẵn trong `AraIcon`; nếu chưa có thì thêm `pencil`) với chú giải "Edit layout" / "Sửa bố cục"; khi sửa thì là "Done" / "Xong", kiểu `isSelected`.
- [ ] **Bước 4: Lớp phủ trong `OverviewPage`.** Khi sửa: nội dung ô `.allowsHitTesting(false)`; rung nhẹ (xoay ±1°, lệch pha theo ô; tắt khi Giảm chuyển động); nút − góc trên trái; nút cỡ góc dưới phải; ô bị từ chối lắc và hiện "No room" / "Hết chỗ". Ô "+ Add tile" / "+ Thêm ô" ở cuối khi `OverviewGrid.showsAddTile`; khi sửa, `onRowsChange` nhận `OverviewGrid.editingRows`. Bấm thì hiện chip các ô đang tắt, màu trang của chúng (`AraChipRow`).
- [ ] **Bước 5: Menu chuột phải** "Edit layout" / "Sửa bố cục" trên mọi ô, gọi `begin()`. Trang trống: `AraEmptyState` có nút "+ Add tile" gọi `begin()` và mở danh sách chip.
- [ ] **Bước 6: Build, thử tay** trên notch thật với `--overview-arrangement` (khi có tham số này, mọi sửa đổi chỉ ở trong bộ nhớ, không ghi cài đặt): vào và ra (Xong, bấm ra ngoài, sang trang khác); bỏ ô; đổi cỡ tới "Hết chỗ"; thêm ô; notch không tự đóng khi con trỏ rời đi lúc đang sửa. Một lần không có tham số để xác nhận bố cục còn sau khi mở lại app: ghi lại `defaults read` khoá `shell.overviewArrangement` trước, và trả lại đúng giá trị đó sau.
- [ ] **Bước 7: Commit** — `feat: the overview is edited on the notch: remove, resize and add tiles`.

---

### Việc 9: Kéo đổi chỗ

**Files:**
- Modify: `Sources/AraNotch/OverviewEditor.swift`, `Sources/AraNotch/Pages.swift`, `Sources/NotchCore/OverviewLayout.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Consumes: `OverviewGrid.index(atColumn:row:in:)`, `moved`.
- Produces:
  - `OverviewGrid.dropIndex(column: Int, row: Int, dragging widget: OverviewWidget, in items: [OverviewItem]) -> Int` — vị trí sẽ thả: chỉ số của ô đang nằm dưới con trỏ, tính trên bố cục không có ô đang kéo; ô trống thì cuối danh sách đó.
  - `public struct OverviewDrag: Equatable, Sendable` (NotchCore): `init(widget: OverviewWidget, from items: [OverviewItem])`, `var preview: [OverviewItem]`, `mutating func move(toColumn: Int, row: Int)` (luôn tính `dropIndex` trên bố cục lúc bắt đầu kéo, rồi `preview = OverviewGrid.moved(start, widget:, to:)`), `func drop(inside: Bool) -> [OverviewItem]?` (bố cục cần lưu; `nil` khi thả ngoài lưới hoặc không có gì đổi).
  - `OverviewEditor.drag: OverviewDrag?`; `OverviewPage` vẽ `editor.drag?.preview ?? settings.overviewArrangement`. Thả: `if let saved = drag.drop(inside:) { settings.overviewArrangement = saved }` — chỗ ghi duy nhất. Notch đóng hoặc `end()` giữa chừng: `drag = nil`.

- [ ] **Bước 1: Test hỏng**

```swift
@Test func aDragLandsWhereTheTileUnderThePointerIs() {
    let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)]
    #expect(OverviewGrid.dropIndex(column: 3, row: 0, dragging: .timer, in: items) == 1)
    #expect(OverviewGrid.dropIndex(column: 0, row: 0, dragging: .agents, in: items) == 0)
    #expect(OverviewGrid.dropIndex(column: 3, row: 1, dragging: .media, in: items) == 3)
}

@Test func aDragShowsTheNewOrderAndIsSavedOnlyWhenDroppedOnTheGrid() {
    let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)]
    var drag = OverviewDrag(widget: .timer, from: items)
    drag.move(toColumn: 3, row: 0)
    drag.move(toColumn: 0, row: 0)
    #expect(drag.preview.map(\.widget) == [.timer, .media, .calendar, .agents])
    #expect(drag.drop(inside: true)?.map(\.widget) == [.timer, .media, .calendar, .agents])
    #expect(drag.drop(inside: false) == nil)
}

@Test func aDragBackToWhereItStartedSavesNothing() {
    let items = [item(.media, .wide), item(.timer, .small)]
    var drag = OverviewDrag(widget: .timer, from: items)
    drag.move(toColumn: 0, row: 0)
    drag.move(toColumn: 3, row: 1)
    #expect(drag.drop(inside: true) == nil)
}
```

- [ ] **Bước 2: Chạy, thấy hỏng; viết `dropIndex` và `OverviewDrag`; chạy, thấy qua.**
- [ ] **Bước 3: Kéo trong `OverviewPage`.** `DragGesture(minimumDistance: 4)` trên ô khi đang sửa; ô kéo đi theo con trỏ ở trên cùng; ô lưới dưới con trỏ tính từ toạ độ trang; khi ô lưới đổi gọi `drag.move`, các ô khác dồn lại có hoạt ảnh và `onRowsChange` báo số hàng mới. `inside` là điểm thả nằm trong khung trang. Xoá hover khi bắt đầu kéo như thẻ clip đã làm với `AraHoverLift` (HISTORY: thẻ còn nhấc lên sau khi bị kéo đi).
- [ ] **Bước 4: Thử tay** kéo qua lại, kéo làm thêm và bớt hàng, thả ra ngoài notch (ô về chỗ cũ), để notch đóng giữa lúc kéo; mở lại thì bố cục là bố cục trước khi kéo.
- [ ] **Bước 5: Commit** — `feat: tiles are dragged to a new place on the overview`.

---

### Việc 10: Cài đặt

**Files:**
- Modify: `Sources/AraNotch/SettingsView.swift`, `Sources/AraNotch/AppDelegate.swift` (`searchPrefixes`), `Resources/*/Localizable.strings`

- [ ] **Bước 1:** Ở chỗ hàng chip `settings.overview` cũ (đã bỏ ở Việc 4): một dòng `settings.overview.hint` ("Arrange the tiles on the notch: press the pencil on the Overview page." / "Sắp xếp các ô ngay trên notch: bấm nút bút chì trên trang Tổng quan.") và nút `settings.overview.reset` ("Reset layout" / "Đặt lại bố cục") gán `settings.overviewArrangement = OverviewGrid.defaultArrangement`. Bỏ các chuỗi `settings.overview.<widget>` không còn dùng.
- [ ] **Bước 2:** Tìm "overview", "tổng quan", "bố cục" trong ô tìm của Cài đặt vẫn ra mục này (giữ `settings.overview` trong `searchPrefixes`).
- [ ] **Bước 3: Build, chụp** mục Trang notch hai thứ tiếng; bấm Đặt lại bố cục và xem notch.
- [ ] **Bước 4: Commit** — `feat: settings point to the notch for the overview layout and can reset it`.

---

### Việc 11: Sổ sách, đồ thị và thử toàn bộ

**Files:**
- Modify: `docs/project/FEATURES.md`, `docs/project/HISTORY.md`, `graphify-out/` (qua lệnh)

- [ ] **Bước 1:** `Scripts/test.sh` toàn bộ; Expected: mọi test qua.
- [ ] **Bước 2:** Thử tay toàn bộ danh sách Kiểm thử của spec trên bản cài ở `/Applications`, với dữ liệu thật; ghi lại cái đã thử và cái chưa.
- [ ] **Bước 3: FEATURES.md.** Thêm một hàng "Tổng quan kiểu widget" (mô tả, module, spec `2026-10-16-overview-widgets-design`, kiểm chứng: số test, ảnh chụp, thử tay); sửa hàng vòng R và các dòng giới hạn 293, 300 cho đúng với hiện nay; thêm giới hạn mới (không để trống ô ở giữa, một tính năng một ô, Bluetooth nếu bỏ ở Việc 7).
- [ ] **Bước 4: HISTORY.md.** Một mục vòng mới: lời chủ dự án, các lựa chọn (mục tiêu, chỗ sửa, lưới A, notch dài thêm hàng, cách làm 1, mặc định 2 hàng), các quyết định tự suy ra trong lúc làm, sơ suất khi thử nếu có.
- [ ] **Bước 5:** `graphify update .`
- [ ] **Bước 6: Commit** — `docs: the overview arranged like widgets, in the feature ledger and the history`.
