import XCTest
@testable import SmoothRoute

final class RideModelTests: XCTestCase {
    func testRoadGlideProfileMatchesBrowserSchema() throws {
        let vehicle = VehicleSpec.roadGlide

        XCTAssertEqual(vehicle.profile_id, "harley_road_glide_special_2021_user_01")
        XCTAssertEqual(vehicle.vehicle_class, "motorcycle")
        XCTAssertEqual(vehicle.year, 2021)
        XCTAssertEqual(vehicle.make, "Harley-Davidson")
        XCTAssertEqual(vehicle.model, "Road Glide Special")
        XCTAssertEqual(vehicle.suspension.front.brand, "Öhlins")
        XCTAssertEqual(vehicle.suspension.rear.product_family, "Screamin' Eagle")
    }

    func testPayloadUsesBrowserCompatibleSnakeCaseKeys() throws {
        let now = Date()
        let ride = RideMetadata(
            version: "smoothroute-native-ios-0.1.0",
            id: "roadtest-test",
            collection_mode: "road_test_beta",
            profile: VehicleProfile.motorcycle.rawValue,
            vehicle: nil,
            area: "san_jose",
            trip_label: "test",
            tester: nil,
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
        let gps = EmbeddedGPS(
            lat: 37.33,
            lon: -121.89,
            accuracy: 4,
            speed: 12,
            heading: 180,
            altitude: 20,
            ts: now.millisecondsSince1970
        )
        let payload = RidePayload(ride: ride, samples: [.location(gps)])

        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(payload)
        ) as? [String: Any]
        let rideJSON = try XCTUnwrap(object?["ride"] as? [String: Any])
        let samplesJSON = try XCTUnwrap(object?["samples"] as? [[String: Any]])

        XCTAssertEqual(rideJSON["collection_mode"] as? String, "road_test_beta")
        XCTAssertEqual(
            rideJSON["background_strategy"] as? String,
            "native-core-location-core-motion"
        )
        XCTAssertEqual(samplesJSON.first?["type"] as? String, "gps")
        XCTAssertEqual(samplesJSON.first?["lat"] as? Double, 37.33)
    }

    func testSystemRecoveryMarkerRoundTrips() throws {
        let sample = RideSample.system(
            "ride_resumed",
            recoveryCount: 2
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(RideSample.self, from: data)

        XCTAssertEqual(decoded.event, "ride_resumed")
        XCTAssertEqual(decoded.recovery_count, 2)
    }
}
