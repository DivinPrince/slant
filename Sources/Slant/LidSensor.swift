import Foundation
import IOKit.hid

/// Reads the hinge angle from the MacBook's lid angle sensor. The sensor is a HID
/// device on Apple's sensor hub (vendor 0x05AC, product 0x8104) with the Sensor usage
/// page (0x20) and Orientation usage (0x8A). Report 1 carries the angle as a 16-bit
/// little-endian integer, and the device streams it as input reports at roughly 10 Hz,
/// so there is no polling: the callback fires when the hardware reports.
final class LidSensor {
    /// Called on the main thread with the angle in degrees whenever it changes.
    var onAngle: ((Double) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    private(set) var angle: Double?
    private(set) var isAvailable = false

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: 64)

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    private func attach(_ device: IOHIDDevice) {
        guard self.device == nil else { return }
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.device = device
        let context = Unmanaged.passUnretained(self).toOpaque()
        reportBuffer.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceRegisterInputReportCallback(device, buffer.baseAddress!, buffer.count, { context, result, _, _, reportID, report, length in
                guard let context, result == kIOReturnSuccess, reportID == 1, length >= 3 else { return }
                let raw = UInt16(report[1]) | UInt16(report[2]) << 8
                Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue().receive(raw: raw)
            }, context)
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        isAvailable = true
        onAvailabilityChange?(true)

        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess, length >= 3 {
            receive(raw: UInt16(report[1]) | UInt16(report[2]) << 8)
        }
    }

    private func detach(_ device: IOHIDDevice) {
        guard self.device == device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        isAvailable = false
        angle = nil
        onAvailabilityChange?(false)
    }

    private func receive(raw: UInt16) {
        // Most machines report whole degrees; a few report hundredths.
        let degrees = raw > 360 ? Double(raw) / 100 : Double(raw)
        guard degrees != angle else { return }
        angle = degrees
        onAngle?(degrees)
    }
}
