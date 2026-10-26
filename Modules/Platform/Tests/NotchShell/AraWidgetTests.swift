import AppKit
import NotchCore
@testable import NotchShell
import SwiftUI
import Testing

@MainActor @Suite struct AraWidgetTests {
    private func matches(_ color: Color, _ expected: ThemeColor) -> Bool {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return abs(rgb.redComponent - expected.red) < 0.01 && abs(rgb.greenComponent - expected.green) < 0.01
            && abs(rgb.blueComponent - expected.blue) < 0.01
    }

    @Test func vividColoursAreTheWidgetPalettes() {
        for hue in AraHue.allCases {
            #expect(matches(AraPalette.vivid(hue), WidgetPalette.vivid(hue)), "\(hue)")
        }
        #expect(matches(AraPalette.vivid(nil), WidgetPalette.text))
        #expect(matches(AraPalette.alert, WidgetPalette.alert))
    }
}
