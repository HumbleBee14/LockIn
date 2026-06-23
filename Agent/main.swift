import Foundation
import LockInAgentCore

let observer = LaunchObserver()
observer.start()

let listener = AgentListener(observer: observer)
listener.start()

FileHandle.standardError.write(Data("lockin-agent observing\n".utf8))
RunLoop.main.run()
