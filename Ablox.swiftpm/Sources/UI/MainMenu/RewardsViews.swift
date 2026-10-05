import SwiftUI
import AbloxCore

// Missions, events and coins on the Play tab: the season's banner, this
// week's missions, the streak, the week in numbers, the coin jar, and a
// birthday. Rules in AbloxCore/EventsAndRewards.swift.

// MARK: - The season

/// What is on now — its bonus, sale and days left — or what is coming.
struct EventBanner: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let event = settings.currentEvent {
            let colours = event.colours
            let left = event.daysLeft(on: Date())
            HStack(spacing: 14) {
                Image(systemName: event.symbolName)
                    .font(.system(size: 30, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.displayName)
                        .font(.title3.weight(.heavy))
                    Text(L("+{}% coins from rounds, and {}% off some looks in the shop.", event.coinBonusPercent, SeasonalEvent.salePercent))
                        .font(.caption.weight(.semibold))
                    Text(left == 0 ? L("Last day!") : L("{} days left", left))
                        .font(.caption2.weight(.bold))
                        .opacity(0.85)
                    // Coins the season's bonus has given so far.
                    let marker = L("{} bonus", event.displayName)
                    let extra = settings.coinLedger.entries.filter { $0.reason.contains(marker) }.reduce(0) { $0 + $1.amount }
                    if extra > 0 {
                        Text(L("{} coins earned this season", extra))
                            .font(.caption2.weight(.bold))
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(LinearGradient(colors: [Color(colours.0), Color(colours.1)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        } else if let next = SeasonalEvent.next(after: Date()), next.days <= 14 {
            Label(L("{} starts in {} days", next.event.displayName, next.days), systemImage: next.event.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
    }
}

/// A happy birthday, and the gift, on the day.
struct BirthdayBanner: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var gift: Int?

    var body: some View {
        if settings.memory.birthday?.isToday() ?? false {
            HStack(spacing: 12) {
                Text(verbatim: "🎂")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Happy birthday, {}!", settings.profile.displayName))
                        .font(.headline)
                    if let gift {
                        Text(L("+{} coins, a present from Ablox.", gift))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.success)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
            .onAppear { if let coins = settings.claimBirthdayGift() { gift = coins } }
        }
    }
}

/// Month and day of a birthday, for the gift. Nothing else is asked.
struct BirthdayPicker: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("My birthday"), isOn: Binding(
                get: { settings.memory.birthday != nil },
                set: { settings.memory.birthday = $0 ? Birthday(month: 1, day: 1) : nil }))
                .tint(Ablox.Palette.accent)
            if let birthday = settings.memory.birthday {
                HStack {
                    Picker(L("Month"), selection: Binding(
                        get: { birthday.month },
                        set: { settings.memory.birthday?.month = $0 })) {
                        ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                    }
                    Picker(L("Day"), selection: Binding(
                        get: { birthday.day },
                        set: { settings.memory.birthday?.day = $0 })) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
                Text(L("Only the month and day, kept on this iPad: a present comes on the day."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
    }
}

// MARK: - This week's missions

struct WeeklyMissionsCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var justClaimed: Int?

    var body: some View {
        let week = settings.thisWeek
        let book = settings.memory.weekly
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(L("This week's missions"), systemImage: "calendar.badge.clock")
                    Spacer()
                    if let justClaimed {
                        Text(L("+{} coins", justClaimed))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.success)
                    }
                }
                ForEach(book.missions(on: week)) { mission in
                    let progress = book.progress(of: mission, on: week)
                    let done = book.isDone(mission, on: week)
                    HStack(spacing: 12) {
                        Image(systemName: book.isClaimed(mission, on: week) ? "checkmark.circle.fill" : mission.kind.symbolName)
                            .font(.title3)
                            .foregroundStyle(done ? Ablox.Palette.success : Ablox.Palette.magenta)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mission.title)
                                .font(.subheadline.weight(.semibold))
                            ProgressView(value: Double(min(progress, mission.target)), total: Double(mission.target))
                                .tint(done ? Ablox.Palette.success : Ablox.Palette.magenta)
                        }
                        if book.isClaimed(mission, on: week) {
                            Text(L("Done")).font(.caption).foregroundStyle(Ablox.Palette.inkFaint)
                        } else if done {
                            Button(L("Take {}", mission.reward)) {
                                if let coins = settings.claimWeekly(mission) { withAnimation { justClaimed = coins } }
                            }
                            .buttonStyle(NeonButtonStyle(.primary))
                        } else {
                            Text("\(min(progress, mission.target))/\(mission.target)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Ablox.Palette.inkMuted)
                        }
                    }
                }
                if book.isAllDoneBonusWaiting(on: week) {
                    Button {
                        if let coins = settings.claimWeeklyAllDoneBonus() { withAnimation { justClaimed = coins } }
                    } label: {
                        Label(L("The whole week done! Take {} more", WeeklyMissionBook.allDoneBonus), systemImage: "gift.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
                }
                let left = WeeklyMissionBook.daysLeft(on: Date())
                Text(left == 0 ? L("New ones tomorrow, Monday.") : L("{} days left this week. New ones every Monday.", left))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
    }
}

// MARK: - The streak, the week, the jar

/// Days in a row, the next milestone, and days that may be missed.
struct StreakCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let bonus = settings.memory.dailyBonus
        let next = StreakRewards.next(after: bonus.streak)
        GlassCard {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.title)
                        .foregroundStyle(Ablox.Palette.warning)
                    Text("\(bonus.streak)")
                        .font(.title2.weight(.black).monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("{} days in a row", bonus.streak))
                        .font(.headline)
                    if let next {
                        Text(L("{} more for +{} coins", next.days - bonus.streak, next.coins))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        ProgressView(value: Double(bonus.streak), total: Double(next.days))
                            .tint(Ablox.Palette.warning)
                    }
                    // The coming week, if the streak goes on.
                    HStack(spacing: 4) {
                        let preview = StreakRewards.preview(streak: bonus.streak, from: Date())
                        ForEach(preview.indices, id: \.self) { index in
                            VStack(spacing: 1) {
                                Text(preview[index].date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Ablox.Palette.inkFaint)
                                Text("\(preview[index].coins)")
                                    .font(.system(size: 10, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(Ablox.Palette.warning)
                            }
                            .frame(width: 30)
                            .padding(.vertical, 3)
                            .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    HStack(spacing: 10) {
                        if let freezes = bonus.freezes, freezes > 0 {
                            Label(L("{} days you can miss", freezes), systemImage: "snowflake")
                                .foregroundStyle(Ablox.Palette.accent)
                        }
                        if StreakRewards.weekendMultiplier(on: Date()) > 1 {
                            Label(L("Double bonus at the weekend"), systemImage: "sparkles")
                                .foregroundStyle(Ablox.Palette.success)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Play and coins over the last seven days, against the seven before.
struct WeekSummaryCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let week = WeekSummary.make(days: settings.playtime.days, ledger: settings.coinLedger)
        if week.minutes > 0 || week.coinsEarned > 0 {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(L("Your week"), systemImage: "chart.bar.fill")
                        Spacer()
                        if let favourite = week.favouriteGame {
                            Label(L("Most played: {}", favourite), systemImage: "crown.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ablox.Palette.warning)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 10) {
                        tile(L("Minutes"), "\(week.minutes)", comparison(week))
                        tile(L("Days played"), "\(week.daysPlayed)", nil)
                        tile(L("Coins earned"), "+\(week.coinsEarned)", nil)
                        tile(L("Coins spent"), "\(week.coinsSpent)", nil)
                    }
                }
            }
        }
    }

    private func comparison(_ week: WeekSummary) -> String? {
        guard week.lastWeekMinutes > 0 else { return nil }
        let change = week.minutes - week.lastWeekMinutes
        return change >= 0 ? L("{} more than last week", change) : L("{} less than last week", -change)
    }

    private func tile(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(Ablox.Palette.inkMuted)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Coins put aside grow a little every week.
struct CoinJarCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var amount = 50.0

    var body: some View {
        let jar = settings.memory.coinJar
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Coin jar"), systemImage: "cylinder.split.1x2.fill")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(jar.balance)")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    Text(L("coins saved"))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                    Spacer()
                    if let days = jar.daysToGrowth() {
                        Label(L("Grows in {} days", days), systemImage: "leaf.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ablox.Palette.success)
                    }
                }
                Text(L("Coins in the jar grow by {}% every week they stay there (up to {} a week).", CoinJar.weeklyPercent, CoinJar.weeklyMaximum))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.wallet.coins >= 10 || jar.balance > 0 {
                    let top = CoinJar.sliderTop(coins: settings.wallet.coins, saved: jar.balance)
                    let chosen = CoinJar.chosen(amount, top: top)
                    HStack {
                        // Only when there is a choice to make: a slider whose
                        // two ends are the same number stops the whole app
                        // (SwiftUI: "max stride must be positive").
                        if top > CoinJar.step {
                            Slider(value: $amount, in: Double(CoinJar.step)...Double(top), step: Double(CoinJar.step))
                                .tint(Ablox.Palette.accent)
                        } else {
                            Spacer()
                        }
                        Text("\(chosen)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44)
                    }
                    HStack {
                        Button(L("Put in")) { settings.putInJar(chosen) }
                            .buttonStyle(NeonButtonStyle(.primary))
                            .disabled(settings.wallet.coins < chosen)
                        Button(L("Take out")) { settings.takeFromJar(chosen) }
                            .buttonStyle(NeonButtonStyle(.secondary))
                            .disabled(jar.balance == 0)
                    }
                }
            }
        }
        .onAppear { settings.growCoinJar() }
    }
}
