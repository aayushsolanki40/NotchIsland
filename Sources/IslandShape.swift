import SwiftUI

/// One shape for both styles: concave top "ears" for the notch look, or
/// rounded top corners for the floating iPhone pill. All radii animate.
struct IslandShape: Shape {
    var topInverted: CGFloat
    var topConvex: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(topInverted, .init(topConvex, bottom)) }
        set { topInverted = newValue.first; topConvex = newValue.second.first; bottom = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, topInverted)
        let l = rect.minX + t, r = rect.maxX - t
        let limit = min((r - l) / 2, rect.height / 2)
        let b = min(bottom, limit), c = min(topConvex, limit)
        var p = Path()
        if t > 0.01 {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: l, y: rect.minY + t), control: CGPoint(x: l, y: rect.minY))
        } else {
            p.move(to: CGPoint(x: l, y: rect.minY + c))
        }
        p.addArc(tangent1End: CGPoint(x: l, y: rect.maxY), tangent2End: CGPoint(x: r, y: rect.maxY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r, y: rect.maxY), tangent2End: CGPoint(x: r, y: rect.minY), radius: b)
        if t > 0.01 {
            p.addLine(to: CGPoint(x: r, y: rect.minY + t))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: r, y: rect.minY))
        } else {
            p.addArc(tangent1End: CGPoint(x: r, y: rect.minY), tangent2End: CGPoint(x: l, y: rect.minY), radius: c)
            p.addArc(tangent1End: CGPoint(x: l, y: rect.minY), tangent2End: CGPoint(x: l, y: rect.maxY), radius: c)
        }
        p.closeSubpath()
        return p
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.85))
    }
}
