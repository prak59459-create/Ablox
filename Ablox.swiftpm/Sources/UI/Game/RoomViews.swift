import SwiftUI
import CoreImage.CIFilterBuiltins
import VisionKit

// The room, on the play screen: people at the door, the vote, who is ready,
// whispering, reporting, teams, and inviting someone with a QR code.

// MARK: - Over the game

/// What the room needs from the players right now, top centre.
struct RoomHUD: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            if session.role == .hosting {
                ForEach(session.joinRequests) { request in
                    joinRequest(request)
                }
            }
            if session.roomState.poll != nil {
                PollCard(session: session)
            }
            if session.isQuietedByHost {
                Label(L("The host has turned off your chat."), systemImage: "mic.slash.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Ablox.Palette.warning)
            }
        }
        .frame(maxWidth: 460)
    }

    private func joinRequest(_ request: SessionCoordinator.JoinRequest) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.title3)
                .foregroundStyle(Ablox.Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("{} wants to join", request.name))
                    .font(.subheadline.weight(.semibold))
                if settings.social.isBlocked(request.id) {
                    Text(L("You blocked this player."))
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.warning)
                } else if settings.social.isFriend(request.id) {
                    Text(L("Your friend"))
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.success)
                }
            }
            Spacer(minLength: 8)
            Button(L("No")) { session.answerJoinRequest(request, allow: false) }
                .buttonStyle(NeonButtonStyle(.secondary))
            Button(L("Let in")) { session.answerJoinRequest(request, allow: true) }
                .buttonStyle(NeonButtonStyle(.primary))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }
}

/// The vote: the question, a button per answer with its count, and the
/// result when it closes.
struct PollCard: View {
    @ObservedObject var session: SessionCoordinator

    var body: some View {
        if let poll = session.roomState.poll {
            card(poll)
        }
    }

