# Bộ widget mới cho Tổng quan — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Mục tiêu:** Thay 15 kiểu ô của Tổng quan bằng 7 widget thẻ tối, mỗi widget ba cỡ thật khác nhau (nhỏ đã đủ, rộng chi tiết hơn, lớn chi tiết hơn và nhiều mục hơn), màu nhấn tương phản và cam đỏ khi cần chú ý.

**Kiến trúc:** Phần thuần ở các module Core (mô hình 7 kiểu và chuyển bố cục cũ, `OverviewAlert`, `WidgetMeasure`, `WidgetPalette`, `UntilNext`, `DaySummary.nextTitle`), có test. Bộ thành phần dùng chung ở `NotchShell/Design/AraWidget.swift`. Mỗi tính năng vẽ widget của mình trong module Feature của nó (`MediaWidget`, `CalendarWidget`, …) theo `\.araTileSize`; `AppDelegate` chỉ nối.

**Công nghệ:** Swift 6, SwiftUI, SwiftPM, Swift Testing (`Scripts/test.sh`).

**Spec:** `docs/superpowers/specs/2026-10-18-overview-widget-set-design.md`

## Ràng buộc chung

- Thẻ `#1E1E1E`, bo 14, lề 9 (dọc) × 11 (ngang), nhân `araScale`; thẻ tối ở cả giao diện sáng và tối.
- Màu nhấn: Nhạc `#4FA8FF`, Lịch `#FFC23D`, Hẹn giờ `#2EE6A6`, Clipboard `#FF8A5B`, Agent `#A98BFF`, Máy `#9BE15D`; cảnh báo `#FF5A1F`; chữ chính `#F2F2F2`, chữ phụ `#9A9A9A`; nền thanh `#333333`; nút phụ `#2A2A2A`.
- Màu theo `ThemeHue`: `sky` → Nhạc, `mustard` → Lịch, `mint` → Hẹn giờ, `peach` → Clipboard, `lilac` → Agent, `sage` → Máy.
- Mọi chữ cỡ tối thiểu 10,5 × `araScale`; chữ dài thì `lineLimit` và `minimumScaleFactor(0.8)`, không bao giờ tràn ô.
- Con số chính: 24 (nhỏ), 26 (rộng); cỡ lớn tuỳ ô. Nút tròn 26. Thanh cao 5.
- Mỗi widget có tên cho VoiceOver; mỗi nút có `accessibilityLabel`; bấm chỗ trống của ô mở trang tính năng (trừ khi spec nói khác: Hẹn giờ nhỏ, Clipboard nhỏ).
- Chuỗi mới có ở cả `Resources/vi.lproj` và `Resources/en.lproj`, khoá bắt đầu bằng `widget.`.
- Không đổi lưới, cách đổi cỡ, kéo thả, chế độ sửa.
- Thử bằng bản trong `build/` với `--data-dir` riêng; không bấm phát/tới bài thật, không bấm hộp xin quyền của hệ thống, không bật Touch ID; trả lại cài đặt thật đã đổi.
- Phiên bản giữ 0.26.0 (chưa phát hành), build lên 52; không phát hành, không đẩy mã nguồn.

## Trọng tâm khi rà soát

1. Chữ dài (tên bài, tên việc, tên thiết bị tiếng Việt có dấu) ở cỡ nhỏ: phải cắt gọn hoặc co nhẹ, không đẩy con số chính ra ngoài ô. Thêm ở Task 4, 5, 6: ảnh chụp với một tên dài 60 ký tự.
2. Số ngoài khoảng hoặc không có: phần trăm < 0 hay > 100, thời lượng 0, mức dùng Claude chưa có (`nil`): thanh không vẽ ngược, không hiện "0%" giả. Test ở Task 2 (`WidgetMeasure`), ảnh chụp Agent không có số ở Task 6.
3. Bố cục cũ đã lưu có cả kiểu cũ và kiểu mới cùng tính năng (`media:wide`, `albumArt:large`): giữ mục đầu, không mất ô, vẫn vừa lưới. Test ở Task 1.
4. Đang ở chế độ sửa: bấm vào nút trong widget (phát, dừng, dán) không được chạy hành động. Thử tay ở Task 7.
5. Mac để bàn không pin, thiết bị Bluetooth không báo pin: "Điện lưới", hàng không có phần trăm, không cảnh báo. Test ở Task 2 (`OverviewAlert.battery` với `percent: nil`), ảnh chụp ở Task 6.

---

### Task 1: Mô hình 7 kiểu, chuyển bố cục cũ, bỏ bản hình ảnh

