import SwiftUI
import AbloxCore

/// The window's `ScreenFit`, for every view under the app's root — the
/// compact layout on an iPhone, the iPad layout on an iPad.
private struct ScreenFitKey: EnvironmentKey {
    static let defaultValue = ScreenFit(width: 1024, height: 768)
}

extension EnvironmentValues {
    var screenFit: ScreenFit {
        get { self[ScreenFitKey.self] }
        set { self[ScreenFitKey.self] = newValue }
    }
}

/// Measures the window once at the root and hands the result down.
struct ScreenFitting: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.screenFit, ScreenFit(width: Double(proxy.size.width), height: Double(proxy.size.height)))
        }
    }
}
