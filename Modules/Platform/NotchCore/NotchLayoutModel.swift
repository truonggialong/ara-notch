import CoreGraphics

/// What the open notch is laid on.
public enum NotchMaterial: String, CaseIterable, Sendable {
    /// Plain black, like the hardware.
    case black
    /// Dark frosted glass: the strip beside the camera stays black, the rest lets the colour
    /// behind show through, blurred.
    case glass
    /// The system's Liquid Glass (macOS 26 and later); dark glass where it is missing.
    case liquid

    public static let standard = NotchMaterial.glass

    /// The material actually drawn: black when the Mac asks for less transparency.
    public func shown(reduceTransparency: Bool) -> NotchMaterial {
        reduceTransparency ? .black : self
    }

    /// How dark the glass is under the camera strip, from 0 (clear) to 1 (black). More
    /// contrast asked for, darker glass.
    public func shade(increasedContrast: Bool) -> Double {
        switch self {
        case .black: 1
        case .glass: increasedContrast ? 0.85 : 0.62
        case .liquid: increasedContrast ? 0.7 : 0.38
        }
    }
}

/// The springs the notch grows and shrinks with: it grows with a little bounce and shrinks
/// without one, so closing feels firm and never wobbles around the camera.
public enum NotchMotion {
    public struct Spring: Equatable, Sendable {
        public let duration: Double
        public let bounce: Double
    }

    public static let grow = Spring(duration: 0.44, bounce: 0.25)
    public static let shrink = Spring(duration: 0.30, bounce: 0)
    /// Points the grown notch may overshoot by; the window keeps this much room around it.
    public static let overshootRoom: CGFloat = 14

    public static func spring(growing: Bool) -> Spring {
        growing ? grow : shrink
    }
}

/// The round buttons that stand around the open notch.
public enum OrbitSlot: String, CaseIterable, Sendable {
    case left0, left1, left2, right0, right1, right2, bottom0, bottom1

    public enum Side: Sendable { case left, right, bottom }

    public var side: Side {
        switch self {
        case .left0, .left1, .left2: .left
        case .right0, .right1, .right2: .right
        case .bottom0, .bottom1: .bottom
        }
    }

    /// Place along its side: top to bottom, or left to right under the notch.
    public var index: Int {
        switch self {
        case .left0, .right0, .bottom0: 0
        case .left1, .right1, .bottom1: 1
        case .left2, .right2: 2
        }
    }
}

/// What one round button beside the open notch does.
public enum OrbitAction: Equatable, Sendable {
    /// Shows every page as a grid of tiles.
    case explore
    case settings
    case pin
    /// Shows one page.
    case page(String)

    public init?(storedName: String) {
        switch storedName {
        case "explore": self = .explore
        case "settings": self = .settings
        case "pin": self = .pin
        default:
            guard storedName.hasPrefix("page:"), storedName.count > 5 else { return nil }
            self = .page(String(storedName.dropFirst(5)))
        }
    }

    public var storedName: String {
        switch self {
        case .explore: "explore"
        case .settings: "settings"
        case .pin: "pin"
        case let .page(id): "page:\(id)"
        }
    }
}

/// Which round button stands in which place around the open notch.
public struct OrbitLayout: Equatable, Sendable {
    public private(set) var actions: [OrbitSlot: OrbitAction]

    public init(actions: [OrbitSlot: OrbitAction]) {
        self.actions = actions
    }

    /// Explore and the timer on the left, settings and pin on the right, the music under it.
    public static let standard = OrbitLayout(actions: [
        .left0: .explore, .left1: .page("timer"), .right0: .settings, .right1: .pin, .bottom0: .page("media"),
    ])

    /// The diameter of a button, before enlargement, and the gap between it and the notch.
    public static let diameter: CGFloat = 44
    public static let gap: CGFloat = 12
    public static let rowPitch: CGFloat = 54
    /// The room each side of the open notch keeps for the buttons.
    public static var gutter: CGFloat { diameter + gap }

    /// Read from what the settings keep: one "slot=action" per button; anything not
    /// understood is left out, and nothing kept at all gives the standard layout.
    public init(stored: [String]?) {
        guard let stored else {
            self = .standard
            return
        }
        var actions: [OrbitSlot: OrbitAction] = [:]
        for entry in stored {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let slot = OrbitSlot(rawValue: parts[0]), let action = OrbitAction(storedName: parts[1])
            else { continue }
            actions[slot] = action
        }
        self.actions = actions
    }

    public var stored: [String] {
        OrbitSlot.allCases.compactMap { slot in actions[slot].map { "\(slot.rawValue)=\($0.storedName)" } }
    }

    public mutating func set(_ action: OrbitAction?, at slot: OrbitSlot) {
        actions[slot] = action
    }

    /// Swaps what two places hold, either of which may be empty.
    public mutating func swap(_ a: OrbitSlot, _ b: OrbitSlot) {
        let first = actions[a]
        actions[a] = actions[b]
        actions[b] = first
    }

    /// Whether any button stands under the notch, which then keeps room below it.
    public var usesBottom: Bool {
        actions.keys.contains { $0.side == .bottom }
    }

    /// How far beyond the open notch the pointer reaches the buttons: their gutter on each
    /// side when a side holds one, and below when the bottom does.
    public func reach(scale: CGFloat) -> CGSize {
        let sides = actions.keys.contains { $0.side != .bottom }
        return CGSize(width: sides ? (Self.gutter * scale).rounded(.up) : 0,
                      height: usesBottom ? (Self.gutter * scale).rounded(.up) : 0)
    }

