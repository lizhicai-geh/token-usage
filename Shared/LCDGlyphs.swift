import SwiftUI

/// The LCD's vector glyphs, in a shared coordinate space with a baseline at 64.
enum LCDGlyphs {
    struct Glyph {
        let width: CGFloat
        let lit: Path
        var unlit = Path()
    }

    static let height: CGFloat = 64
    static let spacing: CGFloat = 5.5
    private static let digitWidth: CGFloat = 36

    // Draw three masters; reflecting the outer segments keeps every seam symmetric.
    private static let segments: [Path] = {
        let top = Path { path in
            path.move(to: CGPoint(x: 2, y: 1.8))
            path.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 4, y: 0))
            path.addLine(to: CGPoint(x: 29, y: 0))
            path.addQuadCurve(to: CGPoint(x: 34, y: 1.8), control: CGPoint(x: 32, y: 0))
            path.addLine(to: CGPoint(x: 28.9, y: 6.9))
            path.addLine(to: CGPoint(x: 7.1, y: 6.9))
            path.closeSubpath()
        }
        let left = Path { path in
            path.move(to: CGPoint(x: 1, y: 2.85))
            path.addQuadCurve(to: CGPoint(x: 0, y: 7), control: CGPoint(x: 0, y: 4.4))
            path.addLine(to: CGPoint(x: 0, y: 26.2))
            path.addQuadCurve(to: CGPoint(x: 2.1, y: 31), control: CGPoint(x: 0, y: 29))
            path.addLine(to: CGPoint(x: 6.4, y: 27.4))
            path.addLine(to: CGPoint(x: 6.4, y: 8.25))
            path.closeSubpath()
        }
        let middle = Path { path in
            path.addLines([
                CGPoint(x: 3.2, y: 32), CGPoint(x: 7.1, y: 28.7), CGPoint(x: 28.9, y: 28.7),
                CGPoint(x: 32.8, y: 32), CGPoint(x: 28.9, y: 35.3), CGPoint(x: 7.1, y: 35.3)
            ])
            path.closeSubpath()
        }
        let flipX = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: digitWidth, ty: 0)
        let flipY = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        let right = left.applying(flipX)

        // Top, upper right, lower right, bottom, lower left, upper left, middle.
        // A reflection reverses winding; contours stay separate within each glyph.
        return [top, right, right.applying(flipY), top.applying(flipY), left.applying(flipY), left, middle]
    }()

    static let glyphs: [Character: Glyph] = {
        let masks: [Character: UInt8] = [
            "0": 0x3f, "1": 0x06, "2": 0x5b, "3": 0x4f, "4": 0x66, "5": 0x6d,
            "6": 0x7d, "7": 0x07, "8": 0x7f, "9": 0x6f, "—": 0x40
        ]
        var glyphs = masks.mapValues { mask in
            var lit = Path()
            var unlit = Path()
            for (index, segment) in segments.enumerated() {
                if mask & (1 << index) != 0 {
                    lit.addPath(segment)
                } else {
                    unlit.addPath(segment)
                }
            }
            return Glyph(width: digitWidth, lit: lit, unlit: unlit)
        }

        let pointSize: CGFloat = 5.8
        glyphs["."] = Glyph(width: pointSize, lit: Path(roundedRect: CGRect(
            x: 0, y: height - pointSize, width: pointSize, height: pointSize), cornerRadius: 0.75))

        // Smaller, single-stroke unit letters use the same baseline as the numbers.
        glyphs["K"] = unit(10.5, [[(1, 0), (1, 14)], [(9.5, 0.7), (1, 8), (9.5, 13.3)]])
        glyphs["M"] = unit(12.5, [[(1, 14), (1, 0.75), (6.25, 7), (11.5, 0.75), (11.5, 14)]])
        glyphs["B"] = unit(10.5, [[(1, 7), (7, 7), (9, 5), (9, 2.75), (7, 1), (1, 1),
                                    (1, 13), (7.5, 13), (9.5, 11.25), (9.5, 9), (7, 7)]])
        glyphs["T"] = unit(10.5, [[(0, 1), (10.5, 1)], [(5.25, 1), (5.25, 14)]])
        glyphs["P"] = unit(10.5, [[(1, 14), (1, 1), (7.5, 1), (9.5, 3), (9.5, 6), (7.5, 8), (1, 8)]])
        glyphs["E"] = unit(10, [[(10, 1), (1, 1), (1, 13), (10, 13)], [(1, 7), (8.25, 7)]])
        return glyphs
    }()

    private static func unit(_ width: CGFloat, _ strokes: [[(CGFloat, CGFloat)]]) -> Glyph {
        var path = Path()
        for stroke in strokes {
            path.addLines(stroke.map { CGPoint(x: $0.0, y: height - 14 + $0.1) })
        }
        return Glyph(width: width, lit: path.strokedPath(StrokeStyle(lineWidth: 2, lineJoin: .bevel)))
    }
}
