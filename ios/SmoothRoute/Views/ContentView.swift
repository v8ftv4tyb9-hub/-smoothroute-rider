import SwiftUI

struct ContentView: View {
    @ObservedObject var recorder: RideRecorder

    @State private var profile: VehicleProfile = .myRoadGlide
    @State private var area = "us101_bay_area"
    @State private var tripLabel = ""
    @State private var tester = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    switch recorder.recordingState {
                    case .recoveryAvailable:
                        recoveryCard
                    case .recording:
                        liveCard
                    case .finished:
                        finishedCard
                    case .idle:
                        setupCard
                    }

                    safetyNote
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .alert(
                "SmoothRoute",
                isPresented: Binding(
                    get: { recorder.errorMessage != nil },
                    set: { if !$0 { recorder.errorMessage = nil } }
                )
            ) {
                Button("OK") { recorder.errorMessage = nil }
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SmoothRoute")
                .font(.largeTitle.bold())
            Text("Native road-surface recorder · 0.1.0")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(recorder.permissionSummary, systemImage: "location.fill")
                    .font(.headline)

                Text("Always Location keeps recording active with the screen locked or a navigation app visible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Enable Background Location") {
                    recorder.requestPermissions()
                }
                .buttonStyle(.borderedProminent)

                Picker("Vehicle", selection: $profile) {
                    ForEach(VehicleProfile.allCases) { vehicle in
                        Text(vehicle.displayName).tag(vehicle)
                    }
                }

                Picker("Travel area", selection: $area) {
                    Text("US-101 Bay Area").tag("us101_bay_area")
                    Text("San Jose").tag("san_jose")
                    Text("South San Francisco").tag("south_san_francisco")
                    Text("San Francisco").tag("san_francisco")
                    Text("Peninsula / US-101").tag("peninsula")
                    Text("Other Bay Area").tag("other_bay_area")
                }

                TextField("Trip label (optional)", text: $tripLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Tester nickname (optional)", text: $tester)
                    .textFieldStyle(.roundedBorder)

                Button {
                    recorder.start(
                        profile: profile,
                        area: area,
                        tripLabel: tripLabel,
                        tester: tester
                    )
                } label: {
                    Label("Start Road Test", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!recorder.canStart)
            }
        } label: {
            Label("Ride setup", systemImage: "motorcycle")
        }
    }

    private var recoveryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("An unfinished ride was recovered from this iPhone.")
                Text(recorder.permissionSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    recorder.resumeSavedRide()
                } label: {
                    Label("Resume Saved Ride", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Discard Saved Ride", role: .destructive) {
                    recorder.discardSavedRide()
                }
                .frame(maxWidth: .infinity)
            }
        } label: {
            Label("Saved ride found", systemImage: "externaldrive.fill.badge.checkmark")
        }
    }

    private var liveCard: some View {
        GroupBox {
            VStack(spacing: 14) {
                HStack {
                    Label("Recording", systemImage: "record.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(duration(recorder.elapsedSeconds))
                        .monospacedDigit()
                }
                .font(.headline)

                HStack(spacing: 10) {
                    stat("GPS", "\(recorder.gpsCount)")
                    stat("Motion", "\(recorder.motionCount)")
                    stat("Samples", "\(recorder.sampleCount)")
                }

                HStack(spacing: 10) {
                    stat(
                        "Accuracy",
                        recorder.latestAccuracy.map { String(format: "%.0f m", $0) } ?? "—"
                    )
                    stat(
                        "Speed",
                        recorder.latestSpeedMph.map { String(format: "%.0f mph", $0) } ?? "—"
                    )
                }

                Text(recorder.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    recorder.stop()
                } label: {
                    Label("End Road Test", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        } label: {
            Label("Live ride", systemImage: "waveform.path.ecg")
        }
    }

    private var finishedCard: some View {
        GroupBox {
            VStack(spacing: 14) {
                Label("Ride saved", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)

                if let exportURL = recorder.exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share / Save JSON", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var safetyNote: some View {
        Text("Start and stop only while parked. Secure the phone before moving and never interact with SmoothRoute while riding.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.vertical)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
