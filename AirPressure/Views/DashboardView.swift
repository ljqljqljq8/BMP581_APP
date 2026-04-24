import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel

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

            HStack(spacing: 12) {
                Button(action: appModel.connectOrScan) {
                    Label("Scan & Connect", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: appModel.disconnect) {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button(action: appModel.sendStart) {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canControlStreaming)

                Button(action: appModel.sendPause) {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canControlStreaming)

                Button(action: appModel.sendCheck) {
                    Label("Check", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canControlStreaming)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Pressure")
                .font(.headline)

            if appModel.chartSamples.isEmpty {
                ContentUnavailableView(
                    "No Live Data Yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Connect to JingQiBMP, then tap Start to begin streaming.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                Chart(appModel.chartSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Pressure (kPa)", sample.pressureKPa)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                }
                .frame(height: 240)
                .chartYAxisLabel("kPa")
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

            if appModel.recentMessages.isEmpty {
                Text("Logs from the Arduino will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appModel.recentMessages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.footnote.monospaced())
                        .padding(.vertical, 2)
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
