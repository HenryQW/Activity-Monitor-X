import Foundation

/// A display's brightness, 0–1, from the private DisplayServices framework: macOS has no public call for it. The built-in
/// display answers; an external display does not (its brightness is set over DDC, which macOS does not read back), so nil.
/// Loaded at run time, so a macOS without the call gives nil, never a crash.
public enum DisplayBrightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    nonisolated(unsafe) private static let get: Get? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Get.self)
    }()

    public static func read(_ display: UInt32) -> Double? {
        var value: Float = 0
        guard let get, get(display, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }
}
