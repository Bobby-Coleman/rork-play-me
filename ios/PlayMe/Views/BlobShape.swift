import SwiftUI

struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.4),
            control1: CGPoint(x: w * 0.85, y: h * 0.02),
            control2: CGPoint(x: w * 1.05, y: h * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.6, y: h),
            control1: CGPoint(x: w * 0.95, y: h * 0.6),
            control2: CGPoint(x: w * 0.85, y: h * 0.9)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.55),
            control1: CGPoint(x: w * 0.35, y: h * 1.1),
            control2: CGPoint(x: w * -0.05, y: h * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.05, y: h * 0.25),
            control2: CGPoint(x: w * 0.2, y: h * -0.05)
        )
        path.closeSubpath()
        return path
    }
}
