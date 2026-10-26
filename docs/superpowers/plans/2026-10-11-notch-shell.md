# Notch Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Một app agent macOS vẽ hình đen trùng notch, nở thành bảng chứa các trang khi rê chuột hoặc bấm, kèm icon thanh menu và cửa sổ Cài đặt.

**Architecture:** Một package SwiftPM với ba target. `NotchCore` chứa toàn bộ quy tắc hành vi dưới dạng kiểu giá trị thuần và được kiểm thử đơn vị. `NotchShell` nối các quy tắc đó với `NSPanel`, sự kiện chuột và SwiftUI. `AraNotch` là chương trình khởi động, đăng ký trang và cung cấp Cài đặt.

**Tech Stack:** Swift 6 (tools-version 6.0, language mode 6), SwiftUI, AppKit, Combine, Swift Testing, SwiftPM. Không dùng thư viện ngoài. Không cần Xcode.

**Spec:** `docs/superpowers/specs/2026-10-11-notch-shell-design.md`

## Global Constraints

- Nền tảng: `platforms: [.macOS(.v15)]`, chỉ arm64.
- Tên sản phẩm `AraNotch`, bundle ID `com.aranotch.app`, phiên bản `0.1.0`.
- `NotchCore` chỉ import Foundation và CoreGraphics. Không import AppKit hay SwiftUI.
- Mọi lớp chạm vào AppKit hoặc SwiftUI đều đánh dấu `@MainActor`.
- Hằng số từ spec: notch ảo rộng 180, cao tối thiểu 24; vùng rê chuột nới 4 điểm; kích thước mở 640×200; độ trễ rê chuột mặc định 0,10 giây trong khoảng 0…0,5; độ trễ đóng 0,25 giây; ngưỡng vuốt 40 điểm; lưới an toàn 15 Hz.
- Chuỗi hiển thị lấy từ `Localizable.strings` trong bundle chính, có đủ `en` và `vi`.
- Không cần quyền hệ thống nào.
- Kiểm thử dùng Swift Testing (`import Testing`, `@Test`, `#expect`).
- Mỗi task kết thúc bằng một commit.

## Review Focus

Năm loại đầu vào mà spec ngầm định nhưng dễ bị bỏ sót, theo thứ tự dễ gặp nhất:

1. **Vào ra liên tục khi đang chờ mở:** con trỏ lướt qua notch nhiều lần không được để lại bộ hẹn giờ thừa. Mỗi lần ra phải huỷ, mỗi lần vào lại phải hẹn mới. Test ở Task 2.
2. **Sự kiện quán tính sau khi vuốt xong:** trackpad tiếp tục gửi sự kiện quán tính sau khi nhấc tay; không được chuyển thêm trang. Test ở Task 3.
3. **Giá trị cài đặt hỏng trong UserDefaults:** khoá chứa sai kiểu (chuỗi thay vì số) hoặc NaN phải trả về mặc định, không crash. Test ở Task 4.
4. **Màn hình hẹp hơn bảng mở:** `openRect` phải bám mép trái màn hình thay vì tràn ra hai bên. Test ở Task 1.
5. **Màn hình phụ có toạ độ âm:** màn hình ngoài đặt bên trái màn hình chính có `frame.minX` âm; mọi hình chữ nhật phải nằm trong đúng màn hình đó. Test ở Task 1.

---

## File Structure

