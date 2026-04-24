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
    @State private var isShowingDevicePicker = false
    private let statusColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]
    private let controlColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        statusCard
                        controlsCard
                        chartCard
                        logCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: PressureCSVDocument(csv: appModel.csvContent),
            contentType: .pressureCSV,
            defaultFilename: appModel.exportFilename
        ) { result in
            appModel.handleExportResult(result)
        }
        .sheet(isPresented: $isShowingDevicePicker) {
            devicePickerSheet
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Air Pressure")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }

            Label(appModel.connectionState.title, systemImage: statusIcon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            LazyVGrid(columns: statusColumns, spacing: 12) {
                metricTile(title: "Pressure (Pa)", value: appModel.currentPressureText)
                metricTile(title: "Pressure (kPa)", value: appModel.currentPressureKPaText)
                metricTile(title: "Sensor", value: appModel.sensorHealth.description)
                metricTile(title: "Battery", value: appModel.batteryStatusText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Controls",
                subtitle: "Scan, connect, and control the currently selected board."
            )

            HStack(spacing: 12) {
                actionButton(title: "Scan", systemImage: "dot.radiowaves.left.and.right", style: .primary) {
                    isShowingDevicePicker = true
                    appModel.startDeviceScan()
                }

                actionButton(
                    title: "Disconnect",
                    systemImage: "xmark.circle",
                    style: .secondary,
                    isDisabled: !appModel.canControlStreaming,
                    action: appModel.disconnect
                )
            }

            LazyVGrid(columns: controlColumns, spacing: 12) {
                actionButton(
                    title: "Start",
                    systemImage: "play.fill",
                    style: .primary,
                    isDisabled: !appModel.canControlStreaming,
                    action: appModel.sendStart
                )

                actionButton(
                    title: "Pause",
                    systemImage: "pause.fill",
                    style: .secondary,
                    isDisabled: !appModel.canControlStreaming,
                    action: appModel.sendPause
                )

                actionButton(
                    title: "Check",
                    systemImage: "stethoscope",
                    style: .secondary,
                    isDisabled: !appModel.canControlStreaming,
                    action: appModel.sendCheck
                )

                actionButton(
                    title: "Battery",
                    systemImage: "battery.75",
                    style: .secondary,
                    isDisabled: !appModel.canControlStreaming,
                    action: appModel.sendBatteryQuery
                )
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "Clear Data",
                    systemImage: "trash",
                    style: .danger,
                    isDisabled: !appModel.canClearCapturedData,
                    action: appModel.clearCapturedData
                )

                actionButton(
                    title: "Save CSV",
                    systemImage: "square.and.arrow.down",
                    style: .success,
                    isDisabled: !appModel.canExportSamples
                ) {
                    isExportingCSV = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Live Pressure",
                subtitle: appModel.chartSummaryText
            )

            if appModel.chartSamples.isEmpty {
                ContentUnavailableView(
                    "No Live Data Yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Scan and connect to a board, then tap Start to begin streaming.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 230)
            } else if let chartPressureDomain = appModel.chartPressureDomain {
                Chart(appModel.chartSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Pressure (Pa)", Double(sample.pressurePa))
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(Color(red: 0.14, green: 0.42, blue: 0.80))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 260)
                .chartYScale(domain: chartPressureDomain)
                .chartPlotStyle { plot in
                    plot
                        .background(Color.clear)
                        .clipped()
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
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
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisTick()
                        AxisValueLabel(format: .dateTime.minute().second())
                    }
                }
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Device Log",
                subtitle: "Raw BLE events and app-side diagnostics."
            )

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
                                    .foregroundStyle(.primary)
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
        .background(cardBackground)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        style: ActionButtonStyleKind,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))

                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(buttonForeground(style: style, isDisabled: isDisabled))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(buttonBackground(style: style, isDisabled: isDisabled))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(buttonBorder(style: style, isDisabled: isDisabled), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func discoveredDeviceRow(_ device: BLEDiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.connectionLabel)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(device.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    private var devicePickerSheet: some View {
        NavigationStack {
            Group {
                if appModel.discoveredDevices.isEmpty {
                    ContentUnavailableView(
                        appModel.isScanningForDevices ? "Scanning for Boards" : "No Boards Found",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Keep the board powered on and nearby. Devices that expose the BMP581 BLE service will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        Section("Nearby Boards") {
                            ForEach(appModel.discoveredDevices) { device in
                                Button {
                                    appModel.connect(to: device.id)
                                    isShowingDevicePicker = false
                                } label: {
                                    discoveredDeviceRow(device)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        isShowingDevicePicker = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rescan") {
                        appModel.startDeviceScan()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            appModel.startDeviceScan()
        }
        .onDisappear {
            appModel.stopDeviceScan()
        }
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

    private func buttonBackground(style: ActionButtonStyleKind, isDisabled: Bool) -> Color {
        if isDisabled {
            return Color(.systemGray5)
        }

        switch style {
        case .primary:
            return .black
        case .secondary:
            return Color(.secondarySystemBackground)
        case .danger:
            return Color(red: 0.90, green: 0.34, blue: 0.29)
        case .success:
            return Color(red: 0.17, green: 0.74, blue: 0.35)
        }
    }

    private func buttonForeground(style: ActionButtonStyleKind, isDisabled: Bool) -> Color {
        if isDisabled {
            return .secondary
        }

        switch style {
        case .primary:
            return .white
        case .secondary:
            return .primary
        case .danger, .success:
            return .white
        }
    }

    private func buttonBorder(style: ActionButtonStyleKind, isDisabled: Bool) -> Color {
        if isDisabled {
            return Color(.systemGray4)
        }

        switch style {
        case .primary:
            return .black
        case .secondary:
            return Color.black.opacity(0.08)
        case .danger:
            return Color(red: 0.90, green: 0.34, blue: 0.29)
        case .success:
            return Color(red: 0.17, green: 0.74, blue: 0.35)
        }
    }
}

private enum ActionButtonStyleKind {
    case primary
    case secondary
    case danger
    case success
}

#Preview {
    DashboardView()
        .environmentObject(AppModel())
}
