import SwiftUI

// The `ICONS` set from `Day Log.dc.html:629`, hand-ported from SVG path data.
// All are authored in a 24x24 space and stroked at 1.7 with round caps/joins.
//
// Two of the source paths use arc commands (`settings` and `timer`); both are
// full circles once decoded, so they become `addEllipse` rather than needing a
// general arc-to-bezier conversion.
//
// `chart` has no counterpart in the design: `Day Log.dc.html:882` references
// `ICONS.chart` for the Weekly review rail item but the ICONS table never
// defines it, so that icon renders empty upstream. This is our replacement.

enum Icon: String, CaseIterable {
    case capture, notes, tasks, settings, roadmap, week, folder, all, chart, timer, pin

    /// Builds the icon in a 24x24 coordinate space.
    private func build(into p: inout Path) {
        func move(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: x, y: y)) }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        switch self {
        case .capture: // M12 5v14 M5 12h14
            move(12, 5); line(12, 19)
            move(5, 12); line(19, 12)

        case .notes: // M6 3h9l4 4v14H6z M15 3v5h4
            move(6, 3); line(15, 3); line(19, 7); line(19, 21); line(6, 21); p.closeSubpath()
            move(15, 3); line(15, 8); line(19, 8)

        case .tasks: // M4 7l3 3 5-6 M4 17l3 3 5-6 M14 8h6 M14 18h6
            move(4, 7); line(7, 10); line(12, 4)
            move(4, 17); line(7, 20); line(12, 14)
            move(14, 8); line(20, 8)
            move(14, 18); line(20, 18)

        case .settings: // gear: r3 hub + 8 spokes
            circle(12, 12, 3)
            move(12, 2.5); line(12, 5.5)
            move(12, 18.5); line(12, 21.5)
            move(2.5, 12); line(5.5, 12)
            move(18.5, 12); line(21.5, 12)
            move(5.2, 5.2); line(7.3, 7.3)
            move(16.7, 16.7); line(18.8, 18.8)
            move(5.2, 18.8); line(7.3, 16.7)
            move(16.7, 7.3); line(18.8, 5.2)

        case .roadmap: // M6 21V4h12l-3 4 3 4H6
            move(6, 21); line(6, 4); line(18, 4); line(15, 8); line(18, 12); line(6, 12)

        case .week: // M4 6h16v15H4z M4 10h16 M9 3v4 M15 3v4
            move(4, 6); line(20, 6); line(20, 21); line(4, 21); p.closeSubpath()
            move(4, 10); line(20, 10)
            move(9, 3); line(9, 7)
            move(15, 3); line(15, 7)

        case .folder: // M3 7h6l2 2h10v10H3z
            move(3, 7); line(9, 7); line(11, 9); line(21, 9); line(21, 19); line(3, 19)
            p.closeSubpath()

        case .all: // M4 6h16 M4 12h16 M4 18h10
            move(4, 6); line(20, 6)
            move(4, 12); line(20, 12)
            move(4, 18); line(14, 18)

        case .chart: // replacement for the undefined ICONS.chart
            move(4, 20); line(20, 20)
            move(7, 20); line(7, 12)
            move(12, 20); line(12, 6)
            move(17, 20); line(17, 15)

        case .timer: // M12 4a8 8 0 100 16 8 8 0 000-16 M12 8v4l3 2
            circle(12, 12, 8)
            move(12, 8); line(12, 12); line(15, 14)

        case .pin: // M9 4h6l-1 6 4 3H6l4-3-1-6 M12 13v7  (:156)
            move(9, 4); line(15, 4); line(14, 10); line(18, 13)
            line(6, 13); line(10, 10); p.closeSubpath()
            move(12, 13); line(12, 20)
        }
    }

    func path(scaledTo size: CGFloat) -> Path {
        var p = Path()
        build(into: &p)

        // Centre each glyph's bounding box in the 24x24 box before scaling.
        // Several of the design's paths sit up to a point off-centre — `notes`
        // leans right, `folder` and `chart` sit low — which is invisible on its
        // own but reads as a wobbly column once they're stacked in the bar.
        // Only the position is normalised; the shapes and their relative sizes
        // are left exactly as drawn.
        let box = p.boundingRect
        let dx = (24 - box.width) / 2 - box.minX
        let dy = (24 - box.height) / 2 - box.minY

        return p
            .applying(CGAffineTransform(translationX: dx, y: dy))
            .applying(CGAffineTransform(scaleX: size / 24, y: size / 24))
    }
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 17
    var lineWidth: CGFloat = 1.7

    var body: some View {
        icon.path(scaledTo: size)
            .stroked(lineWidth: lineWidth)
            .frame(width: size, height: size)
            // A stroked path hit-tests only on the stroke itself, which makes
            // icon buttons feel broken. Claim the whole frame.
            .contentShape(Rectangle())
    }
}

private extension Path {
    func stroked(lineWidth: CGFloat) -> some View {
        self.stroke(
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