**Files:**
- Modify: `Sources/NotchCore/OverviewLayout.swift` (enum `OverviewWidget`, `arrangement(from:)`)
- Modify: `Tests/NotchCoreTests/OverviewLayoutTests.swift`
- Modify: `Sources/AraNotch/AppDelegate.swift` (bảng `overviewTiles.tiles`, bỏ vòng `toolID`)
- Modify: `Sources/AraNotch/OverviewPage.swift` (extension `title`/`icon`/`hue` bỏ nhánh `toolID`)
- Modify: `Sources/AraNotch/OverviewEditor.swift` (`addableWidgets`: bỏ so sánh `isVisual`, giữ thứ tự `OverviewFeature`)
- Delete: `Sources/MediaFeature/AlbumArtTile.swift`, `Sources/TimerFeature/TimerDiscTile.swift`, `Sources/CalendarFeature/DayClockTile.swift`, `Sources/ClipboardFeature/ClipStackTile.swift`, `Sources/ClipboardFeature/ColorPaletteTile.swift`, `Sources/AgentFeature/UsageRingsTile.swift`, `Sources/SystemEventsFeature/DeviceRingsTile.swift`, `Sources/AraNotch/BigToolTile.swift`, `Sources/NotchShell/Design/AraVisualTile.swift`
- Modify: các controller bỏ `makeAlbumArtTile`, `makeTimerDiscTile`, `makeDayClockTile`, `makeClipStackTile`, `makeColorPaletteTile`, `makeUsageRingsTile`, `makeDeviceRingsTile`
- Modify: hai `Localizable.strings` bỏ `overview.tile.<kiểu hình ảnh>` và mọi `overview.caption.*`

**Interfaces:**
- Produces: `OverviewWidget` chỉ có `media, calendar, timer, clipboard, tools, agents, device`; `sizes` luôn `[.small, .wide, .large]`; không còn `isVisual`, `toolID`. `OverviewGrid.arrangement(from:)` nhận cả tên cũ.

- [ ] **Step 1: Viết test hỏng**

Thay `eachKindHasItsFeatureAndSizes`, `resizingCyclesOnlyThroughTheKindsSizes`, `aKindIsAddedAtItsSmallestSize`, `aSavedSizeTheKindDoesNotAllowBecomesItsSmallest` bằng:

```swift
@Test func sevenKindsEachInThreeSizes() {
    #expect(OverviewWidget.allCases.map(\.rawValue) == ["media", "calendar", "timer", "clipboard", "tools", "agents", "device"])
    #expect(OverviewWidget.allCases.allSatisfy { $0.sizes == [.small, .wide, .large] })
}

@Test func oldKindsBecomeTheirFeaturesWidgetAndKeepTheirSize() {
    #expect(OverviewGrid.arrangement(from: [
        "albumArt:large", "dayClock:small", "timerDisc:large", "colorPalette:wide",
        "usageRings:small", "deviceRings:wide", "tool.translate:small",
    ]) == [item(.media, .large), item(.calendar, .small), item(.timer, .large), item(.clipboard, .wide),
           item(.agents, .small), item(.device, .wide), item(.tools, .small)])
    #expect(OverviewGrid.arrangement(from: ["clipStack:large"]) == [item(.clipboard, .large)])
}

@Test func aSecondTileOfTheSameFeatureIsDropped() {
    #expect(OverviewGrid.arrangement(from: ["media:wide", "albumArt:large", "tool.capture:small", "tool.note:small", "tools:wide"])
            == [item(.media, .wide), item(.tools, .small)])
}

@Test func unknownEntriesAreStillDropped() {
    #expect(OverviewGrid.arrangement(from: ["tool:small", "weather:wide", "media:huge", "calendar:wide"]) == [item(.calendar, .wide)])
}
```

Trong `theAddTileCanTakeARowOfItsOwn`, thay `item(.toolNote, .small)` bằng `item(.tools, .small)`.

- [ ] **Step 2: Chạy test, thấy hỏng**

Run: `Scripts/test.sh --filter OverviewLayoutTests 2>&1 | tail -20`
Expected: hỏng ở `sevenKindsEachInThreeSizes` (còn 22 kiểu) và các test chuyển kiểu.

- [ ] **Step 3: Sửa mô hình**

Trong `OverviewLayout.swift`: bỏ các case hình ảnh và `tool.*`, `isVisual`, `toolID`; `sizes` trả `[.small, .wide, .large]`. Thêm `private static let legacyKinds: [String: OverviewWidget]` (`albumArt`→media, `dayClock`→calendar, `timerDisc`→timer, `clipStack`→clipboard, `colorPalette`→clipboard, `usageRings`→agents, `deviceRings`→device); trong `arrangement(from:)` tên bắt đầu bằng `"tool."` và dài hơn `"tool."` → `.tools`, sau đó đến `legacyKinds`, sau đó `OverviewWidget(rawValue:)`. Giữ quy tắc trùng thì bỏ mục sau và cắt khi quá bốn hàng. Sửa chú thích của enum.

