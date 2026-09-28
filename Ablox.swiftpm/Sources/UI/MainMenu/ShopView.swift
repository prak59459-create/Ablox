import SwiftUI
import AbloxCore

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
    // The second round: filters, order, and undoing a mistaken tap.
    @State private var onlyAffordable = false
    @State private var priceOrder: PriceOrder = .cheapest
    @State private var search = ""
    /// Waiting for a grown-up's passcode to buy this.
    @State private var askingFor: ShopItem?
    /// What was new when the shop opened; marked seen as it opens.
    @State private var newItems: Set<String> = []

    enum PriceOrder: String, CaseIterable, Identifiable {
        case cheapest, dearest, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cheapest: return L("Cheapest first")
            case .dearest: return L("Dearest first")
            case .name: return L("Name")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                walletCard
                undoBar
                DailyDealCard { buy($0) }
                SavingsGoalCard()
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
        .onAppear(perform: noticeNewItems)
        .sheet(item: $askingFor) { item in
            PasscodeSheet(title: L("Ask a grown-up: {} costs {} coins", item.displayName, settings.price(of: item))) { code in
                guard settings.parental.accepts(code) else { return false }
                askingFor = nil
                // The purchase goes ahead once the sheet has gone.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    completePurchase(item)
                }
                return true
            }
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

                Divider().frame(height: 38).background(Ablox.Palette.line)

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
                                .background(kind == option ? Ablox.Palette.accent.opacity(0.35) : Ablox.Palette.wash, in: Capsule())
                                .foregroundStyle(Ablox.Palette.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            AbloxTextField(L("Search the shop"), text: $search)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Ablox.Palette.wash, in: Capsule())
                .frame(maxWidth: 360)
            HStack(spacing: 18) {
                Toggle(L("Only my wishlist"), isOn: $onlyWishlist)
                    .tint(Ablox.Palette.accent)
                    .frame(maxWidth: 260)
                Toggle(L("Only what I can buy"), isOn: $onlyAffordable)
                    .tint(Ablox.Palette.accent)
                    .frame(maxWidth: 260)
                Picker(L("Order"), selection: $priceOrder) {
                    ForEach(PriceOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    /// Items added since the shop was last opened get a NEW mark for this
    /// visit. The very first visit marks nothing: everything is new then.
    private func noticeNewItems() {
        let all = Set(ShopCatalogue.items.map(\.id))
        if let seen = settings.memory.seenShopItems {
            newItems = all.subtracting(seen)
        }
        settings.memory.seenShopItems = all
    }

    /// Undo for five minutes after buying something.
    @ViewBuilder private var undoBar: some View {
        if let item = settings.undoablePurchase {
            HStack {
                Label(L("Bought {}", item.displayName), systemImage: "bag.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L("Undo")) {
                    withAnimation { _ = settings.undoLastPurchase() }
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Locked items as chosen: all or affordable, in the order picked.
    private func arranged(_ items: [ShopItem]) -> [ShopItem] {
        let shown = (onlyAffordable ? items.filter { settings.wallet.coins >= settings.price(of: $0) } : items)
            .filter { SearchText.matches(search, in: [$0.displayName, $0.name]) }
        switch priceOrder {
        case .cheapest: return shown.sorted { settings.price(of: $0) < settings.price(of: $1) }
        case .dearest: return shown.sorted { settings.price(of: $0) > settings.price(of: $1) }
        case .name: return shown.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
    }

    private var itemGrid: some View {
        // Locked items first, cheapest at the top, so the next thing worth
        // saving for is always the first thing you see.
        let wanted = settings.memory.wishlist
        let locked = arranged(settings.wallet.lockedItems(of: kind).filter { !onlyWishlist || wanted.contains($0.id) })
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

    /// Buys after a grown-up said yes.
    private func completePurchase(_ item: ShopItem) {
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

    private func buy(_ item: ShopItem) {
        // Family: dear things need a grown-up's passcode.
        if settings.parental.isLocked, settings.parental.family.needsPermission(price: settings.price(of: item)) {
            askingFor = item
            return
        }
        completePurchase(item)
    }

    private func itemCard(_ item: ShopItem, owned: Bool) -> some View {
        // Today's price: the deal of the day, or an event's sale.
        let cost = settings.price(of: item)
        let affordable = settings.wallet.coins >= cost
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
                    if newItems.contains(item.id) {
                        Text(L("NEW"))
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Ablox.Palette.danger, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if !owned, cost < item.price {
                        Text(L("SALE"))
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Ablox.Palette.warning, in: Capsule())
                            .foregroundStyle(.black)
                    }
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
                                if cost < item.price {
                                    Text("\(item.price)")
                                        .font(.caption2.monospacedDigit())
                                        .strikethrough()
                                        .foregroundStyle(Ablox.Palette.inkFaint)
                                }
                                Text("\(cost)")
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
        .accessibilityLabel(owned ? L("{}, owned", item.displayName) : L("{}, {} coins", item.displayName, cost))
    }

    @ViewBuilder
    private func preview(_ item: ShopItem) -> some View {
        if let colours = item.nameplate?.colours ?? item.bubble?.colours {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ablox.Palette.wash)
                Text(item.bubble != nil ? L("Hello!") : settings.profile.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(colours.text))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(colours.background), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(colours.border.map { Color($0) } ?? .clear, lineWidth: 1.5))
            }
            .frame(height: 54)
        } else if let color = item.color {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(color))
                .frame(height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Ablox.Palette.lineStrong, lineWidth: 1)
                )
        } else {
            let symbol = item.hat?.symbolName ?? item.face?.symbolName ?? item.pet?.symbolName
                ?? item.trail?.symbolName ?? item.aura?.symbolName ?? "questionmark"
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Ablox.Palette.wash)
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
        case .trail: return item.trail == settings.profile.trail
        case .aura: return item.aura == settings.profile.aura
        case .nameplate: return item.nameplate == settings.profile.nameplate
        case .bubble: return item.bubble == settings.profile.bubble
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
        case .trail: if let t = trail { look.trail = t }
        case .aura: if let a = aura { look.aura = a }
        case .nameplate: if let n = nameplate { look.nameplate = n }
        case .bubble: if let b = bubble { look.bubble = b }
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
        .abloxColorScheme()
    }
}

/// Every coin in and out, newest first.
private struct CoinHistorySheet: View {
    let ledger: CoinLedger
    @Environment(\.dismiss) private var dismiss

    private enum Show: String, CaseIterable, Identifiable {
        case all, earned, spent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return L("All")
            case .earned: return L("Earned")
            case .spent: return L("Spent")
            }
        }
    }

    @State private var show: Show = .all

    private var entries: [CoinLedger.Entry] {
        switch show {
        case .all: return ledger.entries
        case .earned: return ledger.entries.filter { $0.amount > 0 }
        case .spent: return ledger.entries.filter { $0.amount < 0 }
        }
    }

    /// The entries by day, newest first.
    private var days: [(day: Date, entries: [CoinLedger.Entry])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var groups: [Date: [CoinLedger.Entry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(entry)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker(L("Show"), selection: $show) {
                    ForEach(Show.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                let earned = ledger.entries.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
                let spent = ledger.entries.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
                HStack {
                    Label(L("Earned {}", earned), systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Ablox.Palette.success)
                    Spacer()
                    Label(L("Spent {}", spent), systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(Ablox.Palette.warning)
                }
                .font(.subheadline.weight(.semibold))
                if ledger.entries.isEmpty {
                    Text(L("Nothing yet. Coins you earn and spend are listed here."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            line(entry)
                        }
                    } header: {
                        let total = group.entries.reduce(0) { $0 + $1.amount }
                        HStack {
                            Text(group.day.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(total >= 0 ? "+\(total)" : "\(total)")
                                .monospacedDigit()
                        }
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
        .abloxColorScheme()
    }

    private func line(_ entry: CoinLedger.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.reason)
                    .font(.subheadline)
                Text(entry.date.formatted(date: .omitted, time: .shortened))
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

// MARK: - Deal of the day

/// One locked thing a day, 30% off.
private struct DailyDealCard: View {
    @EnvironmentObject private var settings: AppSettings
    let onBuy: (ShopItem) -> Void

    var body: some View {
        if let deal = ShopDeals.dailyDeal(on: settings.today, owned: settings.wallet.ownedItemIDs) {
            let cost = settings.price(of: deal)
            HStack(spacing: 14) {
                Image(systemName: "tag.fill")
                    .font(.title2)
                    .foregroundStyle(Ablox.Palette.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Deal of the day: {}", deal.displayName))
                        .font(.headline)
                    Text(L("{}% off today only: {} instead of {}", ShopDeals.dealPercent, cost, deal.price))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                Spacer()
                Button(L("Buy for {}", cost)) { onBuy(deal) }
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(settings.wallet.coins < cost)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Ablox.Palette.danger.opacity(0.4), lineWidth: 1.5))
        }
    }
}
