import SwiftUI
import AbloxCore

// Between games: today's missions, carrying on with the last game, a card
// on how a game went, a month of play on a calendar, and a friend starting
// to play nearby. The rules are in the core (`MissionBook`,
// `SessionSummary`, `PlayCalendar`, `FriendSightings`); these only show them.

// MARK: - Today's missions

struct MissionsCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var justClaimed: Int?

    var body: some View {
        let day = settings.today
        let book = settings.memory.missions
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(L("Today's missions"), systemImage: "target")
                    Spacer()
                    if let justClaimed {
                        Text(L("+{} coins", justClaimed))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.success)
                            .transition(.opacity)
                    }
                }
                ForEach(book.missions(on: day)) { mission in
                    row(mission, progress: book.progress(of: mission, on: day),
                        done: book.isDone(mission, on: day), claimed: book.isClaimed(mission, on: day))
                }
            }
        }
    }

    private func row(_ mission: Mission, progress: Int, done: Bool, claimed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: claimed ? "checkmark.circle.fill" : mission.kind.symbolName)
                .font(.title3)
                .foregroundStyle(done ? Ablox.Palette.success : Ablox.Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(mission.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(claimed)
                ProgressView(value: Double(min(progress, mission.target)), total: Double(mission.target))
                    .tint(done ? Ablox.Palette.success : Ablox.Palette.accent)
            }
            if claimed {
                Text(L("Done")).font(.caption).foregroundStyle(Ablox.Palette.inkFaint)
            } else if done {
                Button(L("Take {}", mission.reward)) {
                    if let coins = settings.claim(mission) {
                        withAnimation { justClaimed = coins }
                    }
                }
                .buttonStyle(NeonButtonStyle(.primary))
            } else {
                Text("\(min(progress, mission.target))/\(mission.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Carry on

/// The last game played, one tap away.
struct ContinueCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    var onEnter: (ActiveSession) -> Void
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        if let last = settings.memory.lastPlayed {
            GlassCard(padding: 15) {
                HStack(spacing: 14) {
                    Image(systemName: last.kind == .catalogue ? "gamecontroller.fill" : "cube.transparent.fill")
                        .font(.title2)
                        .foregroundStyle(Ablox.Palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Carry on")).font(.caption.weight(.semibold)).foregroundStyle(Ablox.Palette.inkMuted)
                        Text(last.title).font(.headline).lineLimit(1)
                        if let problem {
                            Text(problem).font(.caption).foregroundStyle(Ablox.Palette.warning)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await carryOn(last) }
                    } label: {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(L("Play"), systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(working)
                }
            }
        }
    }

    private func carryOn(_ last: LastPlayed) async {
        problem = nil
        switch last.kind {
        case .world:
            guard let entry = store.entries.first(where: { $0.id.uuidString == last.id }),
                  let world = store.load(entry) else {
                problem = L("That world is no longer on this iPad.")
                return
            }
            onEnter(ActiveSession(mode: .solo(world)))
        case .catalogue:
            working = true
            defer { working = false }
            let library = GameLibrary(source: settings.catalogueSource)
            guard let listing = library.listings.first(where: { $0.id == last.id }) else {
                problem = L("Open it from Games.")
                return
            }
            var found = library.cachedWorld(for: listing)
            if found == nil { found = await library.download(listing) }
            guard let world = found else {
                problem = L("Could not download “{}”.", listing.title)
                return
            }
            settings.memory.played(listing.id)
            onEnter(ActiveSession(mode: .solo(world)))
        }
    }
}

// MARK: - After a game

struct SessionSummarySheet: View {
    let summary: SessionSummary
    var onPlayAgain: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text(summary.game)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                tile(L("Time"), summary.durationText, "clock.fill")
                tile(L("Coins"), "+\(summary.coins)", "star.fill")
                tile(L("Missions"), "\(summary.missionsDone)", "target")
            }
            if !summary.badges.isEmpty {
                VStack(spacing: 6) {
                    Text(L("New badges!")).font(.headline).foregroundStyle(Ablox.Palette.warning)
                    ForEach(summary.badges, id: \.self) { id in
                        if let badge = Achievement(rawValue: id) {
                            Label(badge.title, systemImage: badge.symbolName)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button(L("Back to the menu")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
                if let onPlayAgain {
                    Button {
                        dismiss()
                        onPlayAgain()
                    } label: {
                        Label(L("Play again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
                }
            }
        }
        .padding(26)
        .frame(maxWidth: 520)
        .presentationDetents([.height(summary.badges.isEmpty ? 300 : 380)])
        .abloxColorScheme()
    }

    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Ablox.Palette.accent)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(Ablox.Palette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - A month of play

struct PlayCalendarCard: View {
    let log: PlaytimeLog
    @State private var month = Date()

    var body: some View {
        let cells = PlayCalendar.cells(month: month, log: log)
        let totals = PlayCalendar.totals(cells)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(L("Previous month"))
                Spacer()
                Text(PlayCalendar.title(month: month)).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(L("Next month"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(cells) { cell in
                    day(cell)
                }
            }
            Text(L("{} days played, {} minutes in all", totals.days, totals.minutes))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            Text(L("Only the last {} days are kept.", PlaytimeLog.keptDays))
                .font(.caption2)
                .foregroundStyle(Ablox.Palette.inkFaint)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func day(_ cell: PlayCalendar.Cell) -> some View {
        if let number = cell.day {
            let level = PlayCalendar.level(minutes: cell.minutes)
            Text("\(number)")
                .font(.caption2.weight(cell.isToday ? .black : .regular).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Ablox.Palette.accent.opacity([0.04, 0.25, 0.5, 0.8][level]),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(cell.isToday ? Ablox.Palette.ink : .clear, lineWidth: 1.5))
                .accessibilityLabel(L("Day {}: {} minutes", number, cell.minutes))
        } else {
            Color.clear.frame(minHeight: 30)
        }
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

// MARK: - A friend nearby

/// Says, once, that a friend has started playing nearby, with a way in.
struct FriendNearbyBanner: View {
    let name: String
    let world: String
    var onJoin: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(Ablox.Palette.success)
            Text(L("{} is playing “{}” nearby.", name, world))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(L("Join"), action: onJoin)
                .buttonStyle(NeonButtonStyle(.primary))
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .accessibilityLabel(L("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Ablox.Palette.success.opacity(0.5), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}
