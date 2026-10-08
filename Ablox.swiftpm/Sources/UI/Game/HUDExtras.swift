import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import AbloxCore

// The play screen's optional furniture: the compass, the little chips of
// facts, extra buttons, the visit's stats and the options that choose them.
// The rules (what the compass shows, how a visit is counted) are in the core
// (`HUDOptions.swift`); these only draw them. Kept out of PlayScreen.swift
// so that file stays quick to compile.

// MARK: - What a visit remembers

/// A visit's running counts, kept outside SwiftUI's state: they change with
/// every step, and nothing on screen needs redrawing when they do. Only
/// touched from the play screen, on the main thread.
final class PlayTracker {
    var tally = VisitTally()
    var idle = IdleWatch()
    /// Power notices already given this visit.
    var powerSaid: Set<String> = []
    /// Everything said in a toast this visit, newest last.
    private(set) var notices: [(date: Date, text: String)] = []
    /// The camera at the last look, to notice the player turning it.
    var lastYaw: Float = 0
    /// What was said lately, and the guard against flooding the chat.
    var sent = SentHistory()
    var limiter = ChatRateLimiter()
    /// This week's missions done, and the season's, at the last look.
    var weeklyDone: Set<String> = []
    var eventWaiting = false
    /// When the last eye-rest note was shown, in seconds of this visit.
    var lastEyeRest: Double = 0
    /// Time warnings already given this visit.
    var timeWarnings: Set<Int> = []
    var warnedQuiet = false

    func note(_ text: String) {
        notices.append((Date(), text))
        if notices.count > 30 { notices.removeFirst(notices.count - 30) }
    }
}

// MARK: - Compass

/// North, east, south and west along the top, turning with the camera.
struct CompassStrip: View {
    let bearing: Float

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            ZStack {
                ForEach(Compass.marks(bearing: bearing), id: \.bearing) { mark in
                    Text(mark.label)
                        .font(.system(size: mark.isCardinal ? 14 : 10, weight: mark.isCardinal ? .black : .semibold))
                        .foregroundStyle(mark.bearing == 0 ? Ablox.Palette.danger : Color.white.opacity(mark.isCardinal ? 1 : 0.7))
                        .position(x: half + CGFloat(mark.position) * (half - 14), y: proxy.size.height / 2)
                }
                Capsule()
                    .fill(Ablox.Palette.accent)
                    .frame(width: 2, height: 10)
                    .position(x: half, y: proxy.size.height - 4)
            }
        }
        .frame(width: 260, height: 30)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Facing {}", Compass.spoken(bearing: bearing)))
    }
}

// MARK: - Facts in the corner

/// A small chip of one fact, like the play clock.
struct FactChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(verbatim: text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }
}

/// The facts the player asked for (Play screen options): where they are,
/// how fast they go, the battery, the time, coins so far and today's mission.
struct FactChips: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

    private var hud: HUDOptions { settings.preferences.hud }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let me = session.localPlayer {
                if hud.showPosition {
                    FactChip(systemImage: "location.fill",
                             text: "x \(Int(me.position.x.rounded()))  y \(Int(me.position.y.rounded()))  z \(Int(me.position.z.rounded()))")
                }
                if hud.showSpeed {
                    let speed = Vec3(me.velocity.x, 0, me.velocity.z).length
                    FactChip(systemImage: "speedometer", text: L("{} m/s", String(format: "%.1f", Double(speed))))
                }
                if hud.showCoinsPreview {
                    FactChip(systemImage: "star.circle.fill", text: L("{} coins so far", CoinRate.coins(forScore: me.score)),
                             tint: Ablox.Palette.warning)
                }
            }
            if hud.showBattery || hud.showTimeOfDay {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 6) {
                        if hud.showTimeOfDay {
                            FactChip(systemImage: "clock.fill", text: context.date.formatted(date: .omitted, time: .shortened))
                        }
                        if hud.showBattery, let battery = BatteryReading.now() {
                            FactChip(systemImage: battery.symbol, text: "\(battery.percent)%",
                                     tint: battery.percent <= 20 && !battery.charging ? Ablox.Palette.danger : .white)
                        }
                    }
                }
            }
            if hud.showMissionTracker {
                missionChip
            }
            // Family: how long is left today, when there is a limit.
            if let left = PlayGate.minutesLeft(settings.parental, log: settings.playtime) {
                FactChip(systemImage: "hourglass", text: L("{} min left today", left),
                         tint: left <= 10 ? Ablox.Palette.warning : .white)
            }
        }
    }

    @ViewBuilder private var missionChip: some View {
        let day = settings.today
        let book = settings.memory.missions
        if let next = book.missions(on: day).first(where: { !book.isDone($0, on: day) }) {
            FactChip(systemImage: next.kind.symbolName,
                     text: next.title + "  " + "\(book.progress(of: next, on: day))/\(next.target)",
                     tint: Ablox.Palette.accent)
        }
    }
}

