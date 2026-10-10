import SwiftUI
import AbloxCore

// Downloads in the Games tab: "Download every game" with the megabytes so
// far, and each game's size — coming down, or already on this iPad.
// The numbers come from GameDownloads (in flight) and GameLibrary (on disk).

/// The card at the top of the Games tab.
struct DownloadAllCard: View {
    @ObservedObject var library: GameLibrary
    @ObservedObject private var downloads = GameDownloads.shared

    private var playable: [GameListing] { library.listings.filter(\.isSupported) }
    private var missing: [GameListing] { playable.filter { !library.isInstalled($0) || library.isOutdated($0) } }

    /// The size still to download, when the list says every game's size.
    private var missingBytes: Int? {
        let sizes = missing.compactMap(\.downloadSize)
        return sizes.count == missing.count ? sizes.reduce(0, +) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let bulk = downloads.bulk {
                if bulk.finished { finished(bulk) } else { running(bulk) }
            } else {
                idle
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Ablox.Palette.line, lineWidth: 1)
        )
        // Another Games tab's library may have done the downloading.
        .onChange(of: downloads.endedCount) { _, _ in library.reloadInstalled() }
    }

    private var idle: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: missing.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(missing.isEmpty ? Ablox.Palette.success : Ablox.Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(missing.isEmpty ? L("Every game is on this iPad") : L("Download every game"))
                    .font(.headline)
                    .foregroundStyle(Ablox.Palette.ink)
                Text(L("{} of {} games downloaded · {}", playable.count - missing.count, playable.count, Megabytes.text(library.installedBytes)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
                if !missing.isEmpty {
                    Text(missingBytes.map { L("{} to go · {}", missing.count, Megabytes.text($0)) } ?? L("{} to go", missing.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            if !missing.isEmpty {
                Button {
                    downloads.downloadAll(with: library)
                } label: {
                    Label(L("Download all"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(NeonButtonStyle(.primary))
            }
        }
    }

    private func running(_ bulk: BulkDownload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(bulk.cancelled ? L("Stopping after this game…") : L("Downloading every game…"), systemImage: "arrow.down.circle")
                    .font(.headline)
                    .foregroundStyle(Ablox.Palette.ink)
                Spacer()
                if !bulk.cancelled {
                    Button(role: .cancel) {
                        downloads.cancelAll()
                    } label: {
                        Label(L("Stop"), systemImage: "stop.fill")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }
            }
            ProgressView(value: bulk.fraction)
                .tint(Ablox.Palette.accent)
            Text(bulk.summary)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Ablox.Palette.ink)
            if let current = bulk.current {
                Text(L("Now: {} · {}", current, bulk.currentMeter.text))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    private func finished(_ bulk: BulkDownload) -> some View {
        HStack(spacing: 12) {
            Image(systemName: bulk.failed > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(bulk.failed > 0 ? Ablox.Palette.warning : Ablox.Palette.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(bulk.cancelled ? L("Stopped. {} games downloaded · {}", bulk.done - bulk.failed, Megabytes.text(bulk.bytes))
                                    : L("Done! {} games downloaded · {}", bulk.done - bulk.failed, Megabytes.text(bulk.bytes)))
                    .font(.headline)
                    .foregroundStyle(Ablox.Palette.ink)
                if bulk.failed > 0 {
                    Text(L("{} could not be downloaded. Try again later.", bulk.failed))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.warning)
                }
                Text(L("{} on this iPad", Megabytes.text(library.installedBytes)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Spacer()
            Button(L("OK")) { downloads.dismissBulk() }
                .buttonStyle(NeonButtonStyle(.secondary))
        }
    }
}

/// A game's size on its card: coming down ("⬇ 0.4 / 1.2 MB"), on this
/// iPad ("✓ 1.2 MB"), or how big it will be.
struct DownloadSizeBadge: View {
    let listing: GameListing
    @ObservedObject var library: GameLibrary
    @ObservedObject private var downloads = GameDownloads.shared

    var body: some View {
        if let meter = downloads.games[listing.id] {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle")
                Text(meter.text)
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Ablox.Palette.accent)
            .accessibilityLabel(L("Downloading: {}", meter.text))
        } else if library.isInstalled(listing) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                if let size = library.installedSizes[listing.id] { Text(Megabytes.text(size)) }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Ablox.Palette.success)
            .accessibilityLabel(L("Downloaded"))
        } else if let size = listing.downloadSize {
            Text(Megabytes.text(size))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Ablox.Palette.inkFaint)
                .accessibilityLabel(L("Download size {}", Megabytes.text(size)))
        }
    }
}

/// Under a game's Play button while it comes down: a bar and the megabytes.
struct GameDownloadMeterView: View {
    let listing: GameListing
    @ObservedObject private var downloads = GameDownloads.shared

    var body: some View {
        if let meter = downloads.games[listing.id] {
            VStack(alignment: .leading, spacing: 4) {
                if let fraction = meter.fraction {
                    ProgressView(value: fraction)
                        .tint(Ablox.Palette.accent)
                } else {
                    ProgressView()
                }
                Text(L("Downloading… {}", meter.text))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
    }
}
