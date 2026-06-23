import Foundation

FileHandle.standardError.write(Data("lockind starting\n".utf8))
RunLoop.main.run()
