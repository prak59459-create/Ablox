import SwiftUI

/// Who may come into a hosted room, asked when the host opens it.
///
/// Internet rooms are listed in the family's database and reached through
/// it (and are on the router too). Router-public rooms put their code in the
/// Bonjour advertisement, so anyone nearby joins from the list with one tap.
/// Router-private rooms keep the code off the air: only someone the host
/// tells it to can get in.
struct RoomVisibilityDialog: ViewModifier {
    @Binding var isPresented: Bool
    /// Settings → Family can rule public rooms out.
    var allowsPublic = true
    /// Settings → Family → Internet, with a database to use.
    var allowsInternet = false
    var onChoose: (_ access: RoomAccess) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(L("Who can join?"), isPresented: $isPresented, titleVisibility: .visible) {
            if allowsPublic && allowsInternet {
                Button(RoomAccess.internet.displayName) { onChoose(.internet) }
            }
            if allowsPublic {
                Button(RoomAccess.routerPublic.displayName) { onChoose(.routerPublic) }
            }
            Button(RoomAccess.routerPrivate.displayName) { onChoose(.routerPrivate) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("On the router, you can switch between public and private any time from the room code at the top of the screen."))
        }
    }
}
