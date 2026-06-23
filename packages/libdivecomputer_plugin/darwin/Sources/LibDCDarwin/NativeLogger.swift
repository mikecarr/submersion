import Foundation

/// Centralized logger that sends log events back to Flutter via Pigeon
/// while also printing to the system console.
class NativeLogger {
    static var flutterApi: DiveComputerFlutterApi?

    // All log output is funneled through this single serial queue so a log call
    // never blocks its caller. The CoreBluetooth delegate queue logs every GATT
    // notification during a download -- hundreds per second under the OSTC
    // fire-hose -- and doing the synchronous print there throttled that queue,
    // which made iOS drop notifications and corrupt the download (issue #394).
    // One serial queue keeps log lines in order while moving the print and the
    // Flutter hand-off off the hot path.
    private static let queue = DispatchQueue(label: "app.submersion.native-logger",
                                             qos: .utility)

    static func d(_ tag: String, category: String, _ message: String) {
        log(tag: tag, category: category, level: "DEBUG", message: message)
    }

    static func i(_ tag: String, category: String, _ message: String) {
        log(tag: tag, category: category, level: "INFO", message: message)
    }

    static func w(_ tag: String, category: String, _ message: String) {
        log(tag: tag, category: category, level: "WARN", message: message)
    }

    static func e(_ tag: String, category: String, _ message: String) {
        log(tag: tag, category: category, level: "ERROR", message: message)
    }

    private static func log(tag: String, category: String, level: String, message: String) {
        queue.async {
            let prefix: String
            switch level {
            case "WARN": prefix = "WARNING: "
            case "ERROR": prefix = "ERROR: "
            default: prefix = ""
            }
            print("[\(tag)] \(prefix)\(message)")
            guard let api = flutterApi else { return }
            DispatchQueue.main.async {
                api.onLogEvent(category: category, level: level, message: message) { _ in
                    // Ignore callback result - don't let logging failures crash the app
                }
            }
        }
    }
}
