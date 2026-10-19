import NIZKit
import SwiftUI

/// Visual chooser for a hardware code: click it on a keyboard, pick from a
/// category grid, search by name, or press the key.
struct KeyPicker: View {
    var selected: Set<UInt8> = []
    var pick: (UInt8) -> Void

    @State private var tab = PickerTab.keyboard
    @State private var query = ""

    enum PickerTab: String, CaseIterable, Identifiable {
        case keyboard = "Keyboard", extra = "Numpad & more", media = "Media", mouse = "Mouse", function = "Functions"
        var id: String { rawValue }

        var codes: [UInt8] {
            switch self {
            case .keyboard: return []
            case .extra: return [72, 0xCC] + Array(91...107) + KeyCodes.codes(in: .power).map(\.code)
            case .media: return KeyCodes.codes(in: .media).map(\.code)
            case .mouse: return KeyCodes.codes(in: .mouse).map(\.code)
            case .function: return KeyCodes.codes(in: .function).map(\.code)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search keys and functions", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Divider().frame(height: 16)
                KeyCaptureButton(title: "Press a key", onCapture: pick)
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            if query.isEmpty {
                Picker("Category", selection: $tab) {
                    ForEach(PickerTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if tab == .keyboard {
                    KeyboardView(selection: []) { pos in
                        let code = Layout.defaultCode(forPosition: pos)
                        return KeyCapStyle(title: KeyCodes.label(code), highlighted: selected.contains(code))
                    } onTap: { pos, _ in
                        pick(Layout.defaultCode(forPosition: pos))
                    }
                    .frame(height: 250)
                    Text("Click the key you want. Right Win, the keypad, media and functions are in the other tabs.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    grid(tab.codes)
                }
            } else {
                let results = KeyCodes.all.filter {
                    $0.name.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query)
                }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query).frame(height: 250)
                } else {
                    grid(results.map(\.code))
                }
            }
        }
        .padding(14)
        .frame(width: 700)
    }

    private func grid(_ codes: [UInt8]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    KeyTile(code: code, selected: selected.contains(code)) { pick(code) }
                }
            }
            .padding(2)
        }
        .frame(height: 280)
    }
}

private struct KeyTile: View {
    let code: UInt8
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(KeyCodes.label(code)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(KeyCodes.name(code)).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor.opacity(0.25) : hover ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Any label that opens the key picker in a popover and closes it after a pick.
struct KeyPickerButton<Label: View>: View {
    var selected: Set<UInt8> = []
    var pick: (UInt8) -> Void
    @ViewBuilder var label: () -> Label
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $shown, arrowEdge: .leading) {
                KeyPicker(selected: selected) { code in
                    pick(code)
                    shown = false
                }
            }
    }
}

/// Keycap-looking chip showing one code.
struct KeyChip: View {
    let code: UInt8?
    var prominent = false

    var body: some View {
        HStack(spacing: 6) {
            if let code {
                Text(KeyCodes.label(code)).fontWeight(.semibold)
                if KeyCodes.label(code) != KeyCodes.name(code) {
                    Text(KeyCodes.name(code)).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Image(systemName: "plus")
                Text("Add key")
            }
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .font(prominent ? .body : .callout)
        .padding(.horizontal, 10)
        .padding(.vertical, prominent ? 7 : 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(code == nil ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.2),
                              style: StrokeStyle(lineWidth: 1, dash: code == nil ? [4, 3] : []))
        )
        .contentShape(Rectangle())
    }
}

/// Modifier toggles plus the main key(s): the usual way to build a shortcut.
struct ComboEditor: View {
    @Binding var codes: [UInt8]
    var limit = 6

    private static let modifiers: [(code: UInt8, title: String)] = [
        (67, "⌃ Ctrl"), (55, "⇧ Shift"), (69, "⌥ Alt"), (68, "⌘ Win"),
    ]
    private static let modifierCodes = Set(modifiers.map(\.code))

    /// Toggled modifiers and the remaining keys. A lone modifier counts as the key itself.
    private var split: (mods: [UInt8], keys: [UInt8]) {
        let mods = codes.filter { Self.modifierCodes.contains($0) }
        let keys = codes.filter { !Self.modifierCodes.contains($0) }
        if keys.isEmpty, let last = mods.last { return (Array(mods.dropLast()), [last]) }
        return (mods, keys)
    }

    var body: some View {
        let (mods, keys) = split
        VStack(alignment: .leading, spacing: 10) {
            Text("Key").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, code in
                    HStack(spacing: 2) {
                        KeyPickerButton(selected: [code]) { new in
                            var k = keys
                            k[i] = new
                            codes = mods + k
                        } label: { KeyChip(code: code, prominent: true) }
                        if keys.count > 1 {
                            Button {
                                var k = keys
                                k.remove(at: i)
                                codes = mods + k
                            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if codes.count < limit {
                    KeyPickerButton { codes = mods + keys + [$0] } label: { KeyChip(code: nil) }
                        .help("Add another key pressed at the same time")
                }
            }
            if keys.isEmpty {
                KeyPickerButton { codes = mods + [$0] } label: { KeyChip(code: nil, prominent: true) }
            }

            Text("Modifiers").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Self.modifiers, id: \.code) { m in
                    let on = mods.contains(m.code)
                    Button {
                        let newMods = on ? mods.filter { $0 != m.code } : Self.modifiers.map(\.code).filter { mods.contains($0) || $0 == m.code }
                        codes = newMods + keys.filter { !newMods.contains($0) }
                    } label: {
                        Text(m.title)
                            .font(.callout)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(on ? 0 : 0.2)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!on && codes.count >= limit)
                }
            }

            if !codes.isEmpty {
                Text("Sends: " + (mods + keys).map(KeyCodes.name).joined(separator: " + "))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
