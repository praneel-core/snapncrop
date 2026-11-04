import os

/// Everything is logged locally. View live with:
///   log stream --predicate 'subsystem == "com.praneelcore.snapncrop"' --level debug
enum Log {
    static let app = Logger(subsystem: "com.praneelcore.snapncrop", category: "app")
    static let capture = Logger(subsystem: "com.praneelcore.snapncrop", category: "capture")
    static let gesture = Logger(subsystem: "com.praneelcore.snapncrop", category: "gesture")
}
