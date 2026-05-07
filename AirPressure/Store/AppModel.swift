import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var connectionState: BLEConnectionState = .idle
    @Published private(set) var discoveredDevices: [BLEDiscoveredDevice] = []
    @Published private(set) var samples: [PressureSample] = []
    @Published private(set) var temperatureSamples: [TemperatureSample] = []
    @Published private(set) var sensorHealth: SensorHealth = .unknown
    @Published private(set) var latestPressurePa: Int?
    @Published private(set) var batteryPercentage: Double?
    @Published private(set) var batteryVoltage: Double?
    @Published private(set) var logEntries: [DeviceLogEntry] = []

    let bleManager = BLEManager()

    private var parser = PressurePacketParser()
    private var rawLogBuffer = ""

    private let displayedChartSampleLimit = 240
    private let logEntryLimit = 250
    private let perBatchSampleInterval: TimeInterval = 0.05
    private let displayedChartTemperatureSampleLimit = 240
    private let validTemperatureRange = -40.0 ... 85.0
    private let maxAcceptedTemperatureJumpC = 5.0
    private let maxAcceptedTemperatureJumpInterval: TimeInterval = 5.0

    init() {
        bleManager.onStateChange = { [weak self] state in
            self?.connectionState = state
        }

        bleManager.onDiscoveredDevicesChange = { [weak self] devices in
            self?.discoveredDevices = devices
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

    var batteryStatusText: String {
        guard let batteryPercentage else { return "--" }

        if let batteryVoltage {
            return String(format: "%.1f%% / %.3f V", batteryPercentage, batteryVoltage)
        }

        return String(format: "%.1f%%", batteryPercentage)
    }

    var canControlStreaming: Bool {
        if case .connected = connectionState {
            return true
        }

        return false
    }

    var isScanningForDevices: Bool {
        if case .scanning = connectionState {
            return true
        }

        return false
    }

    var canExportSamples: Bool {
        !samples.isEmpty
    }

    var canClearCapturedData: Bool {
        !samples.isEmpty || !temperatureSamples.isEmpty || !logEntries.isEmpty || latestPressurePa != nil
    }

    var chartSamples: [PressureSample] {
        Array(samples.suffix(displayedChartSampleLimit))
    }

    var plottedChartSamples: [PressureSample] {
        chartSamples.sorted { $0.timestamp < $1.timestamp }
    }

    var chartTemperatureSamples: [TemperatureSample] {
        let visibleTemperatureSamples = Array(temperatureSamples.suffix(displayedChartTemperatureSampleLimit))

        guard
            let startDate = chartPressureTimeDomain?.lowerBound,
            let endDate = chartPressureTimeDomain?.upperBound
        else {
            return visibleTemperatureSamples
        }

        return visibleTemperatureSamples.filter { sample in
            sample.timestamp >= startDate && sample.timestamp <= endDate
        }
    }

    var plottedChartTemperatureSamples: [TemperatureSample] {
        chartTemperatureSamples.sorted { $0.timestamp < $1.timestamp }
    }

    var chartTimeDomain: ClosedRange<Date>? {
        if let chartPressureTimeDomain {
            return chartPressureTimeDomain
        }

        if let first = plottedChartTemperatureSamples.first?.timestamp, let last = plottedChartTemperatureSamples.last?.timestamp {
            return first ... last
        }

        return nil
    }

    private var chartPressureTimeDomain: ClosedRange<Date>? {
        guard let first = plottedChartSamples.first?.timestamp, let last = plottedChartSamples.last?.timestamp else {
            return nil
        }

        return first ... last
    }

    var chartPressureDomain: ClosedRange<Double>? {
        let visibleSamples = plottedChartSamples
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

    var chartTemperatureDomain: ClosedRange<Double>? {
        let visibleSamples = plottedChartTemperatureSamples
        guard
            let minTemperature = visibleSamples.map(\.temperatureC).min(),
            let maxTemperature = visibleSamples.map(\.temperatureC).max()
        else {
            return nil
        }

        let span = maxTemperature - minTemperature
        let padding = max(span * 0.2, 0.2)
        return (minTemperature - padding) ... (maxTemperature + padding)
    }

    var chartTemperatureAxisTicks: [(plotValue: Double, temperatureC: Double)] {
        guard
            let temperatureDomain = chartTemperatureDomain,
            let pressureDomain = chartPressureDomain
        else {
            return []
        }

        let tickCount = 4
        let temperatureSpan = temperatureDomain.upperBound - temperatureDomain.lowerBound

        return (0..<tickCount).map { index in
            let ratio = tickCount == 1 ? 0.0 : Double(index) / Double(tickCount - 1)
            let temperature = temperatureDomain.lowerBound + (temperatureSpan * ratio)
            return (plotValue: mapTemperatureToPressureAxis(temperature, temperatureDomain: temperatureDomain, pressureDomain: pressureDomain), temperatureC: temperature)
        }
    }

    var chartSummaryText: String {
        let visibleSamples = plottedChartSamples

        guard
            let minPressure = visibleSamples.map(\.pressurePa).min(),
            let maxPressure = visibleSamples.map(\.pressurePa).max()
        else {
            return "Waiting for live samples."
        }

        let span = maxPressure - minPressure
        if
            let minTemperature = plottedChartTemperatureSamples.map(\.temperatureC).min(),
            let maxTemperature = plottedChartTemperatureSamples.map(\.temperatureC).max()
        {
            return "\(visibleSamples.count) pts • \(minPressure)-\(maxPressure) Pa • span \(span) Pa • \(String(format: "%.1f", minTemperature))-\(String(format: "%.1f", maxTemperature)) °C"
        }

        return "\(visibleSamples.count) pts • \(minPressure)-\(maxPressure) Pa • span \(span) Pa"
    }

    var exportFilename: String {
        "air-pressure-\(Self.exportDateFormatter.string(from: Date()))"
    }

    var csvContent: String {
        let rows = samples.enumerated().map { index, sample in
            let deltaMS: String

            if index == 0 {
                deltaMS = ""
            } else {
                let previousSample = samples[index - 1]
                let delta = sample.timestamp.timeIntervalSince(previousSample.timestamp) * 1000.0
                deltaMS = String(Int(delta.rounded()))
            }

            return "\(Self.csvDateFormatter.string(from: sample.timestamp)),\(sample.pressurePa),\(deltaMS)"
        }

        return (["time,pressure_pa,delta_from_previous_ms"] + rows).joined(separator: "\n")
    }

    func startDeviceScan() {
        bleManager.startScan()
    }

    func stopDeviceScan() {
        bleManager.stopScan()
    }

    func connect(to deviceID: UUID) {
        bleManager.connect(to: deviceID)
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

    func sendBatteryQuery() {
        bleManager.sendCommand("BAT")
    }

    func clearCapturedData() {
        samples.removeAll(keepingCapacity: true)
        temperatureSamples.removeAll(keepingCapacity: true)
        logEntries.removeAll(keepingCapacity: true)
        latestPressurePa = nil
        sensorHealth = .unknown
        batteryPercentage = nil
        batteryVoltage = nil
        rawLogBuffer = ""
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
            case .temperature(let temperatureC):
                ingestTemperature(temperatureC)
            case .battery(let levelPercent, let voltage):
                batteryPercentage = levelPercent
                batteryVoltage = voltage
            case .batteryError(let message):
                batteryPercentage = nil
                batteryVoltage = nil
                appendMessage(message)
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

    private func ingestTemperature(_ temperatureC: Double) {
        guard validTemperatureRange.contains(temperatureC) else {
            appendMessage("Ignored invalid temperature sample: \(String(format: "%.3f", temperatureC)) °C")
            return
        }

        if let lastSample = temperatureSamples.last {
            let deltaT = Date().timeIntervalSince(lastSample.timestamp)
            let deltaC = abs(temperatureC - lastSample.temperatureC)
            if deltaT <= maxAcceptedTemperatureJumpInterval, deltaC > maxAcceptedTemperatureJumpC {
                appendMessage(
                    "Ignored temperature outlier: \(String(format: "%.3f", temperatureC)) °C after \(String(format: "%.3f", lastSample.temperatureC)) °C"
                )
                return
            }
        }

        temperatureSamples.append(TemperatureSample(timestamp: Date(), temperatureC: temperatureC))

        let overflow = temperatureSamples.count - displayedChartTemperatureSampleLimit
        if overflow > 0 {
            temperatureSamples.removeFirst(overflow)
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

    func chartPlotValue(for temperatureC: Double) -> Double? {
        guard
            let temperatureDomain = chartTemperatureDomain,
            let pressureDomain = chartPressureDomain
        else {
            return nil
        }

        return mapTemperatureToPressureAxis(
            temperatureC,
            temperatureDomain: temperatureDomain,
            pressureDomain: pressureDomain
        )
    }

    func chartTemperatureLabel(for plotValue: Double) -> String? {
        let matchingTick = chartTemperatureAxisTicks.min { lhs, rhs in
            abs(lhs.plotValue - plotValue) < abs(rhs.plotValue - plotValue)
        }

        guard let matchingTick, abs(matchingTick.plotValue - plotValue) < 0.001 else {
            return nil
        }

        return String(format: "%.1f", matchingTick.temperatureC)
    }

    private func mapTemperatureToPressureAxis(
        _ temperatureC: Double,
        temperatureDomain: ClosedRange<Double>,
        pressureDomain: ClosedRange<Double>
    ) -> Double {
        let temperatureSpan = temperatureDomain.upperBound - temperatureDomain.lowerBound
        let pressureSpan = pressureDomain.upperBound - pressureDomain.lowerBound

        if temperatureSpan == 0 {
            return (pressureDomain.lowerBound + pressureDomain.upperBound) * 0.5
        }

        let ratio = (temperatureC - temperatureDomain.lowerBound) / temperatureSpan
        return pressureDomain.lowerBound + (pressureSpan * ratio)
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
