import SwiftUI

// Settings → Family, and Settings → Comfort.
//
// Family is what a parent decides: how long, until when, what chat, which
// rooms, how many coins, which games. A passcode keeps it that way. Comfort
// is what the player chooses for themselves: shake, field of view, text
// size, the screen's warmth, the battery.

/// The card in Settings that opens the family controls.
struct FamilyCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var asking = false
    @State private var open = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionHeader(L("Family"), systemImage: "figure.and.child.holdinghands")
                    Spacer()
                    if settings.parental.isLocked {
                        Badge(L("Locked"), color: Ablox.Palette.success, systemImage: "lock.fill")
                    }
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let left = PlayGate.minutesLeft(settings.parental, log: settings.playtime) {
                    Label(L("{} minutes of play left today", left), systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(left > 10 ? Ablox.Palette.accent : Ablox.Palette.warning)
                }
                Button {
                    if settings.parental.isLocked { asking = true } else { open = true }
                } label: {
                    Label(settings.parental.isLocked ? L("Unlock and change") : L("Family settings"),
                          systemImage: settings.parental.isLocked ? "lock.open" : "slider.horizontal.3")
                }
                .buttonStyle(NeonButtonStyle(.primary))
            }
        }
        .sheet(isPresented: $asking) {
            PasscodeSheet(title: L("Enter the family passcode")) { code in
                if settings.parental.accepts(code) {
                    asking = false
                    // After this sheet has gone: one sheet at a time.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        open = true
                    }
                    return true
                }
                return false
            }
        }
        .sheet(isPresented: $open) {
            FamilySettingsSheet()
                .environmentObject(settings)
        }
    }

    private var summary: String {
        let p = settings.parental
        var parts: [String] = []
        if let limit = p.dailyLimitMinutes { parts.append(L("{} min a day", limit)) }
        if let quiet = p.quietHours { parts.append(L("quiet {}–{}", QuietHours.clock(quiet.start), QuietHours.clock(quiet.end))) }
        if p.chat != .full { parts.append(L("chat: {}", p.chat.displayName)) }
        if !p.allowPublicRooms { parts.append(L("no public rooms")) }
        if p.hideScaryGames { parts.append(L("no scary games")) }
        if parts.isEmpty { return L("Play time, bedtime, chat, rooms and coins, decided together — and locked with a passcode.") }
        return parts.joined(separator: " · ")
    }
}

/// Four to eight digits, typed on a big number pad.
struct PasscodeSheet: View {
    let title: String
    /// Returns whether the code was right; wrong codes shake and clear.
    let onEnter: (String) -> Bool
    @State private var code = ""
    @State private var wrong = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text(title)
                .font(.title3.weight(.bold))
            HStack(spacing: 12) {
                ForEach(0..<max(4, code.count), id: \.self) { i in
                    Circle()
                        .fill(i < code.count ? Ablox.Palette.accent : Color.white.opacity(0.15))
                        .frame(width: 16, height: 16)
                }
            }
            .offset(x: wrong ? 8 : 0)
            .animation(Animation.default.repeatCount(3, autoreverses: true).speed(4), value: wrong)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 14), count: 3), spacing: 14) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✓"], id: \.self) { key in
                    Button {
                        press(key)
                    } label: {
                        Text(verbatim: key)
                            .font(.title2.weight(.semibold))
                            .frame(width: 78, height: 58)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(key == "✓" && code.count < 4)
                }
            }
            Button(L("Cancel")) { dismiss() }
                .buttonStyle(NeonButtonStyle(.secondary))
        }
        .padding(30)
        .presentationDetents([.large])
    }

    private func press(_ key: String) {
        switch key {
        case "⌫": if !code.isEmpty { code.removeLast() }
        case "✓":
            if !onEnter(code) {
                wrong.toggle()
                code = ""
            }
        default:
            if code.count < 8 { code.append(key) }
        }
    }
}

