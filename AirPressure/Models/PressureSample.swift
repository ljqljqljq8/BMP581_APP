import Foundation

struct PressureSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let pressurePa: Int

    var pressureKPa: Double {
        Double(pressurePa) / 1000.0
    }
}

enum SensorHealth: String {
    case normal = "Normal"
    case error = "Error"
    case unknown = "Unknown"

    var description: String {
        rawValue
    }
}
