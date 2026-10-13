import SwiftUI
import UIKit
import AbloxCore

/// The launch check turns the simulator to a side with a launch argument
/// (`-AbloxOrientation landscape` or `portrait`, scripts/ios-launch-check.sh),
/// so each tab is seen held both ways on an iPhone. An iPad or iPhone in
/// someone's hands never passes one, and nothing changes.
enum LaunchOrientation {
    static func apply() {
        let mask: UIInterfaceOrientationMask
        switch UserDefaults.standard.string(forKey: "AbloxOrientation") {
        case "landscape": mask = .landscapeRight
        case "portrait": mask = .portrait
        default: return
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("AbloxOrientation: \(error.localizedDescription)")
            }
        }
    }
}