- [ ] **Step 4: Sửa phía ứng dụng cho biên dịch được**

Xoá các tệp và hàm `make…Tile` ở danh sách Files; trong `AppDelegate` bảng `overviewTiles.tiles` chỉ còn 7 khoá; bỏ vòng `for widget in OverviewWidget.allCases { if let id = widget.toolID … }`. `OverviewWidget.title` = `L10n.string("overview.tile.\(rawValue)")`, `icon`/`hue` theo `feature`. `addableWidgets` sắp theo thứ tự `OverviewFeature.allCases`. Xoá chuỗi không còn khoá nào dùng (kiểm bằng `grep -rn "overview.caption\|overview.tile.albumArt" Sources` ra rỗng).

- [ ] **Step 5: Chạy toàn bộ test**

Run: `Scripts/test.sh 2>&1 | tail -5`
Expected: tất cả qua (số test bằng trước trừ các test đã thay, cộng 4 test mới).

- [ ] **Step 6: Commit**

```bash
git add -A Sources Tests Resources
git commit -m "feat: the overview has one widget per feature in three sizes; saved visual kinds become their feature's widget"
```

---

### Task 2: Các hàm thuần cho widget

**Files:**
- Create: `Sources/NotchCore/OverviewAlert.swift`, `Sources/NotchCore/WidgetMeasure.swift`, `Sources/NotchCore/WidgetPalette.swift`
- Create: `Sources/CalendarCore/UntilNext.swift`
- Modify: `Sources/CalendarCore/DaySummary.swift`
- Test: `Tests/NotchCoreTests/OverviewAlertTests.swift`, `Tests/NotchCoreTests/WidgetMeasureTests.swift`, `Tests/NotchCoreTests/ThemePaletteTests.swift`, `Tests/CalendarCoreTests/DaySummaryTests.swift`, `Tests/CalendarCoreTests/UntilNextTests.swift`

**Interfaces:**
- Produces:
  - `public enum OverviewAlert { static func battery(percent: Int?, isCharging: Bool) -> Bool; static func usage(percent: Double?) -> Bool; static func timer(remaining: TimeInterval, isFinished: Bool) -> Bool; static func agents(waiting: Int) -> Bool }`
  - `public enum WidgetMeasure { static func fraction(_ value: Double) -> Double; static func segments(percent: Int, of count: Int) -> Int }`
  - `public enum WidgetPalette { static let card, text, secondaryText, track, quietButton, alert: ThemeColor; static func vivid(_ hue: ThemeHue) -> ThemeColor }`
  - `public enum UntilNext: Equatable { case now, minutes(Int), hours(Int); static func make(next: Date?, now: Date) -> UntilNext? }`
  - `DaySummary.nextTitle: String?` (init `init(count:next:nextTitle: String? = nil)`)

- [ ] **Step 1: Viết test hỏng**

```swift
@Suite struct OverviewAlertTests {
    @Test func aLowBatteryAlertsOnlyWhileNotCharging() {
        #expect(OverviewAlert.battery(percent: 20, isCharging: false))
        #expect(!OverviewAlert.battery(percent: 21, isCharging: false))
        #expect(!OverviewAlert.battery(percent: 5, isCharging: true))
        #expect(!OverviewAlert.battery(percent: nil, isCharging: false))
    }
    @Test func usageAlertsFromNinetyPercent() {
        #expect(!OverviewAlert.usage(percent: 89))
        #expect(OverviewAlert.usage(percent: 90))
        #expect(!OverviewAlert.usage(percent: nil))
    }
    @Test func aTimerAlertsInItsLastMinuteAndWhenDone() {
        #expect(OverviewAlert.timer(remaining: 59, isFinished: false))
        #expect(!OverviewAlert.timer(remaining: 60, isFinished: false))
        #expect(OverviewAlert.timer(remaining: 0, isFinished: true))
    }
    @Test func agentsAlertWhenOneWaits() {
        #expect(!OverviewAlert.agents(waiting: 0))
        #expect(OverviewAlert.agents(waiting: 1))
    }
}

@Suite struct WidgetMeasureTests {
    @Test func aBarIsNeverFilledBackwardsOrPastItsEnd() {
        #expect(WidgetMeasure.fraction(-0.2) == 0)
        #expect(WidgetMeasure.fraction(0.4) == 0.4)
        #expect(WidgetMeasure.fraction(1.7) == 1)
        #expect(WidgetMeasure.fraction(.nan) == 0)
    }
    @Test func fiveSegmentsShowAnyChargeAtAll() {
        #expect([0, 5, 20, 30, 83, 100, 120, -4].map { WidgetMeasure.segments(percent: $0, of: 5) } == [0, 1, 1, 2, 4, 5, 5, 0])
    }
}
```

