import Foundation
import LockInDaemonCore

let listener = DaemonListener()
listener.start()
FileHandle.standardError.write(Data("lockind listening\n".utf8))
RunLoop.main.run()
