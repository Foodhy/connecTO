import SwiftUI

struct ControlTileLabel: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 36)
    }
}

struct ControlTile: View {
    var systemName: String
    var title: String
    var accessibilityTitle: String?
    var tint: Color?
    var prominent = false
    var action: () -> Void

    init(
        _ systemName: String,
        _ title: String,
        accessibility: String? = nil,
        tint: Color? = nil,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.title = title
        self.accessibilityTitle = accessibility
        self.tint = tint
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            ControlTileLabel(systemName: systemName)
        }
        .tint(tint)
        .accessibilityLabel(accessibilityTitle ?? title)

        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