Trong `ThemePaletteTests` thêm `widgetColoursStandOutOnTheDarkCard`: `WidgetPalette.text` và `secondaryText` trên `card` ≥ 4.5; `vivid(hue)` của cả 6 hue và `alert` trên `card` ≥ 3; `card` trên `vivid(hue)` (chữ tối trên nút chính) ≥ 4.5; `vivid(.sky) == ThemeColor(hex: 0x4FA8FF)` và `alert == ThemeColor(hex: 0xFF5A1F)`.

`UntilNextTests` (giờ Asia/Ho_Chi_Minh như `DaySummaryTests`): `make(next: nil, now:)` → nil; 13:20 tới 14:00 → `.minutes(40)`; 13:00:30 tới 14:00 → `.hours(1)` (59,5 phút làm tròn lên 60); 11:59 tới 14:00 → `.hours(2)`; next ≤ now → `.now`.

Trong `DaySummaryTests.countsWhatIsLeftOfTodayAndFindsTheNextStart`, mong đợi thành `DaySummary(count: 5, next: at(14), nextTitle: "Chiều")`; thêm `theNextCanBeAReminder`: chỉ có `reminder("Gọi điện", due: at(16))` lúc 10:00 → `DaySummary(count: 1, next: at(16), nextTitle: "Gọi điện")`.

- [ ] **Step 2: Chạy test, thấy hỏng**

Run: `Scripts/test.sh --filter "OverviewAlertTests|WidgetMeasureTests|ThemePaletteTests|DaySummaryTests|UntilNextTests" 2>&1 | tail -20`
Expected: không biên dịch được vì thiếu các kiểu mới.

- [ ] **Step 3: Viết các hàm**

Theo chữ ký ở Interfaces và các giá trị ở Ràng buộc chung. `segments`: `percent <= 0` → 0, ngược lại `max(1, Int((Double(min(percent, 100)) / 100 * Double(count)).rounded()))`. `UntilNext`: phút = làm tròn lên của giây/60; dưới 60 → `.minutes`, còn lại `.hours(phút / 60)`. `DaySummary.make` lấy tên của mục có giờ bắt đầu sớm nhất trong `starts`.

- [ ] **Step 4: Chạy test, thấy qua**

Run: lệnh ở Step 2. Expected: tất cả qua.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchCore Sources/CalendarCore Tests
git commit -m "feat: when a widget turns orange, how full its bars are, its colours and how long until the next thing"
```

---

### Task 3: Bộ thành phần dùng chung

**Files:**
- Create: `Sources/NotchShell/Design/AraWidget.swift`
- Modify: `Sources/NotchShell/Design/AraPalette.swift` (thêm `AraPalette.vivid(_:)`, `alert`, `widgetCard`, `widgetText`, `widgetSecondary`, `widgetTrack`, `widgetQuiet` từ `WidgetPalette`)
- Modify: `Sources/NotchShell/Design/AraOverviewTile.swift` (chuyển khoá môi trường `araTileSize` sang `AraWidget.swift`)
- Test: `Tests/NotchShellTests/AraWidgetTests.swift`

**Interfaces:**
- Consumes: `WidgetPalette`, `WidgetMeasure` (Task 2).
- Produces (đều `public`, trong NotchShell):
  - `AraWidget<Content: View>(name: String, hue: AraHue?, onOpen: (() -> Void)?, @ViewBuilder content:)` — thẻ, VoiceOver đọc `name`; `onOpen` gắn vào nền (chỗ trống), không vào nút con.
  - `AraWidgetHeader(label: String, chip: AraStatusChip?)`
  - `AraStatusChip(text: String, hue: AraHue?, isAlert: Bool = false)` — nền: màu nhấn độ mờ 0.18; chữ: màu nhấn; cảnh báo dùng `alert`.
  - `AraBigValue(text: String, size: CGFloat, isAlert: Bool = false)`
  - `AraTrackBar(fraction: Double, hue: AraHue?, isAlert: Bool = false, spans: [ClosedRange<Double>] = [], marker: Double? = nil, thin: Bool = false)` — `fraction` qua `WidgetMeasure.fraction`; `spans` là các đoạn màu nhấn; `marker` là vạch "bây giờ" màu `alert`; `thin` cao 3.
  - `AraSegmentBar(percent: Int, hue: AraHue?, isAlert: Bool = false)` — 5 khúc, số khúc sáng từ `WidgetMeasure.segments(percent:of: 5)`.
  - `AraRoundButton(icon: AraIcon, label: String, isPrimary: Bool, hue: AraHue?, action:)` — đường kính 26.
  - `AraStatRow(items: [(label: String, value: String)])`
  - `AraPalette.vivid(_ hue: AraHue?) -> Color` (nil → `widgetText`).

- [ ] **Step 1: Viết test hỏng**

`AraWidgetTests.vividColoursAreTheWidgetPalettes`: với mỗi `AraHue.allCases`, `NSColor(AraPalette.vivid(hue)).usingColorSpace(.sRGB)` có đỏ/lục/lam lệch < 0.01 so với `WidgetPalette.vivid(hue)`; `AraPalette.vivid(nil)` khớp `WidgetPalette.text`.

- [ ] **Step 2: Chạy, thấy hỏng**

Run: `Scripts/test.sh --filter AraWidgetTests 2>&1 | tail -10`
Expected: không biên dịch được, thiếu `AraPalette.vivid`.

- [ ] **Step 3: Viết thành phần và màu**

Theo Interfaces và Ràng buộc chung. Màu cố định (không theo giao diện sáng/tối). Chip, nhãn, số đều theo cỡ tối thiểu 10,5 × `ui`.

- [ ] **Step 4: Chạy toàn bộ test**

Run: `Scripts/test.sh 2>&1 | tail -5`
Expected: tất cả qua.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchShell Tests/NotchShellTests
git commit -m "feat: the dark widget card and its parts: header, chip, big number, bars, round buttons, stats"
```

