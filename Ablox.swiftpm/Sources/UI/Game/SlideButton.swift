import SwiftUI
import AbloxCore

/// ⇩: slides, in every game (`QuickSlide`). Beside the jump button, where
/// the run button was; a tap rather than a hold, as a slide has its own
/// length.
struct SlideButton: View {
    var haptics = true
    let onSlide: () -> Void

    @State private var pressed = false

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().strokeBorder(Color.cyan.opacity(pressed ? 0.9 : 0.45), lineWidth: 2))
            .overlay(
                Image(systemName: "arrow.down")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(pressed ? Color.cyan : .white)
            )
            .frame(width: 60, height: 60)
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onSlide()
                    }
                    .onEnded { _ in pressed = false }
            )
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pressed) { _, down in haptics && down }
            .accessibilityLabel(L("Slide"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSlide() }
    }
}
