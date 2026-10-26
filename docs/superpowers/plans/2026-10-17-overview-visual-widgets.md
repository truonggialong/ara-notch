# Widget hình ảnh cho Tổng quan, đợt 1 — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm 8 kiểu widget hình ảnh (Ảnh bìa, Đồng hồ ngày, Đĩa thời gian, Chồng thẻ, Bảng màu, Vòng giới hạn, Vòng thiết bị, Nút lớn theo từng công cụ) vào trang Tổng quan, mỗi kiểu là một ô riêng với cỡ cho phép của nó.

**Architecture:** Mỗi kiểu mới là một trường hợp của `OverviewWidget` (NotchCore) biết tính năng và các cỡ cho phép; các phép tính lưới tôn trọng cỡ cho phép. Phần logic thuần nằm ở Core (góc trên vòng 24 giờ, đọc pin Bluetooth, chọn màu cho bảng màu), có test. Mỗi tính năng tự vẽ ô của mình qua một khung chung `AraVisualTile` và vòng `AraRing` trong NotchShell/Design; AppDelegate đưa các ô vào trang.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 15, Swift Testing (`Scripts/test.sh`).

**Spec:** `docs/superpowers/specs/2026-10-17-overview-visual-widgets-design.md`

## Global Constraints

- Kiểu mới và giá trị lưu: `albumArt`, `dayClock`, `timerDisc`, `clipStack`, `colorPalette`, `usageRings`, `deviceRings`, `tool.capture`, `tool.scroll`, `tool.text`, `tool.color`, `tool.translate`, `tool.panel`, `tool.library`, `tool.note`.
- Cỡ cho phép: `albumArt`, `dayClock`, `timerDisc`, `clipStack`, `usageRings`: nhỏ, lớn; `colorPalette`, `deviceRings`: rộng, lớn; `tool.*`: nhỏ; 7 ô cũ: nhỏ, rộng, lớn.
- Mỗi kiểu nhiều nhất một lần trong bố cục; định dạng lưu `"<kiểu>:<cỡ>"` không đổi.
- Ô hình ảnh không có dòng tên; tên hiện khi rê chuột và qua VoiceOver; màu theo tính năng (Nhạc `.sky`, Lịch `.mustard`, Hẹn giờ `.mint`, Clipboard `.peach`, Agent `.lilac`, Máy `.sage`, Công cụ: màu của từng công cụ).
- Không cần quyền hệ thống mới. Pin Bluetooth đọc bằng `/usr/sbin/system_profiler SPBluetoothDataType -json`, quá 5 giây thì bỏ, chạy lại mỗi 2 phút khi Tổng quan đang hiện và có ô Vòng thiết bị.
- Chữ mới có ở cả `Resources/en.lproj` và `Resources/vi.lproj`.
- Không chép số sê-ri hay địa chỉ thiết bị thật vào test hay tài liệu.
- Build `@State` không dùng được trên máy này; giữ trạng thái view bằng `@StateObject`.
- Thử bằng bản dựng từ `build/` với `--data-dir` riêng, `--overview-arrangement`, `--agent-events-file <tệp rỗng>`; chụp bằng `screencapture -l`; không đổi cài đặt thật mà không trả lại.
- Tiêu đề việc giữ dạng `### Task N:`.

## Review Focus

1. **`system_profiler` chậm hay treo, hoặc trả JSON lạ:** ô giữ kết quả cũ, không đứng app. → Task 3 có test cho JSON hỏng; Task 8 chạy lệnh trên hàng đợi nền có giới hạn 5 giây.
2. **Ngày có 23 hay 25 giờ (đổi giờ mùa hè) và sự kiện qua nửa đêm:** cung vẫn đúng chỗ. → Task 2 test với múi giờ `America/New_York` ngày 2026-11-01.
3. **Màu đã chép nằm trong bảng khoá:** không hiện trong Bảng màu. → Task 4 test bỏ mục mã hoá.
4. **Bố cục cũ có kiểu mới ở cỡ không cho phép** (sửa tay, hay bản sau đổi cỡ): đọc ra cỡ nhỏ nhất cho phép, không mất ô. → Task 1 test.
5. **Ô hình ảnh trong chế độ sửa:** bấm không chạy hành động (không dán, không chạy công cụ). → Trang đã tắt nhận bấm của nội dung ô (0.25.0); Task 9 chụp chế độ sửa và kiểm `AraVisualTile` không tự thêm cử chỉ ngoài nội dung.

