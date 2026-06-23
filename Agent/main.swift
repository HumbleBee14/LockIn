import Foundation

FileHandle.standardError.write(Data("lockin-agent starting\n".utf8))
RunLoop.main.run()
