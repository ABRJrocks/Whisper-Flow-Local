import Foundation
import IOKit.ps

struct HardwareProfile: Sendable {
    let machineIdentifier: String
    let physicalMemoryBytes: UInt64
    let thermalState: ProcessInfo.ThermalState
    let isLowPowerModeEnabled: Bool
    let batteryPowered: Bool

    var memoryGB: Int { Int(physicalMemoryBytes / (1024 * 1024 * 1024)) }

    /// Spec §6.3 tiers.
    enum Tier: String, Sendable { case minimal, balanced, quality, maximum }

    var tier: Tier {
        switch memoryGB {
        case ..<12: return .minimal
        case ..<20: return .balanced
        case ..<28: return .quality
        default: return .maximum
        }
    }
}

enum HardwareProfiler {
    static func current() -> HardwareProfile {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)

        return HardwareProfile(
            machineIdentifier: String(cString: model),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryPowered: isOnBattery()
        )
    }

    private static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue()
        else { return false }
        return (source as String) == kIOPSBatteryPowerValue
    }
}

/// Downshifts model choices under heat / low power (spec §6.4). Engines and the LLM
/// consult `allowHeavyModels` before loading anything big.
@MainActor
final class AdaptivePerformanceController {
    static let shared = AdaptivePerformanceController()

    private(set) var throttled = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reassess() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reassess() }
        }
        reassess()
    }

    private func reassess() {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let wasThrottled = throttled
        throttled = thermal == .serious || thermal == .critical || lowPower
        if throttled != wasThrottled {
            log.info("Adaptive performance: throttled=\(self.throttled)")
            if throttled {
                Task { await LLMManager.shared.unloadForMemoryPressure() }
            }
        }
    }

    /// When throttled and the user allows automatic management, prefer light engines.
    var allowHeavyModels: Bool {
        !throttled || Prefs.performancePreference == "quality"
    }
}
