import SwiftUI
import GameController
import QuartzCore
import AbloxCore

/// Playing with a game controller, a keyboard or a mouse, beside the touch
/// controls rather than instead of them.
///
/// - Controller (PlayStation, Xbox, MFi): left stick walks (all the way
///   runs), right stick looks, A / ✕ jumps, R2 fires, L1 runs, Menu or
///   Options pauses, the D-pad zooms.
/// - Keyboard: W A S D walk, Space jumps, Shift runs, F fires, the arrow keys
///   look, Esc or Tab pauses, 1 to 4 play the favourite emotes (Y or △ on a
///   controller plays them in turn). T chats, M opens the map, P takes a
///   picture, V switches first and third person, R puts the camera behind,
///   H hides the buttons and K lists all of this (`PlayShortcuts`).
/// - Controller extras: pressing the right stick puts the camera behind, the
///   D-pad's left and right change who is being watched.
/// - While a text box has the keyboard, keys type and nothing else.
/// - Mouse or trackpad: hold the right button (or two fingers with a click)
///   and move to look; scroll to zoom. The left button is a touch, as always.
///
/// Read once a frame from `GCController`, `GCKeyboard` and `GCMouse`, and
/// written straight into `controls`, which the 3D view reads every frame:
/// published, a held stick redrew the whole play screen every frame.
@MainActor
final class HardwareInput: NSObject, ObservableObject {

    private(set) var stick: Vec3 = .zero { didSet { controls?.padStick = stick } }
    private(set) var jumping = false { didSet { controls?.padJumping = jumping } }
    private(set) var running = false { didSet { controls?.padRunning = running } }
    private(set) var firing = false { didSet { controls?.padFiring = firing } }
    /// Where the stick and buttons go.
    weak var controls: PlayControls?
    /// What is plugged in or paired, for Settings and the first-time hint.
    @Published private(set) var devices: [String] = []

    /// While chat or a menu is open, keys type rather than walk.
    var suspended = false {
        didSet { if suspended { release() } }
    }
    var sensitivity: Float = 1
    var invertY = false
    /// Degrees to turn: yaw (right is positive), pitch (up is positive).
    var onLook: ((Float, Float) -> Void)?
    var onMenu: (() -> Void)?
    /// Positive zooms out.
    var onZoom: ((Float) -> Void)?
    /// A favourite emote: keys 1 to 4 give its slot (from 0); the
    /// controller's Y (△) gives -1, the next one in turn.
    var onEmote: ((Int) -> Void)?
    /// A one-press action from a key or button.
    var onAction: ((PlayKeyAction) -> Void)?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var menuWasDown = false
    private var emoteWasDown: Int?
    private var actionsDown: Set<PlayKeyAction> = []
    /// Text boxes with the keyboard at the moment.
    private var typing = 0
    private var observers: [NSObjectProtocol] = []
    private let mouse = MouseAccumulator()