---

### Task 4: Nhạc và Hẹn giờ

**Files:**
- Create: `Sources/MediaFeature/MediaWidget.swift` (thay `MediaOverviewTile.swift`, giữ `VolumeOverviewRow` sang tệp này và vẽ lại bằng `AraTrackBar`)
- Create: `Sources/TimerFeature/TimerWidget.swift` (thay `TimerOverviewTile.swift`)
- Delete: `Sources/MediaFeature/MediaOverviewTile.swift`, `Sources/TimerFeature/TimerOverviewTile.swift`
- Modify: `MediaController.makeOverviewTile()`, `TimerController.makeOverviewTile()` trả widget mới
- Modify: hai `Localizable.strings`

**Interfaces:**
- Consumes: Task 3 (mọi thành phần), `OverviewAlert.timer` (Task 2), `NowPlaying.progress(at:)`, `NowPlaying.position(at:)`, `NowPlaying.clock(_:)`, `CountdownTimer.remaining(at:)`, `progress(at:)`, `TimerBoard.soonest(at:)`, các mức sẵn của `TimerSettings`.
- Produces: `public func makeVolumeRow() -> AnyView` vẫn tồn tại (Task 6 dùng cho Máy): thanh âm lượng `AraTrackBar` màu Máy và tên loa đang phát.

Chuỗi (vi / en):

| Khoá | vi | en |
|---|---|---|
| `widget.media.label` | Đang phát | Now playing |
| `widget.media.empty` | Chưa có gì đang phát | Nothing playing |
| `widget.timer.label` | Hẹn giờ | Timer |
| `widget.timer.running` | Đang chạy | Running |
| `widget.timer.paused` | Tạm dừng | Paused |
| `widget.timer.finished` | Hết giờ | Done |
| `widget.timer.count` | %d đang chạy | %d running |
| `widget.timer.new` | + Mới | + New |
| `widget.timer.addMinute` | Thêm 1 phút | Add a minute |

- [ ] **Step 1: Vẽ Nhạc theo spec, mục "Nhạc"**

Nhỏ: ảnh bìa 34, tên bài (1 dòng), ca sĩ (1 dòng), `AraTrackBar`, `AraRoundButton` phát/dừng chính. Rộng: ảnh 52, tên bài, "ca sĩ · ứng dụng" (`sourceApp`), ba nút, thanh có `clock(position)` và `-clock(duration - position)`. Lớn: ảnh 78, `AraWidgetHeader(label: "Đang phát", chip: tên ứng dụng)`, dòng lời đang hát (khi có `lyrics`), thanh có giờ, ba nút, hàng âm lượng (`VolumeOverviewRow`). Chưa phát: nhãn và "Chưa có gì đang phát"; rộng/lớn thêm nút mở nhanh ứng dụng nhạc như trang Nhạc đang có.

