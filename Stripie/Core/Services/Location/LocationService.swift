import CoreLocation
import OSLog

/// Wraps CLLocationManager to request and verify location authorization.
/// Stripe Terminal requires location access before initializing.
@Observable
@MainActor
final class LocationService: NSObject {

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.stripie", category: "LocationService")

    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Requests When In Use authorization if not yet determined. Returns the resolved status.
    @discardableResult
    func requestAuthorization() async -> CLAuthorizationStatus {
        guard authorizationStatus == .notDetermined else { return authorizationStatus }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.logger.debug("Location authorization: \(String(describing: status))")
            self.authorizationContinuation?.resume(returning: status)
            self.authorizationContinuation = nil
        }
    }
}
