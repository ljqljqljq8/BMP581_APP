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
    private let pressureLineColor = Color(red: 0.14, green: 0.42, blue: 0.80)
    private let temperatureLineColor = Color(red: 0.88, green: 0.47, blue: 0.15)
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        chartLegendLabel(color: pressureLineColor, title: "Pressure")

                        if !appModel.plottedChartTemperatureSamples.isEmpty {
                            chartLegendLabel(color: temperatureLineColor, title: "Temperature")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    PressureTemperaturePlot(
                        pressureSamples: appModel.plottedChartSamples,
                        temperatureSamples: appModel.plottedChartTemperatureSamples,
                        pressureDomain: chartPressureDomain,
                        temperatureDomain: appModel.chartTemperatureDomain,
                        timeDomain: appModel.chartTimeDomain,
                        pressureColor: pressureLineColor,
                        temperatureColor: temperatureLineColor
                    )
                    .frame(height: 260)
                    .padding(.top, 4)
                }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.connectionLabel)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(device.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Connect")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
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

    private func chartLegendLabel(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 16, height: 4)

            Text(title)
        }
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
                                        .contentShape(Rectangle())
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
            .safeAreaInset(edge: .top) {
                Text("Tap a board below to connect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .background(Color(.systemBackground))
            }
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

private struct PressureTemperaturePlot: View {
    let pressureSamples: [PressureSample]
    let temperatureSamples: [TemperatureSample]
    let pressureDomain: ClosedRange<Double>
    let temperatureDomain: ClosedRange<Double>?
    let timeDomain: ClosedRange<Date>?
    let pressureColor: Color
    let temperatureColor: Color

    private let leadingAxisWidth: CGFloat = 42
    private let trailingAxisWidth: CGFloat = 54
    private let bottomAxisHeight: CGFloat = 28
    private let topPadding: CGFloat = 10
    private let horizontalTickCount = 4
    private let verticalTickCount = 3

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: leadingAxisWidth,
                y: topPadding,
                width: max(geometry.size.width - leadingAxisWidth - trailingAxisWidth, 1),
                height: max(geometry.size.height - topPadding - bottomAxisHeight, 1)
            )

            ZStack {
                horizontalGrid(plotRect: plotRect)
                verticalGrid(plotRect: plotRect)
                pressurePath(plotRect: plotRect)
                    .stroke(pressureColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                if !temperatureSamples.isEmpty {
                    temperaturePath(plotRect: plotRect)
                        .stroke(
                            temperatureColor,
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round, dash: [8, 6])
                        )

                    temperatureMarkers(plotRect: plotRect)
                }

                leftAxisLabels(plotRect: plotRect)
                rightAxisLabels(plotRect: plotRect)
                bottomAxisLabels(plotRect: plotRect)
            }
        }
    }

    private func horizontalGrid(plotRect: CGRect) -> some View {
        Canvas { context, _ in
            guard horizontalTickCount > 1 else { return }

            for index in 0..<horizontalTickCount {
                let ratio = Double(index) / Double(horizontalTickCount - 1)
                let y = plotRect.maxY - (plotRect.height * ratio)
                var path = Path()
                path.move(to: CGPoint(x: plotRect.minX, y: y))
                path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                context.stroke(path, with: .color(Color(.separator).opacity(0.55)), lineWidth: 1)
            }
        }
    }

    private func verticalGrid(plotRect: CGRect) -> some View {
        Canvas { context, _ in
            guard verticalTickCount > 1 else { return }

            for index in 1..<(verticalTickCount - 1) {
                let ratio = Double(index) / Double(verticalTickCount - 1)
                let x = plotRect.minX + (plotRect.width * ratio)
                var path = Path()
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                context.stroke(
                    path,
                    with: .color(Color(.separator).opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
            }
        }
    }

    private func pressurePath(plotRect: CGRect) -> Path {
        guard
            let timeDomain,
            pressureSamples.count >= 1
        else {
            return Path()
        }

        var path = Path()

        for (index, sample) in pressureSamples.enumerated() {
            let point = CGPoint(
                x: mappedX(for: sample.timestamp, in: timeDomain, plotRect: plotRect),
                y: mappedY(for: Double(sample.pressurePa), in: pressureDomain, plotRect: plotRect)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                let previousSample = pressureSamples[index - 1]
                let previousPoint = CGPoint(
                    x: mappedX(for: previousSample.timestamp, in: timeDomain, plotRect: plotRect),
                    y: mappedY(for: Double(previousSample.pressurePa), in: pressureDomain, plotRect: plotRect)
                )
                path.addLine(to: CGPoint(x: point.x, y: previousPoint.y))
                path.addLine(to: point)
            }
        }

        return path
    }

    private func temperaturePath(plotRect: CGRect) -> Path {
        guard
            let timeDomain,
            let temperatureDomain,
            temperatureSamples.count >= 1
        else {
            return Path()
        }

        var path = Path()

        for (index, sample) in temperatureSamples.enumerated() {
            let point = CGPoint(
                x: mappedX(for: sample.timestamp, in: timeDomain, plotRect: plotRect),
                y: mappedY(for: sample.temperatureC, in: temperatureDomain, plotRect: plotRect)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func leftAxisLabels(plotRect: CGRect) -> some View {
        ZStack {
            if let temperatureDomain {
                ForEach(0..<horizontalTickCount, id: \.self) { index in
                    let ratio = horizontalTickCount == 1 ? 0.0 : Double(index) / Double(horizontalTickCount - 1)
                    let value = temperatureDomain.lowerBound + ((temperatureDomain.upperBound - temperatureDomain.lowerBound) * (1.0 - ratio))
                    let y = plotRect.minY + (plotRect.height * ratio)

                    Text(String(format: "%.1f", value))
                        .font(.caption)
                        .foregroundStyle(temperatureColor.opacity(0.9))
                        .position(x: leadingAxisWidth * 0.5, y: y)
                }
            }
        }
    }

    private func rightAxisLabels(plotRect: CGRect) -> some View {
        ZStack {
            ForEach(0..<horizontalTickCount, id: \.self) { index in
                let ratio = horizontalTickCount == 1 ? 0.0 : Double(index) / Double(horizontalTickCount - 1)
                let value = pressureDomain.lowerBound + ((pressureDomain.upperBound - pressureDomain.lowerBound) * (1.0 - ratio))
                let y = plotRect.minY + (plotRect.height * ratio)

                Text(String(format: "%.0f", value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .position(x: plotRect.maxX + (trailingAxisWidth * 0.5), y: y)
            }
        }
    }

    private func bottomAxisLabels(plotRect: CGRect) -> some View {
        ZStack {
            if let timeDomain {
                ForEach(0..<verticalTickCount, id: \.self) { index in
                    let ratio = verticalTickCount == 1 ? 0.0 : Double(index) / Double(verticalTickCount - 1)
                    let timestamp = timeDomain.lowerBound.addingTimeInterval(timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound) * ratio)
                    let x = plotRect.minX + (plotRect.width * ratio)

                    Text(timestamp.formatted(.dateTime.minute().second()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: x, y: plotRect.maxY + (bottomAxisHeight * 0.55))
                }
            }
        }
    }

    private func temperatureMarkers(plotRect: CGRect) -> some View {
        ZStack {
            if let timeDomain, let temperatureDomain {
                ForEach(temperatureSamples) { sample in
                    Circle()
                        .fill(temperatureColor)
                        .frame(width: 5, height: 5)
                        .position(
                            x: mappedX(for: sample.timestamp, in: timeDomain, plotRect: plotRect),
                            y: mappedY(for: sample.temperatureC, in: temperatureDomain, plotRect: plotRect)
                        )
                }
            }
        }
    }

    private func mappedX(for timestamp: Date, in domain: ClosedRange<Date>, plotRect: CGRect) -> CGFloat {
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard total > 0 else { return plotRect.midX }
        let ratio = timestamp.timeIntervalSince(domain.lowerBound) / total
        return plotRect.minX + (plotRect.width * CGFloat(ratio))
    }

    private func mappedY(for value: Double, in domain: ClosedRange<Double>, plotRect: CGRect) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return plotRect.midY }
        let ratio = (value - domain.lowerBound) / span
        return plotRect.maxY - (plotRect.height * CGFloat(ratio))
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppModel())
}
