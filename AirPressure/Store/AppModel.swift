import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var connectionState: BLEConnectionState = .idle
    @Published private(set) var samples: [PressureSample] = []
    @Published private(set) var sensorHealth: SensorHealth = .unknown
    @Published private(set) var latestPressurePa: Int?
    @Published private(set) var recentMessages: [String] = []

    let bleManager = BLEManager()

    private var parser = PressurePacketParser()

    private let displayedSampleLimit = 600
    private let perBatchSampleInterval: TimeInterval = 0.01

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

    var chartSamples: [PressureSample] {
        samples.suffix(300)
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

    private func handleIncomingPayload(_ data: Data) {
        for event in parser.consume(data) {
            switch event {
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
        if samples.count > displayedSampleLimit {
            samples.removeFirst(samples.count - displayedSampleLimit)
        }

        latestPressurePa = values.last
        sensorHealth = health
    }

    private func appendMessage(_ message: String) {
        recentMessages.insert(message, at: 0)
        if recentMessages.count > 12 {
            recentMessages.removeLast(recentMessages.count - 12)
        }
    }
}
