import SwiftUI

/// What a world's script puts on the screen: its own items at nine anchors,
/// and the shooter furniture — crosshair, health, hit marker — that appears
/// only once the script involves it. A world without a script shows none of
/// this.
struct ScriptHUDLayer: View {
    @ObservedObject var session: SessionCoordinator

    var body: some View {
        let state = session.scripted
        ZStack {
            DamageFlash(count: state.damageFlashCount)

            ForEach(HUDElement.Anchor.allCases, id: \.self) { anchor in
                let items = state.elements(at: anchor)
                if !items.isEmpty {
                    VStack(alignment: horizontalAlignment(anchor), spacing: 8) {
                        ForEach(items) { item in
                            ScriptHUDItem(element: item) {
                                session.send(input: .button(id: item.id))
                            }
                        }
                    }
                    .padding(padding(for: anchor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(anchor))
                }
            }

            if state.weapon != nil || state.camera == .firstPerson {
                Crosshair(hitCount: state.hitMarkerCount, knockedOut: state.lastHitWasKnockout)
                    .allowsHitTesting(false)
            }

            if let health = state.health {
                HealthBar(health: health)
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }

            if state.isKnockedOut {
                knockedOutBanner
            }
        }
    }

    private var knockedOutBanner: some View {
        VStack(spacing: 6) {
            Text(L("Knocked out"))
                .font(.largeTitle.weight(.black))
            Text(L("You'll be back in a moment."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(Ablox.Palette.danger.opacity(0.35), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: Layout

    private func alignment(_ anchor: HUDElement.Anchor) -> Alignment {
        switch anchor {
        case .topLeft: return .topLeading
        case .top: return .top
        case .topRight: return .topTrailing
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottom: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }

    private func horizontalAlignment(_ anchor: HUDElement.Anchor) -> HorizontalAlignment {
        switch anchor {
        case .topLeft, .left, .bottomLeft: return .leading
        case .top, .center, .bottom: return .center
        case .topRight, .right, .bottomRight: return .trailing
        }
    }

    /// Clear of the top bar, the joystick and the buttons, which were there
    /// first. A script cannot move its text under a control.
    private func padding(for anchor: HUDElement.Anchor) -> EdgeInsets {
        switch anchor {
        case .topLeft, .top, .topRight: return EdgeInsets(top: 74, leading: 18, bottom: 0, trailing: 18)
        case .left, .right: return EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        // Below the crosshair rather than on it.
        case .center: return EdgeInsets(top: 120, leading: 0, bottom: 0, trailing: 0)
        case .bottomLeft, .bottomRight: return EdgeInsets(top: 0, leading: 170, bottom: 190, trailing: 170)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: 70, trailing: 0)
        }
    }
}

/// One item: a line of text, a bar, or a button.
private struct ScriptHUDItem: View {
    let element: HUDElement
    let onPress: () -> Void

    private var tint: Color {
        element.color.map { Color($0) } ?? .white
    }

    var body: some View {
        switch element.kind {
        case let .text(text):
            Text(verbatim: text)
                .font(font)
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .allowsHitTesting(false)

        case let .bar(value, maximum):
            let fraction = maximum > 0 ? Swift.min(Swift.max(value / maximum, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule()
                    .fill(element.color.map { Color($0) } ?? Ablox.Palette.accent)
                    .frame(width: barWidth * fraction)
            }
            .frame(width: barWidth, height: barHeight)
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .animation(.easeOut(duration: 0.2), value: fraction)
            .allowsHitTesting(false)

        case let .button(label):
            Button(action: onPress) {
                Text(verbatim: label)
                    .font(font)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .frame(minHeight: Ablox.Metrics.minimumTapTarget)
                    .background(element.color.map { Color($0).opacity(0.85) } ?? Ablox.Palette.accentDeep.opacity(0.85),
                                in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var font: Font {
        switch element.size {
        case .small: return .footnote.weight(.semibold)
        case .medium: return .headline
        case .large: return .title.weight(.heavy)
        }
    }

    private var barWidth: CGFloat {
        switch element.size {
        case .small: return 110
        case .medium: return 190
        case .large: return 300
        }
    }

    private var barHeight: CGFloat {
        element.size == .large ? 16 : 11
    }
}

/// A plus in the middle of the screen, which turns into a red cross for a
/// moment when a shot lands.
private struct Crosshair: View {
    let hitCount: Int
    let knockedOut: Bool
    @State private var showingHit = false

    var body: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 2)
            if showingHit {
                Image(systemName: "xmark")
                    .font(.system(size: knockedOut ? 34 : 26, weight: .heavy))
                    .foregroundStyle(knockedOut ? Ablox.Palette.danger : .white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: hitCount) { _, _ in
            withAnimation(.easeOut(duration: 0.08)) { showingHit = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeIn(duration: 0.15)) { showingHit = false }
            }
        }
    }
}

/// A red edge round the screen when you are hit.
private struct DamageFlash: View {
    let count: Int
    @State private var opacity: Double = 0

    var body: some View {
        Rectangle()
            .fill(RadialGradient(
                colors: [.clear, Ablox.Palette.danger.opacity(0.75)],
                center: .center, startRadius: 180, endRadius: 700
            ))
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: count) { _, _ in
                opacity = 1
                withAnimation(.easeOut(duration: 0.45)) { opacity = 0 }
            }
    }
}

private struct HealthBar: View {
    let health: ScriptedPlayerState.Health

    private var colour: Color {
        health.fraction > 0.5 ? Ablox.Palette.success : health.fraction > 0.25 ? Ablox.Palette.warning : Ablox.Palette.danger
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(colour)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(colour).frame(width: 220 * health.fraction)
            }
            .frame(width: 220, height: 12)
            .animation(.easeOut(duration: 0.2), value: health.fraction)
            Text(verbatim: "\(Int(health.current.rounded()))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(minWidth: 34, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Health {} of {}", Int(health.current.rounded()), Int(health.maximum.rounded())))
    }
}

/// The fire button, held to keep firing, with the ammo count and a reload
/// button beside it. Shown only while the script has given a weapon.
struct CombatControls: View {
    @ObservedObject var session: SessionCoordinator
    @Binding var isFiring: Bool

    var body: some View {
        let state = session.scripted
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 8) {
                if let ammo = state.ammo {
                    Text(verbatim: ammo.isReloading ? "…" : "\(ammo.current) / \(ammo.magazine)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(ammo.current == 0 ? Ablox.Palette.warning : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel(ammo.isReloading ? L("Reloading") : L("{} of {} rounds", ammo.current, ammo.magazine))
                }
                Button {
                    session.send(input: .reload)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(L("Reload"))
            }

            Circle()
                .fill(isFiring ? Ablox.Palette.danger.opacity(0.55) : Color.black.opacity(0.25))
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Ablox.Palette.danger.opacity(isFiring ? 1 : 0.6), lineWidth: 3))
                .overlay(
                    Image(systemName: "scope")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                )
                .frame(width: 96, height: 96)
                .scaleEffect(isFiring ? 0.93 : 1)
                .opacity(state.canFire ? 1 : 0.5)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isFiring)
                .gesture(
                    // Held, not tapped: holding keeps firing at the weapon's
                    // rate, which is how every shooter on a phone works.
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isFiring = true }
                        .onEnded { _ in isFiring = false }
                )
                .accessibilityLabel(L("Fire"))
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// The world script's errors and printed lines, on the host's screen.
struct ScriptLogBanner: View {
    @ObservedObject var session: SessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L("Script"), systemImage: "curlybraces")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Spacer()
                Button {
                    session.clearScriptLog()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                .accessibilityLabel(L("Dismiss"))
            }
            ForEach(session.scriptLog.suffix(4)) { line in
                Text(verbatim: line.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.isError ? Ablox.Palette.danger : .white)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
