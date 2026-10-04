import SwiftUI

// Friends, people played with lately and people blocked (Play → Friends),
// joining with an invitation, and — for a grown-up — the reports kept on
// this iPad (Settings → Family).

/// Friends, recent players, blocked players.
struct FriendsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var cloud: CloudService
    @Environment(\.dismiss) private var dismiss
    /// Joins the room a friend is in.
    var onJoin: (DiscoveredPeer) -> Void
    /// Joins the internet room a friend is in.
    var onJoinInternet: (CloudRoom) -> Void = { _ in }

    private enum Tab: String, CaseIterable, Identifiable {
        case friends, internet, recent, blocked
        var id: String { rawValue }
        var title: String {
            switch self {
            case .friends: return L("Friends")
            case .internet: return L("Internet")
            case .recent: return L("Played with")
            case .blocked: return L("Blocked")
            }
        }
    }

    @State private var tab: Tab = .friends
    @State private var naming: PlayerContact?
    @State private var noting: PlayerContact?
    @State private var search = ""
    @State private var sort: FriendSort = .name
    @State private var group: FriendGroup?

    private var tabs: [Tab] {
        cloud.allowsFriends ? Tab.allCases : Tab.allCases.filter { $0 != .internet }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker(L("Friends"), selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch tab {
                case .friends: friends
                case .internet:
                    InternetFriendsList { room in
                        dismiss()
                        onJoinInternet(room)
                    }
                case .recent: recent
                case .blocked: blocked
                }
            }
            .navigationTitle(L("Friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
        .sheet(item: $naming) { friend in
            NicknameSheet(friend: friend).environmentObject(settings)
        }
        .sheet(item: $noting) { friend in
            FriendNoteSheet(friend: friend).environmentObject(settings)
        }
    }

    /// The room a friend is in, from the list of rooms nearby.
    private func room(of friend: PlayerContact) -> DiscoveredPeer? {
        session.discoveredPeers.first { $0.people.contains(friend.id) && $0.isCompatible && !$0.isFull }
    }

    /// How many friends, how many people met, and who is played with most.
    private var socialSummary: some View {
        let book = settings.social
        return HStack(spacing: 14) {
            Label(L("{} of {} friends", book.friends.count, SocialBook.maximumFriends), systemImage: "person.2.fill")
            Label(L("{} people met", book.recent.count), systemImage: "figure.2.arms.open")
            if let closest = book.closestFriend, closest.timesMet > 1 {
                Label(L("Most with {}", closest.shownName), systemImage: "heart.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(Ablox.Palette.inkMuted)
        .listRowBackground(Color.clear)
    }

    /// Search, order and group, once there are enough friends to need them.
    @ViewBuilder private var friendTools: some View {
        if settings.social.friends.count > 3 {
            AbloxTextField(L("Search friends"), text: $search)
            Picker(L("Order"), selection: $sort) {
                ForEach(FriendSort.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(L("Group"), selection: $group) {
                Text(L("Everyone")).tag(FriendGroup?.none)
                ForEach(FriendGroup.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag(Optional($0)) }
            }
        }
    }

    @ViewBuilder private var friends: some View {
        socialSummary
        if settings.social.friends.isEmpty {
            Text(L("No friends yet. In a game, open the player list, tap … next to someone and choose Add friend."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
        friendTools
        ForEach(settings.social.friends(sortedBy: sort, group: group, search: search)) { friend in
            HStack {
                Button {
                    settings.social.setFavourite(!friend.isFavourite, for: friend.id)
                } label: {
                    Image(systemName: friend.isFavourite ? "pin.fill" : "pin")
                        .foregroundStyle(friend.isFavourite ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(friend.isFavourite ? L("Unpin") : L("Pin to the top"))
                contactText(friend)
                Spacer()
                if let room = room(of: friend) {
                    Button {
                        dismiss()
                        onJoin(room)
                    } label: {
                        Label(L("Join"), systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(NeonButtonStyle(.primary))
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    settings.social.removeFriend(friend.id)
                } label: {
                    Label(L("Remove friend"), systemImage: "person.badge.minus")
                }
                Button {
                    naming = friend
                } label: {
                    Label(L("Nickname"), systemImage: "character.cursor.ibeam")
                }
                .tint(Ablox.Palette.accent)
            }
            .contextMenu {
                Button {
                    naming = friend
                } label: {
                    Label(L("Nickname"), systemImage: "character.cursor.ibeam")
                }
                if friend.nickname != nil {
                    Button {
                        settings.social.setNickname("", for: friend.id)
                    } label: {
                        Label(L("Remove the nickname"), systemImage: "xmark")
                    }
                }
                Button {
                    noting = friend
                } label: {
                    Label(L("Note"), systemImage: "note.text")
                }
                Menu {
                    Button(L("No group")) { settings.social.setGroup(nil, for: friend.id) }
                    ForEach(FriendGroup.allCases) { choice in
                        Button {
                            settings.social.setGroup(choice, for: friend.id)
                        } label: {
                            Label(choice.displayName, systemImage: choice.symbolName)
                        }
                    }
                } label: {
                    Label(L("Group"), systemImage: "tag")
                }
                Button {
                    settings.social.setFavourite(!friend.isFavourite, for: friend.id)
                } label: {
                    Label(friend.isFavourite ? L("Unpin") : L("Pin to the top"), systemImage: "pin")
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        if settings.social.recent.isEmpty {
            Text(L("People you play with appear here."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
        let today = settings.social.metToday()
        if !today.isEmpty {
            Label(L("{} played with today", today.count), systemImage: "sun.max.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.warning)
                .listRowBackground(Color.clear)
        }
        ForEach(settings.social.recent) { contact in
            HStack {
                contactText(contact)
                Spacer()
                if settings.social.isFriend(contact.id) {
                    Image(systemName: "star.fill").foregroundStyle(Ablox.Palette.warning)
                } else if !settings.social.isBlocked(contact.id) {
                    Button {
                        settings.social.addFriend(contact.id, name: contact.name)
                    } label: {
                        Label(L("Add friend"), systemImage: "person.badge.plus")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    settings.block(contact.id, name: contact.name)
                    session.muteList = settings.muteList
                } label: {
                    Label(L("Block"), systemImage: "hand.raised.slash")
                }
            }
        }
        if !settings.social.recent.isEmpty {
            Button(L("Clear this list"), role: .destructive) { settings.social.forgetRecent() }
        }
    }

    @ViewBuilder private var blocked: some View {
        if settings.social.blocked.isEmpty {
            Text(L("Nobody is blocked. Blocking someone hides what they say, and warns you before you join a room they are in."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
        ForEach(settings.social.blocked) { contact in
            HStack {
                Text(contact.name)
                Spacer()
                Button(L("Unblock")) {
                    settings.unblock(contact.id)
                    session.muteList = settings.muteList
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
    }

    private func contactText(_ contact: PlayerContact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(contact.shownName)
                    .font(.headline)
                if contact.nickname != nil {
                    Text(contact.name)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                if let group = contact.group {
                    Label(group.displayName, systemImage: group.symbolName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Ablox.Palette.accent.opacity(0.18), in: Capsule())
                }
            }
            Text(L("{} · {}", contact.lastGame.isEmpty ? "Ablox" : contact.lastGame,
                   contact.lastSeen.formatted(.relative(presentation: .named))))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            // How long and how often, for friends.
            if let since = contact.friendSince {
                Text(L("Friends since {} · played together {} times", since.formatted(date: .abbreviated, time: .omitted), contact.timesMet))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            } else if contact.timesMet > 1 {
                Text(L("Played together {} times", contact.timesMet))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            if let note = contact.note {
                Label(note, systemImage: "note.text")
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
    }
}

// MARK: - Joining with an invitation

/// A QR code from the host's screen, or the invitation text they sent.
struct InvitationJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onJoin: (JoinTicket) -> Void

    @State private var scanning = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if scanning {
                    QRScannerView { ticket in
                        dismiss()
                        onJoin(ticket)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxHeight: 420)
                } else {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(Ablox.Palette.accent)
                    Text(L("The host can show a QR code: Menu → Room → Invite."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    if QRScannerView.isAvailable {
                        Button {
                            scanning.toggle()
                        } label: {
                            Label(scanning ? L("Stop the camera") : L("Scan a QR code"), systemImage: "camera.fill")
                        }
                        .buttonStyle(NeonButtonStyle(.primary))
                    }
                    Button {
                        guard let text = UIPasteboard.general.string, let ticket = JoinTicket(text: text) else {
                            problem = L("There's no invitation to paste. Copy the text the host sent first.")
                            return
                        }
                        dismiss()
                        onJoin(ticket)
                    } label: {
                        Label(L("Paste an invitation"), systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.warning)
                }
                Text(L("For iPads that can't see each other's rooms in the list — on some school networks, or over a VPN. Both still need to reach each other: playing across the internet would need a server, which Ablox doesn't have."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkFaint)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(L("Join with an invitation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
            }
        }
        .abloxColorScheme()
    }
}

// MARK: - Reports, for a grown-up

struct ReportsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [PlayerReport] = []
    @State private var sharing: SharedFile?

    var body: some View {
        NavigationStack {
            List {
                if reports.isEmpty {
                    Text(L("No reports. If a player reports someone, it is kept here with the chat and a picture."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(report.playerName).font(.headline)
                            Spacer()
                            Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                        }
                        Text(report.reason.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ablox.Palette.warning)
                        if !report.note.isEmpty {
                            Text(report.note).font(.subheadline)
                        }
                        Text(L("In {}", report.game))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        if let url = ReportStore.pictureURL(of: report), let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        ForEach(report.chat.suffix(8), id: \.self) { line in
                            Text(verbatim: line)
                                .font(.caption.monospaced())
                                .foregroundStyle(Ablox.Palette.inkMuted)
                        }
                        Button {
                            share(report)
                        } label: {
                            Label(L("Share this report"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        Button(role: .destructive) {
                            ReportStore.delete(report)
                            reports = ReportStore.all()
                        } label: {
                            Label(L("Delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(L("Reports"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
        .onAppear { reports = ReportStore.all() }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
    }

    /// The report as a text file, with its picture beside it when there is one.
    private func share(_ report: PlayerReport) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ablox report \(report.playerName).txt")
        guard (try? report.summary.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        sharing = SharedFile(url: url)
    }
}

// MARK: - A note about a friend

struct FriendNoteSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let friend: PlayerContact
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("A note about {}", friend.shownName), systemImage: "note.text")
                .font(.headline)
            Text(L("Only on this iPad. Like: sits next to me in class, loves racing games."))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("Note"), text: $text, limit: SocialBook.maximumNoteLength, onSubmit: save)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Button(L("Cancel")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary))
                Spacer()
                Button(L("Save"), action: save)
                    .buttonStyle(NeonButtonStyle(.primary))
            }
        }
        .padding(24)
        .presentationDetents([.height(260)])
        .abloxColorScheme()
        .onAppear { text = friend.note ?? "" }
    }

    private func save() {
        settings.social.setNote(text, for: friend.id)
        dismiss()
    }
}
