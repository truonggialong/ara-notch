import Foundation

/// A request to show something beside the closed notch for a while.
public struct LiveActivityRequest: Equatable, Sendable {
    public let id: String
    /// Higher numbers are more important.
    public let priority: Int
    public let duration: TimeInterval

    public init(id: String, priority: Int, duration: TimeInterval) {
        self.id = id
        self.priority = priority
        self.duration = duration
    }
}

/// Decides which live activity is showing. One shows at a time; less important ones wait.
/// Besides those that show for a while, one activity can rest beside the notch for as long
/// as it is true, such as "music is playing": it shows whenever nothing timed does.
public struct LiveActivityQueue: Sendable {
    public static let maxWaiting = 3

    /// What is showing: the timed activity, or failing that the resting one.
    public var current: LiveActivityRequest? { timed ?? (isRestingHidden ? nil : resting) }
    /// When the timed activity expires; nil while none is showing.
    public private(set) var nextDeadline: Date?
    /// The id of the resting activity, showing or not.
    public var restingID: String? { resting?.id }

    private var timed: LiveActivityRequest?
    private var resting: LiveActivityRequest?
    /// The user swept the resting activity away; it stays out of sight until asked back.
    private var isRestingHidden = false

    private var waiting: [(request: LiveActivityRequest, arrival: Int)] = []
    private var arrivals = 0

    public init() {}

    /// Ids of the waiting requests in the order they will be shown.
    public var waitingIDs: [String] {
        ordered(waiting).map(\.request.id)
    }

    public mutating func present(_ request: LiveActivityRequest, at now: Date) {
        waiting.removeAll { $0.request.id == request.id }

        guard let current = timed, current.id != request.id, request.priority < current.priority else {
            // Idle, a refresh of what is showing, or something at least as important:
            // it shows now. Whatever it replaces does not come back.
            show(request, at: now)
            return
        }

        arrivals += 1
        waiting.append((request, arrivals))
        if waiting.count > Self.maxWaiting {
            // Full: drop the least important request, and of those the one waiting longest.
            let dropped = waiting.min {
                $0.request.priority != $1.request.priority
                    ? $0.request.priority < $1.request.priority
                    : $0.arrival < $1.arrival
            }
            waiting.removeAll { $0.arrival == dropped?.arrival }
        }
    }

    /// Call when `nextDeadline` has passed. The next waiting request gets its full duration
    /// from `now`, however late the call is.
    public mutating func advance(to now: Date) {
        guard let nextDeadline, now >= nextDeadline else { return }
        showNext(at: now)
    }

    public mutating func dismiss(id: String, at now: Date) {
        waiting.removeAll { $0.request.id == id }
        if resting?.id == id {
            resting = nil
        }
        if timed?.id == id {
            showNext(at: now)
        }
    }

    /// Sets, replaces or (with nil) takes away the activity that rests beside the notch.
    /// Its priority and duration do not matter: anything timed shows over it, and it has no end.
    public mutating func setResting(_ request: LiveActivityRequest?) {
        if request?.id != resting?.id {
            isRestingHidden = false
        }
        resting = request
    }

    /// Takes what is showing out of sight at the user's wish: a timed activity gives way to
    /// the next one, the resting one stays hidden until `unhideResting`.
    public mutating func hideCurrent(at now: Date) {
        if timed != nil {
            showNext(at: now)
        } else if resting != nil {
            isRestingHidden = true
        }
    }

    public mutating func unhideResting() {
        isRestingHidden = false
    }

    private mutating func show(_ request: LiveActivityRequest, at now: Date) {
        timed = request
        nextDeadline = now.addingTimeInterval(request.duration)
    }

    private mutating func showNext(at now: Date) {
        guard let next = ordered(waiting).first else {
            timed = nil
            nextDeadline = nil
            return
        }
        waiting.removeAll { $0.arrival == next.arrival }
        show(next.request, at: now)
    }

    /// Most important first; among equals, the one that arrived first.
    private func ordered(
        _ entries: [(request: LiveActivityRequest, arrival: Int)]
    ) -> [(request: LiveActivityRequest, arrival: Int)] {
        entries.sorted {
            $0.request.priority != $1.request.priority
                ? $0.request.priority > $1.request.priority
                : $0.arrival < $1.arrival
        }
    }
}
