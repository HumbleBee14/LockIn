import Foundation
import LockInAgentCore

// invariant: never create NSApplication here — it checks the agent into LaunchServices as the LockIn.app
// bundle instance, so `open LockIn.app` activates this invisible agent instead of launching the GUI.
let observer = LaunchObserver()
observer.start()

FileHandle.standardError.write(Data("[LockIn] lockin-agent observing\n".utf8))
RunLoop.main.run()
