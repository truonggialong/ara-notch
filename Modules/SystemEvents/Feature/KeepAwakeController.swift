import AppKit
import IOKit.pwr_mgt
import NotchShell
import SwiftUI
import SystemEventsCore

/// Keeps the Mac awake (`KeepAwakeSession`), the way the user chose: for a while, until a time,
/// while an app runs, or until the downloads are done; with the display awake too, or only the
/// Mac (`KeepAwakeSettings.allowsDisplaySleep`). A session stops on its own by `KeepAwakeRules`
/// (its end, a low battery, unplugging, the Mac put to sleep), reminds five minutes before it
/// ends with a way to extend it, and Triggers start one by themselves. While it runs, a yellow
/// cup and what is left rest beside the closed notch; the tools page shows it through `onChange`.
@MainActor
public final class KeepAwakeController {
    private let notch: NotchController
    public let settings: KeepAwakeSettings
    private var session: KeepAwakeSession?
    private var assertion: IOPMAssertionID = 0
    /// Whether the assertion held now lets the display sleep.
    private var assertionAllowsDisplaySleep = false
    private var ticker: Timer?
    private var triggerTimer: Timer?
    private var remindedFor: Date?
    /// A Trigger the user turned off by hand: it does not start again until its condition
    /// has stopped holding once.
    private var dismissedTrigger: String?
    private var observers: [NSObjectProtocol] = []
    private static let restingID = "keepAwake"
    private static let reminderID = "keepAwake.reminder"

    /// What to show on the tools page: what is left, or nil when off.
    public var onChange: ((String?) -> Void)?
    /// Whether files are downloading now, as the app's downloads say.
    public var isDownloading: () -> Bool = { false }

    public init(notch: NotchController, settings: KeepAwakeSettings) {
        self.notch = notch
        self.settings = settings
        settings.onChange = { [weak self] in self?.settingsChanged() }
    }

