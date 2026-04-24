import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var connectionState: BLEConnectionState = .idle
    @Published private(set) var samples: [PressureSample] = []
    @Published private(set) var sensorHealth: SensorHealth = .unknown
    @Published private(set) var latestPressurePa: Int?
    @Published private(set) var logEntries: [DeviceLogEntry] = []

    let bleManager = BLEManager()

    private var parser = PressurePacketParser()
    private var rawLogBuffer = ""

    private let displayedChartSampleLimit = 240
    private let logEntryLimit = 250
    private let perBatchSampleInterval: TimeInterval = 0.05

    init() {
        bleManager.onStateChange = { [weak self] state in
            self?.connectionState = state
        }

        bleManager.onPayload = { [weak self] data in
            self?.handleIncomingPayload(data)
        }

        bleManager.onLog = { [weak self] message in
            self?.appendMessage(message)
        }

        bleManager.start()
    }

    var currentPressureText: String {
        guard let latestPressurePa else { return "--" }
        return "\(latestPressurePa) Pa"
    }

    var currentPressureKPaText: String {
        guard let latestPressurePa else { return "--" }
        return String(format: "%.3f kPa", Double(latestPressurePa) / 1000.0)
    }

    var canControlStreaming: Bool {
        if case .connected = connectionState {
            return true
        }

        return false
    }

    var canExportSamples: Bool {
        !samples.isEmpty
    }

    var chartSamples: [PressureSample] {
        Array(samples.suffix(displayedChartSampleLimit))
    }

    var chartPressureDomain: ClosedRange<Double>? {
        let visibleSamples = chartSamples
        guard
            let minPressure = visibleSamples.map(\.pressurePa).min(),
            let maxPressure = visibleSamples.map(\.pressurePa).max()
        else {
            return nil
        }

        let span = Double(maxPressure - minPressure)
        let padding = max(span * 0.2, 5.0)
        return Double(minPressure) - padding ... Double(maxPressure) + padding
    }

    var chartSummaryText: String {
        let visibleSamples = chartSamples

        guard
            let minPressure = visibleSamples.map(\.pressurePa).min(),
            let maxPressure = visibleSamples.map(\.pressurePa).max()
        else {
            return "Waiting for live samples."
        }

        let span = maxPressure - minPressure
        return "\(visibleSamples.count) points shown • range \(minPressure)-\(maxPressure) Pa • span \(span) Pa"
    }

    var exportFilename: String {
        "air-pressure-\(Self.exportDateFormatter.string(from: Date()))"
    }

    var csvContent: String {
        let rows = samples.map {
            "\(Self.csvDateFormatter.string(from: $0.timestamp)),\($0.pressurePa)"
        }

        return (["time,pressure_pa"] + rows).joined(separator: "\n")
    }

    func connectOrScan() {
        bleManager.connectOrScan()
    }

    func disconnect() {
        bleManager.disconnect()
    }

    func sendStart() {
        bleManager.sendCommand("S")
    }

    func sendPause() {
        bleManager.sendCommand("P")
    }

    func sendCheck() {
        bleManager.sendCommand("C")
    }

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            appendMessage("Saved CSV: \(url.lastPathComponent)")
        case .failure(let error):
            appendMessage("CSV export failed: \(error.localizedDescription)")
        }
    }

    private func handleIncomingPayload(_ data: Data) {
        logRawPayload(data)

        for event in parser.consume(data) {
            switch event {
            case .sensorHealth(let health, let message):
                sensorHealth = health
                appendMessage(message)
            case .message(let message):
                appendMessage(message)
            case .batch(let values, let health):
                ingestBatch(values, health: health)
            }
        }
    }

    private func ingestBatch(_ values: [Int], health: SensorHealth) {
        let now = Date()
        let totalSpan = perBatchSampleInterval * Double(max(values.count - 1, 0))

        let newSamples: [PressureSample] = values.enumerated().map { index, pressure in
            let offset = perBatchSampleInterval * Double(index)
            let timestamp = now.addingTimeInterval(offset - totalSpan)
            return PressureSample(timestamp: timestamp, pressurePa: pressure)
        }

        samples.append(contentsOf: newSamples)
        latestPressurePa = values.last

        if health != .unknown {
            sensorHealth = health
        } else if sensorHealth != .error {
            sensorHealth = .normal
        }
    }

    private func logRawPayload(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            appendMessage("Rx: <non-UTF8 payload \(data.count) bytes>")
            return
        }

        rawLogBuffer.append(chunk)

        while let newlineRange = rawLogBuffer.range(of: "\n") {
            let line = String(rawLogBuffer[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            rawLogBuffer.removeSubrange(..<newlineRange.upperBound)

            guard !line.isEmpty else { continue }
            appendMessage("Rx: \(line)")
        }
    }

    private func appendMessage(_ message: String) {
        logEntries.append(DeviceLogEntry(timestamp: Date(), message: message))
        if logEntries.count > logEntryLimit {
            logEntries.removeFirst(logEntries.count - logEntryLimit)
        }
    }

    private static let csvDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