    func start() {
        guard link == nil else { return }
        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect,
                                          .GCKeyboardDidConnect, .GCKeyboardDidDisconnect,
                                          .GCMouseDidConnect, .GCMouseDidDisconnect]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
        // A game's own text box, or chat: letters type rather than walk.
        let began: [Notification.Name] = [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        let ended: [Notification.Name] = [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification]
        for name in began {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.typing += 1 }
            })
        }
        for name in ended {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { self.typing = Swift.max(0, self.typing - 1) } }
            })
        }
        refreshDevices()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        release()
    }

    private func release() {
        if stick != .zero { stick = .zero }
        if jumping { jumping = false }
        if running { running = false }
        if firing { firing = false }
        _ = mouse.take()
    }

    private func refreshDevices() {
        var found: [String] = GCController.controllers().map { $0.vendorName ?? L("Game controller") }
        if GCKeyboard.coalesced != nil { found.append(L("Keyboard")) }
        if !GCMouse.mice().isEmpty { found.append(L("Mouse or trackpad")) }
        if found != devices { devices = found }
        // The mouse reports how far it moved, not where the pointer is.
        for each in GCMouse.mice() {
            let accumulator = mouse
            each.mouseInput?.mouseMovedHandler = { _, dx, dy in accumulator.add(dx: dx, dy: dy) }
            each.mouseInput?.scroll.valueChangedHandler = { _, _, y in accumulator.addScroll(y) }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let seconds = Float(lastTimestamp == 0 ? 1.0 / 60 : Swift.min(0.1, link.timestamp - lastTimestamp))
        lastTimestamp = link.timestamp
        guard !suspended else { return }

        var move = Vec3.zero
        var jump = false, run = false, fire = false, menu = false
        var emote: Int?
        var actions: Set<PlayKeyAction> = []
        var yaw: Float = 0, pitch: Float = 0, zoom: Float = 0

        if let pad = GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad {
            let left = StickShaping.shaped(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
            move = Vec3(left.x, 0, left.y)
            let right = StickShaping.shaped(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
            yaw += StickShaping.lookDegrees(right.x, seconds: seconds, sensitivity: sensitivity)
            pitch += StickShaping.lookDegrees(right.y, seconds: seconds, sensitivity: sensitivity) * 0.7
            jump = pad.buttonA.isPressed
            run = pad.leftShoulder.isPressed || (pad.leftThumbstickButton?.isPressed ?? false)
                || (left.x * left.x + left.y * left.y) > 0.9
            fire = pad.rightTrigger.isPressed || pad.rightShoulder.isPressed
            menu = pad.buttonMenu.isPressed || (pad.buttonOptions?.isPressed ?? false)
            if pad.buttonY.isPressed { emote = -1 }
            if pad.dpad.up.isPressed { zoom -= seconds * 1.5 }
            if pad.dpad.down.isPressed { zoom += seconds * 1.5 }
            if pad.rightThumbstickButton?.isPressed ?? false { actions.insert(.cameraBehind) }
            if pad.dpad.left.isPressed { actions.insert(.watchPrevious) }
            if pad.dpad.right.isPressed { actions.insert(.watchNext) }
        }

        if typing == 0, KeyboardController.shared.targetID == nil, let keys = GCKeyboard.coalesced?.keyboardInput {
            func down(_ code: GCKeyCode) -> Bool { keys.button(forKeyCode: code)?.isPressed ?? false }
            let walked = KeyMovement.stick(forward: down(.keyW), back: down(.keyS), left: down(.keyA), right: down(.keyD))
            if walked != .zero { move = walked }
            jump = jump || down(.spacebar)
            run = run || down(.leftShift) || down(.rightShift)
            fire = fire || down(.keyF)
            menu = menu || down(.escape) || down(.tab)
            for (slot, code) in [GCKeyCode.one, .two, .three, .four].enumerated() where down(code) { emote = slot }
            let keyed: [(GCKeyCode, PlayKeyAction)] = [(.keyT, .chat), (.returnOrEnter, .chat), (.keyM, .map), (.keyP, .picture),
                                                       (.keyV, .view), (.keyR, .cameraBehind), (.keyH, .hideButtons),
                                                       (.keyK, .shortcuts), (.slash, .shortcuts)]
            for (code, action) in keyed where down(code) { actions.insert(action) }
            let turn: Float = (down(.rightArrow) ? 1 : 0) - (down(.leftArrow) ? 1 : 0)
            let tilt: Float = (down(.upArrow) ? 1 : 0) - (down(.downArrow) ? 1 : 0)
            yaw += turn * 120 * seconds * sensitivity
            pitch += tilt * 80 * seconds * sensitivity
        }

        let (dx, dy, scroll) = mouse.take()
        if GCMouse.current?.mouseInput?.rightButton?.isPressed ?? false {
            yaw += dx * 0.18 * sensitivity
            pitch += dy * 0.18 * sensitivity
        }
        zoom -= scroll * 0.05

        if move != stick { stick = move }
        if jump != jumping { jumping = jump }
        if run != running { running = run }
        if fire != firing { firing = fire }
        if menu && !menuWasDown { onMenu?() }
        menuWasDown = menu
        if let emote, emote != emoteWasDown { onEmote?(emote) }
        emoteWasDown = emote
        // Once per press, not every frame it is held.
        for action in actions.subtracting(actionsDown) { onAction?(action) }
        actionsDown = actions
        if yaw != 0 || pitch != 0 { onLook?(yaw, invertY ? -pitch : pitch) }
        if zoom != 0 { onZoom?(zoom) }
    }
}

/// A key or button that does one thing each time it is pressed.
enum PlayKeyAction: Hashable {
    case chat, map, picture, view, cameraBehind, hideButtons, shortcuts, watchNext, watchPrevious
}

/// How far the mouse moved and scrolled between frames. Written by
/// GameController's handlers, read once a frame, so it keeps its own lock
/// rather than belonging to the main actor.
private final class MouseAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var dx: Float = 0
    private var dy: Float = 0
    private var scroll: Float = 0

    func add(dx: Float, dy: Float) {
        guard dx.isFinite, dy.isFinite else { return }
        lock.lock()
        self.dx += dx
        self.dy += dy
        lock.unlock()
    }

    func addScroll(_ value: Float) {
        guard value.isFinite else { return }
        lock.lock()
        scroll += value
        lock.unlock()
    }

    func take() -> (Float, Float, Float) {
        lock.lock()
        defer { dx = 0; dy = 0; scroll = 0; lock.unlock() }
        return (dx, dy, scroll)
    }
}
