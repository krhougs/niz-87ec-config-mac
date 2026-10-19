import NIZKit
import SwiftUI

struct LightingPane: View {
    @Bindable var model: AppModel
    @State private var selection: Set<Int> = []
    @State private var brush = Color(.sRGB, red: 1, green: 0.25, blue: 0.1)

    private let presets: [Color] = [
        .init(.sRGB, red: 1, green: 0, blue: 0), .init(.sRGB, red: 1, green: 0.5, blue: 0),
        .init(.sRGB, red: 1, green: 1, blue: 0), .init(.sRGB, red: 0, green: 1, blue: 0),
        .init(.sRGB, red: 0, green: 1, blue: 1), .init(.sRGB, red: 0, green: 0, blue: 1),
        .init(.sRGB, red: 1, green: 0, blue: 1), .init(.sRGB, red: 1, green: 1, blue: 1),
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                KeyboardView(selection: selection) { pos in
                    let c = model.lighting[pos - 1]
                    return KeyCapStyle(title: KeyCodes.label(Layout.defaultCode(forPosition: pos)),
                                       fill: c == .off ? Color.black.opacity(0.75) : c.color)
                } onTap: { pos, flags in
                    if flags.contains(.option) {
                        brush = model.lighting[pos - 1].color
                    } else if flags.contains(.command) || flags.contains(.shift) {
                        if selection.contains(pos) { selection.remove(pos) } else { selection.insert(pos) }
                    } else {
                        selection = [pos]
                    }
                }
                Text("Click to select, ⌘- or ⇧-click to add keys, ⌥-click to pick up a key's colour. These colours are the keyboard's custom backlight (Fn + ` toggles it on a stock layout).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

            Form {
                Section("Colour") {
                    ColorPicker("Brush", selection: $brush, supportsOpacity: false)
                    HStack(spacing: 6) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { _, c in
                            Button { brush = c } label: {
                                Circle().fill(c).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Paint selected keys (\(selection.count))") { paint(selection, RGB(brush)) }
                        .disabled(selection.isEmpty)
                    Button("Turn selected keys off") { paint(selection, .off) }
                        .disabled(selection.isEmpty)
                    Button("Paint every key") { paint(Set(1...Keymap.keyCount), RGB(brush)) }
                }
                Section("Select") {
                    Button("All keys") { selection = Set(1...Keymap.keyCount) }
                    Button("Same colour as selection") {
                        guard let first = selection.first else { return }
                        let c = model.lighting[first - 1]
                        selection = Set((1...Keymap.keyCount).filter { model.lighting[$0 - 1] == c })
                    }
                    .disabled(selection.isEmpty)
                    Button("Clear selection") { selection = [] }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
        }
    }

    private func paint(_ keys: Set<Int>, _ c: RGB) {
        for k in keys { model.lighting[k - 1] = c }
    }
}

struct StatsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        let counts = model.counters ?? Array(repeating: 0, count: Keymap.keyCount)
        let maxCount = Double(counts.max() ?? 1)
        let total = counts.reduce(0) { $0 + UInt64($1) }
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                KeyboardView(selection: []) { pos in
                    let n = counts[pos - 1]
                    let t = n == 0 ? 0 : log(Double(n) + 1) / log(maxCount + 1)
                    return KeyCapStyle(title: KeyCodes.label(Layout.defaultCode(forPosition: pos)),
                                       subtitle: n.formatted(.number.notation(.compactName)),
                                       fill: heat(t))
                } onTap: { _, _ in }
                Text("Lifetime keystrokes per physical key, stored in the keyboard.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

            List {
                Section("Total") {
                    Text(total.formatted()).font(.title2.monospacedDigit())
                }
                Section("Most used") {
                    ForEach(counts.enumerated().sorted { $0.element > $1.element }.prefix(25), id: \.offset) { i, n in
                        HStack {
                            Text(KeyCodes.name(Layout.defaultCode(forPosition: i + 1)))
                            Spacer()
                            Text(n.formatted()).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
        }
    }

    private func heat(_ t: Double) -> Color {
        // Cool blue for rarely used keys through to hot orange for the busiest.
        Color(hue: 0.62 - 0.55 * t, saturation: 0.25 + 0.6 * t, brightness: 0.95 - 0.1 * t)
    }
}