| Đường dẫn | Trách nhiệm |
|---|---|
| `Package.swift` | Khai báo ba target và một test target |
| `Sources/NotchCore/ScreenDescriptor.swift` | Số liệu thuần của một màn hình |
| `Sources/NotchCore/NotchGeometry.swift` | Tính các hình chữ nhật đóng, mở, rê chuột |
| `Sources/NotchCore/NotchStateMachine.swift` | Bảng chuyển trạng thái |
| `Sources/NotchCore/PageRegistry.swift` | `PageDescriptor` và danh sách trang |
| `Sources/NotchCore/SwipeAccumulator.swift` | Gom cử chỉ vuốt ngang |
| `Sources/NotchCore/ShellSettingsStore.swift` | Đọc ghi cài đặt vào UserDefaults |
| `Sources/NotchShell/L10n.swift` | Tra chuỗi từ bundle chính |
| `Sources/NotchShell/ShellSettings.swift` | Lớp quan sát được bọc `ShellSettingsStore` |
| `Sources/NotchShell/NotchPage.swift` | Trang kèm hàm tạo view |
| `Sources/NotchShell/NotchPanel.swift` | Cửa sổ `NSPanel` |
| `Sources/NotchShell/PointerMonitor.swift` | Bộ theo dõi sự kiện chuột |
| `Sources/NotchShell/NotchShape.swift` | Hình notch |
| `Sources/NotchShell/NotchViewModel.swift` | Trạng thái cho view |
| `Sources/NotchShell/NotchRootView.swift` | View gốc, hàng đầu bảng, nội dung trang |
| `Sources/NotchShell/NotchController.swift` | Điều phối tất cả |
| `Sources/NotchShell/NSScreen+Descriptor.swift` | Tạo `ScreenDescriptor` từ `NSScreen` |
| `Sources/AraNotch/main.swift` | Điểm vào |
| `Sources/AraNotch/AppDelegate.swift` | Dựng app |
| `Sources/AraNotch/StatusItemController.swift` | Icon thanh menu |
| `Sources/AraNotch/SettingsWindowController.swift` | Cửa sổ Cài đặt |
| `Sources/AraNotch/SettingsView.swift` | Nội dung Cài đặt |
| `Sources/AraNotch/Pages.swift` | Trang Chào mừng và Thông tin |
| `Resources/Info.plist` | Thông tin bundle |
| `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings` | Chuỗi hiển thị |
| `Scripts/build-app.sh`, `Scripts/run.sh` | Dựng và chạy app |
| `Tests/NotchCoreTests/*.swift` | Một file test cho mỗi kiểu của `NotchCore` |

---

### Task 1: Khung package và `NotchGeometry`

**Files:**
- Create: `Package.swift`, `Sources/NotchCore/ScreenDescriptor.swift`, `Sources/NotchCore/NotchGeometry.swift`
- Test: `Tests/NotchCoreTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:

```swift
public struct ScreenDescriptor: Equatable, Sendable {
    public var frame: CGRect            // toạ độ toàn cục, gốc dưới trái
    public var safeAreaTop: CGFloat
    public var auxLeftWidth: CGFloat?
    public var auxRightWidth: CGFloat?
    public var menuBarHeight: CGFloat
    public init(frame: CGRect, safeAreaTop: CGFloat, auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?, menuBarHeight: CGFloat)
}

public struct NotchGeometry: Equatable, Sendable {
    public static let virtualNotchWidth: CGFloat = 180
    public static let minimumVirtualNotchHeight: CGFloat = 24
    public static let hoverPadding: CGFloat = 4
    public static let defaultOpenSize = CGSize(width: 640, height: 200)
    public let screen: ScreenDescriptor
    public init(screen: ScreenDescriptor)
    public var hasPhysicalNotch: Bool { get }
    public var closedRect: CGRect { get }
    public var hoverRect: CGRect { get }                       // closedRect nới 4 điểm mọi phía
    public func openRect(size: CGSize = NotchGeometry.defaultOpenSize) -> CGRect
    public func openHitRect(size: CGSize = NotchGeometry.defaultOpenSize) -> CGRect  // openRect cao thêm 4 điểm lên trên
}
```

- [ ] **Step 1: Tạo `Package.swift`** với product thư viện `NotchCore`, target `NotchCore` và test target `NotchCoreTests`. Hai target còn lại được thêm ở Task 5 và 6.

- [ ] **Step 2: Viết test thất bại** trong `NotchGeometryTests.swift`:

```swift
let notched = ScreenDescriptor(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                               safeAreaTop: 32, auxLeftWidth: 663.5, auxRightWidth: 663.5, menuBarHeight: 32)
let plain = ScreenDescriptor(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                             safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 25)

