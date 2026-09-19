import SwiftUI
import RealityKit

/// Live avatar editor: a rotating 3D preview beside the controls, so a colour
/// change is visible on the actual rig rather than on a swatch.
struct AvatarCustomizerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator

    private enum Slot: String, CaseIterable, Identifiable {
        case body = "Body"
        case head = "Head & arms"
        case accent = "Legs & hat"

        var id: String { rawValue }
    }

    @State private var slot: Slot = .body

    var body: some View {
        HStack(spacing: 0) {
            AvatarPreview(profile: settings.profile)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Ablox.Palette.accentDeep.opacity(0.22), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Avatar")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("This is how you appear in everyone else's world.")
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }

                    nameField
                    colourSection
                    hatSection
                    heightSection
                    randomiseButton
                }
                .padding(Ablox.Metrics.gutter)
            }
            .frame(width: 420)
            .background(.ultraThinMaterial)
        }
        .onChange(of: settings.profile) { _, newValue in
            // Push straight into any live session so other players see the
            // change without a reconnect.
            session.profile = newValue
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Display name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            TextField("Player", text: $settings.profile.displayName)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .submitLabel(.done)
        }
    }

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Colours")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)

            Picker("Part", selection: $slot) {
                ForEach(Slot.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                ForEach(ColorRGBA.palette, id: \.hexString) { color in
                    ColorSwatch(color: color, isSelected: currentColor == color) {
                        setColor(color)
                    }
                }
            }
        }
    }

    private var currentColor: ColorRGBA {
        switch slot {
        case .body: return settings.profile.bodyColor
        case .head: return settings.profile.headColor
        case .accent: return settings.profile.accentColor
        }
    }

    private func setColor(_ color: ColorRGBA) {
        switch slot {
        case .body: settings.profile.bodyColor = color
        case .head: settings.profile.headColor = color
        case .accent: settings.profile.accentColor = color
        }
    }

    private var hatSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Hat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)

            HStack(spacing: 9) {
                ForEach(AvatarProfile.HatStyle.allCases, id: \.self) { hat in
                    Button {
                        settings.profile.hat = hat
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: hat.symbolName)
                                .font(.title3)
                            Text(hat.displayName)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    settings.profile.hat == hat ? Ablox.Palette.accent : Color.white.opacity(0.1),
                                    lineWidth: settings.profile.hat == hat ? 2 : 1
                                )
                        )
                        .foregroundStyle(settings.profile.hat == hat ? Ablox.Palette.accent : Ablox.Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var heightSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Height")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Spacer()
                Text(String(format: "%.2f×", settings.profile.height))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.accent)
            }
            // Bounded deliberately: an avatar far outside this range would
            // fall through the player collider, which is a fixed size.
            Slider(value: $settings.profile.height, in: 0.8...1.25)
                .tint(Ablox.Palette.accent)
        }
    }

    private var randomiseButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                var generated = AvatarProfile.generated(for: PeerID(), name: settings.profile.displayName)
                generated.displayName = settings.profile.displayName
                settings.profile = generated
            }
        } label: {
            Label("Surprise me", systemImage: "dice.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
    }
}

// MARK: - 3D preview

/// A slowly turning avatar on a pedestal.
private struct AvatarPreview: UIViewRepresentable {
    let profile: AvatarProfile

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        context.coordinator.attach(to: view, profile: profile)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(profile: profile)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private var avatar: AvatarEntity?
        private var subscription: Cancellable?
        private var spin: Float = 0

        func attach(to view: ARView, profile: AvatarProfile) {
            let anchor = AnchorEntity(world: .zero)

            let light = DirectionalLight()
            light.light.intensity = 3200
            light.orientation = Quat.euler(degrees: Vec3(-35, 30, 0)).simd
            anchor.addChild(light)

            let pedestal = ModelEntity(
                mesh: .abloxCylinder(height: 0.15, radius: 1.1),
                materials: [SimpleMaterial(color: .init(white: 0.15, alpha: 1), roughness: 0.9, isMetallic: false)]
            )
            pedestal.position = SIMD3<Float>(0, -0.075, 0)
            anchor.addChild(pedestal)

            let avatar = AvatarEntity(peerID: PeerID(), profile: profile, position: .zero)
            anchor.addChild(avatar)
            self.avatar = avatar

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 38
            camera.look(at: SIMD3<Float>(0, 1.0, 0), from: SIMD3<Float>(0, 1.5, 4.2), relativeTo: nil)
            anchor.addChild(camera)

            view.scene.addAnchor(anchor)

            subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let avatar = self.avatar else { return }
                    self.spin += Float(event.deltaTime) * 28
                    avatar.orientation = Quat.yaw(degrees: self.spin).simd
                }
            }
        }

        func update(profile: AvatarProfile) {
            avatar?.apply(profile: profile)
        }

        func detach() {
            subscription?.cancel()
            subscription = nil
        }
    }
}

import Combine
