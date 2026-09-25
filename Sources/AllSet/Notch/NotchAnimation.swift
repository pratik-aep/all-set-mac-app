import SwiftUI

/// Motion for the notch. Every change to its shape goes through one of these
/// explicitly, so opening and closing can move differently. With Reduce
/// Motion on they become a short dissolve, like the rest of the app (`Motion`).
enum NotchAnimation {
    /// Opening: quick, with a hint of overshoot like the iPhone's island.
    static var open: Animation { Motion.resolved(.spring(duration: 0.5, bounce: 0.18)) }
    /// Closing: no overshoot, so the shape doesn't wobble as it tucks away.
    static var close: Animation { Motion.resolved(.spring(duration: 0.42, bounce: 0)) }
    /// Live activities growing out of, or back into, the closed notch.
    static var activity: Animation { Motion.resolved(.spring(duration: 0.45, bounce: 0.22)) }
    /// The small swell while the pointer rests on the closed notch.
    static var hover: Animation { Motion.resolved(.spring(duration: 0.3, bounce: 0.25)) }
    static var tab: Animation { Motion.resolved(.spring(duration: 0.45, bounce: 0.08)) }

    /// Content fades in once the shape has started to grow, so it never shows
    /// squeezed into a half-open notch...
    static var contentIn: Animation { Motion.reducesMotion ? Motion.reduced : .smooth(duration: 0.3).delay(0.08) }
    /// ...and fades out before the shape has shrunk much.
    static var contentOut: Animation { Motion.resolved(.easeIn(duration: 0.14)) }
}

/// Content that sharpens and settles into place as `progress` goes 0 → 1.
struct RevealEffect: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static func reveal(in insertion: Animation = NotchAnimation.contentIn,
                       out removal: Animation = NotchAnimation.contentOut) -> AnyTransition {
        let reveal = AnyTransition.modifier(active: RevealEffect(progress: 0), identity: RevealEffect(progress: 1))
        return .asymmetric(insertion: reveal.animation(insertion), removal: reveal.animation(removal))
    }
}
