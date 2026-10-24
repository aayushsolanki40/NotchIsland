import Foundation
import IOKit.ps

final class BatteryService: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false

    /// The level that triggered the most recent low-battery alert.
    @Published private(set) var alertLevel = 20

    var onPlugIn: (() -> Void)?
    var onLowBattery: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        update(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue().update(notify: true)
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    func previewLowBattery() {
        alertLevel = 20
        onLowBattery?()
    }

    private func update(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let wasPlugged = isPluggedIn
            let previousLevel = level
            hasBattery = true
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if notify && isPluggedIn && !wasPlugged { onPlugIn?() }
            // Like iOS: warn once when crossing 20% and again at 10%.
            if notify && !isPluggedIn,
               let threshold = [10, 20].first(where: { level <= $0 && previousLevel > $0 }) {
                alertLevel = threshold
                onLowBattery?()
            }
            return
        }
    }
}
