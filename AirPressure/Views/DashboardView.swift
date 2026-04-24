import Charts
import SwiftUI
import UniformTypeIdentifiers

struct PressureCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.pressureCSV]

    let csv: String

    init(csv: String) {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let csv = String(data: data, encoding: .utf8) {
            self.csv = csv
        } else {
            self.csv = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}

extension UTType {
    static let pressureCSV = UTType(filenameExtension: "csv") ?? .plainText
}

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isExportingCSV = false
    private let controlColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    controlsCard
                    chartCard
                    logCard
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Air Pressure")
        }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: PressureCSVDocument(csv: appModel.csvContent),
            contentType: .pressureCSV,
            defaultFilename: appModel.exportFilename
        ) { result in
            appModel.handleExportResult(result)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appModel.connectionState.title, systemImage: statusIcon)
                .font(.headline)

            HStack(spacing: 16) {
                metricView(title: "Pressure", value: appModel.currentPressureText)
                metricView(title: "Pressure", value: appModel.currentPressureKPaText)
                metricView(title: "Sensor", value: appModel.sensorHealth.description)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Controls")
                .font(.headline)

            LazyVGrid(columns: controlColumns, spacing: 12) {
                Button(action: appModel.connectOrScan) {
                    controlButtonLabel(title: "Connect", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)

                Button(action: appModel.disconnect) {
                    controlButtonLabel(title: "Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                
                Button(action: appModel.sendStart) {
                    controlButtonLabel(title: "Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canControlStreaming)

                Button(action: appModel.sendPause) {
                    controlButtonLabel(title: "Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canControlStreaming)

                Button(action: appModel.sendCheck) {
                    controlButtonLabel(title: "Check", systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canControlStreaming)

                Button(action: appModel.clearCapturedData) {
                    controlButtonLabel(title: "Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!appModel.canClearCapturedData)
            }

            Button {
                isExportingCSV = true
            } label: {
                controlButtonLabel(title: "Save CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!appModel.canExportSamples)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Pressure")
                .font(.headline)

            Text(appModel.chartSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.chartSamples.isEmpty {
                ContentUnavailableView(
                    "No Live Data Yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Connect to JingQiBMP, then tap Start to begin streaming.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else if let chartPressureDomain = appModel.chartPressureDomain {
                Chart(appModel.chartSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Pressure (Pa)", Double(sample.pressurePa))
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.blue)
                }
                .frame(height: 240)
                .chartYScale(domain: chartPressureDomain)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let pressure = value.as(Double.self) {
                                Text(String(format: "%.0f", pressure))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxisLabel("Pa")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Device Log")
                .font(.headline)

            if appModel.logEntries.isEmpty {
                Text("Logs from the Arduino will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(appModel.logEntries) { entry in
                                Text(entry.renderedText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                                    .id(entry.id)
                            }
                        }
                    }
                    .frame(height: 220)
                    .onChange(of: appModel.logEntries.last?.id, initial: true) { _, lastID in
                        guard let lastID else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controlButtonLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var statusIcon: String {
        switch appModel.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .scanning:
            return "dot.radiowaves.left.and.right"
        case .unauthorized:
            return "lock.slash"
        case .bluetoothUnavailable:
            return "bolt.slash.fill"
        case .idle:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppModel())
}
