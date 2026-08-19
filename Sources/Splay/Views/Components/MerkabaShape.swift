import SwiftUI
import CoreGraphics

/// Star tetrahedron — two interlocking equilateral triangles (2D projection)
/// with an inner hexagon and an enclosing circle. Used as a faint decorative
/// background mark in the Prompt Library.
///
/// Extracted from the retired Discover feature's `SacredGeometryShapes` set —
/// `MerkabaShape` was the only shape referenced outside Discover, so the rest
/// was removed with the feature and this one moved here.
struct MerkabaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) * 0.42

        // Upward triangle
        for i in 0..<3 {
            let a = CGFloat(i) * 2.0 * .pi / 3.0 - .pi / 2.0
            let pt = CGPoint(x: cx + r * ccos(a), y: cy + r * ssin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()

        // Downward triangle
        for i in 0..<3 {
            let a = CGFloat(i) * 2.0 * .pi / 3.0 + .pi / 2.0
            let pt = CGPoint(x: cx + r * ccos(a), y: cy + r * ssin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()

        // Inner hexagon
        let ir = r * 0.5
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3.0
            let pt = CGPoint(x: cx + ir * ccos(a), y: cy + ir * ssin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()

        // Outer circle
        path.addEllipse(in: circleRect(center: CGPoint(x: cx, y: cy), radius: r))

        return path
    }
}

private func ccos(_ a: CGFloat) -> CGFloat { CoreGraphics.cos(a) }
private func ssin(_ a: CGFloat) -> CGFloat { CoreGraphics.sin(a) }
private func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}
