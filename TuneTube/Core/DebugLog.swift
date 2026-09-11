import Foundation
import os.log

/// App-wide debug logging strategy using Apple's unified `os.Logger`.
///
/// Filter messages in Console.app or Xcode by subsystem `com.tunetube`.
/// Messages logged at `.debug` level do not write to disk or impact performance in production.
public enum DebugLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tunetube"

    public static let general = Logger(subsystem: subsystem, category: "General")
    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let player = Logger(subsystem: subsystem, category: "Player")
    public static let auth = Logger(subsystem: subsystem, category: "Auth")
    public static let store = Logger(subsystem: subsystem, category: "Store")
}