@Test func physicalNotchClosedRect() {
    let g = NotchGeometry(screen: notched)
    #expect(g.hasPhysicalNotch)
    #expect(g.closedRect == CGRect(x: 663.5, y: 950, width: 185, height: 32))
}
@Test func virtualNotchClosedRect() {
    let g = NotchGeometry(screen: plain)
    #expect(!g.hasPhysicalNotch)
    #expect(g.closedRect == CGRect(x: 1190, y: 1415, width: 180, height: 25))
}
@Test func virtualNotchUsesMinimumHeightWhenMenuBarHidden() {
    var s = plain; s.menuBarHeight = 0
    #expect(NotchGeometry(screen: s).closedRect == CGRect(x: 1190, y: 1416, width: 180, height: 24))
}
@Test func safeAreaWithoutAuxAreasIsNotAPhysicalNotch() {
    var s = notched; s.auxLeftWidth = nil
    #expect(!NotchGeometry(screen: s).hasPhysicalNotch)
}
@Test func hoverRectPadsAllSides() {
    #expect(NotchGeometry(screen: notched).hoverRect == CGRect(x: 659.5, y: 946, width: 193, height: 40))
}
@Test func openRectIsCenteredOnNotchAndPinnedToTop() {
    #expect(NotchGeometry(screen: notched).openRect() == CGRect(x: 436, y: 782, width: 640, height: 200))
}
@Test func openHitRectExtendsAboveTop() {
    #expect(NotchGeometry(screen: notched).openHitRect() == CGRect(x: 436, y: 782, width: 640, height: 204))
}
@Test func openRectOnSecondaryScreenWithNegativeOrigin() {
    var s = plain; s.frame.origin = CGPoint(x: -2560, y: 200)
    let g = NotchGeometry(screen: s)
    #expect(g.closedRect == CGRect(x: -1370, y: 1615, width: 180, height: 25))
    #expect(g.openRect() == CGRect(x: -1600, y: 1440, width: 640, height: 200))
}
@Test func openRectClampsWhenNotchIsOffCenter() {
    let s = ScreenDescriptor(frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
                             safeAreaTop: 30, auxLeftWidth: 50, auxRightWidth: 750, menuBarHeight: 30)
    #expect(NotchGeometry(screen: s).openRect().minX == 0)
}
@Test func openRectPinsLeftWhenScreenNarrowerThanPanel() {
    var s = plain; s.frame = CGRect(x: 100, y: 0, width: 500, height: 400)
    let r = NotchGeometry(screen: s).openRect()
    #expect(r.minX == 100)
    #expect(r.maxY == 400)
}
```

- [ ] **Step 3: Chạy và xác nhận thất bại.** Run: `swift test --filter NotchGeometryTests`. Expected: lỗi biên dịch vì chưa có `ScreenDescriptor`.

- [ ] **Step 4: Cài đặt `ScreenDescriptor` và `NotchGeometry`.** Kẹp ngang của `openRect`: `x = min(max(idealX, frame.minX), max(frame.maxX - width, frame.minX))`.

- [ ] **Step 5: Chạy và xác nhận qua.** Run: `swift test --filter NotchGeometryTests`. Expected: 10 test qua.

- [ ] **Step 6: Commit** với thông điệp `feat: add package scaffold and notch geometry`.

---

### Task 2: `NotchStateMachine`

**Files:**
- Create: `Sources/NotchCore/NotchStateMachine.swift`
- Test: `Tests/NotchCoreTests/NotchStateMachineTests.swift`

**Interfaces:**
- Produces:

```swift
public struct NotchStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable { case closed, hoverPending, open, closePending }
    public enum Event: Equatable, Sendable {
        case pointerMoved(inside: Bool), clicked(inside: Bool)
        case hoverDelayElapsed, closeDelayElapsed, forceOpen, forceClose
    }
    public enum Effect: Equatable, Sendable {
        case scheduleHoverTimer, cancelHoverTimer, scheduleCloseTimer, cancelCloseTimer, didOpen, didClose
    }
    public private(set) var state: State
    public var openOnHover: Bool
    public init(openOnHover: Bool = true)
    public var isPresented: Bool { get }      // open hoặc closePending
    public mutating func handle(_ event: Event) -> [Effect]
}
```

- [ ] **Step 1: Viết test thất bại.** Dùng helper `run(_ events: [Event], openOnHover: Bool = true) -> (NotchStateMachine.State, [[Effect]])`. Mỗi dòng của bảng trong spec là một test, cộng thêm `forceOpen`:

| Test | Chuỗi sự kiện | Trạng thái cuối | Hiệu ứng của sự kiện cuối |
|---|---|---|---|
| `hoverStartsTimer` | moved(in) | hoverPending | [scheduleHoverTimer] |
| `hoverIgnoredWhenDisabled` | moved(in), `openOnHover: false` | closed | [] |
| `clickOpensFromClosed` | clicked(in) | open | [didOpen] |
| `clickOpensEvenWhenHoverDisabled` | clicked(in), `openOnHover: false` | open | [didOpen] |
| `leavingCancelsHover` | moved(in), moved(out) | closed | [cancelHoverTimer] |
| `hoverDelayOpens` | moved(in), hoverDelayElapsed | open | [didOpen] |
| `clickDuringHoverOpens` | moved(in), clicked(in) | open | [cancelHoverTimer, didOpen] |
| `leavingOpenStartsCloseTimer` | clicked(in), moved(out) | closePending | [scheduleCloseTimer] |
| `clickOutsideClosesImmediately` | clicked(in), clicked(out) | closed | [didClose] |
| `returningCancelsClose` | clicked(in), moved(out), moved(in) | open | [cancelCloseTimer] |
| `closeDelayCloses` | clicked(in), moved(out), closeDelayElapsed | closed | [didClose] |
| `clickOutsideWhileClosePending` | clicked(in), moved(out), clicked(out) | closed | [cancelCloseTimer, didClose] |
| `forceCloseFromOpen` | clicked(in), forceClose | closed | [didClose] |
| `forceCloseFromClosePending` | clicked(in), moved(out), forceClose | closed | [cancelCloseTimer, didClose] |
| `forceCloseFromHoverPending` | moved(in), forceClose | closed | [cancelHoverTimer] |
| `forceOpenFromClosed` | forceOpen | open | [didOpen] |
| `forceOpenFromHoverPending` | moved(in), forceOpen | open | [cancelHoverTimer, didOpen] |
| `forceOpenFromClosePending` | clicked(in), moved(out), forceOpen | open | [cancelCloseTimer] |

Các test về sự kiện phải bị bỏ qua (trạng thái không đổi, hiệu ứng rỗng):

| Test | Chuỗi sự kiện | Trạng thái cuối |
|---|---|---|
| `staleHoverTimerIgnoredWhenClosed` | hoverDelayElapsed | closed |
| `staleHoverTimerIgnoredWhenOpen` | clicked(in), hoverDelayElapsed | open |
| `staleCloseTimerIgnoredWhenOpen` | clicked(in), closeDelayElapsed | open |
| `clickInsideOpenIsIgnored` | clicked(in), clicked(in) | open |
| `clickOutsideClosedIsIgnored` | clicked(out) | closed |
| `repeatedMovesInsideDoNotRescheduleHover` | moved(in), moved(in) | hoverPending |
| `repeatedMovesOutsideDoNotRescheduleClose` | clicked(in), moved(out), moved(out) | closePending |
| `forceOpenWhenOpenIsIgnored` | clicked(in), forceOpen | open |
| `forceCloseWhenClosedIsIgnored` | forceClose | closed |

Review Focus 1:

```swift
@Test func rapidInOutNeverLeavesTwoHoverTimers() {
    let (state, effects) = run([.pointerMoved(inside: true), .pointerMoved(inside: false),
                                .pointerMoved(inside: true), .pointerMoved(inside: false),
                                .pointerMoved(inside: true)])
    #expect(state == .hoverPending)
    #expect(effects == [[.scheduleHoverTimer], [.cancelHoverTimer], [.scheduleHoverTimer],
                        [.cancelHoverTimer], [.scheduleHoverTimer]])
}
```

Thêm `isPresentedReflectsOpenAndClosePending`: sai khi `closed` và `hoverPending`, đúng khi `open` và `closePending`.

- [ ] **Step 2: Chạy và xác nhận thất bại.** Run: `swift test --filter NotchStateMachineTests`. Expected: lỗi biên dịch.

- [ ] **Step 3: Cài đặt `handle(_:)`** bằng một `switch (state, event)` duy nhất, nhánh `default` trả về `[]`.

- [ ] **Step 4: Chạy và xác nhận qua.** Run: `swift test --filter NotchStateMachineTests`. Expected: 29 test qua.

- [ ] **Step 5: Commit** với thông điệp `feat: add notch state machine`.

---

### Task 3: `PageRegistry` và `SwipeAccumulator`

**Files:**
- Create: `Sources/NotchCore/PageRegistry.swift`, `Sources/NotchCore/SwipeAccumulator.swift`
- Test: `Tests/NotchCoreTests/PageRegistryTests.swift`, `Tests/NotchCoreTests/SwipeAccumulatorTests.swift`

**Interfaces:**
- Produces:

```swift
public struct PageDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let titleKey: String
    public let symbolName: String
    public init(id: String, titleKey: String, symbolName: String)
}
public struct PageRegistry: Equatable, Sendable {
    public private(set) var pages: [PageDescriptor]
    public private(set) var selectedID: String?
    public init()
    public mutating func register(_ page: PageDescriptor)
    public mutating func select(_ id: String)
    public mutating func selectNext()
    public mutating func selectPrevious()
}
public struct SwipeAccumulator: Sendable {
    public enum Direction: Equatable, Sendable { case next, previous }
    public enum Phase: Equatable, Sendable { case began, changed, ended, cancelled, momentum }
    public static let threshold: CGFloat = 40
    public init()
    public mutating func add(deltaX: CGFloat, deltaY: CGFloat, phase: Phase) -> Direction?
}
```

- [ ] **Step 1: Viết test thất bại cho `PageRegistry`.** Với `a`, `b`, `c` là ba descriptor:
  - `emptyRegistryHasNoSelection`: `pages.isEmpty`, `selectedID == nil`.
  - `firstRegisteredPageIsSelected`: đăng ký `a`, `b` thì `selectedID == "a"`, thứ tự `["a","b"]`.
  - `duplicateIDIsIgnored`: đăng ký `a` hai lần (lần hai khác `titleKey`) thì còn một trang và giữ `titleKey` đầu.
  - `selectUnknownIDIsIgnored`: `select("zzz")` giữ `selectedID == "a"`.
  - `selectNextWrapsAround`: từ `c` gọi `selectNext()` về `a`.
  - `selectPreviousWrapsAround`: từ `a` gọi `selectPrevious()` về `c`.
  - `navigationIsNoOpWithFewerThanTwoPages`: rỗng và một trang đều không đổi sau `selectNext()`, `selectPrevious()`.

- [ ] **Step 2: Viết test thất bại cho `SwipeAccumulator`.**
  - `belowThresholdEmitsNothing`: began(-10), changed(-20) trả về `nil` cả hai.
  - `swipeLeftEmitsNext`: began(-10), changed(-30) thì lần hai trả về `.next`.
  - `swipeRightEmitsPrevious`: began(15), changed(30) thì lần hai trả về `.previous`.
  - `emitsOnlyOncePerGesture`: sau khi đã phát, thêm changed(-100) trả về `nil`.
  - `newGestureCanEmitAgain`: sau ended rồi began(-50) trả về `.next`.
  - `endedResetsPartialProgress`: began(-30), ended, began(-30) trả về `nil` ở lần cuối.
  - `cancelledResetsPartialProgress`: tương tự với cancelled.
  - `verticalScrollIsIgnored`: began(x: -45, y: 80) trả về `nil`.
  - Review Focus 2, `momentumAfterGestureDoesNotEmit`: began(-50) phát `.next`, ended, rồi ba lần momentum(-60) đều trả về `nil`.

- [ ] **Step 3: Chạy và xác nhận thất bại.** Run: `swift test --filter "PageRegistryTests|SwipeAccumulatorTests"`. Expected: lỗi biên dịch.

- [ ] **Step 4: Cài đặt hai kiểu.** `SwipeAccumulator` giữ `sumX`, `sumY`, `fired`. `began` đặt lại rồi cộng; `changed` cộng; `ended` và `cancelled` đặt lại và trả `nil`; `momentum` không cộng và trả `nil`. Phát khi `abs(sumX) >= threshold && abs(sumX) > abs(sumY) && !fired`; `sumX` âm là `.next`.

- [ ] **Step 5: Chạy và xác nhận qua.** Expected: 16 test qua.

- [ ] **Step 6: Commit** với thông điệp `feat: add page registry and swipe accumulator`.

---

### Task 4: `ShellSettingsStore`

**Files:**
- Create: `Sources/NotchCore/ShellSettingsStore.swift`
- Test: `Tests/NotchCoreTests/ShellSettingsStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public struct ShellSettingsStore {
    public enum Key { public static let openOnHover = "shell.openOnHover", hoverDelay = "shell.hoverDelay", hapticsEnabled = "shell.hapticsEnabled" }
    public static let hoverDelayRange: ClosedRange<Double> = 0...0.5
    public static let defaultHoverDelay: Double = 0.10
    public static let closeDelay: Double = 0.25
    public init(defaults: UserDefaults)
    public var openOnHover: Bool { get nonmutating set }
    public var hoverDelay: Double { get nonmutating set }
    public var hapticsEnabled: Bool { get nonmutating set }
}
```

- [ ] **Step 1: Viết test thất bại.** Mỗi test tạo `UserDefaults(suiteName: "aranotch.tests.\(UUID())")` và xoá suite khi xong.
  - `defaultsWhenEmpty`: `openOnHover == true`, `hoverDelay == 0.10`, `hapticsEnabled == true`.
  - `valuesRoundTripThroughANewStore`: ghi `false`, `0.3`, `false` rồi tạo store mới trên cùng `UserDefaults` và đọc lại đúng.
  - `hoverDelayIsClampedOnWrite`: ghi `2` đọc ra `0.5`; ghi `-1` đọc ra `0`.
  - `hoverDelayIsClampedOnRead`: `defaults.set(9.0, forKey: Key.hoverDelay)` đọc ra `0.5`.
  - Review Focus 3, `wrongTypesFallBackToDefaults`: đặt chuỗi `"abc"` vào cả ba khoá thì đọc ra ba giá trị mặc định.
  - Review Focus 3, `nanHoverDelayFallsBackToDefault`: đặt `Double.nan` vào khoá thì đọc ra `0.10`; ghi `Double.nan` qua setter rồi đọc ra `0.10`.

- [ ] **Step 2: Chạy và xác nhận thất bại.** Run: `swift test --filter ShellSettingsStoreTests`.

- [ ] **Step 3: Cài đặt.** Đọc bằng `defaults.object(forKey:) as? Bool` và `as? Double` để phân biệt thiếu khoá với sai kiểu.

- [ ] **Step 4: Chạy và xác nhận qua.** Expected: 6 test qua. Sau đó chạy `swift test` toàn bộ. Expected: 61 test qua.

- [ ] **Step 5: Commit** với thông điệp `feat: add shell settings store`.

---

### Task 5: Target `NotchShell`

Target này nối logic với AppKit nên không có test đơn vị; được kiểm chứng trên app thật ở Task 7.

**Files:**
- Modify: `Package.swift` (thêm target `NotchShell` phụ thuộc `NotchCore`)
- Create: mọi file trong `Sources/NotchShell/` theo bảng File Structure

**Interfaces:**
- Consumes: toàn bộ API công khai của Task 1 đến 4.
- Produces:

```swift
public enum L10n { public static func string(_ key: String) -> String }   // NSLocalizedString trên Bundle.main