---

## Bản đồ tệp

| Tệp | Task | Trách nhiệm |
|---|---|---|
| `Sources/NotchCore/OverviewLayout.swift`, `Tests/NotchCoreTests/OverviewLayoutTests.swift` | 1 | Kiểu, tính năng, cỡ cho phép |
| `Sources/CalendarCore/DayRing.swift` (mới), `Tests/CalendarCoreTests/DayRingTests.swift` (mới) | 2 | Góc và cung trên vòng 24 giờ |
| `Sources/SystemEventsCore/BluetoothBatteries.swift` (mới), `Tests/SystemEventsCoreTests/BluetoothBatteriesTests.swift` (mới) | 3 | Đọc pin từ JSON |
| `Sources/ClipboardCore/ColorPalette.swift` (mới), `Tests/ClipboardCoreTests/ColorPaletteTests.swift` (mới) | 4 | Chọn màu cho Bảng màu |
| `Sources/NotchShell/Design/AraVisualTile.swift` (mới) | 5 | `AraVisualTile`, `AraRing` |
| Tệp ô của từng tính năng (mới) | 6, 7, 8 | Vẽ từng kiểu |
| `Sources/AraNotch/OverviewPage.swift`, `AppDelegate.swift`, `Resources/*/Localizable.strings` | 6–9 | Đưa ô vào trang, chip, chữ |
| `docs/project/FEATURES.md`, `HISTORY.md`, `Resources/Info.plist`, `Sources/ClipboardMCP/ClipboardMCPServer.swift` | 10 | Sổ sách, phiên bản 0.26.0 |

---

### Task 1: Kiểu ô mới, tính năng và cỡ cho phép

**Files:**
- Modify: `Sources/NotchCore/OverviewLayout.swift`
- Test: `Tests/NotchCoreTests/OverviewLayoutTests.swift`

**Interfaces:**
- Produces:
  - `OverviewWidget` thêm `albumArt, dayClock, timerDisc, clipStack, colorPalette, usageRings, deviceRings` và `toolCapture = "tool.capture"`, `toolScroll = "tool.scroll"`, `toolText = "tool.text"`, `toolColor = "tool.color"`, `toolTranslate = "tool.translate"`, `toolPanel = "tool.panel"`, `toolLibrary = "tool.library"`, `toolNote = "tool.note"`.
  - `public enum OverviewFeature: String, CaseIterable, Sendable { case media, calendar, timer, clipboard, agents, device, tools }` (thứ tự là thứ tự chip).
  - `OverviewWidget.feature: OverviewFeature`, `OverviewWidget.sizes: [OverviewTileSize]` (nhỏ tới lớn), `OverviewWidget.isVisual: Bool` (true cho 15 kiểu mới), `OverviewWidget.toolID: String?` (`"capture"`… cho `tool.*`, nil cho kiểu khác).

- [ ] **Step 1: Test hỏng**

