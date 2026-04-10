import Foundation

enum DebugLog {
    private static let logPath = "/tmp/Murmur-debug.log"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var initialized = false

    static func log(_ tag: String, _ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(tag)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !initialized {
            initialized = true
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}