@MainActor public final class ShellSettings: ObservableObject {
    @Published public var openOnHover: Bool
    @Published public var hoverDelay: Double
    @Published public var hapticsEnabled: Bool
    public init(store: ShellSettingsStore)        // mỗi thay đổi được ghi ngay vào store
}

public struct NotchPage: Identifiable {
    public let descriptor: PageDescriptor
    public var id: String { get }
    public init<V: View>(id: String, titleKey: String, symbolName: String, @ViewBuilder content: @escaping @MainActor () -> V)
}

extension ScreenDescriptor { @MainActor public init(screen: NSScreen) }

@MainActor public final class NotchController {
    public init(settings: ShellSettings)
    public var onOpenSettings: (() -> Void)?
    public private(set) var geometry: NotchGeometry?
    public func register(page: NotchPage)
    public func start()
    public func open()
    public func close()
}
```

- [ ] **Step 1: `NSScreen+Descriptor.swift`.** `auxLeftWidth` và `auxRightWidth` lấy từ `auxiliaryTopLeftArea?.width` và `auxiliaryTopRightArea?.width`; `menuBarHeight = frame.maxY - visibleFrame.maxY`.

- [ ] **Step 2: `NotchPanel.swift`.** `styleMask: [.borderless, .nonactivatingPanel]`, `level = .mainMenu + 3`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `isMovable = false`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = true` lúc tạo, `canBecomeKey` và `canBecomeMain` trả `false`.