```swift
@Test func eachKindHasItsFeatureAndSizes() {
    #expect(OverviewWidget.albumArt.feature == .media)
    #expect(OverviewWidget.colorPalette.sizes == [.wide, .large])
    #expect(OverviewWidget.toolTranslate.sizes == [.small])
    #expect(OverviewWidget.toolTranslate.rawValue == "tool.translate")
    #expect(OverviewWidget.toolTranslate.toolID == "translate")
    #expect(OverviewWidget.media.sizes == [.small, .wide, .large])
    #expect(OverviewWidget.allCases.filter(\.isVisual).count == 15)
}

@Test func resizingCyclesOnlyThroughTheKindsSizes() {
    let items = [item(.albumArt, .small)]
    #expect(OverviewGrid.resized(items, widget: .albumArt)?.first?.size == .large)
    #expect(OverviewGrid.resized([item(.albumArt, .large)], widget: .albumArt)?.first?.size == .small)
    #expect(OverviewGrid.resized([item(.toolNote, .small)], widget: .toolNote) == nil)
}

@Test func aKindIsAddedAtItsSmallestSize() {
    #expect(OverviewGrid.adding([], widget: .colorPalette) == [item(.colorPalette, .wide)])
    // Only one small cell left (15 of 16 taken): a wide-only kind cannot come in.
    let fifteen = [item(.media, .large), item(.calendar, .large), item(.timer, .large),
                   item(.agents, .wide), item(.device, .small)]
    #expect(OverviewGrid.adding(fifteen, widget: .colorPalette) == nil)
    #expect(OverviewGrid.adding(fifteen, widget: .toolNote) != nil)
}

@Test func aSavedSizeTheKindDoesNotAllowBecomesItsSmallest() {
    #expect(OverviewGrid.arrangement(from: ["albumArt:wide", "deviceRings:small"]) ==
            [item(.albumArt, .small), item(.deviceRings, .wide)])
}
```

- [ ] **Step 2:** `Scripts/test.sh --filter OverviewLayoutTests` — Expected: lỗi biên dịch, chưa có `albumArt`.
- [ ] **Step 3:** Viết mã. `resized`: đi vòng trong `widget.sizes` (sau cỡ lớn nhất là cỡ nhỏ nhất) thay cho `size.next`. `adding`: `widget.sizes.first!`. `arrangement(from:)`: cỡ không có trong `widget.sizes` thì thay bằng `widget.sizes.first!`. Các test cũ phải còn qua (7 ô cũ có ba cỡ nên `resized` cũ không đổi).
- [ ] **Step 4:** `Scripts/test.sh` — Expected: tất cả qua.
- [ ] **Step 5: Commit** — `feat: the overview knows the visual widget kinds, their features and sizes`.

---

### Task 2: Vòng 24 giờ của Đồng hồ ngày

**Files:**
- Create: `Sources/CalendarCore/DayRing.swift`
- Test: `Tests/CalendarCoreTests/DayRingTests.swift`

**Interfaces:**
- Produces: `public enum DayRing` với
  - `static func fraction(of date: Date, on day: Date, calendar: Calendar) -> Double` — phần của ngày đã trôi qua, 0 ở 0 giờ, 1 ở 0 giờ hôm sau, kẹp vào 0…1; ngày dài theo `calendar` (23 hay 25 giờ khi đổi giờ).
  - `static func arcs(for events: [AgendaEvent], on day: Date, calendar: Calendar) -> [ClosedRange<Double>]` — mỗi sự kiện có giờ một cung theo phần của ngày, cắt ở 0 và 1; bỏ sự kiện cả ngày và sự kiện không chạm ngày đó; theo giờ bắt đầu.

- [ ] **Step 1: Test hỏng** (dùng lại `at(_:_:day:)` và `event(...)` như `AgendaTests`, chép vào tệp test này)

