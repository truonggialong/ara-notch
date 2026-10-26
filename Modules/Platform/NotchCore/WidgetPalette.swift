import Foundation

/// The colours of the overview's widgets: dark cards on the black notch, in every appearance,
/// with each feature's colour made brighter so it stands out, and one orange for what wants
/// the user now.
public enum WidgetPalette {
    public static let card = ThemeColor(hex: 0x1E1E1E)
    public static let text = ThemeColor(hex: 0xF2F2F2)
    public static let secondaryText = ThemeColor(hex: 0x9A9A9A)
    /// The empty part of a bar.
    public static let track = ThemeColor(hex: 0x333333)
    /// The fill of a round button that is not the main one.
    public static let quietButton = ThemeColor(hex: 0x2A2A2A)
    public static let alert = ThemeColor(hex: 0xFF5A1F)

    /// The feature's colour on a widget.
    public static func vivid(_ hue: ThemeHue) -> ThemeColor {
        switch hue {
        case .sky: ThemeColor(hex: 0x4FA8FF)
        case .mustard: ThemeColor(hex: 0xFFC23D)
        case .mint: ThemeColor(hex: 0x2EE6A6)
        case .peach: ThemeColor(hex: 0xFF8A5B)
        case .lilac: ThemeColor(hex: 0xA98BFF)
        case .sage: ThemeColor(hex: 0x9BE15D)
        }
    }
}