- [ ] **Step 3: `PointerMonitor.swift`.** Lớp `@MainActor` với `onMove: ((CGPoint) -> Void)?`, `onClick: ((CGPoint) -> Void)?`, `onScroll: ((NSEvent) -> Void)?`, `start()`, `stop()`. Bộ theo dõi toàn cục và cục bộ cho `[.mouseMoved, .leftMouseDragged, .leftMouseDown]`; bộ theo dõi cục bộ cho `.scrollWheel`. Vị trí lấy từ `NSEvent.mouseLocation`. Bộ theo dõi cục bộ luôn trả lại sự kiện.

- [ ] **Step 4: `NotchShape.swift`.** `Shape` có `bottomRadius` và `earRadius`, khai báo `animatableData` là `AnimatablePair` của hai giá trị đó. Đường viền: bắt đầu tại góc trên trái, cong lõm vào trong bằng `earRadius`, đi xuống, bo góc dưới bằng `bottomRadius`, đối xứng bên phải. Thân hình rộng `rect.width - 2 * earRadius`.

- [ ] **Step 5: `NotchViewModel.swift` và `NotchPage.swift`.** View model `@MainActor` `ObservableObject` với `@Published` `isOpen`, `registry`, `closedSize`, `openSize`, `hasPhysicalNotch`; từ điển `pages: [String: NotchPage]`; `onOpenSettings`.

