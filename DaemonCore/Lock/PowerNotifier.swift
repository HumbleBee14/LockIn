import Foundation
import IOKit
import IOKit.pwr_mgt

// kIOMessageSystemWillPowerOn from <IOKit/IOMessage.h>; not surfaced in Swift's IOKit overlay.
private let kIOMessageSystemWillPowerOnValue: UInt32 = 0xE0000320

public final class PowerNotifier {
    private let onWake: () -> Void
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootPort: io_connect_t = 0

    public init(onWake: @escaping () -> Void) { self.onWake = onWake }

    public func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(ctx, &port, { ctx, _, type, _ in
            if type == kIOMessageSystemWillPowerOnValue, let ctx = ctx {
                Unmanaged<PowerNotifier>.fromOpaque(ctx).takeUnretainedValue().onWake()
            }
        }, &notifier)
        if let port = port {
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                               .commonModes)
        }
    }
}
