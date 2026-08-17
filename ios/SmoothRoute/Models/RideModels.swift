import Foundation

enum VehicleProfile: String, CaseIterable, Codable, Identifiable {
    case car
    case motorcycle
    case scooter
    case myRoadGlide = "my_road_glide"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .car: "Car"
        case .motorcycle: "Motorcycle"
        case .scooter: "Scooter"
        case .myRoadGlide: "My Road Glide"
        }
    }
}

struct VehicleSpec: Codable, Equatable {
    struct Wheels: Codable, Equatable {
        let configuration: String
        let notes: String
    }

    struct SuspensionPart: Codable, Equatable {
        let brand: String
        let supplier_installer: String?
        let product_family: String?
        let description: String
    }

    struct Suspension: Codable, Equatable {
        let configuration: String
        let front: SuspensionPart
        let rear: SuspensionPart
    }

    let profile_id: String
    let vehicle_class: String
    let year: Int
    let make: String
    let model: String
    let wheels: Wheels
    let suspension: Suspension

    static let roadGlide = VehicleSpec(
        profile_id: "harley_road_glide_special_2021_user_01",
        vehicle_class: "motorcycle",
        year: 2021,
        make: "Harley-Davidson",
        model: "Road Glide Special",
        wheels: .init(
            configuration: "stock",
            notes: "Stock wheel configuration; exact tire specification can be added after verification."
        ),
        suspension: .init(
            configuration: "modified",
            front: .init(
                brand: "Öhlins",
                supplier_installer: "Big Bear Performance",
                product_family: nil,
                description: "Big Bear Performance / Öhlins front suspension"
            ),
            rear: .init(
                brand: "Öhlins",
                supplier_installer: nil,
                product_family: "Screamin' Eagle",
                description: "Screamin' Eagle / Öhlins rear suspension"
            )
        )
    )
}

struct EmbeddedGPS: Codable, Equatable {
    let lat: Double
    let lon: Double
    let accuracy: Double
    let speed: Double?
    let heading: Double?
    let altitude: Double?
    let ts: Int64
}

struct RideSample: Codable, Equatable {
    let type: String
    let event: String?
    let ts: Int64

    let lat: Double?
    let lon: Double?
    let accuracy: Double?
    let speed: Double?
    let heading: Double?
    let altitude: Double?

    let ax: Double?
    let ay: Double?
    let az: Double?
    let alpha: Double?
    let beta: Double?
    let gamma: Double?
    let gps: EmbeddedGPS?

    let source: String?
    let reason: String?
    let gap_seconds: Int?
    let hidden_seconds: Int?
    let restart_count: Int?
    let recovery_count: Int?

    static func location(_ gps: EmbeddedGPS) -> RideSample {
        RideSample(
            type: "gps", event: nil, ts: gps.ts,
            lat: gps.lat, lon: gps.lon, accuracy: gps.accuracy,
            speed: gps.speed, heading: gps.heading, altitude: gps.altitude,
            ax: nil, ay: nil, az: nil, alpha: nil, beta: nil, gamma: nil,
            gps: nil, source: nil, reason: nil, gap_seconds: nil,
            hidden_seconds: nil, restart_count: nil, recovery_count: nil
        )
    }

    static func motion(
        ts: Int64,
        ax: Double, ay: Double, az: Double,
        alpha: Double, beta: Double, gamma: Double,
        gps: EmbeddedGPS?
    ) -> RideSample {
        RideSample(
            type: "motion", event: nil, ts: ts,
            lat: nil, lon: nil, accuracy: nil, speed: nil, heading: nil, altitude: nil,
            ax: ax, ay: ay, az: az, alpha: alpha, beta: beta, gamma: gamma,
            gps: gps, source: nil, reason: nil, gap_seconds: nil,
            hidden_seconds: nil, restart_count: nil, recovery_count: nil
        )
    }

    static func system(
        _ event: String,
        ts: Int64 = Date().millisecondsSince1970,
        source: String? = nil,
        reason: String? = nil,
        gapSeconds: Int? = nil,
        recoveryCount: Int? = nil
    ) -> RideSample {
        RideSample(
            type: "system", event: event, ts: ts,
            lat: nil, lon: nil, accuracy: nil, speed: nil, heading: nil, altitude: nil,
            ax: nil, ay: nil, az: nil, alpha: nil, beta: nil, gamma: nil,
            gps: nil, source: source, reason: reason, gap_seconds: gapSeconds,
            hidden_seconds: nil, restart_count: nil, recovery_count: recoveryCount
        )
    }
}

struct RideMetadata: Codable, Equatable {
    var version: String
    let id: String
    let collection_mode: String
    let profile: String
    let vehicle: VehicleSpec?
    let area: String
    let trip_label: String?
    let tester: String?
    let started_at: String
    var interruption_count: Int
    var recovery_count: Int
    let persistence: String
    let background_strategy: String
    var ended_at: String?
    var duration_seconds: Int?
    var sample_count: Int?
    var gps_sample_count: Int?
    var motion_sample_count: Int?
    var watcher_restart_count: Int
}

struct ActiveRideState: Codable, Equatable {
    var ride: RideMetadata
    var gpsCount: Int
    var motionCount: Int
    var latestGps: EmbeddedGPS?
    var lastSampleWallMs: Int64
    var saved_at: String
}

struct RidePayload: Codable, Equatable {
    let ride: RideMetadata
    let samples: [RideSample]
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    var iso8601String: String {
        ISO8601DateFormatter.smoothRoute.string(from: self)
    }
}

extension ISO8601DateFormatter {
    static let smoothRoute: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
