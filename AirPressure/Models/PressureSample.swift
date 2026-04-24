import Foundation

struct PressureSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let pressurePa: Int

    var pressureKPa: Double {
        Double(pressurePa) / 1000.0
    }
}

struct DeviceLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var renderedText: String {
        "[\(Self.timestampFormatter.string(from: timestamp))] \(message)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

enum SensorHealth: String {
    case normal = "Normal"
    case error = "Error"
    case unknown = "Unknown"

    var description: String {
        rawValue
    }
}
