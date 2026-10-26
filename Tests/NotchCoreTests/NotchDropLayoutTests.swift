import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct NotchDropLayoutTests {
    private let closed = CGSize(width: 185, height: 32)

    @Test func theNotchGrowsDownIntoACardAndHardlySideways() {
        // A card of 180 by 90 on the sheet, shown a fifth larger like the pages.
        let size = NotchDropLayout.shapeSize(closed: closed, card: CGSize(width: 180, height: 90), scale: 1.2)
        #expect(size == CGSize(width: 216, height: 32 + 108))
    }

    @Test func aNarrowCardLeavesTheNotchItsWidth() {
        let size = NotchDropLayout.shapeSize(closed: closed, card: CGSize(width: 100, height: 40), scale: 1)
        #expect(size == CGSize(width: 185, height: 72))
    }

    @Test func aSignIsNeverWiderThanItIsAllowed() {
        // Whatever a notice asks for, it stays a sign under the notch, not a bar across the screen.
        let size = NotchDropLayout.shapeSize(closed: closed, card: CGSize(width: 900, height: 40), scale: 1)
        #expect(size.width == NotchDropLayout.maxWidth)
        #expect(NotchDropLayout.maxWidth == 520)
    }

    @Test func aSignIsAsTallAsItsRowsAndAsWideAsItsTwoZones() {
        // As tall as the taller of its two zones: a line is 15 points, the small line under
        // it 12 more, rows stand 5 apart, and there are 9 points above and below.
        #expect(NotchSignLayout.height(leftHasSmallLine: false, rowsWithSmallLine: []) == 33)
        #expect(NotchSignLayout.height(leftHasSmallLine: true, rowsWithSmallLine: []) == 45)
        #expect(NotchSignLayout.height(leftHasSmallLine: false, rowsWithSmallLine: [false]) == 33)
        #expect(NotchSignLayout.height(leftHasSmallLine: true, rowsWithSmallLine: [false, false]) == 53)
        #expect(NotchSignLayout.height(leftHasSmallLine: true, rowsWithSmallLine: [true, true]) == 77)
        // The zone of the name, the hairline between, the zone of the news.
        #expect(NotchSignLayout.width(left: 150, right: 120) == 271)
        // With nothing to say on the right there is no hairline either.
        #expect(NotchSignLayout.width(left: 150, right: 0) == 150)
        // On the sheet, before it is enlarged: never so wide that it passes the limit once enlarged a fifth.
        #expect(NotchSignLayout.width(left: 400, right: 400) == NotchSignLayout.maxSheetWidth)
        #expect(NotchSignLayout.maxSheetWidth * 1.2 <= NotchDropLayout.maxWidth)
    }

    @Test func theCardHangsCentredUnderTheNotchOnTheScreen() {
        // Screen coordinates grow upwards: the notch sits at the top, the card below it.
        let closedRect = CGRect(x: 663.5, y: 950, width: 185, height: 32)
        let rect = NotchDropLayout.rect(closedRect: closedRect, card: CGSize(width: 180, height: 90), scale: 1.2)
        #expect(rect == CGRect(x: 648, y: 842, width: 216, height: 140))
    }
}

@Suite struct SignRaysTests {
    private let moments = stride(from: 0.0, through: 30, by: 1.0 / 60).map { $0 }

    @Test func threeRaysFanFromEachTopCornerTowardsTheMiddle() {
        for seconds in [0, 0.4, 1, 7.3, 60] {
            let rays = SignRays.rays(after: seconds)
            #expect(rays.map(\.isLeft) == [true, true, true, false, false, false])
            // Measured from straight down towards the middle: never out of the sign, never flat.
            #expect(rays.map { $0.angle > 10 && $0.angle < 75 } == Array(repeating: true, count: 6))
        }
    }

    @Test func theRaysUnrollWithTheSignAndNeverRollBack() {
        #expect(SignRays.unroll(after: 0) == 0)
        #expect(SignRays.unroll(after: SignRays.unrollTime) == 1)
        #expect(SignRays.unroll(after: 40) == 1)
        var last = 0.0
        for step in 1...18 {
            let now = SignRays.unroll(after: Double(step) * 0.05)
            #expect(now > last)
            last = now
        }
        // When the sign appears the rays are stubs with no light in them yet.
        let first = SignRays.rays(after: 0)
        #expect(first.map { $0.length < 0.15 } == Array(repeating: true, count: 6))
        #expect(first.map(\.brightness) == Array(repeating: 0, count: 6))
    }

    @Test func theRaysSwayAboutTheirPlaceWithoutJumping() {
        var last = SignRays.rays(after: 0)
        for seconds in moments.dropFirst() {
            let rays = SignRays.rays(after: seconds)
            for (index, ray) in rays.enumerated() {
                #expect(abs(ray.angle - SignRays.restAngles[index % 3]) <= SignRays.sway)
                #expect(abs(ray.angle - last[index].angle) < 0.2)
                #expect(abs(ray.brightness - last[index].brightness) < 0.08)
                #expect(ray.brightness >= 0 && ray.brightness <= 1)
                #expect(ray.length > 0 && ray.length <= 1.1)
            }
            last = rays
        }
    }

