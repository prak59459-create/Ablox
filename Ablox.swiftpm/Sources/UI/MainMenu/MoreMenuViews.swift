import SwiftUI
import UIKit
import Network
import AbloxCore

// Smaller additions to the menus: the crosshair's look, games put out of
// sight, a look shared as a code, saving up for something, and what to call
// a friend. The rules are in the core (`CrosshairStyle`, `OutfitCode`,
// `SavingsGoal`, `SocialBook.setNickname`); these only show them.

// MARK: - The crosshair

struct CrosshairPickers: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Crosshair"))
                .font(.subheadline.weight(.medium))
            Picker(L("Crosshair"), selection: $settings.preferences.crosshair) {
                ForEach(CrosshairStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            if settings.preferences.crosshair != .off {
                Picker(L("Crosshair colour"), selection: $settings.preferences.crosshairColor) {
                    ForEach(CrosshairColor.allCases) { colour in
                        Text(colour.displayName).tag(colour)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Settings

/// Settings for the newer pieces: the crosshair, hidden games, searches.
struct MoreSettingsCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                SectionHeader(L("Aiming and searching"), systemImage: "scope")
                CrosshairPickers()
                Text(L("Shown in games with a weapon or a first-person camera."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Hidden games"))
                        Text(L("{} games put out of sight in Games.", settings.memory.hiddenGames.count))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                    Spacer()
                    Button(L("Show them again")) { settings.memory.hiddenGames.removeAll() }
                        .buttonStyle(NeonButtonStyle(.secondary))
                        .disabled(settings.memory.hiddenGames.isEmpty)
                }
                BirthdayPicker()
                HStack {
                    Text(L("Recent searches"))
                    Spacer()
                    Button(L("Clear")) { settings.memory.recentSearches.clear() }
                        .buttonStyle(NeonButtonStyle(.secondary))
                        .disabled(settings.memory.recentSearches.items.isEmpty)
                }
            }
        }
    }
}

// MARK: - A look as a code

struct OutfitCodeSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var message: String?
    @State private var missing: [ShopItem] = []
    @State private var copied = false

    var body: some View {
        let mine = OutfitCode.code(for: settings.profile)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Your look's code")).font(.headline)
                            Text(mine)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .foregroundStyle(Ablox.Palette.accent)
                                .textSelection(.enabled)
                            Text(L("Colours, hat, face, pet and height. Never your name."))
                                .font(.caption)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                            Button {
                                UIPasteboard.general.string = mine
                                copied = true
                            } label: {
                                Label(copied ? L("Copied") : L("Copy the code"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(NeonButtonStyle(.secondary))
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Wear a friend's look")).font(.headline)
                            AbloxTextField(L("Type or paste a code"), text: $typed, onSubmit: wear)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            HStack {
                                Button(L("Paste")) { typed = UIPasteboard.general.string ?? typed }
                                    .buttonStyle(NeonButtonStyle(.secondary))
                                Spacer()
                                Button(L("Wear it"), action: wear)
                                    .buttonStyle(NeonButtonStyle(.primary))
                                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            if let message {
                                Text(message).font(.caption).foregroundStyle(Ablox.Palette.inkMuted)
                            }
                            if !missing.isEmpty {
                                Text(missing.map(\.displayName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Ablox.Palette.warning)
                                Button(L("Add them to my wishlist")) {
                                    for item in missing { settings.memory.wishlist.insert(item.id) }
                                    message = L("Added to your wishlist.")
                                    missing = []
                                }
                                .buttonStyle(NeonButtonStyle(.secondary))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(L("Look codes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
    }

    private func wear() {
        guard let outfit = OutfitCode.outfit(from: typed) else {
            message = L("That code doesn't look right. Check each letter.")
            missing = []
            return
        }
        let result = OutfitCode.wear(outfit, on: settings.profile, wallet: settings.wallet)
        settings.profile = result.profile
        settings.memory.counters.lookCodesWorn += 1
        missing = result.missing
        message = result.missing.isEmpty
            ? L("You're wearing it!")
            : L("Worn, except {} things you don't have yet:", result.missing.count)
    }
}

// MARK: - Saving up

/// What the player is saving for, and how far along: on the Shop tab.
struct SavingsGoalCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let wanted = settings.memory.wishlist.compactMap(ShopCatalogue.item(id:))
            .filter { !settings.wallet.owns($0) }
            .sorted { $0.price < $1.price }
        let goal = settings.memory.savingsGoal.flatMap(ShopCatalogue.item(id:)).flatMap { settings.wallet.owns($0) ? nil : $0 }
        if !wanted.isEmpty || goal != nil {
            GlassCard(padding: 15) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L("Saving up for"), systemImage: "banknote.fill")
                            .font(.headline)
                        Spacer()
                        Menu {
                            ForEach(wanted) { item in
                                Button(L("{} ({} coins)", item.displayName, item.price)) {
                                    settings.memory.savingsGoal = item.id
                                }
                            }
                            if goal != nil {
                                Button(L("No goal"), role: .destructive) { settings.memory.savingsGoal = nil }
                            }
                        } label: {
                            Text(goal == nil ? L("Choose from my wishlist") : L("Change"))
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if let goal {
                        let balance = settings.wallet.coins
                        Text(goal.displayName).font(.subheadline.weight(.semibold))
                        ProgressView(value: SavingsGoal.progress(balance: balance, price: goal.price))
                            .tint(Ablox.Palette.success)
                        let left = SavingsGoal.remaining(balance: balance, price: goal.price)
                        Text(left == 0 ? L("You have enough! Buy it below.") : L("{} more coins to go.", left))
                            .font(.caption)
                            .foregroundStyle(left == 0 ? Ablox.Palette.success : Ablox.Palette.inkMuted)
                        // At this week's pace, roughly when.
                        let perDay = Double(WeekSummary.make(days: settings.playtime.days, ledger: settings.coinLedger).coinsEarned) / 7
                        if left > 0, let days = SavingsGoal.daysToGo(balance: balance, price: goal.price, perDay: perDay) {
                            Text(L("About {} days at this week's pace.", days))
                                .font(.caption2)
                                .foregroundStyle(Ablox.Palette.inkFaint)
                        }
                    } else if !wanted.isEmpty {
                        Text(L("Your wishlist: {} things, {} coins in all.", wanted.count, wanted.reduce(0) { $0 + $1.price }))
                            .font(.caption.weight(.semibold))
                        Text(L("Pick something from your wishlist to see how close you are."))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
            }
        }
    }
}

// MARK: - What to call a friend

struct NicknameSheet: View {
    let friend: PlayerContact
    @EnvironmentObject private var settings: AppSettings
    @State private var text: String

    init(friend: PlayerContact) {
        self.friend = friend
        _text = State(initialValue: friend.nickname ?? "")
    }

    var body: some View {
        TextPromptSheet(title: L("Nickname for {}", friend.name),
                        message: L("Only on this iPad. Their own name still shows beside it."),
                        placeholder: friend.name, confirm: L("Save"), text: $text) {
            settings.social.setNickname(text, for: friend.id)
        }
    }
}

// MARK: - Offline

/// Whether the iPad can reach the internet right now. Nearby play needs no
/// internet, so being offline is said, not treated as a failure.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                if self?.isOnline != online { self?.isOnline = online }
            }
        }
        monitor.start(queue: DispatchQueue(label: "ablox.connectivity"))
    }

    deinit {
        monitor.cancel()
    }
}

/// A quiet line at the top of the menus while there is no internet.
struct OfflineBanner: View {
    @ObservedObject var monitor: ConnectivityMonitor

    var body: some View {
        if !monitor.isOnline {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Ablox.Palette.warning)
                Text(L("No internet. You can still play with iPads nearby, and games you have downloaded."))
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Ablox.Palette.warning.opacity(0.12))
            .accessibilityElement(children: .combine)
        }
    }
}
