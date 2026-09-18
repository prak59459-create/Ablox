import SwiftUI

/// Spend coins earned in play on new looks.
///
/// Everything here is cosmetic, and that is a design rule rather than a
/// coincidence: in a game four children play in one room, the one with the
/// most coins must not also be the fastest. `EconomyTests` asserts it.
struct ShopView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var kind: ShopItem.Kind = .bodyColor
    @State private var lastResult: PlayerWallet.PurchaseResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                walletCard
                kindPicker
                itemGrid
            }
            .padding(Ablox.Metrics.gutter)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.wallet)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Shop")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Ablox.Palette.ink)
            Text("Earn coins by collecting and finishing rounds, then unlock new colours and hats.")
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
    }

    private var walletCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                HStack(spacing: 9) {
                    Image(icon: .star)
                        .font(.title)
                        .foregroundStyle(Ablox.Palette.warning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(settings.wallet.coins)")
                            .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(Ablox.Palette.ink)
                        Text("coins")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }

                Divider().frame(height: 38).background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(settings.wallet.lifetimeEarned)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.accent)
                    Text("earned all time")
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }

                Spacer()

                if let lastResult {
                    Text(lastResult.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(lastResult.succeeded ? Ablox.Palette.success : Ablox.Palette.warning)
                        .transition(.opacity)
                }
            }
        }
    }

    private var kindPicker: some View {
        Picker("Category", selection: $kind) {
            ForEach(ShopItem.Kind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private var itemGrid: some View {
        // Locked items first, cheapest at the top, so the next thing worth
        // saving for is always the first thing you see.
        let locked = settings.wallet.lockedItems(of: kind)
        let owned = settings.wallet.ownedItems(of: kind)

        return VStack(alignment: .leading, spacing: 20) {
            if !locked.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeader("To unlock", systemImage: "lock.fill")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 13)], spacing: 13) {
                        ForEach(locked) { item in
                            itemCard(item, owned: false)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                SectionHeader("Yours", systemImage: "checkmark.seal.fill")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 13)], spacing: 13) {
                    ForEach(owned) { item in
                        itemCard(item, owned: true)
                    }
                }
            }
        }
    }

    private func itemCard(_ item: ShopItem, owned: Bool) -> some View {
        let affordable = settings.wallet.canAfford(item)

        return Button {
            guard !owned else {
                apply(item)
                return
            }
            withAnimation {
                lastResult = settings.wallet.purchase(item.id)
            }
            if lastResult?.succeeded == true { apply(item) }
            clearResultSoon()
        } label: {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    preview(item)

                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.ink)
                        .lineLimit(1)

                    if owned {
                        Badge(isEquipped(item) ? "Worn" : "Tap to wear",
                              color: isEquipped(item) ? Ablox.Palette.success : Ablox.Palette.accent)
                    } else {
                        HStack(spacing: 5) {
                            Image(icon: .star)
                                .font(.caption2)
                            Text("\(item.price)")
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        .foregroundStyle(affordable ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        // Unaffordable items stay visible but dimmed: seeing what you are
        // saving for is the point of a shop.
        .opacity(owned || affordable ? 1 : 0.5)
        .accessibilityLabel(owned ? "\(item.name), owned" : "\(item.name), \(item.price) coins")
    }

    @ViewBuilder
    private func preview(_ item: ShopItem) -> some View {
        if let color = item.color {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(color))
                .frame(height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        } else if let hat = item.hat {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: hat.symbolName)
                    .font(.title)
                    .foregroundStyle(Ablox.Palette.accent)
            }
            .frame(height: 54)
        }
    }

    private func isEquipped(_ item: ShopItem) -> Bool {
        switch item.kind {
        case .bodyColor: return item.color == settings.profile.bodyColor
        case .headColor: return item.color == settings.profile.headColor
        case .accentColor: return item.color == settings.profile.accentColor
        case .hat: return item.hat == settings.profile.hat
        }
    }

    /// Wears a newly unlocked item straight away — buying something and then
    /// having to go and find it in the avatar editor is a step nobody wants.
    private func apply(_ item: ShopItem) {
        withAnimation {
            switch item.kind {
            case .bodyColor: if let c = item.color { settings.profile.bodyColor = c }
            case .headColor: if let c = item.color { settings.profile.headColor = c }
            case .accentColor: if let c = item.color { settings.profile.accentColor = c }
            case .hat: if let h = item.hat { settings.profile.hat = h }
            }
        }
    }

    private func clearResultSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { lastResult = nil }
        }
    }
}
