import IOKit.pwr_mgt
import NotchShell
import SwiftUI
import SystemEventsCore

/// Keeps the Mac and its display awake for a while (`KeepAwakeSession`). While it runs, a
/// yellow cup and the time left rest beside the closed notch; the tools page shows it too,
/// through `onChange`.
@MainActor
public final class KeepAwakeController {
    private let notch: NotchController
    private var session: KeepAwakeSession?
    private var assertion: IOPMAssertionID = 0
    private var ticker: Timer?
    private static let restingID = "keepAwake"

    /// What to show on the tools page: the time left, or nil when off.
    public var onChange: ((String?) -> Void)?

    public init(notch: NotchController) {
        self.notch = notch
    }

    /// One click on the tool: the next length, or off after the last.
    public func step() {
        set(KeepAwakeSession.next(after: session, now: Date()))
    }

    public func stop() {
        set(nil)
    }

    private func set(_ new: KeepAwakeSession?) {
        session = new
        if new != nil, assertion == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "AraNotch keeps the Mac awake" as CFString, &id) == kIOReturnSuccess {
                assertion = id
            }
        } else if new == nil, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
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

    private func refresh() {
        let now = Date()
        if let session, session.isOver(at: now) {
            set(nil)
            return
        }
        guard let session else {
            notch.setRestingActivity(nil, id: Self.restingID)
            onChange?(nil)
            return
        }
        let left = session.left(at: now)
        onChange?(left)
        // The yellow cup and a ring that empties as the time runs out; full without an end.
        let activity = NotchLiveActivity(
            id: Self.restingID, priority: 1, duration: 0, pageID: "tools",
            glance: AraGlance(.cup, color: .awake, value: .ring(session.remaining(at: now))),
            detail: "\(L10n.string("tools.awake")) · \(left)")
        notch.setRestingActivity(activity, id: Self.restingID)
    }
}
