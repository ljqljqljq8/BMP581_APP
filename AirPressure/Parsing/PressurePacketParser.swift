import Foundation

enum DeviceEvent {
    case batch(values: [Int], health: SensorHealth)
    case message(String)
}

struct PressurePacketParser {
    private(set) var buffer = ""

    mutating func consume(_ data: Data) -> [DeviceEvent] {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return [.message("Received non-UTF8 BLE payload (\(data.count) bytes).")]
        }

        buffer.append(chunk)

        var events: [DeviceEvent] = []

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<newlineRange.upperBound)

            guard !line.isEmpty else { continue }
            events.append(parseLine(line))
        }

        return events
    }

    private func parseLine(_ line: String) -> DeviceEvent {
        guard line.hasPrefix("B:") else {
            return .message(line)
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard let batchPart = parts.first else {
            return .message(line)
        }

        let valuesSection = batchPart.dropFirst(2)
        let values = valuesSection
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        let health: SensorHealth
        if let statusPart = parts.first(where: { $0.hasPrefix("S:") }) {
            let statusValue = statusPart.dropFirst(2).trimmingCharacters(in: .whitespaces)
            health = statusValue == "1" ? .normal : .error
        } else {
            health = .unknown
        }

        guard !values.isEmpty else {
            return .message(line)
        }

        return .batch(values: values, health: health)
    }
}
