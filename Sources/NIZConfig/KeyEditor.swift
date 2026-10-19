import NIZKit
import SwiftUI

struct KeyEditor: View {
    @Binding var action: KeyAction
    let position: Int
    let layer: Int

    private enum Kind: String, CaseIterable, Identifiable {
        case none = "None", keys = "Key / Combo", repeating = "Repeat", macro = "Macro"
        var id: String { rawValue }
    }

    private var kind: Binding<Kind> {
        Binding {
            switch action {
            case .none: return .none
            case .keys: return .keys
            case .repeating: return .repeating
            case .macro: return .macro
            }
        } set: { new in
            let codes = action.codes.isEmpty ? [Layout.defaultCode(forPosition: position)] : action.codes
            switch new {
            case .none: action = .none
            case .keys: action = .keys(Array(codes.prefix(6)))
            case .repeating: action = .repeating(interval: 50, keys: Array(codes.prefix(6)))
            case .macro: action = .macro(Macro(steps: codes.map { .init(code: $0) }))
            }
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Physical key", value: KeyCodes.name(Layout.defaultCode(forPosition: position)))
                LabeledContent("Position", value: "\(position)")
                Picker("Action", selection: kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
            } header: {
                Text(layer == 0 ? "Base layer" : "Fn layer")
            }

            switch action {
            case .none:
                Section {
                    Text("This key sends nothing on this layer.")
                        .foregroundStyle(.secondary)
                }
            case .keys(let codes):
                Section("Sends") {
                    ComboEditor(codes: Binding { codes } set: { action = .keys($0) })
                    if codes.contains(KeyCodes.fn) && codes.count == 1 {
                        Text("Fn has to be assigned on both the base and the Fn layer of the same key.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .repeating(let interval, let codes):
                Section("Repeat while held") {
                    MillisecondsField(title: "Every", value: Binding { interval } set: { action = .repeating(interval: $0, keys: codes) })
                    ComboEditor(codes: Binding { codes } set: { action = .repeating(interval: interval, keys: $0) })
                }
            case .macro(let macro):
                MacroEditor(macro: Binding { macro } set: { action = .macro($0) })
            }

            Section {
                Button("Restore factory assignment") {
                    action = Keymap.factoryDefault.layers[layer][position - 1]
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct MillisecondsField: View {
    var title: String
    @Binding var value: UInt16

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: Binding { Int(value) } set: { value = UInt16(clamping: max(0, $0)) }, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("ms").foregroundStyle(.secondary)
            }
        }
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro

    var body: some View {
        Section("Playback") {
            Picker("Mode", selection: $macro.mode) {
                Text("Play a number of times").tag(Macro.Mode.times)
                Text("Play while held").tag(Macro.Mode.whileHeld)
                Text("Press to start / stop").tag(Macro.Mode.toggle)
            }
            if macro.mode == .times {
                Stepper(value: Binding { Int(macro.cycles) } set: { macro.cycles = UInt8(clamping: $0) }, in: 1...255) {
                    LabeledContent("Repeat", value: "\(macro.cycles)×")
                }
            }
            Toggle("Separate delay per step", isOn: $macro.perStepDelays)
            if !macro.perStepDelays {
                MillisecondsField(title: "Delay between steps", value: $macro.autoDelay)
            }
        }
        Section("Steps (\(macro.steps.count))") {
            ForEach(Array(macro.steps.enumerated()), id: \.offset) { i, step in
                HStack {
                    Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                    KeyPickerButton(selected: [step.code]) { macro.steps[i].code = $0 } label: {
                        KeyChip(code: step.code)
                    }
                    Spacer()
                    if macro.perStepDelays {
                        TextField("ms", value: Binding { Int(step.delay) } set: { macro.steps[i].delay = UInt16(clamping: max(0, $0)) }, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        Text("ms").foregroundStyle(.secondary)
                    }
                    Button { macro.steps.swapAt(i, i - 1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(i == 0)
                    Button(role: .destructive) { macro.steps.remove(at: i) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                KeyPickerButton { macro.steps.append(.init(code: $0)) } label: { KeyChip(code: nil) }
                KeyCaptureButton(title: "Add by pressing…") { macro.steps.append(.init(code: $0)) }
            }
        }
    }
}