- [ ] **Step 6: `NotchRootView.swift`.** `ZStack(alignment: .top)` trong khung bằng `openSize`. Hình đen có kích thước `closedSize` khi đóng và `openSize` khi mở; `bottomRadius` 8 khi đóng, 22 khi mở; `earRadius` 6. Hàng đầu bảng cao `closedSize.height`: nút tab bên trái, khoảng trống rộng `closedSize.width` ở giữa khi `hasPhysicalNotch`, nút bánh răng bên phải. Nội dung trang nằm dưới, đệm 14. Hàng đầu bảng và nội dung có `opacity` 0 khi đóng. Animation: `.spring(response: 0.36, dampingFraction: 0.82)` theo `isOpen`. Ép `colorScheme` tối.

- [ ] **Step 7: `NotchController.swift`.**
  - `start()`: chọn màn hình (`NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main`), dựng panel với `NSHostingView`, đặt khung bằng `openRect()`, `orderFrontRegardless()`, khởi động `PointerMonitor`, đăng ký `NSApplication.didChangeScreenParametersNotification`.
  - Sự kiện con trỏ: tính `inside` theo `stateMachine.isPresented` (`openHitRect` nếu đúng, `hoverRect` nếu sai), gọi `handle`, rồi thực hiện từng hiệu ứng.
  - Hiệu ứng: hai bộ hẹn giờ một lần dùng `settings.hoverDelay` và `ShellSettingsStore.closeDelay`; `didOpen` đặt `viewModel.isOpen = true`, `panel.ignoresMouseEvents = false`, rung nếu bật, bật lưới an toàn; `didClose` làm ngược lại.
  - Lưới an toàn: `Timer` 1/15 giây gửi `.pointerMoved` với `NSEvent.mouseLocation`; chạy khi trạng thái khác `closed`, dừng khi về `closed`. Bật cả khi vào `hoverPending`.
  - Cuộn: khi đang mở, đổi `NSEvent.phase` và `momentumPhase` sang `SwipeAccumulator.Phase` rồi gọi `registry.selectNext()` hoặc `selectPrevious()`.
  - `settings.$openOnHover` được đồng bộ vào `stateMachine.openOnHover`.
  - Đổi cấu hình màn hình: gửi `.forceClose`, tính lại hình học, đặt lại khung; nếu không còn màn hình thì `orderOut`.