    /// Watches what Triggers and stop rules depend on. Call once.
    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        // Put to sleep anyway: the session ends with it, when the user wants that.
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.stopsOnSleep, self.session != nil else { return }
                self.set(nil)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        triggerTimer = timer
        check()
    }

    // MARK: Starting and stopping

    /// One click on the tool: the next length, or off after the last. A session of another
    /// kind (an app, the downloads, a Trigger) is stopped.
    public func step() {
        if let session, session.until != .time || session.ends == nil {
            stopByHand()
            return
        }
        set(KeepAwakeSession.next(after: session, now: Date()))
    }

    public func stop() {
        stopByHand()
    }

    /// Starts a session of the length chosen; nil minutes is without an end.
    public func keepAwake(minutes: Int?) {
        let length = minutes.map { TimeInterval($0 * 60) }
        set(KeepAwakeSession(ends: length.map { Date().addingTimeInterval($0) }, length: length))
    }

    public func keepAwake(untilMinutesOfDay minutes: Int) {
        set(KeepAwakeSession.until(minutesOfDay: minutes, now: Date()))
    }

    public func keepAwake(whileAppRuns app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        set(KeepAwakeSession(ends: nil, until: .app(bundleID: bundleID, name: app.localizedName ?? bundleID)))
    }

    public func keepAwakeUntilDownloadsFinish() {
        set(KeepAwakeSession(ends: nil, until: .downloads))
    }

    public func extend(byMinutes minutes: Int) {
        guard let session else { return }
        notch.dismissActivity(id: Self.reminderID)
        set(session.extended(byMinutes: minutes, now: Date()))
    }

    private func stopByHand() {
        if case let .trigger(id) = session?.until {
            dismissedTrigger = id
        }
        set(nil)
    }

    /// The display setting changed: the assertion running is held again the new way.
    public func settingsChanged() {
        if session != nil { holdAssertion() }
        check()
    }

    private func set(_ new: KeepAwakeSession?) {
        session = new
        remindedFor = nil
        if new != nil {
            holdAssertion()
        } else {
            releaseAssertion()
            notch.dismissActivity(id: Self.reminderID)
        }
        ticker?.invalidate()
        ticker = nil
        if new != nil {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        refresh()
    }

    private func holdAssertion() {
        let allows = settings.allowsDisplaySleep
        if assertion != 0, allows == assertionAllowsDisplaySleep { return }
        releaseAssertion()
        // Only the Mac, or the Mac and its display.
        let type = allows ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        var id: IOPMAssertionID = 0
        if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                       "AraNotch keeps the Mac awake" as CFString, &id) == kIOReturnSuccess {
            assertion = id
            assertionAllowsDisplaySleep = allows
        }
    }

    private func releaseAssertion() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

    // MARK: Rules

    private func conditions() -> KeepAwakeConditions {
        let power = PowerMonitor.read()
        let external = NSScreen.screens.filter { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id.map { CGDisplayIsBuiltin($0) == 0 } ?? false
        }.count
        return KeepAwakeConditions(
            batteryPercent: power.hasBattery ? power.percent : nil, isOnPower: power.isOnAC, externalDisplays: external,
            runningApps: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            downloading: isDownloading())
    }

    /// Looks at the Triggers and the stop rules now.
    private func check() {
        let now = Date()
        let state = conditions()
        let rules = KeepAwakeRules.Settings(settings.store)
        let wanted = KeepAwakeRules.trigger(conditions: state, settings: rules, now: now)
        if wanted != dismissedTrigger { dismissedTrigger = nil }
        if let wanted, wanted != dismissedTrigger, session == nil {
            set(KeepAwakeSession(ends: nil, until: .trigger(wanted)))
            return
        }
        if case let .trigger(running) = session?.until, running != wanted {
            set(nil)
            return
        }
        refresh()
    }

    private func refresh() {
        let now = Date()
        guard let session else {
            notch.setRestingActivity(nil, id: Self.restingID)
            onChange?(nil)
            return
        }
        if let stop = KeepAwakeRules.stop(
            session, conditions: conditions(), settings: KeepAwakeRules.Settings(settings.store), now: now) {
            set(nil)
            announce(stop)
            return
        }
        remindIfDue(session, now: now)
        let left = session.left(at: now)
        onChange?(left)
        notch.setRestingActivity(resting(session, left: left, now: now), id: Self.restingID)
    }

    /// The cup and what keeps it going: a ring that empties for a time, the app's icon, the
    /// download tray, or a light for a Trigger.
    private func resting(_ session: KeepAwakeSession, left: String, now: Date) -> NotchLiveActivity {
        let value: AraGlance.Value
        let detail: String
        switch session.until {
        case .time:
            value = .ring(session.remaining(at: now))
            detail = left
        case let .app(bundleID, name):
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            value = icon.map { .picture($0) } ?? .text(name)
            detail = String(format: L10n.string("keepAwake.whileApp"), name)
        case .downloads:
            value = .pictogram(.download)
            detail = L10n.string("keepAwake.untilDownloads")
        case let .trigger(id):
            value = .light(beating: false)
            detail = L10n.string(id.hasPrefix("app:") ? "keepAwake.trigger.app" : "keepAwake.trigger.\(id)")
        }
        let display = L10n.string(settings.allowsDisplaySleep ? "keepAwake.macOnly" : "keepAwake.withDisplay")
        return NotchLiveActivity(
            id: Self.restingID, priority: 1, duration: 0, pageID: "tools",
            glance: AraGlance(.cup, color: .awake, value: value, valueColor: .awake),
            detail: "\(L10n.string("tools.awake")) · \(detail) · \(display)")
    }

    /// Five minutes before a timed session ends: "5′ left", with buttons to add half an hour
    /// or an hour under the notch.
    private func remindIfDue(_ session: KeepAwakeSession, now: Date) {
        guard settings.remindsBeforeEnd, let at = KeepAwakeRules.reminder(for: session), now >= at,
              remindedFor != session.ends else { return }
        remindedFor = session.ends
        var notice = NotchLiveActivity(
            id: Self.reminderID, priority: 3, duration: 60, pageID: "tools",
            glance: AraGlance(.cup, color: .awake, motion: .blink, value: .text(session.left(at: now)), valueColor: .awake),
            detail: L10n.string("keepAwake.endsSoon"))
        notice.keepsSides = true
        notice.setBottom(height: 26) {
            KeepAwakeExtendRow { [weak self] minutes in self?.extend(byMinutes: minutes) }
        }
        notch.present(notice)
    }

    /// Says in one line why a session stopped on its own, when it was not just its time.
    private func announce(_ stop: KeepAwakeRules.Stop) {
        let text: String
        switch stop {
        case .timeUp: return
        case .appQuit: text = L10n.string("keepAwake.stopped.app")
        case .downloadsDone: text = L10n.string("keepAwake.stopped.downloads")
        case let .lowBattery(percent): text = String(format: L10n.string("keepAwake.stopped.battery"), percent)
        case .unplugged: text = L10n.string("keepAwake.stopped.unplugged")
        }
        let warns: Bool = switch stop { case .lowBattery, .unplugged: true; default: false }
        notch.present(NotchLiveActivity(
            id: "keepAwake.stopped", priority: 2, duration: 4, pageID: "tools",
            glance: AraGlance(.cup, color: warns ? .warning : .awake, value: .text(text), valueColor: warns ? .warning : nil),
            detail: text))
    }
}

/// "+30′" and "+1 giờ" under the notch, as the reminder's strip.
private struct KeepAwakeExtendRow: View {
    let extend: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            pill("+30\u{2032}", isMain: true) { extend(30) }
            pill(L10n.string("keepAwake.extendHour"), isMain: false) { extend(60) }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func pill(_ title: String, isMain: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isMain ? Color.black : AraPalette.ink)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(isMain ? AraNoticeColor.awake.color : Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AraPressStyle())
    }
}