```swift
@Test func midnightSixNoonAndSixAreQuarters() {
    let day = at(0)
    #expect(DayRing.fraction(of: at(0), on: day, calendar: calendar) == 0)
    #expect(DayRing.fraction(of: at(6), on: day, calendar: calendar) == 0.25)
    #expect(DayRing.fraction(of: at(12), on: day, calendar: calendar) == 0.5)
    #expect(DayRing.fraction(of: at(18), on: day, calendar: calendar) == 0.75)
}

@Test func anEventOverMidnightIsCutAtTheEdgesOfTheDay() {
    let day = at(0)
    let late = event("a", "Đêm", at(22, day: -1), at(2))
    let night = event("b", "Khuya", at(23), at(1, day: 1))
    #expect(DayRing.arcs(for: [night, late], on: day, calendar: calendar) == [0...(2.0 / 24), (23.0 / 24)...1])
}

@Test func allDayEventsAndOtherDaysHaveNoArc() {
    let day = at(0)
    #expect(DayRing.arcs(for: [event("c", "Lễ", at(0), at(0, day: 1), allDay: true),
                               event("d", "Mai", at(9, day: 1), at(10, day: 1))], on: day, calendar: calendar).isEmpty)
}

@Test func aDayWithAnExtraHourStillEndsAtOne() {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))! // 25 hours
    let noon = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    #expect(abs(DayRing.fraction(of: noon, on: day, calendar: newYork) - 13.0 / 25) < 0.0001)
}
```

- [ ] **Step 2:** `Scripts/test.sh --filter DayRingTests` — Expected: lỗi biên dịch.
- [ ] **Step 3:** Viết `DayRing` (đầu ngày `calendar.startOfDay(for: day)`, cuối ngày là đầu ngày hôm sau theo `calendar.date(byAdding: .day, value: 1, ...)`).
- [ ] **Step 4:** chạy lại, Expected: qua.
- [ ] **Step 5: Commit** — `feat: today's events as arcs on a 24-hour ring`.

---

### Task 3: Đọc pin thiết bị Bluetooth

**Files:**
- Create: `Sources/SystemEventsCore/BluetoothBatteries.swift`
- Test: `Tests/SystemEventsCoreTests/BluetoothBatteriesTests.swift`

**Interfaces:**
- Produces:
  - `public struct BluetoothBattery: Equatable, Sendable { public let name: String; public let kind: BluetoothDeviceKind; public let percent: Int? }`
  - `public enum BluetoothBatteries { static func parse(_ json: Data) -> [BluetoothBattery]? }` — nil khi JSON không đọc được; chỉ thiết bị trong `device_connected`; theo thứ tự trong JSON.

Định dạng (đã xem trên máy chủ dự án): `{"SPBluetoothDataType":[{"device_connected":[{"<tên>":{...}}], "device_not_connected":[...]}]}`. Khoá pin: `device_batteryLevelMain`, `device_batteryLevelLeft`, `device_batteryLevelRight`, `device_batteryLevelCase` (chuỗi như `"71%"`). Khoá loại: `device_minorType` (`"Headphones"`, `"Mouse"`, `"Keyboard"`, `"Trackpad"`, `"Gamepad"`, `"Hi-Fi Stereo"`/`"Speaker"`, `"Phone"`); không khớp thì `BluetoothDeviceKind.guess(fromName:)`.

- [ ] **Step 1: Test hỏng** với một JSON mẫu tự viết (tên giả, không số sê-ri, không địa chỉ):

```swift
private let sample = Data(#"""
{"SPBluetoothDataType":[{"device_connected":[
  {"Tai nghe Lan":{"device_minorType":"Headphones","device_batteryLevelLeft":"80%","device_batteryLevelRight":"65%","device_batteryLevelCase":"40%"}},
  {"Chuột":{"device_minorType":"Mouse","device_batteryLevelMain":"52%"}},
  {"Loa":{"device_minorType":"Hi-Fi Stereo"}}],
 "device_not_connected":[{"Bàn phím cũ":{"device_minorType":"Keyboard","device_batteryLevelMain":"90%"}}]}]}
"""#.utf8)

@Test func connectedDevicesWithTheirLowestBudAndKind() {
    #expect(BluetoothBatteries.parse(sample) == [
        BluetoothBattery(name: "Tai nghe Lan", kind: .headphones, percent: 65),
        BluetoothBattery(name: "Chuột", kind: .mouse, percent: 52),
        BluetoothBattery(name: "Loa", kind: .speaker, percent: nil),
    ])
}

@Test func nothingConnectedAndBrokenOutput() {
    #expect(BluetoothBatteries.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)) == [])
    #expect(BluetoothBatteries.parse(Data("not json".utf8)) == nil)
}
```