- [ ] **Step 2: Vẽ Hẹn giờ theo spec, mục "Hẹn giờ"**

Nhỏ: header "Hẹn giờ" + chip trạng thái; thời gian còn lại `AraBigValue(24)`; thanh; bấm ô = dừng/chạy tiếp bộ đếm sớm nhất. Rộng: "tên · độ dài", số 26; nút +1′ (phụ), dừng/chạy (chính), huỷ (phụ); thanh. Lớn: chip "n đang chạy"; tới 4 bộ đếm (tên, thời gian, thanh); hàng mức sẵn và "+ Mới" (mở trang Hẹn giờ ở chỗ thêm). Không có bộ đếm: mức sẵn (nhỏ 2, rộng 3, lớn 4 và "+ Mới"). `OverviewAlert.timer` đúng thì số và thanh dùng `isAlert: true`.

- [ ] **Step 3: Build và chụp**

Run: `swift build 2>&1 | tail -3`, rồi mở bản thử với `--data-dir` riêng, `--open-on-launch --select-page overview --overview-arrangement "media:small,timer:small"` (rồi `wide`, rồi `large`; các mục cách nhau bằng dấu phẩy), `--simulate-now-playing '<json có tên bài 60 ký tự>'`, `--timer 45` (để thấy cảnh báo) và chụp vùng notch.
Expected: 3 cỡ mỗi ô khác nhau như spec; tên dài bị cắt gọn; Hẹn giờ dưới 60 giây màu cam đỏ; không có gì đang phát thì ô vẫn có chữ.

- [ ] **Step 4: Chạy toàn bộ test và commit**

Run: `Scripts/test.sh 2>&1 | tail -5` — Expected: tất cả qua.

```bash
git add -A Sources Resources
git commit -m "feat: the music and timer widgets, three sizes each, on the dark card"
```

---

### Task 5: Lịch và Clipboard

**Files:**
- Create: `Sources/CalendarFeature/CalendarWidget.swift`, `Sources/ClipboardFeature/ClipboardWidget.swift`
- Delete: `Sources/CalendarFeature/CalendarOverviewTile.swift`, `Sources/ClipboardFeature/ClipboardOverviewTile.swift`
- Modify: `CalendarController.makeOverviewTile()`, `ClipboardController.makeOverviewTile()`; hai `Localizable.strings`

**Interfaces:**
- Consumes: Task 3; `DaySummary.make(…)` với `nextTitle`, `UntilNext.make(next:now:)` (Task 2); `DayRing.fraction(of:on:calendar:)`, `DayRing.arcs(for:on:calendar:)`; `ColorPalette.recent(_:limit:)`; hành động dán và chép lại màu mà ô Clipboard cũ đang dùng.

Chuỗi (vi / en):

| Khoá | vi | en |
|---|---|---|
| `widget.calendar.next` | Tiếp theo | Up next |
| `widget.calendar.inMinutes` | còn %d′ | in %d′ |
| `widget.calendar.inHours` | còn %d giờ | in %d h |
| `widget.calendar.now` | Đang diễn ra | Now |
| `widget.calendar.left` | %d việc | %d left |
| `widget.calendar.today` | Hôm nay · %@ | Today · %@ |
| `widget.calendar.none` | Hôm nay · không còn việc | Today · nothing left |
| `widget.clipboard.latest` | Mới chép | Just copied |
| `widget.clipboard.paste` | Bấm để dán | Click to paste |
| `widget.clipboard.today` | Clipboard · hôm nay | Clipboard · today |

- [ ] **Step 1: Vẽ Lịch theo spec, mục "Lịch"**

Nhỏ: header "Tiếp theo" + chip `UntilNext`; giờ `next` to (24); `nextTitle`. Rộng: "Tiếp theo · còn 40′", giờ (26) và tên trên một dòng; chip "n việc"; `AraTrackBar(fraction: 0, spans: DayRing.arcs, marker: DayRing.fraction(now))`. Lớn: "Hôm nay · thứ, ngày" (định dạng ngày theo ngôn ngữ ứng dụng), chip số việc; tới 6 dòng như ô Lịch cũ (vạch màu, giờ, tên, "Tham gia" hoặc thời lượng; lời nhắc có vòng tròn bấm xong); dải giờ ở đáy. `summary.count == 0` → "Hôm nay · không còn việc"; chưa có quyền → nút xin quyền như trang Lịch.

- [ ] **Step 2: Vẽ Clipboard theo spec, mục "Clipboard"**

