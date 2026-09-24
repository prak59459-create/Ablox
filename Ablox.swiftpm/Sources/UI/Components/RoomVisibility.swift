import SwiftUI

/// Who may come into a hosted room, asked when the host opens it.
///
/// Public rooms put their code in the Bonjour advertisement, so anyone nearby
/// joins from the list with one tap. Private rooms keep the code off the air:
/// only someone the host tells it to can get in.
struct RoomVisibilityDialog: ViewModifier {
    @Binding var isPresented: Bool
    var onChoose: (_ isPublic: Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(L("Who can join?"), isPresented: $isPresented, titleVisibility: .visible) {
            Button(L("Public — anyone nearby can join")) { onChoose(true) }
            Button(L("Private — only people with the room code")) { onChoose(false) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("You can switch this any time from the room code at the top of the screen."))
        }
    }
}

extension View {
    /// Asks public or private before a room opens.
    func roomVisibilityDialog(isPresented: Binding<Bool>, onChoose: @escaping (_ isPublic: Bool) -> Void) -> some View {
        modifier(RoomVisibilityDialog(isPresented: isPresented, onChoose: onChoose))
    }
}
