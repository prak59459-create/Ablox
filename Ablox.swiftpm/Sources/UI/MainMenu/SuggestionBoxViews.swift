import SwiftUI

// Settings → Suggestion box: write an idea or a problem, send it, and see
// what became of the ones sent from this iPad. Rules in
// AbloxCore/Suggestions.swift; sending in Net/CloudService.swift.

struct SuggestionBoxCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var cloud: CloudService
    @StateObject private var replies = SuggestionRepliesLoader()
    @State private var kind: SuggestionKind = .game
    @State private var text = ""
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Suggestion box"), systemImage: "envelope.open.fill")
                Text(L("A game you would like, something to add, or something that went wrong: every idea is read, and the ones that can be made are made."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !cloud.allowsSuggestions {
                    Label(L("Sending is switched off. A grown-up can switch it on in Settings → Family → Internet."), systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                writing
                if !settings.memory.sentSuggestions.items.isEmpty {
                    Divider()
                    Text(L("Sent from this iPad"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(settings.memory.sentSuggestions.items.prefix(10)) { sent in
                        SentSuggestionRow(sent: sent, reply: replies.value.reply(for: sent.id), language: Localization.language.rawValue)
                    }
                }
            }
        }
        .task { await replies.refresh() }
    }

    private var writing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("About"), selection: $kind) {
                ForEach(SuggestionKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
            .pickerStyle(.menu)
            AbloxTextField(L("Write your idea here"), text: $text, axis: .vertical, limit: SuggestionBox.longest)
                .padding(10)
                .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Text(L("Don't write your name, your school or where you live."))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Spacer()
                Text("\(text.count)/\(SuggestionBox.longest)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            HStack {
                Button {
                    send()
                } label: {
                    Label(sending ? L("Sending…") : L("Send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(NeonButtonStyle(.primary))
                .disabled(sending || !cloud.allowsSuggestions || SuggestionBox.tidied(text).count < SuggestionBox.shortest)
                if let message {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func send() {
        if let problem = SuggestionBox.problem(with: text, lastSent: settings.memory.sentSuggestions.lastSent) {
            message = problem
            return
        }
        guard cloud.isReady else {
            message = L("Still connecting to the internet. Try again in a moment.")
            return
        }
        sending = true
        message = nil
        let words = SuggestionBox.tidied(text)
        let kind = self.kind
        Task {
            do {
                let id = try await cloud.sendSuggestion(kind: kind, text: words, app: AppRelease.current.app,
                                                        version: AppRelease.version, language: Localization.language.rawValue)
                settings.memory.sentSuggestions.add(SentSuggestion(id: id, kind: kind, text: words))
                text = ""
                message = L("Sent. Thank you!")
            } catch {
                message = L("It could not be sent. Check the internet, then try again.")
            }
            sending = false
        }
    }
}

/// One suggestion sent from here, and its answer when there is one.
struct SentSuggestionRow: View {
    let sent: SentSuggestion
    let reply: SuggestionReply?
    let language: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sent.kind.symbolName)
                .foregroundStyle(Ablox.Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: sent.text)
                    .font(.subheadline)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(sent.sentAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                    Text(reply?.statusName ?? L("Waiting to be read"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.22), in: Capsule())
                        .foregroundStyle(badgeColor)
                    if let version = reply?.version, reply?.status == .done {
                        Text(L("In version {}", version))
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
                if let answer = reply?.message(in: language) {
                    Text(verbatim: answer)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var badgeColor: Color {
        switch reply?.status {
        case .done: return Ablox.Palette.success
        case .planned: return Ablox.Palette.accent
        case .thanks, .notNow: return Ablox.Palette.inkMuted
        case nil: return Ablox.Palette.warning
        }
    }
}

/// `suggestions/replies.json` from the app's repository, kept on disk so
/// the answers show straight away next time.
@MainActor
final class SuggestionRepliesLoader: ObservableObject {
    @Published private(set) var value = SuggestionReplies()

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("suggestion-replies.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(SuggestionReplies.self, from: data) {
            value = cached
        }
    }

    func refresh() async {
        guard let url = SuggestionReplies.url(for: AppRelease.current.channel) else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fresh = try? JSONDecoder().decode(SuggestionReplies.self, from: data) else { return }
        value = fresh
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}