- [ ] **Step 2:** `Scripts/test.sh --filter BluetoothBatteriesTests` — Expected: lỗi biên dịch.
- [ ] **Step 3:** Viết bằng `JSONSerialization`; phần trăm đọc phần số trước `%`.
- [ ] **Step 4:** chạy lại, Expected: qua.
- [ ] **Step 5: Commit** — `feat: battery levels of connected Bluetooth devices read from the system report`.

---

### Task 4: Màu cho Bảng màu

**Files:**
- Create: `Sources/ClipboardCore/ColorPalette.swift`
- Test: `Tests/ClipboardCoreTests/ColorPaletteTests.swift`

**Interfaces:**
- Produces: `public enum ColorPalette { static func recent(_ items: [ClipItem], limit: Int) -> [ClipItem] }` — theo thứ tự đầu vào (mới nhất trước), chỉ `kind == .color`, bỏ `isEncrypted`, màu trùng (cùng `ClipColor.parse(text, allowingBareHex: true)?.formatted(as: .hex)`) chỉ giữ lần đầu, nhiều nhất `limit`.

- [ ] **Step 1: Test hỏng** (dùng `makeItem` của `TestSupport.swift`; mục mã hoá dựng bằng `ClipItem(..., isEncrypted: true, ...)`)

```swift
@Test func newestColorsOnceEachWithoutLockedOnes() {
    var locked = makeItem(id: 9, kind: .color, text: "#00FF00")
    locked = ClipItem(id: 9, kind: .color, text: "#00FF00", blobName: nil, isEncrypted: true,
                      source: locked.source, createdAt: locked.createdAt, lastUsedAt: locked.lastUsedAt, byteSize: 7)
    let items = [makeItem(id: 1, kind: .color, text: "#4A90D9"), makeItem(id: 2, kind: .text, text: "hello"),
                 locked, makeItem(id: 3, kind: .color, text: "#4a90d9"), makeItem(id: 4, kind: .color, text: "rgb(255, 0, 0)"),
                 makeItem(id: 5, kind: .color, text: "#123456")]
    #expect(ColorPalette.recent(items, limit: 5).map(\.id) == [1, 4, 5])
    #expect(ColorPalette.recent(items, limit: 2).map(\.id) == [1, 4])
}
```

- [ ] **Step 2:** `Scripts/test.sh --filter ColorPaletteTests` — Expected: lỗi biên dịch.
- [ ] **Step 3:** Viết. **Step 4:** chạy lại, qua. **Step 5: Commit** — `feat: the newest distinct colours for a palette, never locked ones`.

---

### Task 5: Khung chung cho ô hình ảnh

**Files:**
- Create: `Sources/NotchShell/Design/AraVisualTile.swift`

**Interfaces:**
- Produces:
  - `public struct AraVisualTile<Content: View>: View` — `init(name: String, hue: AraHue?, action: (() -> Void)?, @ViewBuilder content: @escaping () -> Content)`: thẻ như `AraOverviewTile` (`.araCard(radius: 14)`, `.araHue(hue)`), không dòng tên, nội dung lấp kín với lề 8 điểm × `araScale`; có `action` thì cả ô là một nút (`AraPressStyle(depth: 0.97)`); tên là chú giải khi rê chuột (`araTooltip`) và `accessibilityLabel`.
  - `public struct AraRing: View` — `init(fraction: Double, color: Color, lineWidth: CGFloat, track: Color = AraPalette.track)`: vòng nền và cung từ 12 giờ theo chiều kim đồng hồ, đầu tròn; `fraction` kẹp 0…1.
  - `public struct AraArc: Shape` — `init(from: Double, to: Double)`: một cung trên vòng theo phần (0 là 12 giờ), dùng cho Đồng hồ ngày và cửa sổ 7 ngày.