- [ ] **Step 8: Build.** Run: `swift build`. Expected: `Build complete!` không có lỗi hay cảnh báo concurrency.

- [ ] **Step 9: Commit** với thông điệp `feat: add notch shell window, pointer tracking and views`.

---

### Task 6: Chương trình `AraNotch` và script build

**Files:**
- Modify: `Package.swift` (thêm `executableTarget` `AraNotch` phụ thuộc `NotchShell`)
- Create: mọi file trong `Sources/AraNotch/`, `Resources/`, `Scripts/`

**Interfaces:**
- Consumes: `NotchController`, `ShellSettings`, `NotchPage`, `L10n`, `ShellSettingsStore`.

- [ ] **Step 1: `Resources/Info.plist`.** `CFBundleIdentifier = com.aranotch.app`, `CFBundleName = AraNotch`, `CFBundleExecutable = AraNotch`, `CFBundleShortVersionString = 0.1.0`, `CFBundleVersion = 1`, `CFBundlePackageType = APPL`, `LSUIElement = true`, `LSMinimumSystemVersion = 15.0`, `CFBundleDevelopmentRegion = en`, `CFBundleLocalizations = [en, vi]`, `NSHighResolutionCapable = true`.

- [ ] **Step 2: Hai file `Localizable.strings`** với cùng bộ khoá:

| Khoá | en | vi |
|---|---|---|
| `menu.settings` | Settings… | Cài đặt… |
| `menu.quit` | Quit AraNotch | Thoát AraNotch |
| `page.welcome.title` | Welcome | Chào mừng |
| `page.about.title` | About | Thông tin |
| `welcome.headline` | AraNotch is running | AraNotch đang chạy |
| `welcome.body` | Features will appear here as pages. Swipe sideways or use the tabs to switch. | Các tính năng sẽ xuất hiện ở đây dưới dạng trang. Vuốt ngang hoặc bấm tab để chuyển. |
| `about.version` | Version | Phiên bản |
| `about.notch` | Notch | Notch |
| `about.notch.physical` | Physical | Vật lý |
| `about.notch.virtual` | Virtual | Ảo |
| `about.size` | Size | Kích thước |
| `notch.settings.tooltip` | Settings | Cài đặt |
| `settings.title` | AraNotch Settings | Cài đặt AraNotch |
| `settings.section.general` | General | Chung |
| `settings.openOnHover` | Open the notch on hover | Mở notch khi rê chuột |
| `settings.hoverDelay` | Hover delay | Độ trễ rê chuột |
| `settings.haptics` | Haptic feedback when opening | Rung phản hồi khi mở |

