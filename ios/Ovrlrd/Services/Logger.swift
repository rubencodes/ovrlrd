import Foundation
import os.log

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ovrlrd.app"

    static func debug(
        _ message: String,
        category: String = "general",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let logger = os.Logger(subsystem: subsystem, category: category)
        let filename = (file as NSString).lastPathComponent
        logger.debug("[\(filename):\(line)] \(function) - \(message)")
        #endif
    }

    static func error(
        _ message: String,
        category: String = "general",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let logger = os.Logger(subsystem: subsystem, category: category)
        let filename = (file as NSString).lastPathComponent
        logger.error("[\(filename):\(line)] \(function) - \(message)")
        #endif
    }

    static func info(
        _ message: String,
        category: String = "general",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let logger = os.Logger(subsystem: subsystem, category: category)
        let filename = (file as NSString).lastPathComponent
        logger.info("[\(filename):\(line)] \(function) - \(message)")
        #endif
    }
}
