import SwiftUI
import AbloxCore

// The side list of setting groups, like a Mac's System Settings: a coloured
// icon and a name for each group, the picked one filled in. On a narrow
// screen the same groups are a row of chips instead. The groups and their
// cards are `SettingsPane` (AbloxCore).

/// A group's icon: its symbol in white on a rounded square of its colour.
struct SettingsPaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 28

    var body: some View {
        let c = pane.colour
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// The search field at the top of the settings, in both layouts.
struct SettingsSearchField: View {
    @Binding var search: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("Search settings"), text: $search)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Ablox.Palette.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The groups down the side, on a wide screen.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @Binding var search: String

    var body: some View {
        let matching = SettingsPane.matching(search)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                let picked = search.isEmpty && pane == selection
                Button {
                    selection = pane
                    search = ""
                } label: {
                    HStack(spacing: 10) {
                        SettingsPaneIcon(pane: pane)
                        Text(pane.title)
                            .font(.system(size: 16, weight: picked ? .semibold : .regular))
                            .foregroundStyle(picked ? Color.white : Ablox.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if matching.contains(pane) {
                            Circle()
                                .fill(Ablox.Palette.accent)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: Ablox.Metrics.minimumTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(picked ? Ablox.Palette.accentDeep : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
    }
}

/// The groups as a row of chips, on a narrow screen.
struct SettingsPaneChips: View {
    @Binding var selection: SettingsPane
    @Binding var search: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsPane.allCases) { pane in
                    let picked = search.isEmpty && pane == selection
                    Button {
                        selection = pane
                        search = ""
                    } label: {
                        HStack(spacing: 6) {
                            SettingsPaneIcon(pane: pane, size: 22)
                            Text(pane.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(picked ? Color.white : Ablox.Palette.ink)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .frame(minHeight: Ablox.Metrics.minimumTapTarget)
                        .background(picked ? Ablox.Palette.accentDeep : Ablox.Palette.wash, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }
}

/// The heading over the cards: the group's icon and name, or the search.
struct SettingsPaneHeading: View {
    let pane: SettingsPane
    let search: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            if search.isEmpty {
                SettingsPaneIcon(pane: pane, size: 36)
                Text(pane.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Text(count == 0 ? L("Nothing matches that search.") : L("{} found", count))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }
        }
    }
}
