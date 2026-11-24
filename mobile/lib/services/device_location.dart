/// A granted reading is a measurement, never a recipient authorization.
enum LocationStatus {
  granted,
  denied,
  permanentlyDenied,
  unavailable,
  stale,
  permissionRequired,
  insufficientAccuracy,
  accuracyUnconfirmed,
  cancelled,
}

enum LocationPermissionState {
  notDetermined,
  granted,
  approximate,
  denied,
  permanentlyDenied,
  unavailable,
}

class LocationFix {
  final double latitude, longitude;
  final DateTime measuredAt;
  final double? horizontalAccuracyMeters;
  const LocationFix(
    this.latitude,
    this.longitude,
    this.measuredAt, {
    this.horizontalAccuracyMeters,
  });

  bool freshFor(DateTime started, DateTime now, Duration maxAge) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !measuredAt.isBefore(started) &&
      !measuredAt.isAfter(now) &&
      now.difference(measuredAt) < maxAge;

  Map<String, String> get headers => {
    'X-Client-Latitude': latitude.toString(),
    'X-Client-Longitude': longitude.toString(),
  };

  @override
  String toString() => 'LocationFix(redacted)';
}

class LocationReading {
  final LocationStatus status;
  final LocationFix? fix;
  const LocationReading(this.status, [this.fix]);
}

abstract interface class DeviceLocationSource {
  Future<LocationReading> locate();
}

/// Session-owned foreground resource. Permission interaction is separate from
/// bounded acquisition and must only be offered for a policy requiring location.
abstract interface class ForegroundDeviceLocationSource
    implements DeviceLocationSource {
  Future<LocationPermissionState> requestPermission();
  Future<void> cancelAcquisition();
  Future<void> close();
}

abstract interface class DeviceLocationPermissionStatus {
  Future<LocationPermissionState> readPermission();
}

class UnavailableDeviceLocation implements DeviceLocationSource {
  const UnavailableDeviceLocation();
  @override
  Future<LocationReading> locate() async =>
      const LocationReading(LocationStatus.unavailable);
}
