import SwiftUI
import AbloxCore

/// Shift lock, on the play screen's top bar. Off, the character turns to
/// the way the stick walks it; on, it keeps facing where the camera looks.
struct ShiftLockButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "lock.fill" : "lock.open")
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(isOn ? Ablox.Palette.accent : .white)
        }
        .accessibilityLabel(L("Shift lock"))
        .accessibilityValue(isOn ? L("On") : L("Off"))
        .accessibilityHint(L("Your character faces where the camera looks"))
    }
}
