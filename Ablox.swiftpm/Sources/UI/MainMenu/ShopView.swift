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
    /// Set when today's spending limit (Settings → Family) says no.
    @State private var limitMessage: String?
    @State private var onlyWishlist = false
    @State private var tryingOn: ShopItem?
    @State private var showingHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                walletCard
                wishlistReady
                kindPicker
                itemGrid
            }
            .padding(Ablox.Metrics.gutter)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.wallet)
        .sheet(item: $tryingOn) { item in
            TryOnSheet(item: item) { buy(item) }
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingHistory) {
            CoinHistorySheet(ledger: settings.coinLedger)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Shop"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Ablox.Palette.ink)
            Text(L("Earn coins by collecting and finishing rounds, then unlock new colours, faces, hats and pets."))
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
                        Text(L("coins"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }

                Divider().frame(height: 38).background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 1) {
                    // The collection: how much of the shop is yours.
                    let owned = settings.wallet.ownedItemIDs.intersection(Set(ShopCatalogue.items.map(\.id))).count
                    Text("\(owned) / \(ShopCatalogue.items.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.accent)
                    Text(L("collected"))
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }

                Spacer()

                if let limitMessage {
                    Text(limitMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.warning)
                }
                if let lastResult {
                    Text(lastResult.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(lastResult.succeeded ? Ablox.Palette.success : Ablox.Palette.warning)
                        .transition(.opacity)
                }

                Button {
                    showingHistory = true
                } label: {
                    Label(L("History"), systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
    }

    /// Wanted things that can be bought now.
    @ViewBuilder private var wishlistReady: some View {
        let ready = settings.memory.wishlist.compactMap(ShopCatalogue.item(id:))
            .filter { !settings.wallet.owns($0) && settings.wallet.canAfford($0) }
        if !ready.isEmpty {
            Label(L("You can buy {} things on your wishlist!", ready.count), systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ablox.Palette.warning)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShopItem.Kind.allCases, id: \.self) { option in
                        Button {
                            kind = option
                        } label: {
                            Text(option.displayName)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(kind == option ? Ablox.Palette.accent.opacity(0.35) : Color.white.opacity(0.07), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Toggle(L("Only my wishlist"), isOn: $onlyWishlist)
                .tint(Ablox.Palette.accent)
                .frame(maxWidth: 320)
        }
    }

    private var itemGrid: some View {
        // Locked items first, cheapest at the top, so the next thing worth
        // saving for is always the first thing you see.
        let wanted = settings.memory.wishlist
        let locked = settings.wallet.lockedItems(of: kind).filter { !onlyWishlist || wanted.contains($0.id) }
        let owned = settings.wallet.ownedItems(of: kind).filter { !onlyWishlist || wanted.contains($0.id) }

        return VStack(alignment: .leading, spacing: 20) {
            if !locked.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeader(L("To unlock"), systemImage: "lock.fill")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 13)], spacing: 13) {
                        ForEach(locked) { item in
                            itemCard(item, owned: false)
                        }
                    }
                }
            }

            if !owned.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeader(L("Yours"), systemImage: "checkmark.seal.fill")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 13)], spacing: 13) {
                        ForEach(owned) { item in
                            itemCard(item, owned: true)
                        }
                    }
                }
            }
        }
    }

    private func buy(_ item: ShopItem) {
        withAnimation {
            if let result = settings.buy(item) {
                lastResult = result
                limitMessage = nil
                if result.succeeded { settings.memory.wishlist.remove(item.id) }
            } else {
                lastResult = nil
                limitMessage = L("That's more than today's spending limit.")
            }
        }
        if lastResult?.succeeded == true { apply(item) }
        clearResultSoon()
    }

    private func itemCard(_ item: ShopItem, owned: Bool) -> some View {
        let affordable = settings.wallet.canAfford(item)
        let wanted = settings.memory.wishlist.contains(item.id)

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    preview(item)
                    if !owned {
                        Button {
                            if wanted { settings.memory.wishlist.remove(item.id) } else { settings.memory.wishlist.insert(item.id) }
                        } label: {
                            Image(systemName: wanted ? "heart.fill" : "heart")
                                .foregroundStyle(wanted ? Ablox.Palette.danger : .white)
                                .padding(6)
                                .background(Color.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(wanted ? L("Remove from wishlist") : L("Add to wishlist"))
                    }
                }

                HStack {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ablox.Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !item.isFree {
                        Text(item.rarity.displayName)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(ColorRGBA(hex: item.rarity.colorHex) ?? ColorRGBA(r: 1, g: 1, b: 1)).opacity(0.25), in: Capsule())
                            .foregroundStyle(Color(ColorRGBA(hex: item.rarity.colorHex) ?? ColorRGBA(r: 1, g: 1, b: 1)))
                    }
                }

                if owned {
                    Button {
                        apply(item)
                    } label: {
                        Badge(isEquipped(item) ? L("Worn") : L("Tap to wear"),
                              color: isEquipped(item) ? Ablox.Palette.success : Ablox.Palette.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            buy(item)
                        } label: {
                            HStack(spacing: 5) {
                                Image(icon: .star)
                                    .font(.caption2)
                                Text("\(item.price)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                            }
                            .foregroundStyle(affordable ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                        Spacer()
                        Button(L("Try on")) { tryingOn = item }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Unaffordable items stay visible but dimmed: seeing what you are
        // saving for is the point of a shop.
        .opacity(owned || affordable ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(owned ? L("{}, owned", item.displayName) : L("{}, {} coins", item.displayName, item.price))
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
        } else {
            let symbol = item.hat?.symbolName ?? item.face?.symbolName ?? item.pet?.symbolName ?? "questionmark"
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: symbol)
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
        case .face: return item.face == settings.profile.face
        case .pet: return item.pet == settings.profile.pet
        }
    }

    /// Wears a newly unlocked item straight away — buying something and then
    /// having to go and find it in the avatar editor is a step nobody wants.
    private func apply(_ item: ShopItem) {
        withAnimation { settings.profile = item.wornBy(settings.profile) }
    }

    private func clearResultSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation {
                lastResult = nil
                limitMessage = nil
            }
        }
    }
}

extension ShopItem {
    /// `profile` wearing this item.
    func wornBy(_ profile: AvatarProfile) -> AvatarProfile {
        var look = profile
        switch kind {
        case .bodyColor: if let c = color { look.bodyColor = c }
        case .headColor: if let c = color { look.headColor = c }
        case .accentColor: if let c = color { look.accentColor = c }
        case .hat: if let h = hat { look.hat = h }
        case .face: if let f = face { look.face = f }
        case .pet: if let p = pet { look.pet = p }
        }
        return look
    }
}

/// The avatar wearing something before it is bought.
private struct TryOnSheet: View {
    let item: ShopItem
    let onBuy: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(L("Trying on: {}", item.displayName))
                .font(.title3.weight(.bold))
            AvatarPreview(profile: item.wornBy(settings.profile))
                .frame(height: 360)
            HStack(spacing: 12) {
                Button(L("Buy for {} coins", item.price)) {
                    onBuy()
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(.primary))
                .disabled(!settings.wallet.canAfford(item))
                Button(L("Close")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary))
            }
            if !settings.wallet.canAfford(item) {
                Text(L("{} more coins to go.", item.price - settings.wallet.coins))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

/// Every coin in and out, newest first.
private struct CoinHistorySheet: View {
    let ledger: CoinLedger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if ledger.entries.isEmpty {
                    Text(L("Nothing yet. Coins you earn and spend are listed here."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(ledger.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.reason)
                                .font(.subheadline)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Ablox.Palette.inkFaint)
                        }
                        Spacer()
                        Text(entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(entry.amount > 0 ? Ablox.Palette.success : Ablox.Palette.warning)
                    }
                }
            }
            .navigationTitle(L("Coin history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