/// Everything a parent can set.
struct FamilySettingsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var settingPasscode = false

    private let limits: [Int?] = [nil, 30, 45, 60, 90, 120, 180]
    private let breaks: [Int?] = [nil, 20, 30, 45, 60]
    private let coinLimits: [Int?] = [nil, 20, 50, 100, 300, 1000]

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Play time")) {
                    Picker(L("Each day"), selection: $settings.parental.dailyLimitMinutes) {
                        ForEach(limits, id: \.self) { minutes in
                            Text(minutes.map { L("{} minutes", $0) } ?? L("No limit")).tag(minutes)
                        }
                    }
                    Picker(L("Rest reminder"), selection: $settings.parental.breakEveryMinutes) {
                        ForEach(breaks, id: \.self) { minutes in
                            Text(minutes.map { L("Every {} minutes", $0) } ?? L("Off")).tag(minutes)
                        }
                    }
                    Toggle(L("Quiet hours (no games)"), isOn: Binding(
                        get: { settings.parental.quietHours != nil },
                        set: { settings.parental.quietHours = $0 ? QuietHours(start: 21 * 60, end: 7 * 60) : nil }
                    ))
                    if settings.parental.quietHours != nil {
                        Picker(L("From"), selection: quietBinding(\.start)) { clockOptions }
                        Picker(L("Until"), selection: quietBinding(\.end)) { clockOptions }
                    }
                }

                Section {
                    Picker(L("Chat"), selection: $settings.parental.chat) {
                        ForEach(ChatAllowance.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Toggle(L("May open public rooms"), isOn: $settings.parental.allowPublicRooms)
                    Toggle(L("May join other people's rooms"), isOn: $settings.parental.allowJoiningRooms)
                } header: {
                    Text(L("Playing with others"))
                } footer: {
                    Text(L("“Ready-made phrases only” lets them say hello and thank you with buttons; nothing typed is sent."))
                }

                Section(L("Coins and games")) {
                    Picker(L("Coins spent a day"), selection: $settings.parental.dailyCoinLimit) {
                        ForEach(coinLimits, id: \.self) { coins in
                            Text(coins.map { L("{} coins", $0) } ?? L("No limit")).tag(coins)
                        }
                    }
                    Toggle(L("Hide scary games"), isOn: $settings.parental.hideScaryGames)
                }

                Section(L("What was played")) {
                    ActivitySummary(log: settings.playtime)
                }

                Section {
                    Button(settings.parental.isLocked ? L("Change the passcode") : L("Lock with a passcode")) {
                        settingPasscode = true
                    }
                    if settings.parental.isLocked {
                        Button(L("Remove the passcode"), role: .destructive) {
                            settings.parental.setPasscode(nil)
                        }
                    }
                } header: {
                    Text(L("Passcode"))
                } footer: {
                    Text(L("With a passcode, only someone who knows it can change these. Everything stays on this iPad."))
                }
            }
            .navigationTitle(L("Family"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $settingPasscode) {
            PasscodeSheet(title: L("Choose a passcode (4–8 digits)")) { code in
                guard ParentalControls.isValidPasscode(code) else { return false }
                settings.parental.setPasscode(code)
                settingPasscode = false
                return true
            }
        }
    }

    @ViewBuilder private var clockOptions: some View {
        ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { minute in
            Text(verbatim: QuietHours.clock(minute)).tag(minute)
        }
    }

    private func quietBinding(_ key: WritableKeyPath<QuietHours, Int>) -> Binding<Int> {
        Binding(
            get: { settings.parental.quietHours?[keyPath: key] ?? 0 },
            set: { value in
                guard var quiet = settings.parental.quietHours else { return }
                quiet[keyPath: key] = value
                settings.parental.quietHours = QuietHours(start: quiet.start, end: quiet.end)
            }
        )
    }
}

/// The last seven days as bars, and the games played most.
struct ActivitySummary: View {
    let log: PlaytimeLog

    var body: some View {
        let days = log.recent(7).reversed()
        let most = max(1, days.map(\.minutes).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days)) { day in
                    VStack(spacing: 4) {
                        Text(verbatim: "\(day.minutes)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Ablox.Palette.accent)
                            .frame(width: 26, height: max(3, CGFloat(day.minutes) / CGFloat(most) * 70))
                        Text(verbatim: String(day.date.suffix(5)))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Minutes played each day this week"))

            ForEach(Array(log.favourites.prefix(5).enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(verbatim: entry.game)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(L("{} min · {} times", Int(entry.seconds / 60), entry.times))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
            }
            if log.favourites.isEmpty {
                Text(L("Nothing played yet."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Settings → Comfort: what the player chooses for themselves.
struct ComfortCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(L("Comfort, eyes and battery"), systemImage: "eye")

                Picker(L("Text size"), selection: $settings.preferences.textSize) {
                    ForEach(TextSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $settings.preferences.cameraShake) {
                    label(L("Screen shake"), L("Games shake the camera for explosions and hits. Off if it makes you feel sick."))
                }
                .tint(Ablox.Palette.accent)

                VStack(alignment: .leading, spacing: 4) {
                    label(L("Field of view"), L("Wider can feel better for people who get motion sick."))
                    Slider(value: $settings.preferences.fieldOfViewBoost, in: PlayPreferences.fieldOfViewRange, step: 5)
                        .tint(Ablox.Palette.accent)
                }

                Toggle(isOn: $settings.preferences.reduceFlashing) {
                    label(L("Fewer flashes"), L("Softer damage flashes, fades and shakes."))
                }
                .tint(Ablox.Palette.accent)

                Toggle(isOn: $settings.preferences.warmScreen) {
                    label(L("Warm screen"), L("A warmer colour while playing, easier on the eyes at night."))
                }
                .tint(Ablox.Palette.accent)

                VStack(alignment: .leading, spacing: 4) {
                    label(L("Dim the game"), L("For a dark room."))
                    Slider(value: $settings.preferences.dimming, in: 0...0.5)
                        .tint(Ablox.Palette.accent)
                }

                Picker(L("Vibration strength"), selection: $settings.preferences.hapticStrength) {
                    ForEach(HapticStrength.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.hapticsEnabled)

                Divider().background(Color.white.opacity(0.08))

                Toggle(isOn: $settings.preferences.batterySaver) {
                    label(L("Battery saver"), L("Lower graphics so the battery lasts longer. Low Power Mode does this by itself."))
                }
                .tint(Ablox.Palette.accent)

                Toggle(isOn: $settings.preferences.coolDownWhenHot) {
                    label(L("Cool down when hot"), L("Lower the graphics by itself when the iPad gets warm."))
                }
                .tint(Ablox.Palette.accent)
            }
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Ablox.Palette.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension TextSize {
    /// The system text size this asks for.
    var dynamicType: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xxLarge
        case .huge: return .accessibility1
        }
    }
}
