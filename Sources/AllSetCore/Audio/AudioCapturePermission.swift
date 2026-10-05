import Foundation

/// Permission to capture other apps' sound ("System Audio Recording Only" in
/// Privacy & Security), which per-app volume needs. macOS has no public way
/// to check or ask for it, so this calls TCC, the privacy service, directly.
public enum AudioCapturePermission {
    public enum Status: Sendable {
        case authorized
        case denied
        /// Never asked.
        case unknown
    }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void

    private nonisolated(unsafe) static let framework =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }

    public static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    public static var status: Status {
        // If TCC ever changes, carry on; macOS asks by itself on first use.
        guard let symbol = dlsym(framework, "TCCAccessPreflight") else { return .authorized }
        switch unsafeBitCast(symbol, to: PreflightFunction.self)(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Shows the system's prompt the first time; answers straight away after
    /// that. Calls back on a background queue.
    public static func request(_ completion: @escaping @Sendable (Bool) -> Void) {
        // TCC waits for the person to answer, so never on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let symbol = dlsym(framework, "TCCAccessRequest") else { return completion(true) }
            unsafeBitCast(symbol, to: RequestFunction.self)(service, nil) { granted in
                completion(granted)
            }
        }
    }
}
