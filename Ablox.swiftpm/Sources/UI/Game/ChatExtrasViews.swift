import SwiftUI
import UIKit
import AbloxCore

// The chat while playing: lines with times, stars and mentions, phrases in
// groups and the player's own, emoji, what they said lately, whispering to
// one person, and a guard against flooding. Also the chat's options and the
// whole conversation in the pause menu. Rules in AbloxCore/ChatExtras.swift.

// MARK: - The chat panel

struct ChatPanel: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    let tracker: PlayTracker

    @State private var draft = ""
    /// Nil: the player's own phrases.
    @State private var group: QuickChatGroup? = .hello
    @State private var expanded = false
    @State private var whisperTo: PeerID?
    @State private var whispering: PlayerSnapshot?
    @State private var notice: String?
    @State private var addingPhrase = false

    private var options: ChatOptions { settings.preferences.chat }
    private var scale: Double { options.textSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lines
            if session.isQuietedByHost {
                Label(L("The host has turned off your chat."), systemImage: "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            } else {
                phraseGroups
                phraseRow
                if options.showEmojiBar { emojiRow }
                if settings.parental.chat == .full { composer }
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.leading, 18)
        .padding(.bottom, 130)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $whispering) { player in
            WhisperSheet(session: session, player: player)
        }
        .sheet(isPresented: $addingPhrase) {
            PhraseEditorSheet()
        }
    }

    // MARK: Lines

    @ViewBuilder private var lines: some View {
        let all = session.visibleChatLog
        let count = options.compact && !expanded ? 1 : options.lines
        ForEach(all.suffix(count)) { entry in
            ChatLineView(entry: entry, localPeerID: session.localPeerID, options: options,
                         friend: settings.social.friends.first { $0.id == entry.senderID },
                         mentionsMe: mentionsMe(entry))
                .contextMenu { menu(for: entry) }
        }
        if options.compact, all.count > 1 {
            Button(expanded ? L("Show less") : L("Show more")) {
                withAnimation { expanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ablox.Palette.accent)
        }
    }

    private func mentionsMe(_ entry: SessionCoordinator.ChatEntry) -> Bool {
        options.highlightMentions && entry.senderID != session.localPeerID
            && ChatTidy.mentions(settings.profile.displayName, in: entry.text)
    }

    /// Things to do with one line: answer in a whisper, befriend, mute,
    /// copy, or say one's own line again.
    @ViewBuilder private func menu(for entry: SessionCoordinator.ChatEntry) -> some View {
        let id = entry.senderID
        if id == session.localPeerID {
            Button {
                send(entry.text)
            } label: {
                Label(L("Say it again"), systemImage: "arrow.clockwise")
            }
        } else if id != SessionCoordinator.gamePeerID, let player = session.people.first(where: { $0.peerID == id }) {
            if session.allowsWhispers, session.allowsPlayerChat {
                Button {
                    whispering = player
                } label: {
                    Label(L("Whisper"), systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            if !settings.social.isFriend(id) {
                Button {
                    settings.social.addFriend(id, name: player.profile.displayName)
                } label: {
                    Label(L("Add friend"), systemImage: "person.badge.plus")
                }
            }
            Button {
                settings.muteList.mute(id)
                session.muteList = settings.muteList
            } label: {
                Label(L("Mute"), systemImage: "speaker.slash")
            }
        }
        Button {
            UIPasteboard.general.string = entry.text
        } label: {
            Label(L("Copy"), systemImage: "doc.on.doc")
        }
    }

    // MARK: Phrases and emoji

    private var phraseGroups: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickChatGroup.allCases) { choice in
                    groupChip(choice.displayName, choice.symbolName, selected: group == choice) { group = choice }
                }
                groupChip(L("Mine"), "star.fill", selected: group == nil) { group = nil }
            }
        }
    }

    private func groupChip(_ title: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11 * scale, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected ? Ablox.Palette.accent.opacity(0.4) : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var phraseRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let group {
                    ForEach(group.phrases, id: \.self) { phrase in
                        phraseButton(L(phrase)) { send(L(phrase)) }
                    }
                } else {
                    ForEach(settings.memory.phrases.phrases, id: \.self) { phrase in
                        phraseButton(phrase) { send(phrase) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    settings.memory.phrases.remove(phrase)
                                } label: {
                                    Label(L("Remove"), systemImage: "trash")
                                }
                            }
                    }
                    if settings.memory.phrases.phrases.count < SavedPhrases.maximum {
                        phraseButton(L("+ Add my own")) { addingPhrase = true }
                    }
                }
            }
        }
    }

    private func phraseButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.system(size: 12 * scale, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Ablox.Palette.accent.opacity(0.2), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var emojiRow: some View {
        HStack(spacing: 4) {
            ForEach(ChatEmoji.all, id: \.self) { emoji in
                Button {
                    send(emoji)
                } label: {
                    Text(verbatim: emoji)
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Typing

    private var others: [PlayerSnapshot] {
        session.people.filter { $0.peerID != session.localPeerID }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let whisperTo, let person = others.first(where: { $0.peerID == whisperTo }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text(L("Whispering to {}", person.profile.displayName))
                    Button {
                        self.whisperTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(L("Stop whispering"))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.magenta)
            }
            HStack(spacing: 8) {
                AbloxTextField(whisperTo == nil ? L("Say something…") : L("Whisper something…"), text: $draft,
                               limit: AbloxProtocol.maxChatLength, onSubmit: sendDraft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                Text("\(draft.count)/\(AbloxProtocol.maxChatLength)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(draft.count >= AbloxProtocol.maxChatLength ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                    .accessibilityHidden(true)
                historyMenu
                whisperMenu
                Button(action: sendDraft) {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 38, height: 38)
                        .background(Ablox.Palette.brand, in: Circle())
                        .foregroundStyle(.black)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L("Send"))
            }
        }
    }

    @ViewBuilder private var historyMenu: some View {
        let said = tracker.sent.lines
        if !said.isEmpty {
            Menu {
                ForEach(said, id: \.self) { line in
                    Button(line) { draft = line }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(L("What I said lately"))
        }
    }

    @ViewBuilder private var whisperMenu: some View {
        if session.allowsWhispers, !others.isEmpty {
            Menu {
                Button(L("Everyone")) { whisperTo = nil }
                ForEach(others) { person in
                    Button(person.profile.displayName) { whisperTo = person.peerID }
                }
            } label: {
                Image(systemName: whisperTo == nil ? "person.2.fill" : "lock.fill")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(whisperTo == nil ? .white : Ablox.Palette.magenta)
            }
            .accessibilityLabel(L("Who hears this"))
        }
    }

    private func sendDraft() {
        if send(draft) { draft = "" }
    }

    /// Sends a line, unless it is too soon or the same again. Phone numbers,
    /// emails and links never leave this iPad.
    @discardableResult
    private func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch tracker.limiter.allow(trimmed, at: Date().timeIntervalSinceReferenceDate) {
        case .repeated:
            show(L("You just said that."))
            return false
        case let .tooFast(seconds):
            show(L("Slow down a little — wait {} seconds.", seconds))
            return false
        case .ok:
            break
        }
        var outgoing = trimmed
        if options.hidePersonalInfo {
            outgoing = ChatTidy.personalInfoHidden(trimmed)
            if outgoing != trimmed { show(L("Phone numbers, emails and links are hidden in chat, to keep everyone safe.")) }
        }
        if let whisperTo, others.contains(where: { $0.peerID == whisperTo }) {
            session.whisper(to: whisperTo, text: outgoing)
        } else {
            session.sendChat(outgoing)
        }
        tracker.sent.said(trimmed)
        return true
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

// MARK: - One line

struct ChatLineView: View {
    let entry: SessionCoordinator.ChatEntry
    let localPeerID: PeerID
    let options: ChatOptions
    let friend: PlayerContact?
    let mentionsMe: Bool

    private var scale: Double { options.textSize.scale }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if options.showTimes {
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10 * scale).monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            if let partner = entry.privateWith {
                // A whisper: only the two of them see it.
                Image(systemName: "lock.fill")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(Ablox.Palette.magenta)
                Text(entry.senderID == localPeerID ? L("You → {}", partner) : entry.senderName)
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(Ablox.Palette.magenta)
            } else {
                if let friend, options.markFriends {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(Ablox.Palette.warning)
                    Text(friend.shownName)
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Ablox.Palette.warning)
                } else {
                    Text(entry.senderName)
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Ablox.Palette.accent)
                }
            }
            Text(verbatim: entry.text)
                .font(.system(size: 12 * scale))
                .foregroundStyle(.white)
            if entry.wasFiltered {
                // Marked, so a child can see the filter acting rather
                // than assume the message arrived that way.
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(Ablox.Palette.warning)
            }
        }
        .padding(.horizontal, mentionsMe ? 6 : 0)
        .padding(.vertical, mentionsMe ? 3 : 0)
        .background(mentionsMe ? Ablox.Palette.warning.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A phrase of one's own

struct PhraseEditorSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("A phrase of your own"), systemImage: "star.bubble.fill")
                .font(.headline)
            Text(L("Say it with one tap in the chat, under Mine."))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("Like: Meet me at the castle!"), text: $text, limit: SavedPhrases.maximumLength, onSubmit: add)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
            HStack {
                Button(L("Cancel")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary))
                Spacer()
                Button(L("Add"), action: add)
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .preferredColorScheme(.dark)
    }

    private func add() {
        switch settings.memory.phrases.add(text, moderator: settings.chatModerator) {
        case .added: dismiss()
        case .empty: problem = nil
        case .full: problem = L("You have {} already. Remove one first.", SavedPhrases.maximum)
        case .duplicate: problem = L("You have that one already.")
        case .notAllowed: problem = L("That can't be kept: it has a word the filter hides, or a number, email or link.")
        }
    }
}

// MARK: - The whole conversation

/// Everything said this visit, in the pause menu, with whispers or lines
/// naming the player picked out.
struct ChatHistoryList: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    enum Filter: String, CaseIterable, Identifiable {
        case all, whispers, mentions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return L("All")
            case .whispers: return L("Whispers")
            case .mentions: return L("About me")
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var showingOptions = false

    private var entries: [SessionCoordinator.ChatEntry] {
        let all = session.visibleChatLog
        switch filter {
        case .all: return all
        case .whispers: return all.filter(\.isPrivate)
        case .mentions: return all.filter { ChatTidy.mentions(settings.profile.displayName, in: $0.text) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Chat"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Spacer()
                Button {
                    showingOptions = true
                } label: {
                    Label(L("Chat options"), systemImage: "slider.horizontal.3")
                }
                .font(.caption.weight(.semibold))
                if !session.chatLog.isEmpty {
                    Button(L("Clear"), role: .destructive) { session.clearChat() }
                        .font(.caption.weight(.semibold))
                }
            }
            Picker(L("Chat"), selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if entries.isEmpty {
                Text(L("Nothing here yet."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            ForEach(entries.reversed()) { entry in
                ChatLineView(entry: entry, localPeerID: session.localPeerID,
                             options: withTimes(settings.preferences.chat),
                             friend: settings.social.friends.first { $0.id == entry.senderID },
                             mentionsMe: false)
            }
        }
        .sheet(isPresented: $showingOptions) {
            ChatOptionsView()
        }
    }

    /// The history always shows when each line was said.
    private func withTimes(_ options: ChatOptions) -> ChatOptions {
        var shown = options
        shown.showTimes = true
        return shown
    }
}

// MARK: - Options

/// How the chat, bubbles and names look and behave. In Settings and in the
/// pause menu.
struct ChatOptionsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var chat: Binding<ChatOptions> { $settings.preferences.chat }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Text size"), selection: chat.textSize) {
                        ForEach(ChatTextSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(L("Lines shown"), selection: chat.lines) {
                        ForEach(ChatOptions.lineChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Toggle(L("Only the newest line until tapped"), isOn: chat.compact)
                    Toggle(L("Show when each line was said"), isOn: chat.showTimes)
                    Toggle(L("Emoji buttons"), isOn: chat.showEmojiBar)
                    Toggle(L("Highlight lines that name me"), isOn: chat.highlightMentions)
                    Toggle(L("Stars and nicknames for friends"), isOn: chat.markFriends)
                } header: {
                    Text(L("Chat"))
                }
                Section {
                    Toggle(L("Read new lines aloud"), isOn: chat.readAloud)
                    Toggle(L("Feel new lines"), isOn: chat.feelNewMessages)
                } header: {
                    Text(L("Noticing new lines"))
                }
                Section {
                    Toggle(L("Hide phone numbers, emails and links"), isOn: chat.hidePersonalInfo)
                    Toggle(L("Soften shouting in capitals"), isOn: chat.softenShouting)
                    Toggle(L("Shorten long runs of one letter"), isOn: chat.squashRepeats)
                } header: {
                    Text(L("Tidying"))
                } footer: {
                    Text(L("Applied to lines as they arrive. The word filter is in Settings → Family."))
                }
                Section {
                    Toggle(L("Bubbles over heads"), isOn: chat.showBubbles)
                    Picker(L("Bubble size"), selection: chat.bubbleSize) {
                        ForEach(ChatTextSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(L("How long bubbles stay"), selection: chat.bubbleTime) {
                        ForEach(BubbleTime.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(L("Names over heads"), selection: chat.nameTags) {
                        ForEach(NameTagMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(L("Name size"), selection: chat.nameSize) {
                        ForEach(ChatTextSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text(L("Over heads"))
                }
            }
            .navigationTitle(L("Chat options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Reset")) { settings.preferences.chat = ChatOptions() }
                }
            }
        }
        .tint(Ablox.Palette.accent)
    }
}

/// The chat's options, in Settings.
struct ChatOptionsCard: View {
    @State private var showing = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(L("Chat and names"), systemImage: "bubble.left.and.bubble.right")
                Text(L("The chat's size and emoji, reading new lines aloud, hiding numbers and links, and the bubbles and names over heads."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showing = true
                } label: {
                    Label(L("Change the chat"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
        .sheet(isPresented: $showing) {
            ChatOptionsView()
        }
    }
}
