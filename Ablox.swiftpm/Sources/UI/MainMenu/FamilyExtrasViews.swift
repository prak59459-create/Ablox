import SwiftUI
import UniformTypeIdentifiers
import AbloxCore

// Settings → Family, the second round: presets by age, a weekend limit,
// days off, extra time today, which games, asking before big purchases,
// rest for the eyes, a note on the menu, a passcode hint, the record of
// changes and the week's report. Rules in AbloxCore/FamilyExtras.swift.

struct FamilyMoreSections: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmingPreset: AgePreset?

    private let weekendLimits: [Int?] = [nil, 60, 90, 120, 180, 240]
    private let askChoices: [Int?] = [nil, 100, 200, 300, 500, 1000]
    private let eyeRests: [Int?] = [nil, 20, 30, 45]

    private var family: Binding<FamilyExtras> { $settings.parental.family }

    var body: some View {
        allowedSection
        presetsSection
        moreTimeSection
        gamesAndShopSection
        notesSection
        recordsSection
    }

    private var allowedSection: some View {
        Section {
            Toggle(L("Pause all games now"), isOn: family.pausedNow)
                .tint(Ablox.Palette.warning)
            Toggle(L("Taking pictures"), isOn: family.picturesAllowed)
            Toggle(L("The shop"), isOn: family.shopAllowed)
            Toggle(L("Building worlds"), isOn: family.buildingAllowed)
            Toggle(L("Chat with friends only"), isOn: family.chatFriendsOnly)
            Toggle(L("Whispers"), isOn: family.whispersAllowed)
            Toggle(L("Quiet hours on school days only"), isOn: family.quietSchoolDaysOnly)
                .disabled(settings.parental.quietHours == nil)
        } header: {
            Text(L("What's allowed"))
        } footer: {
            Text(L("Pausing closes any game at once and keeps them closed until you switch it off."))
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(AgePreset.allCases) { preset in
                Button {
                    confirmingPreset = preset
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.displayName).font(.headline)
                        Text(preset.summary).font(.caption).foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
            }
        } header: {
            Text(L("Ready-made by age"))
        } footer: {
            Text(L("Sets play time, chat, rooms, coins and quiet hours in one go. Change anything afterwards."))
        }
        .alert(L("Use these settings?"), isPresented: Binding(get: { confirmingPreset != nil }, set: { if !$0 { confirmingPreset = nil } })) {
            Button(L("Cancel"), role: .cancel) { confirmingPreset = nil }
            Button(L("Use them")) {
                if let preset = confirmingPreset { preset.apply(to: &settings.parental) }
                confirmingPreset = nil
            }
        } message: {
            Text(confirmingPreset?.summary ?? "")
        }
    }

    private var moreTimeSection: some View {
        Section(L("More about time")) {
            Picker(L("At the weekend"), selection: family.weekendLimitMinutes) {
                ForEach(weekendLimits, id: \.self) { minutes in
                    Text(minutes.map { L("{} minutes", $0) } ?? L("Same as every day")).tag(minutes)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Days off (no games)"))
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { weekday in
                        let off = settings.parental.family.daysOff.contains(weekday)
                        Button {
                            if off { settings.parental.family.daysOff.remove(weekday) } else { settings.parental.family.daysOff.insert(weekday) }
                        } label: {
                            Text(FamilyExtras.weekdayName(weekday))
                                .font(.caption.weight(.semibold))
                                .frame(width: 40, height: 32)
                                .background(off ? Ablox.Palette.warning.opacity(0.4) : Ablox.Palette.wash,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(off ? .isSelected : [])
                    }
                }
            }
            HStack {
                let extra = settings.parental.family.extra(on: settings.today)
                Text(extra > 0 ? L("Extra today: {} minutes", extra) : L("Extra time today"))
                Spacer()
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button(L("+{}", minutes)) { settings.parental.family.giveExtra(minutes, on: settings.today) }
                        .buttonStyle(NeonButtonStyle(.secondary))
                }
            }
            Picker(L("Rest for the eyes"), selection: family.eyeRestMinutes) {
                ForEach(eyeRests, id: \.self) { minutes in
                    Text(minutes.map { L("Every {} minutes", $0) } ?? L("Off")).tag(minutes)
                }
            }
        }
    }

    private var gamesAndShopSection: some View {
        Section {
            NavigationLink {
                FamilyGamesView()
            } label: {
                let f = settings.parental.family
                Label(f.onlyChosenGames ? L("Only chosen games ({})", f.chosenGames.count)
                                        : L("Games put away ({})", f.hiddenGames.count), systemImage: "gamecontroller")
            }
            Picker(L("Ask me before buying things over"), selection: family.askAbove) {
                ForEach(askChoices, id: \.self) { coins in
                    Text(coins.map { L("{} coins", $0) } ?? L("Never ask")).tag(coins)
                }
            }
        } header: {
            Text(L("Games and the shop"))
        } footer: {
            Text(L("Asking needs the family passcode, so set one below first."))
        }
    }

    private var notesSection: some View {
        Section(L("Notes")) {
            AbloxTextField(L("A note on the Play tab, like: Dinner at six!"), text: Binding(
                get: { settings.parental.family.note ?? "" },
                set: { settings.parental.family.note = $0.isEmpty ? nil : String($0.prefix(FamilyExtras.maximumNoteLength)) }),
                limit: FamilyExtras.maximumNoteLength)
            AbloxTextField(L("A hint to remember the passcode (only grown-ups see it)"), text: Binding(
                get: { settings.parental.family.passcodeHint ?? "" },
                set: { settings.parental.family.passcodeHint = $0.isEmpty ? nil : String($0.prefix(60)) }),
                limit: 60)
        }
    }

    private var recordsSection: some View {
        Section(L("Looking back")) {
            NavigationLink {
                FamilyReportView()
            } label: {
                Label(L("This week's report"), systemImage: "chart.bar.doc.horizontal")
            }
            NavigationLink {
                FamilyLogView()
            } label: {
                Label(L("Changes to these settings ({})", settings.memory.familyLog.entries.count), systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

// MARK: - Which games

struct FamilyGamesView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library = GameLibrary()

    var body: some View {
        List {
            Section {
                Toggle(L("Only the games I choose"), isOn: $settings.parental.family.onlyChosenGames)
            } footer: {
                Text(settings.parental.family.onlyChosenGames
                     ? L("Only games switched on below can be seen and played.")
                     : L("Switch off a game to put it away; everything else can be played."))
            }
            Section {
                if library.listings.isEmpty {
                    Text(L("The game list has not been loaded yet. Open the Games tab once, then come back."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(library.listings) { listing in
                    Toggle(isOn: binding(for: listing.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(listing.title)
                            if !listing.tags.isEmpty {
                                Text(listing.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Ablox.Palette.inkMuted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Games"))
        .task {
            library.source = settings.catalogueSource
            await library.refreshIfStale()
        }
    }

    /// On: allowed (chosen, or not put away).
    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                let f = settings.parental.family
                return f.onlyChosenGames ? f.chosenGames.contains(id) : !f.hiddenGames.contains(id)
            },
            set: { on in
                if settings.parental.family.onlyChosenGames {
                    if on { settings.parental.family.chosenGames.insert(id) } else { settings.parental.family.chosenGames.remove(id) }
                } else {
                    if on { settings.parental.family.hiddenGames.remove(id) } else { settings.parental.family.hiddenGames.insert(id) }
                }
            })
    }
}

// MARK: - Looking back

struct FamilyLogView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            if settings.memory.familyLog.entries.isEmpty {
                Text(L("No changes yet."))
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            ForEach(settings.memory.familyLog.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.text)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
            }
        }
        .navigationTitle(L("Changes"))
    }
}

/// The last seven days: minutes each day, games played most, coins, and
/// missions — for a grown-up.
struct FamilyReportView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let days = settings.playtime.recent(7)
        let week = WeekSummary.make(days: settings.playtime.days, ledger: settings.coinLedger)
        let most = days.map(\.minutes).max() ?? 0
        List {
            Section(L("Minutes each day")) {
                ForEach(days) { day in
                    HStack {
                        Text(verbatim: day.date)
                            .font(.caption.monospacedDigit())
                            .frame(width: 90, alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Ablox.Palette.accent)
                                .frame(width: most > 0 ? proxy.size.width * CGFloat(day.minutes) / CGFloat(most) : 0)
                        }
                        .frame(height: 14)
                        Text(L("{} min", day.minutes))
                            .font(.caption.monospacedDigit())
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Text(L("{} minutes in all, on {} days", week.minutes, week.daysPlayed))
                    .font(.subheadline.weight(.semibold))
            }
            Section(L("Played most this week")) {
                let games = weekGames(days)
                if games.isEmpty {
                    Text(L("Nothing played this week."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(games.prefix(5), id: \.game) { item in
                    HStack {
                        Text(verbatim: item.game)
                        Spacer()
                        Text(L("{} min", item.minutes))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
            }
            Section(L("Coins and missions")) {
                LabeledContent(L("Coins earned"), value: "\(week.coinsEarned)")
                LabeledContent(L("Coins spent"), value: "\(week.coinsSpent)")
                LabeledContent(L("Missions finished in all"), value: "\(settings.memory.counters.missionsClaimed)")
                LabeledContent(L("Friends"), value: "\(settings.social.friends.count)")
            }
        }
        .navigationTitle(L("This week's report"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: reportText) {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    /// The report as plain text, to send to another grown-up.
    private var reportText: String {
        let days = settings.playtime.recent(7)
        let week = WeekSummary.make(days: settings.playtime.days, ledger: settings.coinLedger)
        var lines = [L("Ablox: {}'s week", settings.profile.displayName), ""]
        for day in days { lines.append("\(day.date): " + L("{} min", day.minutes)) }
        lines.append("")
        lines.append(L("{} minutes in all, on {} days", week.minutes, week.daysPlayed))
        for item in weekGames(days).prefix(5) { lines.append("• \(item.game): " + L("{} min", item.minutes)) }
        return lines.joined(separator: "\n")
    }

    private func weekGames(_ days: [PlaytimeLog.Day]) -> [(game: String, minutes: Int)] {
        var seconds: [String: Double] = [:]
        for day in days {
            for (game, value) in day.games { seconds[game, default: 0] += value }
        }
        return seconds.map { (game: $0.key, minutes: Int($0.value / 60)) }.sorted { $0.minutes > $1.minutes }
    }
}

/// A grown-up's note, on the Play tab.
struct FamilyNoteBanner: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let note = settings.parental.family.note, !note.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text")
                    .font(.title3)
                    .foregroundStyle(Ablox.Palette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("A note from a grown-up"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                    Text(verbatim: note)
                        .font(.headline)
                }
                Spacer()
            }
            .padding(14)
            .background(Ablox.Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
        }
    }
}

/// Minutes of play left today, on the Play tab, when there is a limit.
struct PlayTimeLeftChip: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let message = PlayGate.message(for: settings.playVerdict) {
            Label(message, systemImage: "moon.zzz.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ablox.Palette.warning)
        } else if let left = PlayGate.minutesLeft(settings.parental, log: settings.playtime) {
            Label(L("{} minutes of play left today", left), systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(left > 10 ? Ablox.Palette.accent : Ablox.Palette.warning)
        }
    }
}

// MARK: - Settings: help and moving settings

/// Today's tip, the keyboard shortcuts, and the iPad's own Settings.
struct SettingsHelpCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingShortcuts = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Tips"), systemImage: "lightbulb.fill")
                Label(SettingsTips.tip(on: settings.today), systemImage: "sparkles")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        showingShortcuts = true
                    } label: {
                        Label(L("Keyboard shortcuts"), systemImage: "keyboard")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: url) {
                            Label(L("The iPad's Settings for Ablox"), systemImage: "gear")
                        }
                        .buttonStyle(NeonButtonStyle(.secondary))
                    }
                }
            }
        }
        .sheet(isPresented: $showingShortcuts) {
            ShortcutsCard { showingShortcuts = false }
                .presentationBackground(.clear)
        }
    }
}

/// These settings as a file, to set up another iPad the same way.
struct SettingsTransferCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var sharing: SharedFile?
    @State private var choosing = false
    @State private var message: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Move my settings"), systemImage: "arrow.left.arrow.right.circle")
                Text(L("Save how Ablox looks and feels as a file, and open it on another iPad. Family settings, coins and friends stay here."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        export()
                    } label: {
                        Label(L("Save as a file"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                    Button {
                        choosing = true
                    } label: {
                        Label(L("Open a file"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }
                if let message {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.accent)
                }
            }
        }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            let reading = url.startAccessingSecurityScopedResource()
            defer { if reading { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let transfer = SettingsTransfer.read(data) {
                settings.preferences = transfer.preferences
                message = L("Settings opened.")
            } else {
                message = L("That isn't an Ablox settings file.")
            }
        }
    }

    private func export() {
        guard let data = try? SettingsTransfer(preferences: settings.preferences).data() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ablox settings.json")
        do {
            try data.write(to: url, options: .atomic)
            sharing = SharedFile(url: url)
        } catch {
            message = L("The file could not be made.")
        }
    }
}
