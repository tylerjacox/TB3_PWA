// TB3 iOS — Weather Service (WeatherKit + CoreLocation)
// Fetches ambient temperature once at session start for workout context.
// Uses one-shot location fix → WeatherKit current conditions → returns °F.

import WeatherKit
import CoreLocation

@MainActor
final class TB3WeatherService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    /// Fetch current temperature in Fahrenheit. Returns nil on any failure
    /// (permission denied, no location, WeatherKit error, no network).
    func fetchCurrentTemperature() async -> Double? {
        // 1. Request location (one-shot)
        let location = await requestLocation()
        guard let location else { return nil }

        // 2. Query WeatherKit
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let celsius = weather.currentWeather.temperature.value
            let fahrenheit = celsius * 9.0 / 5.0 + 32.0
            return fahrenheit.rounded() // e.g. 72.0
        } catch {
            print("[TB3Weather] WeatherKit error: \(error.localizedDescription)")
            return nil
        }
    }

    private func requestLocation() async -> CLLocation? {
        let status = locationManager.authorizationStatus

        if status == .denied || status == .restricted {
            print("[TB3Weather] Location permission denied/restricted")
            return nil
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // Coarse is fine for weather

        // If not determined, request authorization first and wait for it
        if status == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }

            // Check again after authorization response
            let newStatus = locationManager.authorizationStatus
            if newStatus == .denied || newStatus == .restricted {
                print("[TB3Weather] Location permission denied after prompt")
                return nil
            }
        }

        // Now request the actual location
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.first)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("[TB3Weather] Location error: \(error.localizedDescription)")
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Resume the auth continuation if we were waiting for authorization
            if let authContinuation {
                self.authContinuation = nil
                authContinuation.resume()
            }
        }
    }
}
