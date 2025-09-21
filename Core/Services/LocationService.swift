import Combine
import CoreLocation
import Foundation

enum LocationServiceError: LocalizedError {
    case monitoringUnavailable
    case authorizationDenied
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .monitoringUnavailable:
            return "Geofencing is not supported on this device."
        case .authorizationDenied:
            return "Location permissions are required to register merchant geofences."
        case .invalidCoordinate:
            return "The coordinate provided for the merchant is invalid."
        }
    }
}

@MainActor
protocol LocationServicing: AnyObject {
    var didEnterMerchantRegion: AnyPublisher<UUID, Never> { get }
    var didExitMerchantRegion: AnyPublisher<UUID, Never> { get }

    func requestAuthorization() async -> CLAuthorizationStatus
    func registerGeofence(
        merchantId: UUID,
        coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async throws
    func removeGeofence(for merchantId: UUID)
    func removeAllGeofences()
}

@MainActor
final class LocationService: NSObject, LocationServicing {
    private let locationManager: CLLocationManager
    private let enterSubject = PassthroughSubject<UUID, Never>()
    private let exitSubject = PassthroughSubject<UUID, Never>()
    private var monitoredRegions: [UUID: CLCircularRegion] = [:]
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    var didEnterMerchantRegion: AnyPublisher<UUID, Never> {
        enterSubject.eraseToAnyPublisher()
    }

    var didExitMerchantRegion: AnyPublisher<UUID, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            let status = locationManager.authorizationStatus
            switch status {
            case .notDetermined:
                authorizationContinuation?.resume(returning: status)
                authorizationContinuation = continuation
                locationManager.requestAlwaysAuthorization()
            default:
                continuation.resume(returning: status)
            }
        }
    }

    func registerGeofence(
        merchantId: UUID,
        coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async throws {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw LocationServiceError.invalidCoordinate
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            throw LocationServiceError.monitoringUnavailable
        }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            throw LocationServiceError.authorizationDenied
        }

        let maximumRadius = locationManager.maximumRegionMonitoringDistance
        let resolvedRadius: CLLocationDistance
        if maximumRadius > 0 {
            resolvedRadius = min(radius, maximumRadius)
        } else {
            resolvedRadius = radius
        }

        let region = CLCircularRegion(
            center: coordinate,
            radius: resolvedRadius,
            identifier: merchantId.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true

        monitoredRegions[merchantId] = region
        locationManager.startMonitoring(for: region)
    }

    func removeGeofence(for merchantId: UUID) {
        guard let region = monitoredRegions.removeValue(forKey: merchantId) else { return }
        locationManager.stopMonitoring(for: region)
    }

    func removeAllGeofences() {
        for region in monitoredRegions.values {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegions.removeAll()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if let continuation = authorizationContinuation {
            continuation.resume(returning: manager.authorizationStatus)
            authorizationContinuation = nil
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        if let continuation = authorizationContinuation {
            continuation.resume(returning: status)
            authorizationContinuation = nil
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let identifier = UUID(uuidString: region.identifier) else { return }
        enterSubject.send(identifier)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard let identifier = UUID(uuidString: region.identifier) else { return }
        exitSubject.send(identifier)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        guard let region, let identifier = UUID(uuidString: region.identifier) else { return }
        monitoredRegions.removeValue(forKey: identifier)
    }
}