    /// The room the window keeps around the open notch: the buttons' reach and the spring's
    /// overshoot, on each side and below.
    public func windowMargin(scale: CGFloat) -> CGSize {
        let room = reach(scale: scale)
        let overshoot = (NotchMotion.overshootRoom * scale).rounded(.up)
        return CGSize(width: room.width + overshoot, height: room.height + overshoot)
    }

    /// The centre of a button, measured from the top left of the open notch, in its points.
    public static func centre(of slot: OrbitSlot, openSize: CGSize, scale: CGFloat) -> CGPoint {
        let d = diameter * scale, g = gap * scale, pitch = rowPitch * scale
        switch slot.side {
        case .left:
            return CGPoint(x: -g - d / 2, y: 8 * scale + d / 2 + CGFloat(slot.index) * pitch)
        case .right:
            return CGPoint(x: openSize.width + g + d / 2, y: 8 * scale + d / 2 + CGFloat(slot.index) * pitch)
        case .bottom:
            let offset = (CGFloat(slot.index) - 0.5) * pitch
            return CGPoint(x: openSize.width / 2 + offset, y: openSize.height + g + d / 2)
        }
    }
}

/// How large a page opens. Each page may say the sheet it is laid out on; the notch shows it
/// enlarged like everything else. A page that says nothing gets the usual sheet.
public enum PageSize {
    /// - Parameters:
    ///   - base: the page's own sheet, before enlargement; nil for the usual one.
    ///   - sheetHeight: a taller sheet the page asks for now (a long day, many rows).
    public static func open(
        base: CGSize?, sheetHeight: CGFloat?, size: NotchSize, screen: CGSize
    ) -> CGSize {
        let sheet = base ?? NotchGeometry.defaultOpenSize
        let width = min((sheet.width * size.scale).rounded(), max(screen.width - 2 * OrbitLayout.gutter * size.scale, 200))
        let usual = (sheet.height * size.scale).rounded()
        guard let sheetHeight else { return CGSize(width: width, height: usual) }
        let most = max(usual, (screen.height * PageHeight.maximumShare).rounded())
        return CGSize(width: width, height: min(max((sheetHeight * size.scale).rounded(), usual), most))
    }
}

/// How wide each side of the closed notch is for what shows there: as wide as its content,
/// within bounds, so the closed notch covers as little of the menu bar as it can.
public enum ActivityWings {
    public static let padding: CGFloat = 6
    public static let narrowest: CGFloat = 32
    public static let widest: CGFloat = 72
    /// Two things shown together need a little more.
    public static let widestCombined: CGFloat = 96

    /// The side width for content of this width (as drawn, already enlarged).
    public static func width(content: CGFloat, combined: Bool = false) -> CGFloat {
        let bound = combined ? widestCombined : widest
        return min(max((content + 2 * padding).rounded(.up), narrowest), bound)
    }
}

/// Which of the things resting beside the closed notch is shown, when several are true at
/// once (a track playing, a timer running, an agent at work): the one the user chose, two the
/// user chose to see together, or else the most important.
public struct RestingSelection: Equatable, Sendable {
    public enum Choice: Equatable, Sendable {
        case one(String)
        /// `primary` is drawn on the right of the camera, `companion` on the left.
        case pair(primary: String, companion: String)
    }

    public var preferred: Choice?

    public init(preferred: Choice? = nil) {
        self.preferred = preferred
    }

    public init(stored: String?) {
        guard let stored, !stored.isEmpty else {
            preferred = nil
            return
        }
        let parts = stored.split(separator: "+").map(String.init)
        if parts.count == 2 {
            preferred = .pair(primary: parts[0], companion: parts[1])
        } else {
            preferred = .one(stored)
        }
    }

    public var stored: String? {
        switch preferred {
        case let .one(id): id
        case let .pair(primary, companion): "\(primary)+\(companion)"
        case nil: nil
        }
    }

    /// What to show of the resting things now true, by id and importance. A choice whose
    /// things are not all true now gives way, without being forgotten, so it comes back.
    public func shown(_ priorities: [String: Int]) -> Choice? {
        switch preferred {
        case let .pair(primary, companion) where priorities[primary] != nil && priorities[companion] != nil:
            return .pair(primary: primary, companion: companion)
        case let .pair(primary, companion):
            if priorities[primary] != nil { return .one(primary) }
            if priorities[companion] != nil { return .one(companion) }
        case let .one(id) where priorities[id] != nil:
            return .one(id)
        default:
            break
        }
        return Self.mostImportant(priorities).map(Choice.one)
    }

    /// The most important, and of equals the first by id.
    public static func mostImportant(_ priorities: [String: Int]) -> String? {
        priorities.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}

/// The keys that open each page from the Explore grid while the notch has the keyboard:
/// Option-Command and a letter of the page's name, the first letter not taken yet.
public enum ExploreKeys {
    public static func letters(for titles: [String]) -> [Character?] {
        var taken = Set<Character>()
        return titles.map { title in
            // Đ has no accent to fold away; it is a D to the keyboard.
            let candidates = title.replacingOccurrences(of: "Đ", with: "D").replacingOccurrences(of: "đ", with: "d")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .uppercased().filter { $0.isLetter && $0.isASCII }
            guard let letter = candidates.first(where: { !taken.contains($0) }) else { return nil }
            taken.insert(letter)
            return letter
        }
    }
}