    @Test func onceUnrolledEveryRayKeepsSomeLight() {
        for seconds in moments where seconds >= SignRays.unrollTime {
            #expect(SignRays.rays(after: seconds).map { $0.brightness >= 0.45 } == Array(repeating: true, count: 6))
        }
    }

    @Test func theRaysAreOutOfStepWithOneAnother() {
        // Neither all bright at once, nor one side the mirror of the other.
        let rays = SignRays.rays(after: 5)
        #expect(Set(rays.map { ($0.brightness * 100).rounded() }).count >= 4)
        #expect(rays[0].angle != rays[3].angle)
        let brightest = moments.map { SignRays.rays(after: $0).map(\.brightness).min() ?? 0 }.max() ?? 0
        #expect(brightest < 0.95)
    }

    @Test func eachRaysSwingIsWhatItsMotionReaches() {
        // The swings are what Core Animation plays; they must be the motion described above.
        let samples = moments.filter { $0 >= SignRays.unrollTime }.map { SignRays.rays(after: $0) }
        for index in 0..<6 {
            let swing = SignRays.swing(of: index)
            let angles = samples.map { $0[index].angle }
            let lengths = samples.map { $0[index].length }
            let lights = samples.map { $0[index].brightness }
            #expect(abs((angles.min() ?? 0) - swing.angles.lowerBound) < 0.05)
            #expect(abs((angles.max() ?? 0) - swing.angles.upperBound) < 0.05)
            #expect(abs((lengths.min() ?? 0) - swing.lengths.lowerBound) < 0.01)
            #expect(abs((lengths.max() ?? 0) - swing.lengths.upperBound) < 0.01)
            #expect(abs((lights.min() ?? 0) - swing.brightness.lowerBound) < 0.01)
            #expect(abs((lights.max() ?? 0) - swing.brightness.upperBound) < 0.01)
        }
    }

    @Test func noTwoRaysSwingInTheSameTime() {
        let periods = (0..<6).map { SignRays.swing(of: $0).period }
        #expect(Set(periods).count == 6)
        #expect((0..<6).allSatisfy { SignRays.swing(of: $0).lead < SignRays.swing(of: $0).period })
    }

    @Test func standingStillTheRaysAreAtRestAndLit() {
        let rays = SignRays.still
        #expect(rays.map(\.angle) == SignRays.restAngles + SignRays.restAngles)
        #expect(rays.map(\.length) == Array(repeating: 1, count: 6))
        #expect(rays.map { $0.brightness >= 0.6 && $0.brightness <= 1 } == Array(repeating: true, count: 6))
    }
}

@Suite struct SignRayLayoutTests {
    private let sign = CGSize(width: 388, height: 54)

    @Test func aRayIsALongBladeSizedByTheSign() {
        let layout = SignRayLayout(signSize: sign)
        #expect(layout.length == 291)
        #expect(abs(layout.breadth - 38.8) < 0.001)
        // A narrow sign still has rays wide enough to read as light.
        #expect(SignRayLayout(signSize: CGSize(width: 200, height: 50)).breadth == 34)
    }

    @Test func thePictureOfARayHoldsAllOfItsBlur() {
        let layout = SignRayLayout(signSize: sign)
        #expect(layout.margin >= 3 * layout.blur)
        #expect(layout.imageSize.width == layout.breadth + 2 * layout.margin)
        #expect(layout.imageSize.height == layout.length * 1.08 + 2 * layout.margin)
    }

    @Test func aRayHangsFromItsTopCentre() {
        let layout = SignRayLayout(signSize: sign)
        #expect(layout.anchor.x == 0.5)
        #expect(layout.anchor.y == (layout.margin + layout.length * 0.08) / layout.imageSize.height)
        #expect(layout.anchor.y > 0 && layout.anchor.y < 0.2)
    }

    @Test func theRaysHangFromJustAboveTheSignsTopCorners() {
        let layout = SignRayLayout(signSize: sign)
        #expect(layout.pivot(isLeft: true) == CGPoint(x: 0, y: -54 * 0.12))
        #expect(layout.pivot(isLeft: false) == CGPoint(x: 388, y: -54 * 0.12))
    }
}

@Suite struct NotchClickAreaTests {
    private let closed = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    @Test func aSignIsClickedWhereItsCardIs() {
        let card = CGSize(width: 323, height: 54)
        #expect(NotchClickArea.rect(closedRect: closed, dropCard: card, sideWidth: 110, scale: 1.2)
            == NotchDropLayout.rect(closedRect: closed, card: card, scale: 1.2))
    }

    @Test func somethingBesideTheNotchIsClickedOnEitherSide() {
        #expect(NotchClickArea.rect(closedRect: closed, dropCard: nil, sideWidth: 110, scale: 1.2)
            == CGRect(x: 553.5, y: 950, width: 405, height: 32))
    }

    @Test func clicksAreTakenOnlyWhileSomethingShowsOnTheClosedNotch() {
        #expect(NotchClickArea.takesClicks(isOpen: false, showsSomething: true, isHidden: false))
        // Open, the notch's own window takes them; with nothing on it, the menu bar does.
        #expect(!NotchClickArea.takesClicks(isOpen: true, showsSomething: true, isHidden: false))
        #expect(!NotchClickArea.takesClicks(isOpen: false, showsSomething: false, isHidden: false))
        #expect(!NotchClickArea.takesClicks(isOpen: false, showsSomething: true, isHidden: true))
    }
}
