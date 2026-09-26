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
        case hat = "Hat"
        case pet = "Pet"

        var id: String { rawValue }
    }

    @State private var slot: Slot = .body
    @EnvironmentObject private var store: ProjectStore
    @State private var previewLink = AvatarPreviewLink()
    @State private var boothOpen = false
    @State private var profileOpen = false
    @State private var sharing: SharedFile?
    @State private var outfitMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            AvatarPreview(profile: settings.profile, link: previewLink, still: boothOpen)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if boothOpen { photoBooth }
                }
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
                        Text(L("Avatar"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(L("This is how you appear in everyone else's world."))
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }

                    nameField
                    outfitsSection
                    colourSection
                    hatSection
                    faceSection
                    petSection
                    heightSection
                    randomiseButton
                    HStack(spacing: 10) {
                        Button {
                            withAnimation { boothOpen.toggle() }
                        } label: {
                            Label(L("Photo booth"), systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
                        Button {
                            profileOpen = true
                        } label: {
                            Label(L("Badges & album"), systemImage: "rosette")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
                    }
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
        .sheet(isPresented: $profileOpen) {
            ProfileSheet()
                .environmentObject(settings)
                .environmentObject(store)
        }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
    }

    // MARK: Outfits

    /// Three saved looks: tap to wear, hold to save the current one.
    private var outfitsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("Outfits"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { index in
                    let saved = settings.memory.outfits[index]
                    Menu {
                        if saved != nil {
                            Button(L("Wear it")) { wear(index) }
                        }
                        Button(L("Save what I'm wearing here")) {
                            var look = settings.profile
                            look.displayName = ""
                            settings.memory.outfits[index] = look
                            outfitMessage = L("Saved in outfit {}", index + 1)
                        }
                        if saved != nil {
                            Button(L("Clear"), role: .destructive) { settings.memory.outfits[index] = nil }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach([saved?.bodyColor, saved?.headColor, saved?.accentColor].indices, id: \.self) { i in
                                    let colour = [saved?.bodyColor, saved?.headColor, saved?.accentColor][i]
                                    Circle()
                                        .fill(colour.map { Color($0) } ?? Color.white.opacity(0.12))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            Text(L("Outfit {}", index + 1))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(saved == nil ? Ablox.Palette.inkFaint : Ablox.Palette.ink)
                    }
                }
            }
            if let outfitMessage {
                Text(outfitMessage)
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.accent)
            }
        }
    }

    private func wear(_ index: Int) {
        guard var look = settings.memory.outfits[index] else { return }
        look.displayName = settings.profile.displayName
        look.title = settings.profile.title
        withAnimation { settings.profile = look }
    }

    // MARK: Face and pet

    private var faceSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("Face"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 9)], spacing: 9) {
                ForEach(AvatarProfile.Face.allCases, id: \.self) { face in
                    let owned = settings.wallet.owns("face.\(face.rawValue)")
                    choice(face.displayName, face.symbolName, selected: settings.profile.face == face, locked: !owned) {
                        settings.profile.face = face
                    }
                }
            }
        }
    }

    private var petSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("Pet"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 9)], spacing: 9) {
                ForEach(AvatarProfile.Pet.allCases, id: \.self) { pet in
                    let owned = settings.wallet.owns("pet.\(pet.rawValue)")
                    choice(pet.displayName, pet.symbolName, selected: settings.profile.pet == pet, locked: !owned) {
                        settings.profile.pet = pet
                    }
                }
            }
        }
    }

    /// One option: tap to wear it, or — locked — a hint that the shop has it.
    private func choice(_ title: String, _ symbol: String, selected: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if !locked { action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: locked ? "lock.fill" : symbol)
                    .font(.title3)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Ablox.Palette.accent : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .foregroundStyle(selected ? Ablox.Palette.accent : (locked ? Ablox.Palette.inkFaint : Ablox.Palette.inkMuted))
        }
        .buttonStyle(.plain)
        .accessibilityHint(locked ? L("In the shop") : "")
    }

    // MARK: Photo booth

    private var photoBooth: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Emote.allCases.filter { $0 != .sit }, id: \.self) { emote in
                    Button {
                        previewLink.play(emote)
                    } label: {
                        Image(systemName: emote.symbolName)
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emote.displayName)
                }
            }
            Button {
                previewLink.snapshot { image in
                    guard let image, let url = ScreenshotStore.save(image, game: L("Photo booth")) else { return }
                    sharing = SharedFile(url: url)
                }
            } label: {
                Label(L("Take a picture"), systemImage: "camera.fill")
            }
            .buttonStyle(NeonButtonStyle(.primary))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.bottom, 24)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L("Display name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            TextField(L("Player"), text: $settings.profile.displayName)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .submitLabel(.done)
        }
    }

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("Colours"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)

            Picker(L("Part"), selection: $slot) {
                ForEach(Slot.allCases) { Text(L($0.rawValue)).tag($0) }
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
        case .hat: return settings.profile.hatColor ?? settings.profile.accentColor
        case .pet: return settings.profile.petColor
        }
    }

    private func setColor(_ color: ColorRGBA) {
        switch slot {
        case .body: settings.profile.bodyColor = color
        case .head: settings.profile.headColor = color
        case .accent: settings.profile.accentColor = color
        case .hat: settings.profile.hatColor = color
        case .pet: settings.profile.petColor = color
        }
    }

    private var hatSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("Hat"))
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
                Text(L("Height"))
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
                // Only from what they own, so a surprise never wears
                // something they have not got.
                var look = settings.profile
                func pick<T>(_ kind: ShopItem.Kind, _ value: (ShopItem) -> T?) -> T? {
                    settings.wallet.ownedItems(of: kind).compactMap(value).randomElement()
                }
                look.bodyColor = pick(.bodyColor) { $0.color } ?? look.bodyColor
                look.headColor = pick(.headColor) { $0.color } ?? look.headColor
                look.accentColor = pick(.accentColor) { $0.color } ?? look.accentColor
                look.hat = pick(.hat) { $0.hat } ?? look.hat
                look.face = pick(.face) { $0.face } ?? look.face
                look.pet = pick(.pet) { $0.pet } ?? look.pet
                look.hatColor = ColorRGBA.palette.randomElement()
                look.petColor = ColorRGBA.palette.randomElement() ?? look.petColor
                settings.profile = look
            }
        } label: {
            Label(L("Surprise me"), systemImage: "dice.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
    }
}

