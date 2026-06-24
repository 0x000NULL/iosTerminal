import Foundation
import CoreGraphics

/// Lightweight app settings backed by UserDefaults so both UIKit (AppTerminalView) and SwiftUI
/// (@AppStorage in SettingsView) read/write the same keys.
enum SettingsStore {
    enum Key {
        static let fontSize = "settings.fontSize"
        static let appLock = "settings.appLock"
        static let bellMode = "settings.bellMode"
    }

    static let minFont: CGFloat = 9
    static let maxFont: CGFloat = 28

    static var fontSize: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: Key.fontSize)
            return v > 0 ? CGFloat(v) : 14
        }
        set {
            let clamped = min(max(newValue, minFont), maxFont)
            UserDefaults.standard.set(Double(clamped), forKey: Key.fontSize)
        }
    }

    /// App-lock (Face ID gate) — defaults ON.
    static var appLockEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.appLock) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.appLock) }
    }

    enum BellMode: String, CaseIterable, Identifiable {
        case haptic, notify, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .haptic: return "Haptic"
            case .notify: return "Notify when backgrounded"
            case .off: return "Off"
            }
        }
    }

    static var bellMode: BellMode {
        get { BellMode(rawValue: UserDefaults.standard.string(forKey: Key.bellMode) ?? "") ?? .haptic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.bellMode) }
    }
}
