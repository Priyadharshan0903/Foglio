import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance, workflow, agents, storage, shortcuts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .workflow: "Tasks & calendar"
        case .agents: "Agent connections"
        case .storage: "Data & storage"
        case .shortcuts: "Shortcuts"
        }
    }
    var subtitle: String {
        switch self {
        case .appearance: "Choose your colors and where the floating bar lives."
        case .workflow: "A few preferences for your day-to-day work."
        case .agents: "Connect your assistants to the workspace on this Mac."
        case .storage: "Find your files, export a backup, or restore your library."
        case .shortcuts: "Keep the things you do most close at hand."
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .workflow: "checklist"
        case .agents: "point.3.connected.trianglepath.dotted"
        case .storage: "externaldrive"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let hint: String?
    let theme: Theme
    @ViewBuilder var content: () -> Content

    init(_ title: String, hint: String? = nil, theme: Theme, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.hint = hint; self.theme = theme; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Typo.sans(14, .semibold)).foregroundStyle(theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let hint { Text(hint).font(Typo.sans(12)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1) }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let hint: String
    let theme: Theme
    @ViewBuilder var control: () -> Control
    init(_ title: String, hint: String, theme: Theme, @ViewBuilder control: @escaping () -> Control) {
        self.title = title; self.hint = hint; self.theme = theme; self.control = control
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Typo.sans(12.5, .medium)).foregroundStyle(theme.text)
            Text(hint).font(Typo.sans(11.5)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 200, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 26) { label; control().fixedSize() }
            VStack(alignment: .leading, spacing: 12) { label; control() }
        }
    }
}

/// The switch uses palette colors rather than the system accent.
struct SettingsSwitch: ToggleStyle {
    let theme: Theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            RoundedRectangle(cornerRadius: 11)
                .fill(configuration.isOn ? theme.accent : theme.muted.opacity(0.4))
                .frame(width: 36, height: 21)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? theme.onAccent : theme.surface)
                        .frame(width: 15, height: 15).padding(3)
                }.contentShape(Rectangle())
        }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme)).opacity(enabled ? 1 : 0.45)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
    }
}

struct SettingsFocus: ViewModifier {
    let theme: Theme
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).focusEffectDisabled().overlay {
            RoundedRectangle(cornerRadius: 6).stroke(focused ? theme.accentDeep : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
