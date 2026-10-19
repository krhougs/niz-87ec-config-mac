import NIZKit
import SwiftUI

struct KeyCapStyle {
    var title: String
    var subtitle: String?
    var fill: Color?
    var highlighted = false
    var dimmed = false
}

/// Draws the 87-key board; each key's look comes from `style`.
struct KeyboardView: View {
    var selection: Set<Int>
    var style: (Int) -> KeyCapStyle
    var onTap: (Int, NSEvent.ModifierFlags) -> Void

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width / Layout.width, geo.size.height / Layout.height)
            let gap = max(2, unit * 0.06)
            ZStack(alignment: .topLeading) {
                ForEach(Layout.keys) { key in
                    let s = style(key.position)
                    KeyCap(style: s, selected: selection.contains(key.position), unit: unit)
                        .frame(width: key.width * unit - gap, height: unit - gap)
                        .offset(x: key.x * unit, y: key.y * unit)
                        .onTapGesture {
                            onTap(key.position, NSEvent.modifierFlags)
                        }
                        .help(s.subtitle.map { "\(s.title) — \($0)" } ?? s.title)
                }
            }
            .frame(width: Layout.width * unit, height: Layout.height * unit, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(Layout.width / Layout.height, contentMode: .fit)
    }
}

private struct KeyCap: View {
    var style: KeyCapStyle
    var selected: Bool
    var unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
        ZStack {
            shape.fill(background)
            shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: selected ? 2.5 : 1)
            VStack(spacing: 1) {
                Text(style.title)
                    .font(.system(size: max(8, unit * 0.22), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let sub = style.subtitle {
                    Text(sub)
                        .font(.system(size: max(7, unit * 0.15)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(.horizontal, 3)
            .foregroundStyle(textColor)
            .opacity(style.dimmed ? 0.45 : 1)
        }
        .contentShape(shape)
    }

    private var background: Color {
        if let f = style.fill { return f }
        if style.highlighted { return Color.accentColor.opacity(0.22) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var textColor: Color {
        guard let f = style.fill, let c = NSColor(f).usingColorSpace(.sRGB) else { return .primary }
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return lum > 0.55 ? .black : .white
    }
}

extension RGB {
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: UInt8((c.redComponent * 255).rounded().clamped(0, 255)),
                  g: UInt8((c.greenComponent * 255).rounded().clamped(0, 255)),
                  b: UInt8((c.blueComponent * 255).rounded().clamped(0, 255)))
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
