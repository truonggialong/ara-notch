# Clipboard Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Panel lịch sử clipboard mở bằng ⌘⇧C, điều khiển hoàn toàn bằng bàn phím, kèm điều hướng bàn phím trên trang notch.

**Architecture:** Quy tắc chọn mục, ánh xạ phím và vị trí panel là kiểu giá trị thuần trong `ClipboardCore`. `ClipboardFeature` thêm phím tắt Carbon, một `NSPanel` nổi và một bộ định tuyến phím dùng chung cho panel và notch.

**Tech Stack:** Swift 6, Carbon HIToolbox (phím tắt), AppKit, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-clipboard-panel-design.md`

## Global Constraints

- `ClipboardCore` không import AppKit, SwiftUI hay Carbon.
- Không dùng `@State`, `@FocusState` hay macro SwiftUI khác (thiếu Xcode); trạng thái cục bộ dùng `ObservableObject`.
- Hằng số từ spec: panel 560×380; lệch con trỏ 12 điểm; chờ 0,08 giây trước ⌘V; phím tắt ⌘⇧C (mã phím 8).
- Mã phím: ← 123, → 124, ↓ 125, ↑ 126, Return 36, Enter 76, Esc 53, ⌫ 51, số 1…9 lần lượt 18, 19, 20, 21, 23, 22, 26, 28, 25.
- Chuỗi hiển thị có đủ `en` và `vi`.
- Phím giả cho kiểm chứng chỉ được đưa vào hàng đợi của chính app (`NSApp.postEvent`), không gửi ra hệ thống.
- Chạy test bằng `Scripts/test.sh`. Mỗi task kết thúc bằng một commit.

## Review Focus

1. **Di chuyển khi chưa chọn gì:** `moveNext` và `movePrevious` trên lựa chọn rỗng phải chọn phần tử đầu, không crash. Test ở Task 1.
2. **Danh sách co lại dưới mục đang chọn:** sau khi lọc hoặc xoá, lựa chọn phải rơi về phần tử đầu. Test ở Task 1.
3. **Phím soạn thảo trong ô tìm kiếm:** ⌥←, ⇧→, ⌘A, chữ thường phải là `passThrough`. Test ở Task 2.
4. **⌘ kèm số ngoài phạm vi:** ⌘0 là `passThrough`; ⌘9 khi chỉ có 3 mục không dán gì. Test ở Task 2 và Task 1.
5. **Panel lớn hơn vùng hiển thị hoặc màn hình có gốc toạ độ âm:** khung phải nằm trong vùng hiển thị, bám góc trên trái. Test ở Task 3.

---

### Task 1: `ClipSelection`

**Files:** Create `Sources/ClipboardCore/ClipSelection.swift`; Test `Tests/ClipboardCoreTests/ClipSelectionTests.swift`

**Interfaces — Produces:**

```swift
public struct ClipSelection: Equatable, Sendable {
    public private(set) var selectedID: Int64?
    public init()
    public mutating func sync(with ids: [Int64])
    public mutating func moveNext(in ids: [Int64])
    public mutating func movePrevious(in ids: [Int64])
    @discardableResult public mutating func select(index: Int, in ids: [Int64]) -> Bool
    public mutating func select(id: Int64, in ids: [Int64])
    public func index(in ids: [Int64]) -> Int?
}
```

- [ ] **Step 1: Test thất bại.** Với `ids = [10, 20, 30]`:
  - `startsEmpty`: `selectedID == nil`, `index(in:) == nil`.
  - `syncSelectsFirstWhenNothingSelected`: sau `sync` là 10.
  - `syncKeepsExistingSelection`: chọn 20, `sync(with: [30, 20, 10])` vẫn 20.
  - `syncFallsBackToFirstWhenSelectionDisappears`: chọn 20, `sync(with: [10, 30])` là 10.
  - `syncWithEmptyListClearsSelection`.
  - `moveNextAdvancesAndStopsAtEnd`: 10 → 20 → 30 → 30.
  - `movePreviousStopsAtStart`: từ 20 → 10 → 10.
  - `movingWithNoSelectionSelectsFirst` cho cả hai chiều.
  - `movingInEmptyListDoesNothing`.
  - `selectIndexInRange` trả đúng và chọn 30 với index 2; `selectIndexOutOfRangeIsIgnored` với index 3 và -1 trả sai, giữ nguyên lựa chọn.
  - `selectIDIgnoresUnknownID`.
- [ ] **Step 2:** Chạy, xác nhận thất bại vì thiếu kiểu.
- [ ] **Step 3:** Cài đặt.
- [ ] **Step 4:** Chạy, xác nhận qua.
- [ ] **Step 5:** Commit `feat: add clip selection model`.

---

### Task 2: `ClipPanelKeyMap`

**Files:** Create `Sources/ClipboardCore/ClipPanelKeyMap.swift`; Test `Tests/ClipboardCoreTests/ClipPanelKeyMapTests.swift`

**Interfaces — Produces:**

```swift
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int)
    public static let command, shift, option, control: KeyModifiers
}
public enum ClipPanelCommand: Equatable, Sendable {
    case moveNext, movePrevious, paste, copy, delete, pasteIndex(Int), clearSearch, close, passThrough
}
public enum ClipListAxis: Sendable { case vertical, horizontal }
public enum ClipPanelKeyMap {
    public static func command(keyCode: UInt16, modifiers: KeyModifiers,
                               axis: ClipListAxis, searchIsEmpty: Bool) -> ClipPanelCommand
}
```

- [ ] **Step 1: Test thất bại**, mỗi dòng của bảng trong spec là một ca, cộng thêm:
  - Dọc: ↓ `moveNext`, ↑ `movePrevious`, ← và → `passThrough`.
  - Ngang, ô rỗng: → `moveNext`, ← `movePrevious`, ↑ và ↓ `passThrough`. Ngang, ô có chữ: ← và → `passThrough`.
  - Mũi tên kèm `.option`, `.shift`, `.command`, `.control`: `passThrough`.
  - Return và Enter (76): `paste`; ⌘Return: `copy`; ⇧Return: `passThrough`.
  - ⌘⌫: `delete`; ⌫ không kèm ⌘: `passThrough`.
  - ⌘1 → `pasteIndex(0)`, ⌘5 → `pasteIndex(4)`, ⌘9 → `pasteIndex(8)`; ⌘0 (mã 29) `passThrough`; phím 1 không kèm ⌘ `passThrough`; ⌘⇧1 `passThrough`.
  - Esc: `clearSearch` khi ô có chữ, `close` khi rỗng.
  - Chữ a (mã 0) và ⌘A: `passThrough`.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua.
- [ ] **Step 5:** Commit `feat: add clipboard panel key map`.

---

### Task 3: `PanelPlacement` và khoá cài đặt

**Files:** Create `Sources/ClipboardCore/PanelPlacement.swift`; Modify `Sources/ClipboardCore/ClipboardSettingsStore.swift`; Test `Tests/ClipboardCoreTests/PanelPlacementTests.swift`, bổ sung `ClipboardSettingsStoreTests.swift`

**Interfaces — Produces:**

```swift
public enum PanelPlacement {
    public static let cursorOffset: CGFloat = 12
    /// Toạ độ gốc dưới trái. `point` là vị trí con trỏ, `visibleFrame` là vùng hiển thị của màn hình chứa con trỏ.
    public static func frame(size: CGSize, near point: CGPoint, in visibleFrame: CGRect) -> CGRect
}
extension ClipboardSettingsStore {
    public var hotKeyEnabled: Bool { get nonmutating set }   // khoá "clipboard.hotKeyEnabled", mặc định true
}
```

- [ ] **Step 1: Test thất bại.** Với `visible = (0, 0, 1512, 950)`, `size = 560×380`:
  - `placesBelowRightOfCursor`: con trỏ (400, 700) cho khung (412, 308, 560, 380) — mép trên của panel ở y = 700 − 12.
  - `shiftsLeftAtRightEdge`: con trỏ (1500, 700) cho `maxX == 1512`.
  - `shiftsUpAtBottomEdge`: con trỏ (400, 100) cho `minY == 0`.
  - `staysInsideAtTopLeft`: con trỏ (0, 950) cho khung nằm trọn trong `visible`.
  - `worksOnScreenWithNegativeOrigin`: `visible = (-1920, 100, 1920, 1080)`, con trỏ (-10, 150) cho khung nằm trọn trong `visible`.
  - `pinsTopLeftWhenPanelIsLargerThanScreen`: `visible = (0, 0, 400, 300)` cho `minX == 0`, `maxY == 300`.
  - Cài đặt: mặc định `hotKeyEnabled == true`; ghi `false` đọc lại `false`; chuỗi sai kiểu trả `true`.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua toàn bộ.
- [ ] **Step 5:** Commit `feat: add panel placement and hot key setting`.

---

### Task 4: Phím tắt, panel và bộ định tuyến phím

Không có test đơn vị; kiểm chứng ở Task 6.

**Files:** Create `Sources/ClipboardFeature/HotKey.swift`, `ClipboardPanel.swift`, `ClipboardPanelView.swift`, `KeyCommandRouter.swift`; Modify `ClipboardSettings.swift`, `ClipboardViewModel.swift`, `ClipboardController.swift`, `ClipCardView.swift`, `ClipboardPageView.swift`, `ClipboardSettingsSection.swift`; Modify `Sources/NotchShell/NotchController.swift` (thêm `public var isKeyWindow: Bool` và `public func owns(_ window: NSWindow?) -> Bool`)

**Interfaces — Produces:**

```swift
extension ClipboardController {
    public func togglePanel()
    public func showPanel()
    public var isHotKeyRegistered: Bool { get }
    public func handleKey(_ event: NSEvent) -> Bool     // true nếu đã xử lý; dùng cho bộ theo dõi và kiểm chứng
}
```

- [ ] **Step 1: `HotKey`.** Lớp `@MainActor` bọc `RegisterEventHotKey` (chữ ký `'ARNC'`, id 1, mã phím 8, `cmdKey | shiftKey`) và một `InstallEventHandler` cho `kEventHotKeyPressed`; `register() -> Bool`, `unregister()`, `onPressed`.
- [ ] **Step 2: View model.** Thêm `@Published var selection = ClipSelection()`, `@Published var isPanelVisible = false`, hàm `syncSelection()` gọi mỗi khi `items` hoặc `searchText` đổi, và `selectedItem`.
- [ ] **Step 3: `ClipboardPanel` và `ClipboardPanelView`.** Panel `[.borderless, .nonactivatingPanel]`, `level = .floating`, bo góc 14, nền `NSVisualEffectView` chất liệu `.hudWindow`, `canBecomeKey` trả `true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`. View theo spec; dòng đang chọn có nền màu nhấn; `ScrollViewReader` cuộn tới mục đang chọn. Ô tìm kiếm là `NSViewRepresentable` bọc `NSTextField` và tự nhận tiêu điểm khi panel hiện.
- [ ] **Step 4: `KeyCommandRouter`.** `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`; hỏi `controller.handleKey(event)`; trả `nil` nếu đã xử lý.
- [ ] **Step 5: `ClipboardController`.** `handleKey`: xác định hướng (`vertical` nếu `event.window` là panel, `horizontal` nếu là cửa sổ notch và notch đang nhận phím, còn lại trả `false`), đổi cờ `NSEvent.ModifierFlags` sang `KeyModifiers`, gọi `ClipPanelKeyMap`, thực hiện lệnh. `showPanel` đặt khung bằng `PanelPlacement` theo `NSEvent.mouseLocation` và màn hình chứa con trỏ, `makeKeyAndOrderFront`. Panel đóng khi `didResignKey`. Phím tắt theo `settings.$hotKeyEnabled`.
- [ ] **Step 6: Trang notch.** Thẻ đang chọn có viền màu nhấn; hàng thẻ cuộn tới thẻ đang chọn.
- [ ] **Step 7: Cài đặt.** Thêm `Toggle` cho phím tắt.
- [ ] **Step 8:** `swift build` sạch. Commit `feat: add clipboard panel, global hot key and keyboard navigation`.

---

### Task 5: Tích hợp và tham số kiểm chứng

**Files:** Modify `Sources/AraNotch/LaunchArguments.swift`, `AppDelegate.swift`, hai file `Localizable.strings`

- [ ] **Step 1:** Chuỗi mới: `settings.clipboard.hotKey`, `clipboard.panel.empty`, `clipboard.panel.hint`.
- [ ] **Step 2:** Tham số `--show-clipboard-panel` gọi `showPanel()`. Tham số `--send-keys "<danh sách>"` (cách nhau bằng dấu phẩy; tên: `down`, `up`, `left`, `right`, `return`, `cmd-return`, `cmd-delete`, `esc`, `cmd-1`…`cmd-9`, hoặc `text:<chuỗi>` để đặt ô tìm kiếm) được thực hiện sau 0,6 giây, mỗi phím cách nhau 0,1 giây, bằng `NSApp.postEvent` với `windowNumber` của panel. Ảnh chụp chờ tới sau phím cuối.
- [ ] **Step 3:** `Scripts/build-app.sh`. Commit `feat: wire clipboard panel into the app`.

---

### Task 6: Kiểm chứng

Mọi lần chạy dùng `--data-dir` tạm, `--pasteboard-name aranotch.test` và `--seed-clipboard`.

- [ ] **Step 1:** `Scripts/test.sh` qua toàn bộ.
- [ ] **Step 2:** Ảnh panel ban đầu: sáu dòng, dòng đầu được chọn, khung xem trước hiện toàn văn mục đầu.
- [ ] **Step 3:** `--send-keys "down,down"`: dòng thứ ba được chọn, khung xem trước là ô màu.
- [ ] **Step 4:** `--send-keys "down,cmd-delete"`: còn năm dòng trong ảnh và trong `clipboard.sqlite`.
- [ ] **Step 5:** `--send-keys "text:@image"`: một dòng, khung xem trước là ảnh. `--send-keys "text:abc,esc"`: ô tìm kiếm rỗng, panel còn mở. `--send-keys "esc"`: không còn ảnh của panel.
- [ ] **Step 6:** `--send-keys "down,cmd-return"`: clipboard riêng `aranotch.test` chứa nội dung mục thứ hai; panel đã đóng.
- [ ] **Step 7:** Log có dòng đăng ký phím tắt thành công. Chạy với `defaults` tạm đặt `clipboard.hotKeyEnabled` sai: log báo không đăng ký. Xoá khoá `defaults` sau khi thử.
- [ ] **Step 8:** Commit các sửa đổi phát sinh.
