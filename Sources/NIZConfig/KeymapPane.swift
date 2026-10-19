import NIZKit
import SwiftUI

struct KeymapPane: View {
    @Bindable var model: AppModel
    @State private var layer = 0
    @State private var selected: Int? = 1

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Layer", selection: $layer) {
                        Text("Base layer").tag(0)
                        Text("Fn layer").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                    Legend()
                }
                KeyboardView(selection: selected.map { [$0] } ?? []) { pos in
                    style(for: pos)
                } onTap: { pos, _ in
                    selected = pos
                }
                Text(layer == 0
                     ? "Click a key to change what it sends. Highlighted keys differ from the factory layout."
                     : "Fn layer: what each key does while Fn is held. Empty keys do nothing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label("The keyboard keeps a factory layout and a programmable layout; Fn + Pause switches between them. Writing always updates the programmable one, and Read shows whichever is active.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

            Group {
                if let pos = selected {
                    KeyEditor(action: binding(layer: layer, position: pos), position: pos, layer: layer)
                        .id("\(layer)-\(pos)")
                } else {
                    ContentUnavailableView("No key selected", systemImage: "keyboard")
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
        }
    }

    private func binding(layer: Int, position: Int) -> Binding<KeyAction> {
        Binding(
            get: { model.keymap.layers[layer][position - 1] },
            set: { model.keymap.layers[layer][position - 1] = $0 }
        )
    }

    private func style(for pos: Int) -> KeyCapStyle {
        let action = model.keymap.layers[layer][pos - 1]
        let physical = KeyCodes.label(Layout.defaultCode(forPosition: pos))
        let factory = Keymap.factoryDefault.layers[layer][pos - 1]
        let changedFromDevice = model.deviceKeymap.map { $0.layers[layer][pos - 1] != action } ?? false
        var s = KeyCapStyle(title: action.shortLabel ?? physical)
        if action == .none {
            s.title = physical
            s.dimmed = true
        } else if s.title != physical {
            s.subtitle = physical
        }
        s.highlighted = action != factory
        if changedFromDevice {
            s.fill = Color.orange.opacity(0.35)
        }
        return s
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 12) {
            swatch(Color.accentColor.opacity(0.22), "Custom")
            swatch(Color.orange.opacity(0.35), "Not yet written")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func swatch(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 14, height: 10)
            Text(text)
        }
    }
}

extension KeyAction {
    var shortLabel: String? {
        switch self {
        case .none: return nil
        case .keys(let codes): return codes.map(KeyCodes.label).joined(separator: "+")
        case .repeating(_, let codes): return "⟳" + codes.map(KeyCodes.label).joined(separator: "+")
        case .macro: return "Macro"
        }
    }
}
