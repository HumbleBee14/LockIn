import Foundation
import LockInDaemonCore

let controller = BlockController.makeSystemController()
let listener = DaemonListener(controller: controller)
listener.start()
FileHandle.standardError.write(Data("lockind listening\n".utf8))
RunLoop.main.run()
