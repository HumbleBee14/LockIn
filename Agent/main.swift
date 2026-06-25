import Foundation
import AppKit
import LockInAgentCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let observer = LaunchObserver()
observer.start()

FileHandle.standardError.write(Data("[LockIn] lockin-agent observing\n".utf8))
app.run()
