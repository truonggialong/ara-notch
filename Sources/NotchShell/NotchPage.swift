import NotchCore
import SwiftUI

/// A page shown inside the open notch: its tab descriptor plus the view to display.
public struct NotchPage: Identifiable {
    public let descriptor: PageDescriptor
    let makeView: @MainActor () -> AnyView
    /// The page's own colour: its tab, its name up the edge, its labels and filled controls.
    let hue: AraHue?
    /// Keys pressed while the notch has the keyboard and this page is showing. `isTyping` is
    /// true while a text field has the keys. Returns true when the key was used.
    public var keyHandler: (@MainActor (_ key: NotchKey, _ isTyping: Bool) -> Bool)?
    /// True for a page whose content scrolls sideways: a mouse wheel, which only turns up and
    /// down, then moves it along.
    public var wheelScrollsSideways = false
    /// A button of the page's own on the tab row, before the pin, shown while the page is.
    public var headerAccessory: (@MainActor () -> AnyView)?

    public var id: String { descriptor.id }

    public init<V: View>(
        id: String,
        titleKey: String,
        symbolName: String,
        hue: AraHue? = nil,
        @ViewBuilder content: @escaping @MainActor () -> V
    ) {
        descriptor = PageDescriptor(id: id, titleKey: titleKey, symbolName: symbolName)
        self.hue = hue
        makeView = { AnyView(content()) }
    }
}
