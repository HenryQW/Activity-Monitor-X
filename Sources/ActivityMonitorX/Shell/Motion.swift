import AppKit
import SwiftUI

/// The one place that decides if the app moves (DESIGN.md, Type, numbers and motion). Curves are `.smooth` only: no bounce.
/// Reduce Motion is read at each call, so a change in System Settings applies at once. Low Power Mode is read through an
/// observable, so a view that asks `Motion` redraws when the mode changes.
@MainActor
enum Motion {
    static var on: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !LowPower.shared.enabled }

    /// For a move, a scale or a number roll; nil (a cut) with Reduce Motion or Low Power Mode.
    static func smooth(_ seconds: Double) -> Animation? { on ? .smooth(duration: seconds) : nil }

    /// For a change of opacity, and for a move or scale that becomes a fade with Reduce Motion or Low Power Mode (0.1 s).
    static func fade(_ seconds: Double = 0.2) -> Animation { .smooth(duration: on ? seconds : 0.1) }
}

/// Low Power Mode, kept current from the system's power state notification.
@Observable @MainActor
final class LowPower {
    static let shared = LowPower()
    private(set) var enabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    private init() {
        Task {
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