/// The iPad's battery, when it can be read.
struct BatteryReading {
    let percent: Int
    let charging: Bool

    var symbol: String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    @MainActor
    static func now() -> BatteryReading? {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return BatteryReading(percent: Int((level * 100).rounded()),
                              charging: device.batteryState == .charging || device.batteryState == .full)
    }
}

/// "2nd of 5", beside the score.
struct PlaceChip: View {
    let place: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: place == 1 ? "crown.fill" : "trophy.fill")
                .font(.caption)
                .foregroundStyle(place == 1 ? Ablox.Palette.warning : Ablox.Palette.accent)
            Text(Placing.text(place: place, of: count))
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }
}

// MARK: - Extra buttons

/// A round button of the play screen's own look.
struct HUDRoundButton: View {
    let systemImage: String
    let label: String
    var active = false
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(active ? Ablox.Palette.accent : Color.white.opacity(0.2), lineWidth: active ? 2 : 1))
                .foregroundStyle(active ? Ablox.Palette.accent : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Closer and further, for anyone who cannot pinch.
struct ZoomButtons: View {
    let onZoom: (Float) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HUDRoundButton(systemImage: "plus.magnifyingglass", label: L("Zoom in"), size: 46) { onZoom(-0.15) }
            HUDRoundButton(systemImage: "minus.magnifyingglass", label: L("Zoom out"), size: 46) { onZoom(0.15) }
        }
    }
}

/// Held down to run.
struct RunButton: View {
    @Binding var isPressed: Bool
    var haptics = true

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().strokeBorder(Ablox.Palette.warning.opacity(isPressed ? 0.9 : 0.4), lineWidth: 2))
            .overlay(
                Image(systemName: "hare.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isPressed ? Ablox.Palette.warning : .white)
            )
            .frame(width: 58, height: 58)
            .scaleEffect(isPressed ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in isPressed = false }
            )
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isPressed) { _, pressed in haptics && pressed }
            .accessibilityLabel(L("Run"))
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Keyboard shortcuts

/// What each key does while playing; the K key shows it.
struct ShortcutsCard: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L("Keyboard shortcuts"), systemImage: "keyboard")
                        .font(.headline)
                    Spacer()
                    Button(L("Done"), action: onClose)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Ablox.Palette.accent)
                }
                let shortcuts = PlayShortcuts.all
                ForEach(shortcuts.indices, id: \.self) { index in
                    HStack {
                        Text(verbatim: shortcuts[index].keys)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .frame(width: 130, alignment: .leading)
                        Text(shortcuts[index].action)
                            .font(.subheadline)
                        Spacer()
                    }
                }
                Text(L("A game controller: the left stick walks, the right stick looks, A jumps, Y plays a favourite emote, pressing the right stick puts the camera behind you."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .foregroundStyle(.white)
        }
    }
}

// MARK: - This visit

