import SwiftUI
import AbloxCore

// Settings → AI helper ("Ablobo"): questions about using Ablox. The help
// list answers first, on the iPad; the AI only when a grown-up has turned it
// on and saved a key in Family settings. Rules in AbloxCore/AIHelper.swift,
// sending in Net/AIHelperClient.swift.

struct AIHelperCard: View {
    @State private var open = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("AI helper"), systemImage: "sparkles")
                Text(L("Hi! I'm Ablobo. Ask me how to use Ablox."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    open = true
                } label: {
                    Label(L("Ask Ablobo"), systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(NeonButtonStyle(.primary))
            }
        }
        .sheet(isPresented: $open) { AIHelperSheet() }
    }
}

/// One line of the conversation.
private struct HelperLine: Identifiable, Hashable {
    enum Who: Hashable { case child, list, ai, note }
    let id = UUID()
    let who: Who
    let text: String
}

struct AIHelperSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [HelperLine] = [HelperLine(who: .note, text: L("Hi! I'm Ablobo. Ask me how to use Ablox."))]
    @State private var question = ""
    @State private var thinking = false
    @State private var history: [AIHelper.Turn] = []

    private var aiReady: Bool { settings.aiHelper.enabled && AIHelperKey.isSet }
    private var left: Int { settings.aiUsage.left(limit: settings.aiHelper.dailyLimit, on: Date()) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(lines) { line in
                                bubble(line).id(line.id)
                            }
                            if thinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(L("Thinking…")).font(.subheadline).foregroundStyle(Ablox.Palette.inkMuted)
                                }
                                .padding(.leading, 6)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: lines.count) { _ in
                        if let last = lines.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HelpFAQ.suggestions, id: \.self) { s in
                                Button(L(s)) { Task { await ask(L(s)) } }
                                    .buttonStyle(NeonButtonStyle(.secondary))
                                    .disabled(thinking)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        AbloxTextField(L("Ask about Ablox…"), text: $question, limit: AIHelper.maximumQuestionLength)
                            .padding(10)
                            .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button {
                            let q = question
                            question = ""
                            Task { await ask(q) }
                        } label: {
                            Label(L("Ask"), systemImage: "paperplane.fill")
                        }
                        .buttonStyle(NeonButtonStyle(.primary))
                        .disabled(thinking || question.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .navigationTitle(L("AI helper"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
    }

    private var status: String {
        guard aiReady else { return L("A grown-up can turn on the AI in Family settings. Until then, answers come from the help list.") }
        if left == 0 { return L("No AI questions left today. The help list still answers.") }
        return L("{} AI questions left today", left) + " · " + L("AI answers can be wrong. If something seems odd, ask a grown-up.")
    }

    @ViewBuilder private func bubble(_ line: HelperLine) -> some View {
        let mine = line.who == .child
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if line.who == .list || line.who == .ai {
                    Text(line.who == .ai ? L("From the AI") : L("From the help list"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                Text(verbatim: line.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(mine ? Ablox.Palette.accent.opacity(0.22) : Ablox.Palette.wash,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func ask(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let moderator = ChatModerator(additionalTerms: settings.parental.extraBlockedWords ?? [], strict: settings.parental.strictChatFilter ?? false)
        if let refusal = AIHelper.check(q, moderator: moderator) {
            if refusal != .empty { lines.append(HelperLine(who: .note, text: refusal.message)) }
            return
        }
        lines.append(HelperLine(who: .child, text: q))
        let known = HelpFAQ.answer(for: q)
        // The help list first: sure answers never use the AI (or the day's count).
        if let known, known.score >= 0.75 || !aiReady || left == 0 {
            lines.append(HelperLine(who: .list, text: known.text))
            return
        }
        guard aiReady else {
            lines.append(HelperLine(who: .note, text: L("I don't know that one yet. Try one of the buttons, or ask a grown-up.")))
            return
        }
        guard left > 0 else {
            lines.append(HelperLine(who: .note, text: L("No AI questions left today. The help list still answers.")))
            return
        }
        if settings.aiUsage.coolingDown(at: Date().timeIntervalSince1970) {
            lines.append(HelperLine(who: .note, text: L("Wait a moment before the next question.")))
            return
        }
        thinking = true
        settings.aiUsage.record(on: Date())
        let result = await AIHelperClient().ask(q, history: history, japanese: Localization.language == .japanese, moderator: moderator)
        thinking = false
        switch result {
        case let .success(answer):
            lines.append(HelperLine(who: .ai, text: answer))
            history.append(AIHelper.Turn(question: q, answer: answer))
        case let .failure(failure):
            lines.append(HelperLine(who: .note, text: failure.message))
            if let known { lines.append(HelperLine(who: .list, text: known.text)) }
        }
    }
}

// MARK: - Family settings

/// Family settings → AI helper: on or off, how many questions a day, and the
/// grown-up's own key, kept in the keychain.
struct AIHelperFamilySection: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var typedKey = ""
    @State private var hasKey = AIHelperKey.isSet
    @State private var note: String?

    var body: some View {
        Section {
            Toggle(L("Use the AI for questions the help list can't answer"), isOn: $settings.aiHelper.enabled)
            Picker(L("Questions a day"), selection: $settings.aiHelper.dailyLimit) {
                ForEach(AIHelperSettings.limits, id: \.self) { Text("\($0)").tag($0) }
            }
            if hasKey {
                Label(L("Key saved on this iPad"), systemImage: "key.fill")
                    .foregroundStyle(Ablox.Palette.success)
                Button(L("Remove key"), role: .destructive) {
                    AIHelperKey.remove()
                    hasKey = false
                }
            } else {
                SecureField(L("API key (Groq)"), text: $typedKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L("Save key")) {
                    let key = typedKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard AIHelper.isPlausibleKey(key) else {
                        note = L("That doesn't look like a key.")
                        return
                    }
                    AIHelperKey.save(key)
                    typedKey = ""
                    hasKey = true
                    note = nil
                }
                .disabled(typedKey.isEmpty)
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(Ablox.Palette.warning)
            }
        } header: {
            Text(L("AI helper (for grown-ups)"))
        } footer: {
            Text(L("The key stays in this iPad's keychain. Questions go to the provider with it; nothing else from the iPad is sent. Get a free key at console.groq.com."))
        }
    }
}