- [ ] **Step 1:** Viết ba kiểu trên. Trạng thái hover dùng `@StateObject AraHover`.
- [ ] **Step 2:** `swift build --product AraNotch` — Expected: không lỗi.
- [ ] **Step 3: Commit** — `feat: a frame and rings for the overview's visual tiles`.

---

### Task 6: Ảnh bìa, Đĩa thời gian, Đồng hồ ngày

**Files:**
- Create: `Sources/MediaFeature/AlbumArtTile.swift`, `Sources/TimerFeature/TimerDiscTile.swift`, `Sources/CalendarFeature/DayClockTile.swift`
- Modify: `MediaController.swift`, `TimerController.swift`, `CalendarController.swift` (mỗi tệp một hàm `public func make<Kind>Tile() -> AnyView`), `Sources/AraNotch/AppDelegate.swift` (thêm vào `overviewTiles.tiles`), `Resources/*/Localizable.strings` (`overview.tile.albumArt` "Album art" / "Ảnh bìa", `overview.tile.dayClock` "Day clock" / "Đồng hồ ngày", `overview.tile.timerDisc` "Time disc" / "Đĩa thời gian")

**Interfaces:**
- Consumes: `AraVisualTile`, `AraRing`, `AraArc` (Task 5); `DayRing` (Task 2); `\.araTileSize`.
- Produces: `MediaController.makeAlbumArtTile()`, `TimerController.makeTimerDiscTile()`, `CalendarController.makeDayClockTile()`.

Nội dung và cú bấm theo bảng "Tám kiểu" của spec, không thêm chữ ngoài những gì spec ghi (Đĩa thời gian cỡ lớn: số phút còn lại). Đĩa thời gian vẽ phần còn lại `1 - entry.timer.progress(at: now)` bằng `Path` hình quạt, cập nhật theo `model.now` sẵn có. Đồng hồ ngày vẽ `DayRing.arcs(for: model.agenda.today, on: model.now, calendar: .current)` bằng `AraArc`, kim ở `DayRing.fraction(of: model.now, ...)`; cỡ lớn thêm chấm cho lời nhắc có `due` và `dueHasTime` hôm nay, và bốn vạch 0, 6, 12, 18 giờ.

- [ ] **Step 1:** Viết ba ô và nối vào `AppDelegate`.
- [ ] **Step 2:** `Scripts/build-app.sh debug` — không lỗi.
- [ ] **Step 3: Chụp** mỗi kiểu ở mỗi cỡ cho phép: `--overview-arrangement "albumArt:small,timerDisc:small,dayClock:small,albumArt…"` (mỗi kiểu một lần mỗi lượt chụp), với `--simulate-now-playing` hoặc bài đang phát thật (không bấm), `--timer 600` và không có bộ đếm, `--simulate-agenda`. Không bấm nút phát.
- [ ] **Step 4: Commit** — `feat: album art, time disc and day clock tiles`.

---

### Task 7: Chồng thẻ, Bảng màu, Vòng giới hạn

**Files:**
- Create: `Sources/ClipboardFeature/ClipStackTile.swift`, `Sources/ClipboardFeature/ColorPaletteTile.swift`, `Sources/AgentFeature/UsageRingsTile.swift`
- Modify: `ClipboardController.swift`, `AgentController.swift`, `AppDelegate.swift`, `Localizable.strings` (`overview.tile.clipStack` "Card stack" / "Chồng thẻ", `overview.tile.colorPalette` "Colour palette" / "Bảng màu", `overview.tile.usageRings` "Limit rings" / "Vòng giới hạn")

