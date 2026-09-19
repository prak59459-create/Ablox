import SwiftUI

/// A thumbstick for touch.
///
/// Floating rather than fixed: the stick centres itself wherever the thumb
/// first lands inside its zone. On a 13" iPad there is no single spot a thumb
/// reliably reaches, and a fixed stick forces the hand to hunt for it.
public struct VirtualJoystick: View {
    /// Normalised offset, `x` right and `z` forward, each in `-1...1`.
    @Binding var value: Vec3
    var onRunStateChange: ((Bool) -> Void)?

    private let outerRadius: CGFloat = 78
    private let knobRadius: CGFloat = 32
    /// Past this fraction of the travel, the player is running.
    private let runThreshold: CGFloat = 0.85

    @State private var origin: CGPoint?
    @State private var knobOffset: CGSize = .zero
    @State private var isRunning = false

    public init(value: Binding<Vec3>, onRunStateChange: ((Bool) -> Void)? = nil) {
        self._value = value
        self.onRunStateChange = onRunStateChange
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The whole zone is the touch target; the ring is only drawn
                // once a thumb is down.
                Color.clear.contentShape(Rectangle())

                if let origin {
                    ring
                        .position(origin)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if origin == nil {
                            withAnimation(.easeOut(duration: 0.12)) {
                                origin = gesture.startLocation
                            }
                        }
                        update(with: gesture.translation)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            origin = nil
                            knobOffset = .zero
                        }
                        value = .zero
                        setRunning(false)
                    }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel(L("Movement stick"))
        .accessibilityHint(L("Drag to walk. Push all the way to run."))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color.white.opacity(isRunning ? 0.5 : 0.18), lineWidth: isRunning ? 2 : 1))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            Circle()
                .fill(isRunning ? Ablox.Palette.accent : Color.white.opacity(0.85))
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .offset(knobOffset)
        }
        .allowsHitTesting(false)
    }

    private func update(with translation: CGSize) {
        let maxTravel = outerRadius - knobRadius
        let raw = CGVector(dx: translation.width, dy: translation.height)
        let distance = (raw.dx * raw.dx + raw.dy * raw.dy).squareRoot()

        // Clamp to the ring so the knob never leaves its housing, and so the
        // reported magnitude tops out at exactly 1.
        let clamped: CGVector
        if distance > maxTravel, distance > 0 {
            let scale = maxTravel / distance
            clamped = CGVector(dx: raw.dx * scale, dy: raw.dy * scale)
        } else {
            clamped = raw
        }

        knobOffset = CGSize(width: clamped.dx, height: clamped.dy)

        let nx = Float(clamped.dx / maxTravel)
        // Screen-down is +y, but forward is +z in the movement input, so the
        // vertical axis is negated here rather than at every read site.
        let nz = Float(-clamped.dy / maxTravel)
        value = Vec3(nx, 0, nz)

        setRunning(distance >= maxTravel * runThreshold)
    }

    private func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        onRunStateChange?(running)
    }
}

// MARK: - Camera pad

/// The half of the screen that turns the camera. Invisible by design: any
/// drag that is not on the stick or a button orbits the view.
public struct CameraPad: View {
    @Binding var yaw: Float
    @Binding var pitch: Float
    var sensitivity: Double
    var invertY: Bool
    /// A tap that did not move is forwarded, so tapping a block still works
    /// through the pad.
    var onTap: ((CGPoint) -> Void)?

    @State private var lastTranslation: CGSize = .zero
    @State private var didDrag = false

    public init(
        yaw: Binding<Float>,
        pitch: Binding<Float>,
        sensitivity: Double = 1,
        invertY: Bool = false,
        onTap: ((CGPoint) -> Void)? = nil
    ) {
        self._yaw = yaw
        self._pitch = pitch
        self.sensitivity = sensitivity
        self.invertY = invertY
        self.onTap = onTap
    }

    public var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Deltas, not absolute translation: a long drag must
                        // keep turning rather than snapping back.
                        let dx = gesture.translation.width - lastTranslation.width
                        let dy = gesture.translation.height - lastTranslation.height
                        lastTranslation = gesture.translation

                        if abs(gesture.translation.width) > 6 || abs(gesture.translation.height) > 6 {
                            didDrag = true
                        }

                        let factor = Float(0.28 * sensitivity)
                        yaw = normalizeDegrees(yaw - Float(dx) * factor)
                        pitch = max(-75, min(20, pitch + Float(dy) * factor * (invertY ? -1 : 1)))
                    }
                    .onEnded { gesture in
                        if !didDrag { onTap?(gesture.startLocation) }
                        lastTranslation = .zero
                        didDrag = false
                    }
            )
            .accessibilityLabel(L("Camera"))
            .accessibilityHint(L("Drag to look around."))
    }
}

// MARK: - Jump button

public struct JumpButton: View {
    @Binding var isPressed: Bool

    public init(isPressed: Binding<Bool>) {
        self._isPressed = isPressed
    }

    public var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().strokeBorder(Ablox.Palette.accent.opacity(isPressed ? 0.9 : 0.4), lineWidth: 2))
            .overlay(
                Image(systemName: "arrow.up")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(isPressed ? Ablox.Palette.accent : .white)
            )
            .frame(width: 76, height: 76)
            .scaleEffect(isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .gesture(
                // A press-and-hold gesture rather than a Button, so holding
                // the key down keeps `isJumping` true for the solver.
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel(L("Jump"))
            .accessibilityAddTraits(.isButton)
    }
}
