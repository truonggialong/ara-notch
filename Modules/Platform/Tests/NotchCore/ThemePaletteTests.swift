import Foundation
import Testing
@testable import NotchCore

@Suite struct ThemePaletteTests {
    private let palettes: [(name: String, palette: ThemePalette)] = [("dark", .night), ("light", .paper)]

    @Test func contrastIsMeasuredTheUsualWay() {
        let white = ThemeColor(hex: 0xFFFFFF), black = ThemeColor(hex: 0x000000)
        #expect(abs(white.contrast(with: black) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.01)
    }

    @Test func readsAColourFromItsHexNumber() {
        let colour = ThemeColor(hex: 0xF4E3B5)
        #expect(abs(colour.red - 244.0 / 255) < 0.0001)
        #expect(abs(colour.green - 227.0 / 255) < 0.0001)
        #expect(abs(colour.blue - 181.0 / 255) < 0.0001)
    }

    @Test func textIsReadableOnTheSurfacesItSitsOn() {
        for (name, palette) in palettes {
            // Body text: at least 4.5 to 1, on the ground, on a card and in a well.
            #expect(palette.onGround.contrast(with: palette.ground) >= 4.5, "\(name): text on the ground")
            #expect(palette.ink.contrast(with: palette.card) >= 4.5, "\(name): text on a card")
            #expect(palette.ink.contrast(with: palette.cardRaised) >= 4.5, "\(name): text in a well")
            // Quiet text: captions and the facts beside them, on a card and in a well.
            #expect(palette.label.contrast(with: palette.card) >= 4.5, "\(name): captions on a card")
            #expect(palette.value.contrast(with: palette.card) >= 4.5, "\(name): facts on a card")
            #expect(palette.label.contrast(with: palette.cardRaised) >= 4.5, "\(name): captions in a well")
            #expect(palette.label.contrast(with: palette.ground) >= 4.5, "\(name): captions on the ground")
        }
    }

    @Test func aCardAndAWellAreNotTheGroundsColour() {
        for (name, palette) in palettes {
            // Cards carry no outline in this design: they are told from the ground, and a
            // well (a field, a quiet button) from the card, by a step of tone.
            #expect(palette.card != palette.ground, "\(name): a card against the ground")
            #expect(palette.cardRaised != palette.card, "\(name): a well against a card")
        }
    }

    @Test func aWarningIsReadableOnACard() {
        for (name, palette) in palettes {
            #expect(palette.warning.contrast(with: palette.card) >= 4.5, "\(name): a warning on a card")
            #expect(palette.danger.contrast(with: palette.card) >= 3, "\(name): a danger mark on a card")
        }
    }

    @Test func marksOnAFilledControlAreReadable() {
        for (name, palette) in palettes {
            #expect(palette.onAccent.contrast(with: palette.accent) >= 4.5, "\(name): marks on the accent fill")
            #expect(palette.onDanger.contrast(with: palette.danger) >= 4.5, "\(name): marks on the danger fill")
            #expect(palette.onBrand.contrast(with: palette.brand) >= 4.5, "\(name): marks on the brand colour")
        }
    }

    @Test func outlinesStandOutFromTheCardTheyAreDrawnOn() {
        for (name, palette) in palettes {
            // An outline is a shape, not text: 3 to 1 against the card and the ground.
            #expect(palette.line.contrast(with: palette.card) >= 3, "\(name): the outline against a card")
            #expect(palette.line.contrast(with: palette.ground) >= 3, "\(name): the outline against the ground")
        }
    }

    @Test func widgetColoursStandOutOnTheDarkCard() {
        let card = WidgetPalette.card
        #expect(WidgetPalette.text.contrast(with: card) >= 4.5)
        #expect(WidgetPalette.secondaryText.contrast(with: card) >= 4.5)
        for hue in ThemeHue.allCases {
            let vivid = WidgetPalette.vivid(hue)
            #expect(vivid.contrast(with: card) >= 3, "\(hue): bars and chips on the card")
            // A primary round button: the card's dark on the vivid fill.
            #expect(card.contrast(with: vivid) >= 4.5, "\(hue): marks on a primary button")
        }
        #expect(WidgetPalette.alert.contrast(with: card) >= 3)
        #expect(WidgetPalette.vivid(.sky) == ThemeColor(hex: 0x4FA8FF))
        #expect(WidgetPalette.alert == ThemeColor(hex: 0xFF5A1F))
    }

    @Test func everyTintIsReadableOnItsOwnCardAndOnAPlainOne() {
        for (name, palette) in palettes {
            for hue in ThemeHue.allCases {
                let tint = palette.tint(hue)
                // A card filled with the tint: its text, and its captions.
                #expect(tint.ink.contrast(with: tint.fill) >= 4.5, "\(name) \(hue): text on the tinted card")
                // Also a control filled with the tint's line, whose marks take the fill's colour.
                #expect(tint.line.contrast(with: tint.fill) >= 4.5, "\(name) \(hue): captions on the tinted card")
                // A page's colour is used for captions on plain cards and in wells too.
                #expect(tint.line.contrast(with: palette.card) >= 4.5, "\(name) \(hue): captions on a plain card")
                #expect(tint.line.contrast(with: palette.cardRaised) >= 3, "\(name) \(hue): marks in a well")
            }
        }
    }

    @Test func aPagesColourReadsOnTheNightGround() {
        // The notch is always the night sheet: tabs sit on its ground.
        for hue in ThemeHue.allCases {
            #expect(ThemePalette.night.tint(hue).line.contrast(with: ThemePalette.night.ground) >= 4.5, "\(hue)")
        }
    }

    @Test func noTwoTintsShareAColour() {
        let lines = ThemeHue.allCases.map { ThemePalette.night.tint($0).line }
        for (index, line) in lines.enumerated() {
            #expect(!lines[(index + 1)...].contains(line))
        }
    }

    @Test func theDayPaletteIsTheReferenceSheet() {
        // Off-white ground, white cards, near-black ink and one orange.
        #expect(ThemePalette.paper.ground == ThemeColor(hex: 0xF7F5EF))
        #expect(ThemePalette.paper.card == ThemeColor(hex: 0xFFFFFF))
        #expect(ThemePalette.paper.ink == ThemeColor(hex: 0x1A1A1A))
        #expect(ThemePalette.paper.brand == ThemeColor(hex: 0xF2703E))
        // The one control a view is about is a black pill by day and a light one by night.
        #expect(ThemePalette.paper.accent == ThemePalette.paper.ink)
        #expect(ThemePalette.night.accent == ThemePalette.night.ink)
    }
}
