import Foundation
import LockInAgentCore

let observer = LaunchObserver()
observer.start()

FileHandle.standardError.write(Data("[LockIn] lockin-agent observing\n".utf8))
RunLoop.main.run()
