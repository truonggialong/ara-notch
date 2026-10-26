import NotchShell

/// One thing the tools page can start.
public struct NotchTool: Identifiable {
    public let id: String
    let icon: AraIcon
    let hue: AraHue
    let action: () -> Void

    /// The tool's symbol and colour come from its name; a name with none of its own gets the grid in peach.
    public init(id: String, action: @escaping () -> Void) {
        let look = Self.looks[id] ?? (.grid, .peach)
        self.id = id
        icon = look.icon
        hue = look.hue
        self.action = action
    }

    /// Each tool's symbol and colour by its name, the same on the tools page, the overview's
    /// quick tools, its big buttons and their chips.
    static let looks: [String: (icon: AraIcon, hue: AraHue)] = [
        "capture": (.captureRegion, .peach), "scroll": (.captureScroll, .peach), "text": (.readText, .mustard),
        "color": (.pickColor, .lilac), "translate": (.translate, .sky), "panel": (.clipboard, .peach),
        "library": (.grid, .sage), "note": (.newNote, .mint),
    ]
}
