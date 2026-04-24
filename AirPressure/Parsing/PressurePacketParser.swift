import Foundation

enum DeviceEvent {
    case batch(values: [Int], health: SensorHealth)
    case sensorHealth(SensorHealth, message: String)
    case message(String)
}

struct PressurePacketParser {
    private(set) var buffer = ""
    private let validPressureRange = 30_000...125_000

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
            events.append(contentsOf: parseLine(line))
        }

        return events
    }

    private func parseLine(_ line: String) -> [DeviceEvent] {
        if line == "BMP:OK" {
            return [.sensorHealth(.normal, message: "Sensor check passed (BMP581 detected).")]
        }

        if line == "BMP:ERR" {
            return [.sensorHealth(.error, message: "Sensor check failed (BMP581 not detected).")]
        }

        guard line.hasPrefix("B:") else {
            return [.message(line)]
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard let batchPart = parts.first else {
            return [.message("Ignored malformed pressure packet: \(line)")]
        }

        let health: SensorHealth
        if let statusPart = parts.first(where: { $0.hasPrefix("S:") }) {
            let statusValue = statusPart.dropFirst(2).trimmingCharacters(in: .whitespaces)
            health = statusValue == "1" ? .normal : .error
        } else {
            health = .unknown
        }

        guard let values = parseValues(String(batchPart.dropFirst(2))) else {
            return [.message("Ignored malformed pressure packet: \(line)")]
        }

        return [.batch(values: values, health: health)]
    }

    private func parseValues(_ payload: String) -> [Int]? {
        if payload.contains(";") {
            return parseDeltaEncodedValues(payload)
        }

        let values = payload
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        return validate(values)
    }

    private func parseDeltaEncodedValues(_ payload: String) -> [Int]? {
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard
            let baselineText = parts.first,
            let baseline = Int(baselineText.trimmingCharacters(in: .whitespaces))
        else {
            return nil
        }

        var values = [baseline]

        if parts.count == 2 {
            let deltaValues = parts[1]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            guard deltaValues.count == parts[1].split(separator: ",").count else {
                return nil
            }

            values.append(contentsOf: deltaValues.map { baseline + $0 })
        }

        return validate(values)
    }

    private func validate(_ values: [Int]) -> [Int]? {
        guard !values.isEmpty else {
            return nil
        }

        guard values.allSatisfy({ validPressureRange.contains($0) }) else {
            return nil
        }

        return values
    }
}
