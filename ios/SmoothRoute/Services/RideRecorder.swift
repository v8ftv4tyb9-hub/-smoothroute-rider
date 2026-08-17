import CoreLocation
import CoreMotion
import Foundation
import SwiftUI

@MainActor
final class RideRecorder: NSObject, ObservableObject {
    enum RecordingState: Equatable {
        case idle
        case recording
        case recoveryAvailable
        case finished
    }

    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var gpsCount = 0
    @Published private(set) var motionCount = 0
    @Published private(set) var sampleCount = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var latestAccuracy: Double?
    @Published private(set) var latestSpeedMph: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var exportURL: URL?
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "SmoothRoute.Motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let store: RideStore

    private var activeState: ActiveRideState?
    private var checkpointTimer: Timer?
    private var lastCheckpointMs: Int64 = 0
    private var startedDate: Date?

    override init() {
        store = RideStore()
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        do {
            if let recovered = try store.loadActive(), recovered.ride.ended_at == nil {
                activeState = recovered
                recordingState = .recoveryAvailable
                gpsCount = recovered.gpsCount
                motionCount = recovered.motionCount
                startedDate = ISO8601DateFormatter.smoothRoute.date(from: recovered.ride.started_at)
                statusMessage = "Saved ride found"
            }
        } catch {
            errorMessage = "Recovery check failed: \(error.localizedDescription)"
        }
    }

    var canStart: Bool {
        authorizationStatus == .authorizedAlways && motionManager.isDeviceMotionAvailable
    }

    var permissionSummary: String {
        switch authorizationStatus {
        case .authorizedAlways: "Location: Always"
        case .authorizedWhenInUse: "Location: While Using — tap again for Always"
        case .denied: "Location: Denied"
        case .restricted: "Location: Restricted"
        case .notDetermined: "Location: Not requested"
        @unknown default: "Location: Unknown"
        }
    }

