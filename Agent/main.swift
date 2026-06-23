import Foundation
import LockInAgentCore

let observer = LaunchObserver()
observer.start()
FileHandle.standardError.write(Data("lockin-agent observing\n".utf8))
RunLoop.main.run()