/// How the visit has gone so far: time, distance, jumps, best speed, coins.
struct VisitStatsCard: View {
    let tally: VisitTally
    let seconds: Double
    let score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("This visit"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            HStack(spacing: 8) {
                stat(L("Time"), SelfTimer.clock(Int(seconds)), "clock.fill")
                stat(L("Walked"), L("{} m", Int(tally.metresWalked.rounded())), "figure.walk")
                stat(L("Jumps"), "\(tally.jumps)", "arrow.up.circle.fill")
                stat(L("Top speed"), L("{} m/s", String(format: "%.1f", tally.topSpeed)), "speedometer")
                stat(L("Coins"), "+\(CoinRate.coins(forScore: score))", "star.fill")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(Ablox.Palette.accent)
            Text(verbatim: value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Ablox.Palette.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Options

/// Everything about the play screen a player can change: what shows, the
/// stick, the camera and small habits. In Settings and in the pause menu.
struct PlayScreenOptionsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                showingSection
                chipsSection
                buttonsSection
                stickSection
                cameraSection
                habitsSection
            }
            .navigationTitle(L("Play screen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Reset")) { settings.preferences.hud = HUDOptions() }
                }
            }
        }
        .tint(Ablox.Palette.accent)
    }

    private var hud: Binding<HUDOptions> { $settings.preferences.hud }

    private var showingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("How solid the buttons look"))
                Slider(value: hud.opacity, in: HUDOptions.opacityRange)
            }
            ForEach(TopBarItem.allCases) { item in
                Toggle(item.displayName, isOn: Binding(
                    get: { settings.preferences.hud.shows(item) },
                    set: { settings.preferences.hud.set(item, shown: $0) }))
            }
        } header: {
            Text(L("Top bar"))
        }
    }

    private var chipsSection: some View {
        Section {
            Toggle(L("Compass"), isOn: hud.showCompass)
            Toggle(L("Where I am"), isOn: hud.showPosition)
            Toggle(L("Speed"), isOn: hud.showSpeed)
            Toggle(L("Battery"), isOn: hud.showBattery)
            Toggle(L("Time of day"), isOn: hud.showTimeOfDay)
            Toggle(L("Coins so far"), isOn: hud.showCoinsPreview)
            Toggle(L("My place in the room"), isOn: hud.showRank)
            Toggle(L("Today's next mission"), isOn: hud.showMissionTracker)
            Picker(L("Map size"), selection: hud.mapSize) {
                ForEach(MapSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(L("Map turns with the camera"), isOn: hud.mapTurnsWithCamera)
        } header: {
            Text(L("On the screen"))
        }
    }

    private var buttonsSection: some View {
        Section {
            Toggle(L("Zoom buttons"), isOn: hud.showZoomButtons)
            Toggle(L("Run button"), isOn: hud.showRunButton)
            Toggle(L("Keep walking button"), isOn: hud.showWalkButton)
            Toggle(L("First-person button"), isOn: hud.showViewButton)
            Toggle(L("Shift lock button"), isOn: hud.showShiftLockButton)
            Picker(L("Button layout"), selection: Binding(
                get: { ButtonPreset.allCases.first { $0.matches(settings.preferences) } },
                set: { preset in if let preset { preset.apply(to: &settings.preferences) } })) {
                ForEach(ButtonPreset.allCases) { Text($0.displayName).tag(Optional($0)) }
                if !ButtonPreset.allCases.contains(where: { $0.matches(settings.preferences) }) {
                    Text(L("My own")).tag(ButtonPreset?.none)
                }
            }
        } header: {
            Text(L("Buttons"))
        }
    }

    private var stickSection: some View {
        Section {
            Picker(L("Stick"), selection: hud.joystickStyle) {
                ForEach(JoystickStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(L("Stick on the right"), isOn: $settings.joystickOnRight)
            labelledSlider(L("Stick size"), hud.joystickScale, HUDOptions.joystickScaleRange)
            labelledSlider(L("How solid the stick looks"), hud.joystickOpacity, HUDOptions.joystickOpacityRange)
            labelledSlider(L("Still zone in the middle"), hud.stickDeadZone, HUDOptions.deadZoneRange)
            Toggle(L("Only eight directions"), isOn: hud.eightWay)
            Toggle(L("Always run"), isOn: hud.alwaysRun)
        } header: {
            Text(L("Stick"))
        }
    }

    private var cameraSection: some View {
        Section {
            Toggle(L("Camera follows behind me"), isOn: hud.cameraFollows)
            Toggle(L("Shift lock (face where the camera looks)"), isOn: hud.shiftLock)
            Toggle(L("Two taps put the camera behind me"), isOn: hud.doubleTapResetsCamera)
            Toggle(L("Swap left and right looking"), isOn: hud.invertLookX)
            Toggle(L("Swap up and down looking"), isOn: $settings.invertCameraY)
            labelledSlider(L("Up and down look speed"), hud.verticalLookSpeed, HUDOptions.verticalLookRange)
        } header: {
            Text(L("Camera"))
        }
    }

    private var habitsSection: some View {
        Section {
            Toggle(L("Feel button presses"), isOn: hud.buttonHaptics)
            Toggle(L("Pause when I'm away"), isOn: hud.pauseWhenAway)
            Toggle(L("Warn me about the battery and heat"), isOn: hud.powerWarnings)
        } header: {
            Text(L("Habits"))
        } footer: {
            Text(L("A game you play alone pauses itself after three minutes with nothing touched."))
        }
    }

    private func labelledSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Slider(value: value, in: range)
        }
    }
}

/// The play screen's options, in Settings.
struct PlayScreenOptionsCard: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showing = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(L("Play screen"), systemImage: "rectangle.on.rectangle")
                Text(L("Choose the buttons and facts on the screen while you play: a compass, your speed, the battery, a run button, the stick's size and more."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showing = true
                } label: {
                    Label(L("Change the play screen"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
        .sheet(isPresented: $showing) {
            PlayScreenOptionsView()
        }
    }
}

// MARK: - Noticing a touch

/// Tells the play screen whenever a finger touches anywhere — a game's own
/// button included — without getting in the way of the touch. Used to know
/// that somebody is still playing.
struct TouchWatcher: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.isUserInteractionEnabled = false
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: WatcherView, context: Context) {
        view.onTouch = onTouch
    }

    static func dismantleUIView(_ view: WatcherView, coordinator: ()) {
        view.detach()
    }

    final class WatcherView: UIView {
        var onTouch: (() -> Void)?
        private var recognizer: AnyTouchRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let recognizer = AnyTouchRecognizer(target: nil, action: nil)
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.onTouch = { [weak self] in self?.onTouch?() }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }
    }
}

/// Sees every touch begin, then steps aside at once so nothing else is
/// delayed or cancelled.
final class AnyTouchRecognizer: UIGestureRecognizer {
    var onTouch: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch?()
        state = .failed
    }
}

extension DeviceHeat {
    /// How hot the iPad is running now.
    static var now: DeviceHeat {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }
}
