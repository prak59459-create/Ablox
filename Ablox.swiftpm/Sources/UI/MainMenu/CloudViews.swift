import SwiftUI

// Everything on screen about the internet: the rooms open there (Play), the
// friends added by friend code and their chat (Play → Friends → Internet),
// and what a grown-up switches on (Settings → Family → Internet).

// MARK: - Internet rooms

/// Rooms anyone with Ablox can join, from the family's database.
struct InternetRoomsSection: View {
    @EnvironmentObject private var cloud: CloudService
    @EnvironmentObject private var settings: AppSettings
    var onJoin: (CloudRoom) -> Void

    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L("Internet rooms"), systemImage: "globe") {
                Button {
                    Task { await refresh() }
                } label: {
                    if loading {
                        ProgressView().controlSize(.small).tint(Ablox.Palette.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ablox.Palette.accent)
                .accessibilityLabel(L("Refresh"))
            }

            switch cloud.state {
            case .off, .connecting:
                GlassCard {
                    HStack(spacing: 10) {
                        ProgressView().tint(Ablox.Palette.accent)
                        Text(L("Connecting to the internet…"))
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
            case let .failed(message):
                GlassCard {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .ready:
                if cloud.rooms.isEmpty {
                    GlassCard {
                        EmptyStateView(title: L("No internet rooms right now"),
                                       message: L("Host a game and choose Internet, and it appears here for everyone."),
                                       systemImage: "globe")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(cloud.rooms) { room in
                            roomCard(room)
                        }
                    }
                }
            }
        }
        .task {
            // Every ten seconds while the list is on screen.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func refresh() async {
        loading = true
        await cloud.refreshRooms()
        loading = false
    }

    private func roomCard(_ room: CloudRoom) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(room.world)
                    .font(.headline)
                    .lineLimit(1)
                Text(L("Hosted by {}", room.hostName))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                HStack {
                    Badge(L("{}/{} players", room.players, room.capacity),
                          color: room.isFull ? Ablox.Palette.warning : Ablox.Palette.success, systemImage: "person.2.fill")
                    Spacer()
                    Button(L("Join")) { onJoin(room) }
                        .buttonStyle(NeonButtonStyle(.primary))
                        .disabled(room.isFull || !room.isCompatible)
                }
                if !room.isCompatible {
                    Text(room.protocolVersion > AbloxProtocol.version
                         ? L("That iPad has a newer Ablox. Update this one in Settings, then join.")
                         : L("That iPad has an older Ablox. It needs to update before you can join."))
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.warning)
                }
            }
        }
    }
}

// MARK: - A friend's look

/// A small drawing of someone's avatar: head, body and the colour they chose.
struct SkinBadge: View {
    let avatar: AvatarProfile
    var size: CGFloat = 34

    private func color(_ value: ColorRGBA) -> Color {
        Color(red: Double(value.r), green: Double(value.g), blue: Double(value.b))
    }

