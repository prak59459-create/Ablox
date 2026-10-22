import SwiftUI
import AbloxCore

/// The bell at the top of the menu (8.8): notifications from Ablox — a new
/// version, news, friend requests, friends' rooms to join, new messages —
/// with a count of the new ones (`AbloxInbox`).
struct InboxButton: View {
    @EnvironmentObject private var updater: AppUpdater
    @EnvironmentObject private var notices: NoticeService
    @EnvironmentObject private var cloud: CloudService
    @ObservedObject private var notifier = InboxNotifier.shared
    /// A friend who has started playing nearby: name and world.
    var nearby: (name: String, world: String)?

    @State private var showing = false

    private var items: [InboxItem] {
        var sources = AbloxInbox.Sources(notices: notices.active, nearby: nearby)
        if case let .newer(required) = updater.availability, let latest = updater.latest {
            sources.update = (version: latest.version, required: required)
        }
        let mutual = cloud.friends.filter(\.isMutual)
        sources.requests = cloud.requests.map { (id: $0.id, name: $0.name) }
        sources.unread = mutual.filter(\.hasUnread).map { (id: $0.id, name: $0.label) }
        sources.friendRooms = cloud.rooms.compactMap { room in
            mutual.contains { $0.id == room.host } ? (id: room.id, host: room.hostName, world: room.world) : nil
        }
        return AbloxInbox.items(sources, language: Localization.language)
    }

    var body: some View {
        let list = items
        let unseen = AbloxInbox.unseenCount(list, seen: Set(notifier.seen))
        Button { showing = true } label: {
            Image(systemName: unseen > 0 ? "bell.badge.fill" : "bell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Ablox.Palette.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Ablox.Palette.wash))
                .overlay(alignment: .topTrailing) {
                    if unseen > 0 {
                        Text(verbatim: unseen > 9 ? "9+" : "\(unseen)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Ablox.Palette.danger))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(unseen > 0 ? L("Notifications, {} new", unseen) : L("Notifications")))
        .onAppear { notifier.itemsChanged(list) }
        .onChange(of: list.map(\.id)) { _, _ in notifier.itemsChanged(items) }
        .sheet(isPresented: $showing) {
            InboxSheet(items: list, notifier: notifier)
        }
    }
}

/// Every notification, newest kinds first, and the switch for iPad
/// notifications.
private struct InboxSheet: View {
    let items: [InboxItem]
    @ObservedObject var notifier: InboxNotifier
    @Environment(\.dismiss) private var dismiss
    /// What was new when the list opened, marked while it shows.
    @State private var newOnOpen: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        row(item, isNew: newOnOpen.contains(item.id))
                    }
                    if items.isEmpty {
                        Text(L("Nothing new right now."))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(L("iPad notifications"), isOn: Binding(
                                get: { notifier.isEnabled },
                                set: { on in Task { await notifier.setEnabled(on) } }
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(notifier.wasRefused
                                 ? L("The iPad said no. Turn notifications on in the iPad's Settings, then try again.")
                                 : L("Shows these on the iPad, even during a game, while Ablox is open."))
                                .font(.caption)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(Ablox.Palette.surface)
            .navigationTitle(L("Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
        .onAppear {
            newOnOpen = Set(items.map(\.id)).subtracting(notifier.seen)
            notifier.markSeen(items)
        }
    }

    private func row(_ item: InboxItem, isNew: Bool) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: item.kind))
                    .font(.title3)
                    .foregroundStyle(Ablox.Palette.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: item.title)
                            .font(.headline)
                            .foregroundStyle(Ablox.Palette.ink)
                        if isNew {
                            Text(L("New"))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Ablox.Palette.danger))
                        }
                    }
                    Text(verbatim: item.body)
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func symbol(for kind: InboxItem.Kind) -> String {
        switch kind {
        case .update: return "arrow.down.circle.fill"
        case .notice: return "megaphone.fill"
        case .friendRequest: return "person.badge.plus"
        case .friendRoom: return "gamecontroller.fill"
        case .friendMessage: return "bubble.left.fill"
        case .friendNearby: return "person.2.fill"
        }
    }
}
