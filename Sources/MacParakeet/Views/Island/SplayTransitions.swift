import SwiftUI

/// A blur-in / blur-out transition: content resolves *into focus* as it scales
/// and fades, instead of hard-popping.
///
/// Harvested from DynamicNotchKit (MrKai77, MIT) — its compact↔expanded morph
/// blurs content across the transition, which reads noticeably softer and more
/// "Apple" than a bare `.scale + .opacity`. We evaluated adopting DynamicNotchKit
/// as the island substrate and rejected it (its hard black notch-mask clips our
/// light, it can't host the below-windows glow, and it has no always-on idle
/// state on non-notched screens). This one animation technique was the keeper —
/// so it lives here as a first-party `AnyTransition`, not a dependency.
private struct SplayBlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// Blurs by `intensity` at the transition's active (inserting/removing) edge,
    /// sharpening to 0 at identity. Combine with `.scale`/`.opacity` for a soft
    /// settle: `.scale(scale: 0.8).combined(with: .opacity).combined(with: .splayBlur(intensity: 6))`.
    static func splayBlur(intensity: CGFloat) -> AnyTransition {
        .modifier(
            active: SplayBlurModifier(radius: intensity),
            identity: SplayBlurModifier(radius: 0)
        )
    }
}
