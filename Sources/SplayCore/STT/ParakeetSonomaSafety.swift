import CoreML
import FluidAudio
import Foundation

/// Parakeet settings that keep long transcriptions alive on macOS 14 (Sonoma).
///
/// Sonoma's Neural Engine cannot run Core ML work on the same compiled models
/// in parallel: FluidAudio's default decodes four 15 s windows at once, and
/// upstream MacParakeet measured 0–6 % success on 50+ minute Parakeet jobs on
/// Sonoma (≈ 99 % on macOS 15+). One window at a time (#998) still crashed
/// minutes in (SIGBUS/SIGSEGV), so upstream also moved the encoder off the
/// Neural Engine on 14 only (#1089). FluidAudio 0.14.5 has no encoder-only
/// compute-unit override, so on 14 every Parakeet model goes to CPU + GPU —
/// slower, but it finishes. macOS 15+ keeps FluidAudio's defaults untouched.
/// Revisit with the FluidAudio 0.15.x bump (`encoderComputeUnits:`).
public enum ParakeetSonomaSafety {
    /// macOS major version, or `nil` off macOS (iOS 18+ is not affected).
    public static var currentMacOSMajorVersion: Int? {
        #if os(macOS)
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        #else
        return nil
        #endif
    }

    static func needsSafety(macOSMajorVersion: Int?) -> Bool {
        macOSMajorVersion == 14
    }

    /// `AsrManager` config: one long-form window at a time on Sonoma.
    public static func asrConfig(macOSMajorVersion: Int? = currentMacOSMajorVersion) -> ASRConfig {
        needsSafety(macOSMajorVersion: macOSMajorVersion) ? ASRConfig(parallelChunkConcurrency: 1) : .default
    }

    /// Model configuration: CPU + GPU on Sonoma; `nil` (FluidAudio's default) elsewhere.
    public static func modelConfiguration(macOSMajorVersion: Int? = currentMacOSMajorVersion) -> MLModelConfiguration? {
        guard needsSafety(macOSMajorVersion: macOSMajorVersion) else { return nil }
        // FluidAudio's helper, not a bare MLModelConfiguration: the argument
        // replaces FluidAudio's whole default, which also enables low-precision
        // GPU accumulation — the setting that matters once work is on the GPU.
        return MLModelConfigurationUtils.defaultConfiguration(computeUnits: .cpuAndGPU)
    }
}