    func requestPermissions() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            errorMessage = "Enable Location → Always for SmoothRoute in iPhone Settings."
        case .authorizedAlways:
            statusMessage = "Background location is enabled"
        @unknown default:
            break
        }
    }

    func start(
        profile: VehicleProfile,
        area: String,
        tripLabel: String?,
        tester: String?
    ) {
        guard canStart else {
            errorMessage = "Location must be set to Always and motion must be available before recording."
            return
        }

        let now = Date()
        let ride = RideMetadata(
            version: "smoothroute-native-ios-0.1.0",
            id: "roadtest-\(now.millisecondsSince1970)",
            collection_mode: "road_test_beta",
            profile: profile.rawValue,
            vehicle: profile == .myRoadGlide ? .roadGlide : nil,
            area: area,
            trip_label: tripLabel?.nilIfBlank,
            tester: tester?.nilIfBlank,
            started_at: now.iso8601String,
            interruption_count: 0,
            recovery_count: 0,
            persistence: "jsonl-journal-v1",
            background_strategy: "native-core-location-core-motion",
            ended_at: nil,
            duration_seconds: nil,
            sample_count: nil,
            gps_sample_count: nil,
            motion_sample_count: nil,
            watcher_restart_count: 0
        )

        let state = ActiveRideState(
            ride: ride,
            gpsCount: 0,
            motionCount: 0,
            latestGps: nil,
            lastSampleWallMs: now.millisecondsSince1970,
            saved_at: now.iso8601String
        )

        do {
            try store.prepareNewRide(state)
            activeState = state
            gpsCount = 0
            motionCount = 0
            sampleCount = 0
            startedDate = now
            exportURL = nil
            recordingState = .recording
            appendSystem("ride_started")
            startSensors()
            checkpoint(reason: "started")
            startCheckpointTimer()
            statusMessage = "Recording in background"
        } catch {
            errorMessage = "Could not create the ride journal: \(error.localizedDescription)"
        }
    }

    func resumeSavedRide() {
        guard authorizationStatus == .authorizedAlways else {
            errorMessage = "Enable Location → Always before resuming."
            return
        }

        do {
            guard var recovered = try store.loadActive() else {
                throw RideStore.StoreError.noActiveRide
            }
            recovered.ride.version = "smoothroute-native-ios-0.1.0"
            recovered.ride.recovery_count += 1
            recovered.ride.watcher_restart_count += 1
            activeState = recovered
            gpsCount = recovered.gpsCount
            motionCount = recovered.motionCount
            sampleCount = try store.loadSamples().count
            startedDate = ISO8601DateFormatter.smoothRoute.date(from: recovered.ride.started_at)
            recordingState = .recording
            appendSystem("ride_resumed", recoveryCount: recovered.ride.recovery_count)
            startSensors()
            checkpoint(reason: "manual_recovery")
            startCheckpointTimer()
            statusMessage = "Recovered and recording"
        } catch {
            errorMessage = "Could not resume the saved ride: \(error.localizedDescription)"
        }
    }

    func discardSavedRide() {
        do {
            try store.clearActiveRide()
            activeState = nil
            recordingState = .idle
            resetPublishedStats()
            statusMessage = "Saved ride discarded"
        } catch {
            errorMessage = "Could not discard the saved ride: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard recordingState == .recording, var state = activeState else { return }
        stopSensors()
        stopCheckpointTimer()
        appendSystem("ride_ended")

        do {
            let ended = Date()
            let samples = try store.loadSamples()
            state = activeState ?? state
            state.ride.ended_at = ended.iso8601String
            state.ride.duration_seconds = max(
                0,
                Int(ended.timeIntervalSince(startedDate ?? ended).rounded())
            )
            state.ride.sample_count = samples.count
            state.ride.gps_sample_count = gpsCount
            state.ride.motion_sample_count = motionCount
            state.saved_at = ended.iso8601String
            try store.checkpoint(state)

            let payload = RidePayload(ride: state.ride, samples: samples)
            exportURL = try store.finish(payload)
            activeState = nil
            recordingState = .finished
            statusMessage = "Ride saved"
        } catch {
            activeState = state
            errorMessage = "Could not finalize the ride: \(error.localizedDescription)"
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard recordingState == .recording else { return }
        switch phase {
        case .background:
            appendSystem("app_backgrounded", source: "scene_phase")
            checkpoint(reason: "background")
        case .active:
            appendSystem("app_active", source: "scene_phase")
            checkpoint(reason: "active")
        case .inactive:
            checkpoint(reason: "inactive")
        @unknown default:
            checkpoint(reason: "unknown_scene_phase")
        }
    }

    private func startSensors() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()

        guard motionManager.isDeviceMotionAvailable else {
            errorMessage = "Device motion is unavailable."
            return
        }

        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = "Motion error: \(error.localizedDescription)"
                }
                if let motion {
                    self?.recordMotion(motion)
                }
            }
        }
    }

    private func stopSensors() {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
    }

    private func recordLocation(_ location: CLLocation) {
        guard recordingState == .recording else { return }
        let gps = EmbeddedGPS(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil,
            heading: location.course >= 0 ? location.course : nil,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            ts: location.timestamp.millisecondsSince1970
        )

        append(.location(gps))
        gpsCount += 1
        latestAccuracy = gps.accuracy
        latestSpeedMph = gps.speed.map { $0 * 2.236_936_292_1 }
        activeState?.gpsCount = gpsCount
        activeState?.latestGps = gps
        checkpointIfNeeded(reason: "location")
    }

    private func recordMotion(_ motion: CMDeviceMotion) {
        guard recordingState == .recording else { return }
        let gravity = motion.gravity
        let acceleration = motion.userAcceleration
        let metersPerSecondSquared = 9.80665
        let radiansToDegrees = 180.0 / Double.pi

        let sample = RideSample.motion(
            ts: Date().millisecondsSince1970,
            ax: (acceleration.x + gravity.x) * metersPerSecondSquared,
            ay: (acceleration.y + gravity.y) * metersPerSecondSquared,
            az: (acceleration.z + gravity.z) * metersPerSecondSquared,
            alpha: motion.rotationRate.x * radiansToDegrees,
            beta: motion.rotationRate.y * radiansToDegrees,
            gamma: motion.rotationRate.z * radiansToDegrees,
            gps: activeState?.latestGps
        )

        append(sample)
        motionCount += 1
        activeState?.motionCount = motionCount
        checkpointIfNeeded(reason: "motion")
    }

    private func append(_ sample: RideSample, detectGap: Bool = true) {
        guard var state = activeState else { return }
        let nowMs = Date().millisecondsSince1970

        do {
            if detectGap,
               state.lastSampleWallMs > 0,
               nowMs - state.lastSampleWallMs > 10_000 {
                let gap = Int((nowMs - state.lastSampleWallMs) / 1_000)
                try store.append(.system("sample_gap", gapSeconds: gap))
                state.ride.interruption_count += 1
                sampleCount += 1
            }

            try store.append(sample)
            state.lastSampleWallMs = nowMs
            state.saved_at = Date().iso8601String
            activeState = state
            sampleCount += 1
        } catch {
            errorMessage = "Journal write failed: \(error.localizedDescription)"
        }
    }

    private func appendSystem(
        _ event: String,
        source: String? = nil,
        recoveryCount: Int? = nil
    ) {
        append(
            .system(event, source: source, recoveryCount: recoveryCount),
            detectGap: event == "ride_resumed"
        )
    }

    private func checkpointIfNeeded(reason: String) {
        let now = Date().millisecondsSince1970
        guard now - lastCheckpointMs >= 1_000 else { return }
        checkpoint(reason: reason)
    }

    private func checkpoint(reason: String) {
        guard var state = activeState else { return }
        state.gpsCount = gpsCount
        state.motionCount = motionCount
        state.saved_at = Date().iso8601String

        do {
            try store.checkpoint(state)
            activeState = state
            lastCheckpointMs = Date().millisecondsSince1970
        } catch {
            errorMessage = "Checkpoint failed (\(reason)): \(error.localizedDescription)"
        }
    }

    private func startCheckpointTimer() {
        stopCheckpointTimer()
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsedSeconds = max(
                    0,
                    Int(Date().timeIntervalSince(self.startedDate ?? Date()))
                )
                self.checkpoint(reason: "timer")
            }
        }
    }

    private func stopCheckpointTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
    }

    private func resetPublishedStats() {
        gpsCount = 0
        motionCount = 0
        sampleCount = 0
        elapsedSeconds = 0
        latestAccuracy = nil
        latestSpeedMph = nil
        exportURL = nil
    }
}

extension RideRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways {
            statusMessage = "Background location ready"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 {
            recordLocation(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