// MARK: - 3D preview

/// Takes a picture of the avatar preview, for the photo booth.
@MainActor
final class AvatarPreviewLink {
    fileprivate weak var view: ARView?
    fileprivate weak var coordinator: AvatarPreview.Coordinator?

    // Nonisolated so a view can make one as a `@State` default.
    nonisolated init() {}

    func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        guard let view else { return completion(nil) }
        view.snapshot(saveToHDR: false) { completion($0) }
    }

    /// A pose for the picture.
    func play(_ emote: Emote) {
        coordinator?.play(emote)
    }
}

/// A slowly turning avatar on a pedestal.
struct AvatarPreview: UIViewRepresentable {
    let profile: AvatarProfile
    var link: AvatarPreviewLink?
    /// Stop turning (the photo booth faces the camera).
    var still = false

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        context.coordinator.attach(to: view, profile: profile)
        link?.view = view
        link?.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(profile: profile)
        context.coordinator.still = still
        link?.view = view
        link?.coordinator = context.coordinator
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
        var still = false

        func play(_ emote: Emote) {
            avatar?.play(emote)
        }

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
                    if self.still {
                        // Ease round to face the camera.
                        self.spin += (0 - self.spin.truncatingRemainder(dividingBy: 360)) * 0.15
                    } else {
                        self.spin += Float(event.deltaTime) * 28
                    }
                    avatar.orientation = Quat.yaw(degrees: self.spin + 180).simd
                    avatar.animate(travelled: 0, deltaTime: Float(event.deltaTime))
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
