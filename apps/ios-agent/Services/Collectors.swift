import Foundation
import UIKit

@MainActor protocol BatteryCollecting { func read() -> BatteryReading }
@MainActor struct BatteryCollector: BatteryCollecting {
    func read() -> BatteryReading {
        let device = UIDevice.current; device.isBatteryMonitoringEnabled = true
        let state: BatteryState
        switch device.batteryState {
        case .charging: state = .charging
        case .full: state = .full
        case .unplugged: state = .unplugged
        default: state = .unknown
        }
        return BatteryReading(level: device.batteryLevel, state: state)
    }
}
struct StorageCollector {
    // Read only when the foreground view will display it (required reason 85F4.1).
    func read() -> LocalStorageReading? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return LocalStorageReading.make(total: Int64(total), available: Int64(available))
    }
}