    private func card(_ poll: Poll) -> some View {
        let tally = poll.tally
        let mine = poll.votes[session.localPeerID]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L(poll.question), systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if poll.isClosed {
                    Badge(L("Closed"), color: Ablox.Palette.inkFaint)
                } else if let ends = session.pollEndsAt, ends > Date() {
                    Text(timerInterval: Date()...ends, countsDown: true)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            ForEach(poll.options.indices, id: \.self) { index in
                Button {
                    session.vote(choice: index)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mine == index ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(mine == index ? Ablox.Palette.accent : Ablox.Palette.inkFaint)
                        Text(L(poll.options[index]))
                            .font(.subheadline)
                        Spacer()
                        if poll.isClosed, poll.winner == index {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Ablox.Palette.warning)
                        }
                        Text("\(tally[index])")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(mine == index ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(poll.isClosed)
            }
            if poll.isClosed {
                Text(poll.winner.map { L("Most votes: {}", L(poll.options[$0])) } ?? L("No clear winner."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ablox.Palette.accent)
            }
            if session.role == .hosting {
                HStack(spacing: 14) {
                    if !poll.isClosed {
                        Button(L("End the vote")) { session.endPoll() }
                    }
                    Button(L("Close")) { session.clearPoll() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.accent)
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
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

// MARK: - The room tab in the menu

/// Ready, and — for the host — who may come in, warping, teams, a vote, a
/// new round and an invitation.
struct RoomMenuTab: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    @State private var choosingTeams = false
    @State private var composingPoll = false
    @State private var inviting = false

    private var isHost: Bool { session.role == .hosting }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let people = session.people.map(\.peerID)
            HStack {
                Toggle(isOn: Binding(get: { session.isReady }, set: { session.setReady($0) })) {
                    Label(L("I'm ready"), systemImage: "checkmark.seal.fill")
                }
                .tint(Ablox.Palette.success)
                Text(L("{} of {} ready", session.roomState.readyCount(of: people), people.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }

            if isHost {
                Divider().background(Color.white.opacity(0.1))
                Button {
                    session.startNewRound()
                } label: {
                    Label(L("Start a new round for everyone"), systemImage: "flag.checkered")
                }
                .buttonStyle(NeonButtonStyle(.secondary))

                Toggle(isOn: Binding(get: { session.roomState.needsApproval }, set: { session.setNeedsApproval($0) })) {
                    Label(L("Ask me before anyone joins"), systemImage: "person.badge.key.fill")
                }
                Toggle(isOn: Binding(get: { session.roomState.allowsWarp }, set: { session.setAllowsWarp($0) })) {
                    Label(L("Players may jump to their friends"), systemImage: "figure.walk.arrival")
                }
                HStack(spacing: 10) {
                    Button { choosingTeams = true } label: { Label(L("Teams"), systemImage: "person.3.fill") }
                    Button { composingPoll = true } label: { Label(L("Start a vote"), systemImage: "hand.raised.fill") }
                    Button { inviting = true } label: { Label(L("Invite"), systemImage: "qrcode") }
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            } else {
                Text(L("The host looks after the room: who comes in, teams and votes."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
        .toggleStyle(.switch)
        .sheet(isPresented: $choosingTeams) {
            TeamPickerSheet(session: session)
        }
        .sheet(isPresented: $composingPoll) {
            PollComposerSheet(session: session)
        }
        .sheet(isPresented: $inviting) {
            InviteSheet(session: session)
        }
    }
}

// MARK: - Teams

struct TeamPickerSheet: View {
    @ObservedObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var teamCount = 2

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("Teams"), selection: $teamCount) {
                        ForEach(2...TeamPicker.names.count, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        let players = session.people.map(\.peerID)
                        session.assignTeams(TeamPicker.shuffled(players, teams: teamCount, seed: UInt64.random(in: 1...UInt64.max)))
                    } label: {
                        Label(L("Shuffle everyone"), systemImage: "shuffle")
                    }
                    Button(role: .destructive) {
                        session.assignTeams(Dictionary(uniqueKeysWithValues: session.people.map { ($0.peerID, "") }))
                    } label: {
                        Label(L("No teams"), systemImage: "xmark.circle")
                    }
                } footer: {
                    Text(L("Tap a player to move them to the next team. A game's own script can still choose teams itself."))
                }
                Section(L("Players")) {
                    ForEach(session.people) { player in
                        Button {
                            session.assignTeams([player.peerID: TeamPicker.next(after: player.team, teams: teamCount)])
                        } label: {
                            HStack {
                                Text(player.profile.displayName)
                                Spacer()
                                TeamBadge(team: player.team)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Teams"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TeamBadge: View {
    let team: String

    var body: some View {
        if team.isEmpty {
            Text(L("No team"))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkFaint)
        } else {
            let colour = TeamPicker.colorHex(for: team).flatMap { ColorRGBA(hex: $0) }.map { Color($0) } ?? Ablox.Palette.accent
            Label(L(team), systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colour)
        }
    }
}

// MARK: - Votes

struct PollComposerSheet: View {
    @ObservedObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]

    var body: some View {
        NavigationStack {
            List {
                Section(L("Ready-made")) {
                    ForEach(Poll.presets.indices, id: \.self) { index in
                        let preset = Poll.presets[index]
                        Button {
                            session.startPoll(question: preset.question, options: preset.options)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(preset.question))
                                Text(preset.options.map { L($0) }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Ablox.Palette.inkMuted)
                            }
                        }
                    }
                }
                Section(L("Your own question")) {
                    TextField(L("Question"), text: $question)
                    ForEach(options.indices, id: \.self) { index in
                        TextField(L("Answer {}", index + 1), text: $options[index])
                    }
                    if options.count < Poll.maximumOptions {
                        Button(L("Add an answer")) { options.append("") }
                    }
                    Button(L("Ask everyone")) {
                        session.startPoll(question: question, options: options)
                        dismiss()
                    }
                    .disabled(Poll(question: question, options: options, closesAt: 0) == nil)
                }
            }
            .navigationTitle(L("Start a vote"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Whispers

struct WhisperSheet: View {
    @ObservedObject var session: SessionCoordinator
    let player: PlayerSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Whisper to {}", player.profile.displayName), systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.headline)
            Text(L("Only {} sees this. Be kind — the word filter still works.", player.profile.displayName))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            TextField(L("Say something…"), text: $text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .onSubmit(send)
            HStack {
                Button(L("Cancel")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary))
                Spacer()
                Button(L("Send"), action: send)
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .presentationDetents([.height(260)])
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            focused = true
        }
    }

    private func send() {
        session.whisper(to: player.peerID, text: text)
        dismiss()
    }
}

// MARK: - Reports

/// Reports kept on this iPad: `Documents/Reports/<id>.json`, with the
/// picture beside it. Only a grown-up in Settings → Family reads them.
enum ReportStore {
    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Reports", isDirectory: true)
    }

    static func save(_ report: PlayerReport, picture: UIImage?) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report = report
        if let png = picture?.pngData() {
            let name = "\(report.id.uuidString).png"
            if (try? png.write(to: folder.appendingPathComponent(name), options: [.atomic])) != nil { report.picture = name }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: folder.appendingPathComponent("\(report.id.uuidString).json"), options: [.atomic])
        }
    }

    static func all() -> [PlayerReport] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PlayerReport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    static func pictureURL(of report: PlayerReport) -> URL? {
        guard let name = report.picture else { return nil }
        return folder?.appendingPathComponent(name)
    }

    static func delete(_ report: PlayerReport) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(report.id.uuidString).json"))
        if let picture = pictureURL(of: report) { try? FileManager.default.removeItem(at: picture) }
    }
}

struct ReportSheet: View {
    @ObservedObject var session: SessionCoordinator
    let player: PlayerSnapshot
    let link: ViewportLink?
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var reason: PlayerReport.Reason = .rudeWords
    @State private var note = ""
    @State private var alsoBlock = true
    @State private var picture: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("Tell a grown-up too. This report is kept on this iPad with a picture of the game and the recent chat, so they can see what happened."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                Section(L("What happened?")) {
                    Picker(L("What happened?"), selection: $reason) {
                        ForEach(PlayerReport.Reason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    TextField(L("Anything else (optional)"), text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle(L("Block {} too", player.profile.displayName), isOn: $alsoBlock)
                }
            }
            .navigationTitle(L("Report {}", player.profile.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Report"), action: file) }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // The moment as it was, before the sheet covered it.
            link?.snapshot { picture = $0 }
        }
    }

    private func file() {
        let chat = session.chatLog.filter { !$0.isPrivate || $0.senderID == player.peerID }
            .map { "\($0.senderName): \($0.text)" }
        let report = PlayerReport(playerID: player.peerID, playerName: player.profile.displayName, game: session.world.name,
                                  reason: reason, note: note, chat: chat)
        ReportStore.save(report, picture: picture)
        if alsoBlock {
            settings.block(player.peerID, name: player.profile.displayName)
            session.muteList = settings.muteList
        }
        dismiss()
    }
}

// MARK: - Inviting with a QR code

enum QRCode {
    /// A sharp QR code for `text`, or nil.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct InviteSheet: View {
    @ObservedObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let ticket = session.invitation, let image = QRCode.image(for: ticket.text) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(L("On the other iPad: Play → Join with an invitation → Scan a QR code."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        VStack(spacing: 4) {
                            Text(L("Room code {}", RoomCode.formatted(ticket.code)))
                                .font(.headline.monospaced())
                            Text(verbatim: "\(ticket.host):\(ticket.port)")
                                .font(.caption.monospaced())
                                .foregroundStyle(Ablox.Palette.inkMuted)
                        }
                        Button {
                            sharing = true
                        } label: {
                            Label(L("Send the invitation as text"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(NeonButtonStyle(.secondary))
                        .sheet(isPresented: $sharing) {
                            ActivityShareSheet(items: [ticket.text])
                        }
                    } else {
                        EmptyStateView(title: L("No invitation yet"),
                                       message: L("This iPad needs to be on Wi-Fi to invite someone this way. The room code still works from the list."),
                                       systemImage: "wifi.slash")
                    }
                    Text(L("Invitations work on the same network, or over a VPN — for iPads that can't see each other's rooms in the list. Playing across the internet would need a server in between, which Ablox doesn't have."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle(L("Invite"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Reads a room's QR code with the camera.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (JoinTicket) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (JoinTicket) -> Void
        private var found = false

        init(onFound: @escaping (JoinTicket) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !found else { return }
            for item in addedItems {
                guard case let .barcode(code) = item, let text = code.payloadStringValue,
                      let ticket = JoinTicket(text: text) else { continue }
                found = true
                onFound(ticket)
                return
            }
        }
    }
}
