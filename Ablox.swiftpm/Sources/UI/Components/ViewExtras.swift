import SwiftUI
import AbloxCore

// Every modifier the app adds to `View`, in one file that seldom changes.
//
// An extension of `View` makes its file a dependency of every SwiftUI file
// in the app, so one in a screen's own file would make any change to that
// screen rebuild them all (AbloxCore/Comparisons.swift says why). A new
// modifier goes here, or is a `ViewModifier` used with `.modifier(_:)`.
// The design system's own, shared with Studio, are in DesignSystem.swift.

// MARK: - Access (rules in AbloxCore/FamilyExtras.swift)

extension View {
    /// Bold text and less motion, as chosen, for everything inside.
    func abloxAccess(_ options: AccessOptions) -> some View {
        self
            .bold(options.boldText)
            .transaction { transaction in
                if options.reduceMotion { transaction.animation = nil }
            }
    }
}

// MARK: - Leaving as the host

extension View {
    /// For a host with people still playing: hand the room on, or end it
    /// for everyone.
    func leaveRoomChoice(isPresented: Binding<Bool>, session: SessionCoordinator, onLeave: @escaping () -> Void) -> some View {
        confirmationDialog(L("Leave the room?"), isPresented: isPresented, titleVisibility: .visible) {
            if let next = HostMove.successor(in: session.people, leavingHost: session.localPeerID) {
                Button(L("Hand the room to {} and leave", next.profile.displayName)) {
                    session.handOverAndLeave()
                    onLeave()
                }
            }
            Button(L("End the game for everyone"), role: .destructive, action: onLeave)
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Handing it over keeps the game going on another iPad, with the same room code."))
        }
    }
}

// MARK: - Who can join (the dialog is in RoomVisibility.swift)

extension View {
    /// Asks who can join before a room opens.
    func roomVisibilityDialog(isPresented: Binding<Bool>, allowsPublic: Bool = true, allowsInternet: Bool = false,
                              onChoose: @escaping (_ access: RoomAccess) -> Void) -> some View {
        modifier(RoomVisibilityDialog(isPresented: isPresented, allowsPublic: allowsPublic, allowsInternet: allowsInternet,
                                      onChoose: onChoose))
    }
}