Lọc `!$0.isEncrypted` trước mọi thứ. Nhỏ: header "Mới chép" + thời gian tương đối; tên ngắn 2 dòng; "Bấm để dán"; bấm ô = dán mục đó. Rộng: "Clipboard · hôm nay", chip số mục chép hôm nay; 3 thẻ theo màu loại, bấm thẻ = dán. Lớn: 6 thẻ có thời gian; hàng chấm `ColorPalette.recent(items, limit: 8)`, bấm chấm = chép lại, mỗi chấm một phần tử VoiceOver đọc mã màu. Trống hoặc lỗi kho: giữ hai thông báo của ô cũ.

- [ ] **Step 3: Build và chụp**

Run: `swift build 2>&1 | tail -3`, rồi bản thử với `--simulate-agenda`, `--pasteboard-name aranotch.test`, ba cỡ mỗi ô, có và không có dữ liệu, một sự kiện tên 60 ký tự.
Expected: như spec; dải giờ có vạch cam đỏ đúng giờ hiện tại; mục bảng khoá không hiện.

- [ ] **Step 4: Chạy toàn bộ test và commit**

Run: `Scripts/test.sh 2>&1 | tail -5` — Expected: tất cả qua.

```bash
git add -A Sources Resources
git commit -m "feat: the calendar and clipboard widgets, three sizes each"
```

---

### Task 6: Agent, Máy và Công cụ

**Files:**
- Create: `Sources/AgentFeature/AgentWidget.swift`, `Sources/SystemEventsFeature/DeviceWidget.swift`
- Delete: `Sources/AgentFeature/AgentOverviewTile.swift`
- Modify: `Sources/AraNotch/Pages.swift` (thay `ToolsOverviewTile` bằng `ToolsWidget`, bỏ `DeviceOverviewTile`)
- Modify: `SystemEventsController` (thay `makeBatteryRow`/`makeBluetoothRow` bằng `makeOverviewTile(volume:)`; bỏ `BatteryOverviewRow`, `BluetoothOverviewRow` nếu không còn ai dùng), `AgentController.makeOverviewTile()`, `AppDelegate` (khoá `.device`, `.tools`); hai `Localizable.strings`

**Interfaces:**
- Consumes: Task 3; `OverviewAlert.battery/usage/agents` (Task 2); `AgentViewModel.sessions/claudeUsage/codexUsage`, `UsageMeter.resetText`; `BatteryModel.snapshot` (`hasBattery`, `isCharging`, `percent`, `minutesLeft`), `BluetoothBatteryReader.devices`, `BluetoothDeviceKind.symbolName`; `media.makeVolumeRow()` (Task 4); `NotchTool.looks`.
- Produces: `public func makeOverviewTile(volume: AnyView) -> AnyView` trên `SystemEventsController`; `AppDelegate` gọi `systemEvents.makeOverviewTile(volume: media.makeVolumeRow())`.

Chuỗi (vi / en):

| Khoá | vi | en |
|---|---|---|
| `widget.agents.label` | Agent | Agents |
| `widget.agents.waiting` | %d chờ bạn | %d waiting |
| `widget.agents.sessions` | Agent · %d phiên | Agents · %d sessions |
| `widget.agents.none` | Chưa có agent nào chạy | No agent running |
| `widget.agents.fiveHour` | %@ 5 giờ | %@ 5 h |
| `widget.device.battery` | Pin · Mac | Battery · Mac |
| `widget.device.left` | còn ~%@ | ~%@ left |
| `widget.device.charging` | Đang sạc | Charging |
| `widget.device.mains` | Điện lưới | Power adapter |
| `widget.device.title` | Pin và thiết bị | Battery and devices |

- [ ] **Step 1: Vẽ Agent theo spec, mục "Agent"**

Nhỏ: header "Agent" + chip "n chờ bạn" (cảnh báo) khi `waiting > 0`; số phiên (24); thanh "Claude 5 giờ" với phần trăm — chỉ khi `claudeUsage?.fiveHour` có. Rộng: hai phiên đầu (sắp như ô cũ: chờ bạn trước), chip "+n"; thanh Claude. Lớn: "Agent · n phiên", chip chờ bạn; tới 5 phiên (chấm, tên, trạng thái, thời gian); Claude và Codex: thanh 5 giờ, thanh mảnh 7 ngày, `resetText`. Không phiên: "Chưa có agent nào chạy" và thanh Claude nếu có số. Thanh dùng `isAlert: OverviewAlert.usage(percent:)`.

- [ ] **Step 2: Vẽ Máy theo spec, mục "Máy"**