**Interfaces:**
- Consumes: Task 4 `ColorPalette.recent`, Task 5.
- Produces: `ClipboardController.makeClipStackTile()`, `ClipboardController.makeColorPaletteTile()`, `AgentController.makeUsageRingsTile()`.

Chồng thẻ: ba mục mới nhất `!isEncrypted` của `model.items`; bấm gọi `model.onPaste?(item)` với mục trên cùng; ảnh thu nhỏ qua `model.thumbnail?(item)`. Bảng màu: `ColorPalette.recent(model.items, limit: size == .large ? 10 : 5)`; mỗi chấm là một nút gọi `model.onCopyColor?(item, .hex)`; chưa có màu thì 5 vòng nét đứt; bản thân ô không có `action` (các chấm là nút). Vòng giới hạn: `model.claudeUsage?.fiveHour?.current(at:)` vòng ngoài, Codex vòng trong, số phần trăm Claude ở giữa; cỡ lớn thêm `AraArc` mỏng cho `sevenDay`; rê chuột hiện giờ đặt lại như `UsageMeter`; bấm `notch.selectPage(id: "agents")`.

- [ ] **Step 1:** Viết ba ô và nối vào `AppDelegate`.
- [ ] **Step 2:** `Scripts/build-app.sh debug` — không lỗi.
- [ ] **Step 3: Chụp** mỗi kiểu ở mỗi cỡ cho phép với `--data-dir <tạm> --seed-clipboard` (có màu mẫu), một lần thêm `--seed-boards --seed-vault <mật mã thử>`, và `--agent-events-file`/`--claude-usage-file` với tệp thử.
- [ ] **Step 4: Commit** — `feat: card stack, colour palette and limit ring tiles`.

---

### Task 8: Vòng thiết bị và Nút lớn

**Files:**
- Create: `Sources/SystemEventsFeature/BluetoothBatteryReader.swift`, `Sources/SystemEventsFeature/DeviceRingsTile.swift`, `Sources/AraNotch/BigToolTile.swift`
- Modify: `SystemEventsController.swift`, `AppDelegate.swift`, `Localizable.strings` (`overview.tile.deviceRings` "Device rings" / "Vòng thiết bị"; tên Nút lớn dùng `tools.<id>` sẵn có)

**Interfaces:**
- Consumes: Task 3 `BluetoothBatteries.parse`, Task 5, `BatteryModel` sẵn có, danh sách `tools: [NotchTool]` trong `AppDelegate`.
- Produces:
  - `@MainActor final class BluetoothBatteryReader: ObservableObject { @Published private(set) var devices: [BluetoothBattery]; func refreshIfStale() }` — chạy `/usr/sbin/system_profiler SPBluetoothDataType -json` bằng `Process` trên hàng đợi nền, hết 5 giây thì `terminate()` và giữ kết quả cũ; `refreshIfStale` không chạy lại nếu lần trước chưa quá 2 phút hay đang chạy. Callback của `Process` là `nonisolated` và chuyển về main (ghi chú kiểm thử: callback hệ thống gọi hàm `@MainActor` từ hàng đợi khác đã làm app chết hai lần).
  - `SystemEventsController.makeDeviceRingsTile() -> AnyView` — ô gọi `reader.refreshIfStale()` khi hiện và theo một `TimelineView(.periodic(from: .now, by: 120))`.
  - `BigToolTile(tool: NotchTool)`; `AppDelegate` thêm `.toolCapture: AnyView(BigToolTile(tool: tools[...]))`… cho 8 công cụ, ghép theo `OverviewWidget.toolID == tool.id`.

Vòng thiết bị: Mac trước (`BatteryModel.snapshot`; không có pin thì biểu tượng ổ điện, vòng đầy), rồi `reader.devices`; biểu tượng theo `BluetoothDeviceKind` (dùng biểu tượng mà thông báo Bluetooth sẵn có dùng); rộng tối đa 4, lớn tối đa 8 hai hàng; rê chuột: tên và phần trăm.

