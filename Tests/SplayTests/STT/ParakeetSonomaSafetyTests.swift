import XCTest
@testable import SplayCore

/// Sonoma's Neural Engine crashes on parallel/long Parakeet work (upstream
/// MacParakeet #998, #1089); every other OS keeps FluidAudio's defaults.
final class ParakeetSonomaSafetyTests: XCTestCase {
    func testSonomaDecodesOneWindowAtATimeOnCPUAndGPU() {
        XCTAssertEqual(ParakeetSonomaSafety.asrConfig(macOSMajorVersion: 14).parallelChunkConcurrency, 1)
        let configuration = ParakeetSonomaSafety.modelConfiguration(macOSMajorVersion: 14)
        XCTAssertEqual(configuration?.computeUnits, .cpuAndGPU)
        XCTAssertEqual(configuration?.allowLowPrecisionAccumulationOnGPU, true, "keep FluidAudio's GPU default")
    }

    func testNewerMacOSKeepsFluidAudioDefaults() {
        for version in [15, 26] {
            XCTAssertEqual(
                ParakeetSonomaSafety.asrConfig(macOSMajorVersion: version).parallelChunkConcurrency,
                4, "FluidAudio 0.14.5 default"
            )
            XCTAssertNil(ParakeetSonomaSafety.modelConfiguration(macOSMajorVersion: version))
        }
    }

    func testNonMacKeepsDefaults() {
        XCTAssertNil(ParakeetSonomaSafety.modelConfiguration(macOSMajorVersion: nil))
    }
}