Nhỏ: "Pin · Mac" + chip giờ còn lại (khi `minutesLeft` có); phần trăm (24); `AraSegmentBar`. Rộng: phần trăm (26), "Pin · còn ~4 giờ"; chip "Đang sạc" khi sạc; `volume`. Lớn: "Pin và thiết bị"; mỗi thiết bị một hàng (biểu tượng, tên, `AraTrackBar`, phần trăm; không có phần trăm thì không có thanh); hàng `volume`. `hasBattery == false`: "Điện lưới", không có thanh pin. Mỗi hàng `isAlert: OverviewAlert.battery(percent:isCharging:)` (thiết bị Bluetooth coi như không sạc). Đọc lại `PowerMonitor.read()` khi hiện, như hàm cũ.

- [ ] **Step 3: Vẽ Công cụ theo spec, mục "Công cụ"**

Nhỏ: 4 công cụ (`capture, text, color, translate`) lưới 2 × 2, `AraRoundButton` nền `vivid(look.hue)` và tên ngắn dưới (cỡ 10,5, co nhẹ). Rộng: 4 công cụ một hàng, tên đầy đủ. Lớn: 8 công cụ, hai hàng. Không có `onOpen`.

- [ ] **Step 4: Build và chụp**

Run: `swift build 2>&1 | tail -3`, rồi bản thử với `--claude-usage-file` (một tệp 62% và một tệp 93%), `--agent-events-file` có một phiên chờ, ba cỡ mỗi ô; một lần không có tệp mức dùng.
Expected: như spec; 93% và phiên chờ có màu cam đỏ; không có số thì không hiện thanh Claude; Mac để bàn hay thiết bị không pin hiện đúng chữ.

- [ ] **Step 5: Chạy toàn bộ test và commit**

Run: `Scripts/test.sh 2>&1 | tail -5` — Expected: tất cả qua.

```bash
git add -A Sources Resources
git commit -m "feat: the agents, device and tools widgets, three sizes each"
```

---

### Task 7: Dọn dẹp, thử tay, sổ dự án

**Files:**
- Delete: `Sources/NotchShell/Design/AraOverviewTile.swift` (khi không còn ai dùng `AraOverviewTile`)
- Modify: hai `Localizable.strings` (bỏ `page.overview.*` không còn dùng)
- Modify: `Resources/Info.plist` (build 52, sửa bằng `sed` giữ định dạng)
- Modify: `docs/project/FEATURES.md`, `docs/project/HISTORY.md`

- [ ] **Step 1: Bỏ mã và chuỗi thừa**

Run: `grep -rn "AraOverviewTile\|araCard(radius: 14)" Sources/*Feature Sources/AraNotch` — xoá tệp khi chỉ còn định nghĩa. Với mỗi khoá trong hai tệp chuỗi bắt đầu bằng `page.overview.` hoặc `overview.`, `grep -rn "<khoá>" Sources` rỗng thì xoá ở cả hai tệp (chú ý khoá ghép bằng `\(…)` như `overview.tile.\(rawValue)` và `overview.agents.\(kind)`).
Expected: `swift build` sạch, không cảnh báo mới.

- [ ] **Step 2: Chụp đủ bộ**

7 ô × 3 cỡ, có và không có dữ liệu, tiếng Việt và tiếng Anh (thêm `-AppleLanguages "(en)"` khi mở bản thử), một ảnh có cảnh báo. Lưu ở scratchpad, xem từng ảnh.
Expected: không chữ nào bị tràn hay đè; mọi ô có chữ nói nó là gì.

- [ ] **Step 3: Thử tay qua trợ năng**

Trên bản thử: bấm từng nút ở từng cỡ (trừ phát/tới bài thật — chỉ kiểm nút có mặt và có nhãn); bấm chỗ trống mở đúng trang; chế độ sửa: đổi cỡ đủ ba cỡ cho từng ô, bấm nút phát/dán trong lúc sửa không chạy gì; mở với bố cục cũ `--overview-arrangement "media:wide,albumArt:large,tool.capture:small"` ra Nhạc rộng và Công cụ nhỏ.
Expected: đúng như trên; mọi lệch ghi lại và sửa bằng test hỏng trước nếu là logic.

- [ ] **Step 4: Sổ dự án, build, graphify**

`FEATURES.md`: thay dòng widget hình ảnh bằng bộ widget mới (7 ô, ba cỡ, màu nhấn, cảnh báo). `HISTORY.md`: một mục ngày 2026-10-18 với lời chủ dự án và các lựa chọn. Build 52. Run: `Scripts/test.sh 2>&1 | tail -5` rồi `graphify update .`.
Expected: test qua hết; graph cập nhật.

- [ ] **Step 5: Commit**

```bash
git add -A Sources Resources docs graphify-out
git commit -m "chore: the overview's old tile card goes; the widget set in the ledger and the history; build 52"
```
