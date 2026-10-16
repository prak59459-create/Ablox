import SwiftUI
import AbloxCore

/// The first time Ablox opens (Ablox NEXT, step 5): hello, the language, a
/// name, a look, and where things are. Four short steps; any can be left,
/// and nothing here is needed to play. The browser version asks the same
/// (web/src/app/welcome.ts in AbloxGames).
struct WelcomeSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.screenFit) private var fit
    var onDone: () -> Void

    /// `UserDefaults`: set once the welcome has been seen (or was not needed).
    static let seenKey = "ablox.welcomed"

    @State private var step = 0
    @State private var ideas = Array(Self.nameIdeas.shuffled().prefix(4))
    @State private var part: Part = .body

    private static let nameIdeas = ["BlueFox", "SunnyCat", "StarPanda", "LuckyDuck", "MintBunny", "RocketOwl", "PixelBear", "CloudFrog", "TurboPenguin", "MapleDog"]

    enum Part: CaseIterable, Identifiable {
        case body, head, accent
        var id: Self { self }
        var title: String {
            switch self {
            case .body: return L("Body")
            case .head: return L("Head & arms")
            case .accent: return L("Legs & hat")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Ablox.Palette.accent : i < step ? Ablox.Palette.success : Ablox.Palette.wash)
                        .frame(width: i == step ? 28 : 10, height: 10)
                }
                Spacer()
                Button(L("Close")) { finish() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            ScrollView {
                Group {
                    switch step {
                    case 0: hello
                    case 1: name
                    case 2: colours
                    default: tour
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button(L("Back")) { withAnimation { step -= 1 } }
                        .buttonStyle(BlockButtonStyle(.plain))
                }
                Spacer()
                Button(step == 3 ? L("Let's go!") : L("Next")) { next() }
                    .buttonStyle(BlockButtonStyle(.green, big: true))
            }
        }
        .padding(fit.isCompact ? 18 : 28)
        .frame(maxWidth: 620)
        .abloxColorScheme()
        .interactiveDismissDisabled(false)
    }

    private func next() {
        if step == 3 {
            MenuSounds.fanfare()
            finish()
        } else {
            MenuSounds.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step += 1 }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        onDone()
    }

    // MARK: The steps

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                DrawnIconImage(.mascot, size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Welcome to Ablox!"))
                        .font(.system(size: fit.isCompact ? 26 : 32, weight: .black, design: .rounded))
                    Text(L("Play block games with friends, dress up your avatar, and make games of your own."))
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
            }
            Text(L("Language")).font(.headline)
            Picker(L("Language"), selection: $settings.language) {
                ForEach(LanguagePreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("What should we call you?"))
                .font(.system(size: 24, weight: .black, design: .rounded))
            Text(L("Everyone in a room sees this name. Not your real name — make one up!"))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("Your name"), text: $settings.profile.displayName, limit: AvatarProfile.maximumNameLength)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                ForEach(ideas, id: \.self) { idea in
                    Button(idea) {
                        MenuSounds.tap()
                        settings.profile.displayName = idea
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Ablox.Palette.wash))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Pick your colours"))
                .font(.system(size: 24, weight: .black, design: .rounded))
            HStack(alignment: .top, spacing: 16) {
                AvatarPreview(profile: settings.profile)
                    .frame(width: fit.isCompact ? 120 : 170, height: fit.isCompact ? 160 : 220)
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L("Part"), selection: $part) {
                        ForEach(Part.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
                        ForEach(ColorRGBA.palette, id: \.hexString) { colour in
                            ColorSwatch(color: colour, isSelected: current == colour, size: 36) {
                                MenuSounds.tap()
                                set(colour)
                            }
                        }
                    }
                }
            }
            Text(L("Earn coins in games for more colours, hats, faces and pets in Me."))
                .font(.footnote)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
    }

    private var current: ColorRGBA {
        switch part {
        case .body: return settings.profile.bodyColor
        case .head: return settings.profile.headColor
        case .accent: return settings.profile.accentColor
        }
    }

    private func set(_ colour: ColorRGBA) {
        switch part {
        case .body: settings.profile.bodyColor = colour
        case .head: settings.profile.headColor = colour
        case .accent: settings.profile.accentColor = colour
        }
    }

    private var tour: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Here is where everything is"))
                .font(.system(size: 24, weight: .black, design: .rounded))
            row(.home, L("Home"), L("Your daily bonus and today’s missions."))
            row(.play, L("Play"), L("Every game, and rooms to play with friends."))
            row(.me, L("Me"), L("Your look, the shop, badges and records."))
            if settings.parental.family.buildingAllowed {
                row(.create, L("Create"), L("Make worlds of your own and play them."))
            }
        }
    }

    private func row(_ icon: DrawnIcon, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            DrawnIconImage(icon, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ablox.Palette.wash))
    }
}