- [ ] **Step 3: Mã nguồn app.**
  - `main.swift`: tạo `NSApplication.shared`, gán `AppDelegate`, `run()`.
  - `AppDelegate`: `setActivationPolicy(.accessory)`; `ShellSettings(store: ShellSettingsStore(defaults: .standard))`; `NotchController`; đăng ký trang `welcome` (symbol `sparkles`) rồi `about` (symbol `info.circle`); `controller.onOpenSettings` mở Cài đặt; `controller.start()`; nếu `CommandLine.arguments.contains("--open-on-launch")` thì gọi `controller.open()`; nếu có `--show-settings` thì mở Cài đặt.
  - `StatusItemController`: `NSStatusItem` độ dài vuông, ảnh SF Symbol `rectangle.topthird.inset.filled`, menu hai mục theo bảng chuỗi.
  - `SettingsWindowController`: một `NSWindow` duy nhất dùng lại, 420×220, tiêu đề `settings.title`, `isReleasedWhenClosed = false`; khi mở thì `NSApp.activate(ignoringOtherApps: true)` và `makeKeyAndOrderFront`.
  - `SettingsView`: `Form` kiểu `.grouped` với `Toggle` cho `openOnHover`, `Slider` cho `hoverDelay` trong `ShellSettingsStore.hoverDelayRange` bước 0,05 (bị vô hiệu khi `openOnHover` tắt) kèm nhãn hiện số giây, `Toggle` cho `hapticsEnabled`.
  - `Pages.swift`: `WelcomePage` hiện `welcome.headline` và `welcome.body`; `AboutPage` nhận `NotchGeometry?` và hiện phiên bản từ `Bundle.main`, loại notch và kích thước `closedRect` dạng `185 × 32`.

- [ ] **Step 4: `Scripts/build-app.sh`.** Nhận tham số `debug` (mặc định) hoặc `release`. Các bước: `swift build -c "$CONFIG" --product AraNotch`; xoá và tạo lại `build/AraNotch.app/Contents/{MacOS,Resources}`; chép file thực thi từ `$(swift build -c "$CONFIG" --show-bin-path)`; chép `Info.plist` và hai thư mục `.lproj`; `codesign --force --sign - build/AraNotch.app`. Dùng `set -euo pipefail` và chạy từ gốc repo bất kể thư mục hiện tại.

- [ ] **Step 5: `Scripts/run.sh`.** `pkill -x AraNotch || true`, gọi `build-app.sh`, rồi `open build/AraNotch.app --args "$@"`.

- [ ] **Step 6: Build và kiểm tra bundle.** Run: `Scripts/build-app.sh && codesign --verify --verbose build/AraNotch.app && plutil -lint build/AraNotch.app/Contents/Info.plist`. Expected: `valid on disk` và `OK`.

- [ ] **Step 7: Commit** với thông điệp `feat: add AraNotch app target, settings window and build scripts`.

---

### Task 7: Kiểm chứng trên app thật

**Files:**
- Modify: bất kỳ file nào cần sửa theo kết quả kiểm chứng.

- [ ] **Step 1: Chạy toàn bộ test.** Run: `swift test`. Expected: 61 test qua.
- [ ] **Step 2: Khởi động.** Run: `Scripts/run.sh`. Expected: tiến trình `AraNotch` còn sống sau 3 giây (`pgrep -x AraNotch`), không có bản ghi crash mới trong `~/Library/Logs/DiagnosticReports`.
- [ ] **Step 3: Kiểm tra cửa sổ.** Liệt kê cửa sổ của tiến trình bằng `CGWindowListCopyWindowInfo`. Expected: một cửa sổ 640×200 căn giữa mép trên màn hình có notch, layer bằng `NSWindow.Level.mainMenu + 3`.
- [ ] **Step 4: Tiêu chí 2 và 3.** Chụp màn hình: không có icon Dock, có icon thanh menu, notch đóng không nhìn thấy. Bấm được một mục trên thanh menu nằm cạnh notch.
- [ ] **Step 5: Tiêu chí 4.** Đưa con trỏ vào notch, chụp màn hình thấy bảng mở với trang Chào mừng. Đưa con trỏ ra xa, sau 1 giây chụp màn hình thấy bảng đã đóng.
- [ ] **Step 6: Tiêu chí 5.** Mở bảng, bấm tab Thông tin, chụp màn hình thấy kích thước notch `185 × 32`.
- [ ] **Step 7: Tiêu chí 6.** Mở Cài đặt, tắt "mở khi rê chuột", xác nhận rê chuột không mở nữa nhưng bấm vẫn mở. Thoát và chạy lại, xác nhận cài đặt còn nguyên. Bật lại cài đặt về mặc định.
- [ ] **Step 8: Ngôn ngữ.** Chạy với `-AppleLanguages "(vi)"` và chụp cửa sổ Cài đặt thấy chuỗi tiếng Việt.
- [ ] **Step 9: Commit** các sửa đổi phát sinh, mỗi lỗi một commit có mô tả nguyên nhân.
