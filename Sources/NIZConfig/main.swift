import AppKit
import NIZKit
import SwiftUI

struct NIZConfigApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("NIZ Config", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 560)
        }
        .defaultSize(width: 1240, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Profile…") { model.openProfile() }.keyboardShortcut("o")
                Button("Save Profile…") { model.saveProfile() }.keyboardShortcut("s")
            }
            CommandMenu("Keyboard") {
                Button("Read from Keyboard") { model.readAll() }.keyboardShortcut("r")
                    .disabled(!model.isConnected || model.busy != nil)
                Button("Write Keys") { model.requestWriteKeys() }.keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(!model.isConnected || model.busy != nil)
                Button("Write Lighting") { model.writeLighting() }
                    .disabled(!model.isConnected || model.busy != nil)
                Divider()
                Button("Load Factory Key Layout") { model.loadFactoryKeys() }
            }
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case keys = "Keys", lighting = "Lighting", stats = "Stats"
    var id: String { rawValue }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var tab = Tab.keys

    var body: some View {
        VStack(spacing: 0) {
            switch model.connection {
            case .macMode(let name):
                MacModeHelp(product: name)
            default:
                switch tab {
                case .keys: KeymapPane(model: model)
                case .lighting: LightingPane(model: model)
                case .stats: StatsPane(model: model)
                }
            }
            Divider()
            StatusBar(model: model)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.readAll() } label: { Label("Read", systemImage: "arrow.down.circle") }
                    .help("Read keys, lighting and counters from the keyboard")
                    .disabled(!model.isConnected || model.busy != nil)
                switch tab {
                case .keys:
                    Button { model.revertKeys() } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                        .disabled(!model.keysDirty || model.busy != nil)
                    Button { model.requestWriteKeys() } label: { Label("Write Keys", systemImage: "square.and.arrow.down.on.square") }
                        .help("Write the base and Fn layers to the keyboard")
                        .disabled(!model.isConnected || model.busy != nil || !model.keysDirty)
                case .lighting:
                    Button { model.revertLighting() } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                        .disabled(!model.lightingDirty || model.busy != nil)
                    Button { model.writeLighting() } label: { Label("Write Lighting", systemImage: "square.and.arrow.down.on.square") }
                        .disabled(!model.isConnected || model.busy != nil || !model.lightingDirty)
                case .stats:
                    Button { model.readCounters() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(!model.isConnected || model.busy != nil)
                }
            }
        }
        .navigationTitle("NIZ Config")
        .alert("Write this layout anyway?", isPresented: Binding {
            !model.pendingWriteWarnings.isEmpty
        } set: { if !$0 { model.pendingWriteWarnings = [] } }) {
            Button("Write Anyway", role: .destructive) { model.writeKeys() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.pendingWriteWarnings.joined(separator: "\n\n"))
        }
    }
}

struct StatusBar: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            Text(statusText).lineLimit(1)
            if !model.firmware.isEmpty, model.isConnected {
                Text(model.firmware).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let busy = model.busy {
                Text(busy + "…").foregroundStyle(.secondary)
                if let p = model.progress {
                    ProgressView(value: p).frame(width: 120)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if let err = model.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).lineLimit(2)
            } else if let note = model.notice {
                Label(note, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).lineLimit(1)
            } else if model.keysDirty || model.lightingDirty {
                Text("Unwritten changes").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var statusText: String {
        switch model.connection {
        case .searching: return "Waiting for keyboard (USB)…"
        case .macMode(let n): return "\(n) is in Mac mode"
        case .connected(let i): return String(format: "%@ (%04X:%04X)", i.product, i.vendorID, i.productID)
        case .failed(let e): return e
        }
    }

    private var dotColor: Color {
        switch model.connection {
        case .connected: return .green
        case .macMode: return .orange
        case .searching: return .gray
        case .failed: return .red
        }
    }
}

struct MacModeHelp: View {
    var product: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("\(product) is in Mac mode").font(.title2.bold())
            Text("In Mac mode the keyboard pretends to be an Apple keyboard and hides its configuration interface.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Hold **Fn** and press **Left Alt** (third key from the left on the bottom row).", systemImage: "1.circle")
                Label("Unplug the USB cable and plug it back in.", systemImage: "2.circle")
                Label("This window connects automatically.", systemImage: "3.circle")
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Text("To return to Mac mode afterwards, do the same again.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

NSApplication.shared.setActivationPolicy(.regular)
NIZConfigApp.main()