    var body: some View {
        VStack(spacing: size * 0.04) {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(color(avatar.headColor))
                .frame(width: size * 0.42, height: size * 0.38)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(color(avatar.bodyColor))
                .frame(width: size * 0.62, height: size * 0.46)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(color(avatar.accentColor)).frame(height: size * 0.1)
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Friends over the internet

struct InternetFriendsList: View {
    @EnvironmentObject private var cloud: CloudService
    @EnvironmentObject private var session: SessionCoordinator
    var onJoinRoom: (CloudRoom) -> Void

    @State private var code = ""
    @State private var problem: String?
    @State private var adding = false
    @State private var chatting: CloudFriend?

    var body: some View {
        Group {
            Section {
                if let friendCode = cloud.friendCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Your friend code"))
                                .font(.caption)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                            Text(verbatim: CloudIDs.displayFriendCode(friendCode))
                                .font(.title2.monospaced().weight(.bold))
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = CloudIDs.displayFriendCode(friendCode)
                        } label: {
                            Label(L("Copy"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(NeonButtonStyle(.secondary))
                    }
                } else if case let .failed(message) = cloud.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Ablox.Palette.warning)
                } else {
                    HStack {
                        ProgressView()
                        Text(L("Connecting to the internet…")).foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
                HStack {
                    AbloxTextField(L("A friend's code, like ABCD-2345"), text: $code, limit: 12) { add() }
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(L("Add")) { add() }
                        .buttonStyle(NeonButtonStyle(.primary))
                        .disabled(adding || code.isEmpty || !cloud.isReady)
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(Ablox.Palette.warning)
                }
            } footer: {
                Text(L("Give your code only to people you know. Someone is a friend once you have both added each other; only then can you see what they play and chat."))
            }

            if !cloud.requests.isEmpty {
                Section(L("Want to be friends")) {
                    ForEach(cloud.requests) { request in
                        HStack {
                            Text(request.name).font(.headline)
                            Spacer()
                            Button(L("Accept")) { cloud.accept(request) }
                                .buttonStyle(NeonButtonStyle(.primary))
                            Button(L("No thanks")) { cloud.decline(request) }
                                .buttonStyle(NeonButtonStyle(.secondary))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                cloud.block(request.id)
                            } label: {
                                Label(L("Block"), systemImage: "hand.raised.slash")
                            }
                        }
                    }
                }
            }

            Section(L("Internet friends")) {
                if cloud.friends.isEmpty {
                    Text(L("No internet friends yet. Swap friend codes with someone you know."))
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(cloud.friends) { friend in
                    friendRow(friend)
                        .swipeActions {
                            Button(role: .destructive) {
                                cloud.remove(friend)
                            } label: {
                                Label(L("Remove friend"), systemImage: "person.badge.minus")
                            }
                            Button {
                                cloud.block(friend.id)
                            } label: {
                                Label(L("Block"), systemImage: "hand.raised.slash")
                            }
                            .tint(Ablox.Palette.danger)
                        }
                }
            }
        }
        .sheet(item: $chatting) { friend in
            CloudChatSheet(friend: friend)
                .environmentObject(cloud)
        }
    }

    private func friendRow(_ friend: CloudFriend) -> some View {
        let now = Date().timeIntervalSince1970 * 1000
        let online = friend.profile?.isOnline(now: now) ?? false
        return HStack(spacing: 12) {
            if let profile = friend.profile {
                SkinBadge(avatar: profile.avatar)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(online ? Ablox.Palette.success : Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    }
            } else {
                Image(systemName: "hourglass")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.label).font(.headline)
                    if let title = friend.profile?.avatar.title, !title.isEmpty {
                        Text(title).font(.caption2).foregroundStyle(Ablox.Palette.warning)
                    }
                }
                Text(status(friend, online: online))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
            if online, friend.profile?.room != nil, cloud.allowsInternetPlay {
                Button {
                    Task {
                        if let key = friend.profile?.room {
                            if !cloud.rooms.contains(where: { $0.id == key }) { await cloud.refreshRooms() }
                            if let room = cloud.rooms.first(where: { $0.id == key }) {
                                onJoinRoom(room)
                            } else {
                                problem = L("That room has closed.")
                            }
                        }
                    }
                } label: {
                    Label(L("Join"), systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(NeonButtonStyle(.primary))
            }
            if friend.isMutual, cloud.allowsChat {
                Button {
                    chatting = friend
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .overlay(alignment: .topTrailing) {
                            if friend.hasUnread {
                                Circle().fill(Ablox.Palette.danger).frame(width: 9, height: 9).offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(NeonButtonStyle(.secondary))
                .accessibilityLabel(L("Chat with {}", friend.label))
            }
        }
    }

    private func status(_ friend: CloudFriend, online: Bool) -> String {
        guard let profile = friend.profile else { return L("Waiting for them to add you back") }
        guard online else {
            guard profile.seen > 0 else { return L("Offline") }
            let seen = Date(timeIntervalSince1970: profile.seen / 1000)
            return L("Last on {}", seen.formatted(.relative(presentation: .named)))
        }
        if let game = profile.game, !game.isEmpty { return L("Playing {}", game) }
        return L("Online")
    }

    private func add() {
        let typed = code
        adding = true
        problem = nil
        Task {
            problem = await cloud.addFriend(code: typed)
            if problem == nil { code = "" }
            adding = false
        }
    }
}

// MARK: - Chat with one friend

struct CloudChatSheet: View {
    @EnvironmentObject private var cloud: CloudService
    @Environment(\.dismiss) private var dismiss
    let friend: CloudFriend

    @State private var draft = ""
    @State private var problem: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if cloud.messages.isEmpty {
                                Text(L("Say hello! Messages are only for the two of you, and the chat filter still applies."))
                                    .font(.subheadline)
                                    .foregroundStyle(Ablox.Palette.inkMuted)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 30)
                            }
                            ForEach(cloud.messages) { message in
                                bubble(message).id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: cloud.messages.last?.id) { _, last in
                        if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                    }
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(Ablox.Palette.warning).padding(.horizontal, 16)
                }
                HStack(spacing: 10) {
                    AbloxTextField(L("Message"), text: $draft, limit: CloudMessage.maximumLength) { send() }
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(L("Send"))
                }
                .padding(16)
            }
            .navigationTitle(friend.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { cloud.openChat(with: friend) }
        .onDisappear { cloud.closeChat() }
    }

    private func bubble(_ message: CloudMessage) -> some View {
        let mine = message.from == cloud.uid
        return HStack {
            if mine { Spacer(minLength: 60) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(mine ? Ablox.Palette.accentDeep.opacity(0.7) : Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            if !mine { Spacer(minLength: 60) }
        }
    }

    private func send() {
        let text = draft
        sending = true
        problem = nil
        Task {
            problem = await cloud.send(text)
            if problem == nil { draft = "" }
            sending = false
        }
    }
}

// MARK: - For a grown-up

/// Settings → Family → Internet: what may happen over the internet, and
/// which database it goes through.
struct InternetFamilySection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var cloud: CloudService
    @State private var copied = false
    @State private var showingAdvanced = false

    var body: some View {
        Section {
            Toggle(L("Internet rooms"), isOn: $settings.cloud.allowInternetPlay)
            Toggle(L("Friends over the internet"), isOn: $settings.cloud.allowFriends)
            Toggle(L("Chat with internet friends"), isOn: $settings.cloud.allowFriendChat)
                .disabled(!settings.cloud.allowFriends)
            Toggle(L("Friends can see what I'm playing"), isOn: $settings.cloud.shareWhatIPlay)
                .disabled(!settings.cloud.allowFriends)

            if CloudConfig.builtIn.isUsable {
                Label(L("Uses Ablox's own database."), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.success)
            }
            // Only for a family running its own database; the built-in one
            // needs nothing typed.
            DisclosureGroup(L("Advanced: use a different database"), isExpanded: $showingAdvanced) {
                HStack {
                    AbloxTextField(L("Database URL (https://…firebasedatabase.app)"), text: $settings.cloud.custom.databaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    pasteButton { settings.cloud.custom.databaseURL = $0 }
                }
                HStack {
                    AbloxTextField(L("Web API key"), text: $settings.cloud.custom.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    pasteButton { settings.cloud.custom.apiKey = $0 }
                }
                if !settings.cloud.custom.databaseURL.isEmpty && !settings.cloud.custom.isUsable {
                    Text(L("That doesn't look like a Firebase Realtime Database address and key yet."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.warning)
                }
                if settings.cloud.custom != CloudConfig() {
                    Button(L("Go back to Ablox's own database"), role: .destructive) {
                        settings.cloud.custom = CloudConfig()
                    }
                }
                Button {
                    UIPasteboard.general.string = CloudRules.json
                    copied = true
                } label: {
                    Label(copied ? L("Copied — paste them in the Firebase console") : L("Copy the database rules"),
                          systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
            }
            .onAppear { showingAdvanced = !CloudConfig.builtIn.isUsable }

            HStack {
                Text(L("Status"))
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.trailing)
            }

        } header: {
            Text(L("Internet"))
        } footer: {
            Text(L("Everything here starts off. Internet rooms and friends go through Ablox's database: games travel through it encrypted, a profile (name, look, what they're playing) is readable only by friends who have added each other, and chat only by the two friends in it. No real names or places are sent."))
        }
    }

    /// Long and fiddly to type: pasted from the Firebase console instead.
    private func pasteButton(_ set: @escaping (String) -> Void) -> some View {
        Button {
            if let text = UIPasteboard.general.string { set(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("Paste"))
    }

    private var statusText: String {
        switch cloud.state {
        case .off: return settings.cloud.isActive ? L("Starting…") : L("Off")
        case .connecting: return L("Connecting…")
        case .ready: return cloud.friendCode.map { L("Connected · code {}", CloudIDs.displayFriendCode($0)) } ?? L("Connected")
        case let .failed(message): return message
        }
    }

    private var statusColor: Color {
        switch cloud.state {
        case .ready: return Ablox.Palette.success
        case .failed: return Ablox.Palette.warning
        default: return Ablox.Palette.inkMuted
        }
    }
}