- [ ] **Step 1:** Viết đọc pin, hai ô và nối vào `AppDelegate`.
- [ ] **Step 2:** `Scripts/build-app.sh debug` — không lỗi; sau một lần chạy thử đọc `~/Library/Logs/DiagnosticReports/AraNotch-*.ips` mới (không được có).
- [ ] **Step 3: Chụp** Vòng thiết bị rộng và lớn (với thiết bị đang nối nếu có; không có thì chỉ Mac), Nút lớn của 2 công cụ. Không bấm Nút lớn trong bản thử.
- [ ] **Step 4: Commit** — `feat: device ring and big button tiles`.

---

### Task 9: Chip theo tính năng, nút cỡ, màu và biểu tượng theo tính năng

**Files:**
- Modify: `Sources/AraNotch/OverviewPage.swift`, `Sources/AraNotch/OverviewEditor.swift`

**Interfaces:**
- Consumes: Task 1 `feature`, `sizes`, `toolID`.

- [ ] **Step 1:** `OverviewWidget.icon` và `.hue` (phần mở rộng trong `OverviewPage.swift`) suy từ `feature`, riêng `tool.*` lấy biểu tượng và màu của công cụ (truyền từ danh sách công cụ qua `OverviewPage`, hoặc bảng cố định khớp `AppDelegate`); `title` giữ `overview.tile.<rawValue>`, riêng `tool.*` dùng `tools.<toolID>`.
- [ ] **Step 2:** `OverviewEditor.addableWidgets` xếp theo `OverviewFeature.allCases`, trong mỗi tính năng ô cũ trước (`!isVisual`), rồi kiểu mới theo thứ tự khai báo; `AddTileChooser` thêm một khoảng nhỏ giữa các tính năng.
- [ ] **Step 3:** Nút cỡ chỉ hiện khi `item.widget.sizes.count > 1`; biểu tượng phóng to/thu nhỏ theo cỡ kế tiếp trong `sizes`.
- [ ] **Step 4:** `Scripts/build-app.sh debug`; chụp chế độ sửa với bố cục trống (`--overview-arrangement none --edit-overview`), tiếng Việt và tiếng Anh: chip đủ 22 kiểu, xếp theo tính năng, xuống dòng không bị cắt; và một bố cục có kiểu mới để thấy Nút lớn không có nút cỡ.
- [ ] **Step 5: Commit** — `feat: the add choice groups tiles by feature; size buttons only where a tile has sizes`.

---

### Task 10: Sổ sách, phiên bản, toàn bộ

**Files:**
- Modify: `docs/project/FEATURES.md`, `docs/project/HISTORY.md`, `Resources/Info.plist` (chỉ sửa hai dòng phiên bản bằng `sed`, không dùng PlistBuddy để định dạng không đổi), `Sources/ClipboardMCP/ClipboardMCPServer.swift`

- [ ] **Step 1:** `Scripts/test.sh` — Expected: tất cả qua; ghi số test.
- [ ] **Step 2:** Phiên bản 0.26.0, bản dựng 51 (Info.plist và máy chủ MCP).
- [ ] **Step 3:** FEATURES.md: một hàng "Widget hình ảnh cho Tổng quan, đợt 1 (bản 0.26.0)" (mô tả 8 kiểu, module, spec `overview-visual-widgets-design`, kiểm chứng: số test mới, ảnh chụp, phần chưa thử tay); giới hạn mới: pin Bluetooth là con số hệ thống báo, cập nhật mỗi 2 phút; mỗi kiểu một lần; Bảng màu chỉ chép dạng HEX. HISTORY.md: một mục cho vòng này (lời chủ dự án, các lựa chọn, quyết định khi làm).
- [ ] **Step 4:** Commit — `docs: the overview's first visual widgets in the ledger and the history; version 0.26.0`; rồi `graphify update .` (khi không có phiên khác đang dùng graph.json).
