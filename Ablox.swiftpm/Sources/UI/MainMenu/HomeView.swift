import SwiftUI
import AbloxCore

/// Home: who you are and what is waiting today. Your avatar and level at the
/// top, then the day's cards — carry on, today's missions, the week's, the
/// streak, the badges nearly earned, the coin jar — gathered here from the
/// old Play tab, so the rooms can have the Play tab to themselves.
struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.screenFit) private var fit

    var onEnter: (ActiveSession) -> Void
    /// Another tab: Me for a new look, Play for the games.
    var onOpen: (MenuTab) -> Void
    /// The Plaza, when it can be opened.
    var onPlaza: (() -> Void)?

    @State private var pictures = 0

    private var stats: ProgressStats {
        settings.progressStats(worldsMade: store.entries.count, pictures: pictures)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                FamilyNoteBanner()
                PlayTimeLeftChip()
                BirthdayBanner()
                EventBanner()
                if fit.isCompact {
                    VStack(spacing: 18) {
                        firstColumn
                        secondColumn
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 18) { firstColumn }
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 18) { secondColumn }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(fit.gutter)
        }
        .onAppear { pictures = ScreenshotStore.all().count }
    }

    @ViewBuilder private var firstColumn: some View {
        ContinueCard(onEnter: onEnter)
        MissionsCard()
        StreakCard()
        CoinJarCard()
    }

    @ViewBuilder private var secondColumn: some View {
        nearlyThere
        WeeklyMissionsCard()
        WeekSummaryCard()
    }

    // MARK: Who you are

    private var greeting: String {
        let name = settings.profile.displayName
        let hour = Calendar.current.component(.hour, from: Date())
        if (5..<11).contains(hour) { return L("Good morning, {}!", name) }
        if (11..<17).contains(hour) { return L("Good afternoon, {}!", name) }
        return L("Good evening, {}!", name)
    }

    private var hero: some View {
        let level = stats.level
        let streak = settings.memory.dailyBonus.streak
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return HStack(spacing: 18) {
            if !fit.isCompact {
                AvatarPreview(profile: settings.profile)
                    .frame(width: 230, height: 250)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(.me) }
                    .accessibilityLabel(Text(L("Change my look")))
                    .accessibilityAddTraits(.isButton)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: greeting)
                    .font(.system(size: fit.isCompact ? 26 : 34, weight: .black, design: .rounded))
                    .foregroundStyle(Ablox.Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !settings.profile.title.isEmpty {
                    Text(verbatim: settings.profile.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Ablox.Palette.warning)
                }
                HStack(spacing: 8) {
                    CountPill(.level, L("Level {}", level.number))
                    CountPill(.coin, "\(settings.wallet.coins)", colour: Ablox.Palette.warning)
                    if streak > 1 {
                        CountPill(.bell, L("{} days in a row", streak), colour: Ablox.Palette.danger)
                    }
                }
                if level.number < PlayerLevel.maximum {
                    ProgressView(value: Double(level.progress), total: Double(max(1, level.span)))
                        .tint(Ablox.Palette.accent)
                    Text(L("{} more to level {}. Play, win and finish missions.", level.span - level.progress, level.number + 1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                HStack(spacing: 10) {
                    Button { onOpen(.me) } label: {
                        Label { Text(L("Change my look")) } icon: { DrawnIconImage(.meShirt, size: 26) }
                    }
                    .buttonStyle(BlockButtonStyle(.plain))
                    if let onPlaza {
                        Button(action: onPlaza) {
                            Label { Text(L("Go to the Plaza")) } icon: { DrawnIconImage(.mascot, size: 26) }
                        }
                        .buttonStyle(BlockButtonStyle(.blue))
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(fit.isCompact ? 16 : 10)
        .padding(.trailing, fit.isCompact ? 0 : 12)
        .background(
            shape.fill(LinearGradient(
                colors: [Ablox.Palette.accentDeep.opacity(0.42), Ablox.Palette.magenta.opacity(0.28), Ablox.Palette.magenta.opacity(0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(shape.strokeBorder(Ablox.Palette.lineStrong, lineWidth: 1.5))
        .background(shape.fill(Color.black.opacity(0.3)).offset(y: 6))
        .padding(.bottom, 6)
    }

    // MARK: Badges nearly earned

    @ViewBuilder private var nearlyThere: some View {
        let next = Achievement.nextUp(stats)
        if !next.isEmpty {
            BlockCard(L("Nearly there"), icon: .meTrophies) {
                VStack(spacing: 8) {
                    ForEach(next) { badge in
                        BadgeProgressRow(badge: badge, stats: stats)
                    }
                }
            }
        }
    }
}
