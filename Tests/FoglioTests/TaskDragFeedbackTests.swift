import Foundation
@testable import FoglioCore

func taskDragFeedbackTests() {
    Check.suite("Task drag feedback — lane and insertion share a hover session") {
        let a = UUID(), b = UUID(), source = UUID()
        let frames = [a: CGRect(x: 12, y: 52, width: 276, height: 100),
                      b: CGRect(x: 12, y: 160, width: 276, height: 180)]
        var feedback = TaskColumnDragState()
        func hover(_ y: CGFloat) {
            feedback.update(sourceID: source, location: CGPoint(x: 40, y: y), taskIDs: [a, b], frames: frames)
        }
        hover(80)
        Check.equal(feedback.sourceID, source, "lane highlighting stays active while a card has insertion feedback")
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: a, after: false), "upper half inserts before a card")
        hover(130)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: a, after: true), "lower half inserts after a card")
        let belowA = feedback.indicatorY(frames: frames, emptyY: 52)
        Check.equal(belowA, 156, "line sits in the gap, outside the card border")
        for y in [CGFloat(153), 156, 159, 180] {
            hover(y)
            Check.equal(feedback.sourceID, source, "card gaps do not turn off lane highlighting")
            Check.equal(feedback.indicatorY(frames: frames, emptyY: 52), belowA, "crossing between cards keeps the same insertion line")
        }
        hover(320)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: b, after: true), "variable-height cards use their own midpoint")
        hover(500)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: b, after: true), "trailing lane space appends after the last card")
        hover(20)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: a, after: false), "lane header inserts at the top")
        feedback.update(sourceID: a, location: CGPoint(x: 40, y: 80), taskIDs: [a, b], frames: frames)
        Check.equal(feedback.placement?.anchorID, b, "same-lane dragging never creates a self anchor")
        Check.equal(feedback.sourceID, a, "the source lane still gets both cues")
        let scrolled = frames.mapValues { $0.offsetBy(dx: 0, dy: -108) }
        feedback.update(sourceID: source, location: CGPoint(x: 40, y: 80), taskIDs: [a, b], frames: scrolled)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: b, after: false), "scroll offsets use lane coordinates, not stale content coordinates")
        let viewport = CGRect(x: 8, y: 48, width: 284, height: 240)
        feedback.update(sourceID: source, location: CGPoint(x: 40, y: 50), taskIDs: [a, b], frames: frames.mapValues { $0.offsetBy(dx: 0, dy: -140) })
        Check.equal(feedback.indicatorY(frames: frames.mapValues { $0.offsetBy(dx: 0, dy: -140) }, emptyY: 52, viewport: viewport), 50,
                    "a clipped upper edge keeps its marker below the lane header")
        hover(500)
        Check.equal(feedback.indicatorY(frames: frames, emptyY: 52, viewport: viewport), 286,
                    "a clipped lower edge keeps its marker inside the scroll area")
        feedback.update(sourceID: source, location: .zero, taskIDs: [], frames: [:])
        Check.equal(feedback.sourceID, source, "an empty lane remains highlighted")
        Check.expect(feedback.placement == nil, "empty lanes do not invent a task anchor")
        Check.equal(feedback.indicatorY(frames: [:], emptyY: 52), 52, "empty lane has a visible insertion position")
        feedback.clear()
        Check.expect(feedback.sourceID == nil && feedback.location == nil && feedback.placement == nil,
                     "leaving, dropping, and cancelling clear both feedback cues")
    }

    Check.suite("Task dragging — temporary card slots and reflow stability") {
        let a = UUID(), source = UUID(), b = UUID(), c = UUID()
        let ids = [a, source, b, c]
        Check.equal(TaskLaneDragLayout.index(taskIDs: ids, sourceID: source, placement: nil, restoringSource: true), 1,
                    "lifting reserves the source card's original position")
        Check.equal(TaskLaneDragLayout.index(taskIDs: ids, sourceID: source,
                    placement: TaskDropPlacement(anchorID: c, after: true)), 3, "dragging to the end reserves the last slot")
        let afterA = TaskLaneDragLayout.index(taskIDs: ids, sourceID: source, placement: TaskDropPlacement(anchorID: a, after: true))
        let beforeB = TaskLaneDragLayout.index(taskIDs: ids, sourceID: source, placement: TaskDropPlacement(anchorID: b, after: false))
        Check.equal(afterA, beforeB, "both sides of a gap describe one stable slot")
        Check.equal(TaskLaneDragLayout.placement(at: afterA, taskIDs: ids, sourceID: source),
                    TaskDropPlacement(anchorID: b, after: false), "equivalent slots normalize before notifying the board")
        Check.expect(TaskLaneDragLayout.placement(at: 0, taskIDs: [source], sourceID: source) == nil,
                     "a lane with only its source card does not invent a self anchor")
        Check.equal(TaskLaneDragLayout.index(taskIDs: [], sourceID: source, placement: nil), 0,
                    "an empty destination has an initial slot")
        var feedback = TaskColumnDragState()
        let initial = [a: CGRect(x: 12, y: 52, width: 276, height: 100),
                       b: CGRect(x: 12, y: 160, width: 276, height: 100)]
        feedback.update(sourceID: source, location: CGPoint(x: 80, y: 130), taskIDs: ids, frames: initial)
        let selected = feedback.placement
        let gap = CGRect(x: 12, y: 160, width: 276, height: 120)
        let shifted = [a: initial[a]!, b: initial[b]!.offsetBy(dx: 0, dy: 128),
                       c: CGRect(x: 12, y: 396, width: 276, height: 100)]
        for y in [CGFloat(162), 220, 278] {
            feedback.update(sourceID: source, location: CGPoint(x: 80, y: y), taskIDs: ids, frames: shifted, placeholder: gap)
            Check.equal(feedback.placement, selected, "cards moving around the placeholder cannot bounce the selected slot")
        }
        feedback.update(sourceID: source, location: CGPoint(x: 80, y: 370), taskIDs: ids, frames: shifted, placeholder: gap)
        Check.equal(feedback.placement, TaskDropPlacement(anchorID: b, after: true), "moving past the next card advances the slot")
        feedback.clear()
        Check.expect(feedback.placement == nil, "cancelling removes the projected slot without a stored order")
        Check.equal(feedback.indicatorY(frames: shifted, emptyY: 52,
                    viewport: CGRect(x: 8, y: 48, width: 284, height: 240),
                    placeholder: gap.offsetBy(dx: 0, dy: -200)), 50,
                    "the placeholder's line stays below the header when scrolled out of view")
        Check.equal(ids, [a, source, b, c], "preview calculations leave the original task order intact")
    }
}
