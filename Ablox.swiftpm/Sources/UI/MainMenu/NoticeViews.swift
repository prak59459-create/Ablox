import SwiftUI

/// The newest notice under the update banner, with × to close it and a tap
/// to read the rest.
struct NoticeBanner: View {
    @ObservedObject var service: NoticeService
    @State private var reading: AppNotice?

    var body: some View {
        if let notice = service.active.first {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: notice.kind))
                    .font(.title3)
                    .foregroundStyle(color(for: notice.kind))
                Button {
                    reading = notice
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: notice.title(in: Localization.language))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Ablox.Palette.ink)
                        Text(verbatim: notice.body(in: Localization.language))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if service.active.count > 1 {
                    Text(verbatim: "+\(service.active.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                Button {
                    withAnimation { service.dismiss(notice) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ablox.Palette.inkMuted)
                .accessibilityLabel(L("Close this notice"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color(for: notice.kind).opacity(0.12))
            .overlay(alignment: .bottom) { Divider().background(Ablox.Palette.line) }
            .sheet(item: $reading) { _ in
                NoticeListSheet(service: service)
            }
        }
    }

    fileprivate func symbol(for kind: AppNotice.Kind) -> String {
        switch kind {
        case .info: return "megaphone.fill"
        case .event: return "party.popper.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    fileprivate func color(for kind: AppNotice.Kind) -> Color {
        switch kind {
        case .info: return Ablox.Palette.accent
        case .event: return Ablox.Palette.magenta
        case .warning: return Ablox.Palette.warning
        }
    }
}

/// Every notice showing now, in full.
private struct NoticeListSheet: View {
    @ObservedObject var service: NoticeService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(service.active) { notice in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: notice.title(in: Localization.language))
                                    .font(.headline)
                                    .foregroundStyle(Ablox.Palette.ink)
                                Text(verbatim: notice.body(in: Localization.language))
                                    .font(.subheadline)
                                    .foregroundStyle(Ablox.Palette.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(L("Close this notice")) { service.dismiss(notice) }
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if service.active.isEmpty {
                        Text(L("No notices right now."))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
                .padding(20)
            }
            .background(Ablox.Palette.surface)
            .navigationTitle(L("Notices"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
    }
}
