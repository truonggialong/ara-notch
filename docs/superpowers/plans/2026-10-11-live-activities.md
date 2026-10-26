# Live Activities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notch đang đóng nở sang hai bên để báo sự kiện nguồn điện, Caps Lock và mạng.

**Architecture:** Hàng đợi hoạt động và hình học nằm trong `NotchCore`; `NotchShell` vẽ và hẹn giờ. Bộ dò sự kiện là kiểu giá trị thuần trong target mới `SystemEventsCore`; `SystemEventsFeature` đọc IOKit, cờ phím và `NWPathMonitor` rồi gọi `NotchController.present`.

**Tech Stack:** Swift 6, IOKit.ps, Network, AppKit, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-live-activities-design.md`

## Global Constraints

- `NotchCore` và `SystemEventsCore` không import AppKit, SwiftUI, IOKit hay Network.
- Hằng số từ spec: hàng chờ tối đa 3; bề rộng mỗi bên 92; ngưỡng pin 20 và 10; mất mạng 3 giây; đọc Caps Lock mỗi 0,3 giây; thời hạn và ưu tiên theo bảng.
- Không cần quyền hệ thống nào. Không dùng macro SwiftUI.
- Sự kiện giả cho kiểm chứng đi qua `SystemEventsController`, không thay đổi trạng thái thật của máy.
- Chuỗi hiển thị có đủ `en` và `vi`. Chạy test bằng `Scripts/test.sh`. Mỗi task kết thúc bằng một commit.

## Review Focus

1. **Hàng chờ đầy:** yêu cầu thứ tư phải đẩy đúng cái ưu tiên thấp nhất, cũ nhất ra. Test ở Task 1.
2. **Cùng `id` lặp lại:** làm mới thời hạn, không nhân đôi trong hàng. Test ở Task 1.
3. **Pin dao động quanh ngưỡng:** 21 → 20 → 21 → 20 chỉ báo một lần. Test ở Task 3.
4. **Khởi động khi đã ở trạng thái xấu:** pin 8% lúc mở app, hoặc đang mất mạng lúc mở app. Test ở Task 3.
5. **Mạng chập chờn:** mất 2 giây rồi có lại, lặp nhiều lần, không báo gì. Test ở Task 3.

---

### Task 1: `LiveActivityQueue` và `compactRect`

**Files:** Create `Sources/NotchCore/LiveActivityQueue.swift`; Modify `Sources/NotchCore/NotchGeometry.swift`; Test `Tests/NotchCoreTests/LiveActivityQueueTests.swift`, bổ sung `NotchGeometryTests.swift`

**Interfaces — Produces:**

```swift
public struct LiveActivityRequest: Equatable, Sendable {
    public let id: String
    public let priority: Int
    public let duration: TimeInterval
    public init(id: String, priority: Int, duration: TimeInterval)
}
public struct LiveActivityQueue: Sendable {
    public static let maxWaiting = 3
    public init()
    public private(set) var current: LiveActivityRequest?
    public var waitingIDs: [String] { get }
    public var nextDeadline: Date? { get }
    public mutating func present(_ request: LiveActivityRequest, at now: Date)
    public mutating func advance(to now: Date)
    public mutating func dismiss(id: String)
}
extension NotchGeometry {
    public static let defaultActivitySideWidth: CGFloat = 92
    public func compactRect(sideWidth: CGFloat = NotchGeometry.defaultActivitySideWidth) -> CGRect
}
```

- [ ] **Step 1: Test thất bại.** `presentsImmediatelyWhenIdle`; `expiresAfterDuration` (trước hạn vẫn hiện, đúng hạn thì hết); `sameIDRefreshesDeadline`; `higherPriorityReplacesCurrent` (cái cũ không quay lại); `equalPriorityReplacesCurrent`; `lowerPriorityWaitsThenShows` (thời hạn tính từ lúc được hiện); `waitingOrderIsPriorityThenArrival`; `waitingSameIDIsReplacedNotDuplicated`; `fullWaitingListDropsLowestOldest`; `dismissCurrentPromotesNext`; `dismissWaiting`; `dismissUnknownIsIgnored`; `nextDeadlineIsNilWhenIdle`; `advanceSkipsSeveralExpired` (gọi `advance` rất muộn: cái chờ được hiện với hạn tính từ lúc gọi). Hình học: `compactRect` cho màn hình có notch là `(571.5, 950, 369, 32)`; cho màn hình thường căn giữa.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua.
- [ ] **Step 5:** Commit `feat: add live activity queue and compact notch geometry`.

---

### Task 2: Vẽ hoạt động trong khung notch

**Files:** Create `Sources/NotchShell/NotchLiveActivity.swift`; Modify `NotchViewModel.swift`, `NotchRootView.swift`, `NotchController.swift`

**Interfaces — Produces:**

```swift
public struct NotchLiveActivity {
    public let request: LiveActivityRequest
    public init<L: View, T: View>(id: String, priority: Int, duration: TimeInterval,
                                  @ViewBuilder leading: @escaping @MainActor () -> L,
                                  @ViewBuilder trailing: @escaping @MainActor () -> T)
}
extension NotchController {
    public func present(_ activity: NotchLiveActivity)
    public func dismissActivity(id: String)
}
```

- [ ] **Step 1:** View model thêm `@Published var activity: NotchLiveActivity?` và `activitySideWidth`.
- [ ] **Step 2:** `NotchRootView`: khi đóng và có `activity`, hình có bề rộng `closedSize.width + 2 × sideWidth`; hai view nằm hai bên, căn giữa theo chiều dọc, đệm ngang 10; ẩn khi mở.
- [ ] **Step 3:** `NotchController`: giữ `LiveActivityQueue` và từ điển nội dung theo `id`; một `Timer` một lần tới `nextDeadline`; sau mỗi `present`, `dismiss`, hết hạn thì cập nhật `viewModel.activity`.
- [ ] **Step 4:** `swift build` sạch, `Scripts/test.sh` qua. Commit `feat: render live activities beside the closed notch`.

---

### Task 3: `SystemEventsCore`

**Files:** Modify `Package.swift`; Create `Sources/SystemEventsCore/PowerEventDetector.swift`, `CapsLockDetector.swift`, `ConnectivityDebouncer.swift`, `AlertSettingsStore.swift`; Test `Tests/SystemEventsCoreTests/*.swift` (kèm bản sao `InMemoryDefaults.swift`)

**Interfaces — Produces:**

```swift
public struct PowerSnapshot: Equatable, Sendable {
    public var hasBattery: Bool; public var isOnAC: Bool; public var isCharging: Bool; public var percent: Int
    public init(hasBattery: Bool = true, isOnAC: Bool, isCharging: Bool, percent: Int)
}
public enum PowerEvent: Equatable, Sendable { case pluggedIn(percent: Int), unplugged(percent: Int), low(percent: Int), full }
public struct PowerEventDetector: Sendable {
    public static let lowThresholds = [20, 10]
    public init()
    public mutating func update(_ snapshot: PowerSnapshot) -> [PowerEvent]
}
public enum CapsLockEvent: Equatable, Sendable { case on, off }
public struct CapsLockDetector: Sendable { public init(); public mutating func update(isOn: Bool) -> CapsLockEvent? }
public enum ConnectivityEvent: Equatable, Sendable { case offline, online }
public struct ConnectivityDebouncer: Sendable {
    public static let offlineDelay: TimeInterval = 3
    public init()
    public var nextDeadline: Date? { get }
    public mutating func update(isOnline: Bool, at now: Date) -> ConnectivityEvent?
    public mutating func advance(to now: Date) -> ConnectivityEvent?
}
public struct AlertSettingsStore {
    public enum Key { public static let power = "alerts.power", capsLock = "alerts.capsLock", network = "alerts.network" }
    public init(defaults: UserDefaults)
    public var power: Bool { get nonmutating set }
    public var capsLock: Bool { get nonmutating set }
    public var network: Bool { get nonmutating set }
}
```

- [ ] **Step 1: Test thất bại.**
  - Nguồn: `firstSnapshotIsSilent`; `plugAndUnplug`; `lowAt20ThenAt10` (25 → 20 → 15 → 10: hai lần `low`); `oscillationAroundThresholdAlertsOnce` (21, 20, 21, 20); `skippingPastBothThresholdsAlertsOnceWithLowest` (30 → 5: một lần `low(5)`); `pluggingInResetsLowAlerts`; `noLowAlertWhileOnAC`; `fullOncePerPlugIn` (99 → 100 → 100 một lần; rút, cắm lại ở 100: `pluggedIn` và `full`); `startingLowOnBatteryAlertsOnce` (lần đầu 8% dùng pin: `low(8)`); `startingFullOnACIsSilent`; `noBatteryIsSilent`.
  - Caps Lock: lần đầu không phát; đổi thì phát; lặp cùng giá trị không phát.
  - Mạng: `startOnlineIsSilent`; `offlineIsReportedAfter3Seconds` (qua `advance`); `flappingIsNotReported` (mất 2 giây rồi có lại, ba lần); `onlineAfterReportedOfflineIsImmediate`; `onlineBeforeDelayIsSilent`; `startingOfflineIsReportedAfterDelay`; `repeatedOfflineUpdatesDoNotExtendTheDelay`; `nextDeadline` đúng trong lúc chờ và `nil` khi không chờ.
  - Cài đặt: mặc định cả ba bật; ghi rồi đọc lại; sai kiểu trả bật.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua toàn bộ.
- [ ] **Step 5:** Commit `feat: add system event detectors`.

---

### Task 4: `SystemEventsFeature`

**Files:** Modify `Package.swift`; Create `Sources/SystemEventsFeature/PowerMonitor.swift`, `CapsLockMonitor.swift`, `NetworkMonitor.swift`, `AlertSettings.swift`, `SystemEventsController.swift`, `ActivityViews.swift`, `AlertSettingsSection.swift`

**Interfaces — Produces:**

```swift
@MainActor public final class AlertSettings: ObservableObject { public init(store: AlertSettingsStore) /* power, capsLock, network */ }
public enum SimulatedSystemEvent: String, CaseIterable, Sendable {
    case plug, unplug, low, full, capsOn = "caps-on", capsOff = "caps-off", offline, online
}
@MainActor public final class SystemEventsController {
    public init(settings: AlertSettings, notch: NotchController)
    public func start()
    public func makeSettingsSection() -> AnyView
    public func simulate(_ event: SimulatedSystemEvent)
}
```

- [ ] **Step 1:** Ba monitor theo spec. `PowerMonitor.read() -> PowerSnapshot` dùng `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription` với các khoá `kIOPSPowerSourceStateKey`, `kIOPSIsChargingKey`, `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`.
- [ ] **Step 2:** `SystemEventsController`: mỗi nguồn đưa dữ liệu vào bộ dò tương ứng; sự kiện ra được đổi thành `NotchLiveActivity` theo bảng trong spec, chỉ khi công tắc tương ứng bật. Tắt công tắc gọi `dismissActivity`. Lúc `start` ghi log trạng thái pin và mạng đọc được. `simulate` tạo thẳng hoạt động tương ứng, cũng tôn trọng công tắc.
- [ ] **Step 3:** `ActivityViews`: biểu tượng SF Symbol cỡ 13 và chữ cỡ 12 đậm vừa, màu theo bảng.
- [ ] **Step 4:** `AlertSettingsSection` với ba `Toggle`.
- [ ] **Step 5:** `swift build` sạch. Commit `feat: add power, caps lock and network alerts`.

---

### Task 5: Tích hợp

**Files:** Modify `Package.swift`, `Sources/AraNotch/AppDelegate.swift`, `LaunchArguments.swift`, `SettingsView.swift`, `SettingsWindowController.swift`, hai file `Localizable.strings`

- [ ] **Step 1:** Chuỗi: `settings.section.alerts`, `settings.alerts.power`, `settings.alerts.capsLock`, `settings.alerts.network`, `alert.capsLock.on`, `alert.capsLock.off`, `alert.network.offline`, `alert.network.online`.
- [ ] **Step 2:** `AppDelegate` tạo `SystemEventsController`, thêm mục Cài đặt. Tham số `--simulate-events "<danh sách>"`: mỗi sự kiện cách nhau 0,2 giây, bắt đầu sau 0,5 giây; ảnh chụp chờ tới sau sự kiện cuối 0,7 giây.
- [ ] **Step 3:** `Scripts/build-app.sh`. Commit `feat: integrate system alerts into the app`.

---

### Task 6: Kiểm chứng

- [ ] **Step 1:** `Scripts/test.sh` qua toàn bộ.
- [ ] **Step 2:** Một ảnh notch cho mỗi sự kiện giả: `plug`, `unplug`, `low`, `full`, `caps-on`, `caps-off`, `offline`, `online`, tiếng Việt.
- [ ] **Step 3:** Ưu tiên: `--simulate-events "offline,caps-on"` vẫn hiện mất mạng; `--simulate-events "caps-on,offline"` hiện mất mạng.
- [ ] **Step 4:** Log lúc khởi động có trạng thái pin và mạng thật; so với `pmset -g batt`.
- [ ] **Step 5:** Tắt `alerts.capsLock` bằng `defaults` tạm rồi `--simulate-events "caps-on"`: notch không nở. Xoá khoá sau khi thử.
- [ ] **Step 6:** Ảnh Cài đặt có mục Thông báo. Đo CPU của app khi rảnh trong 10 giây bằng `ps`.
- [ ] **Step 7:** Commit các sửa đổi phát sinh.
