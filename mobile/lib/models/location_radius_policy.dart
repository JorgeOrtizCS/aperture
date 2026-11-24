import 'dart:math' as math;

import '../services/device_location.dart';

/// Prototype policy, ADR 0001 (2026-11-06), not a GPS security certification.
enum LocationRadiusPreset {
  verySmall('Very small area', 10),
  home('Home / small building', 30),
  building('Large building', 100),
  campus('Campus / large property', 500),
  large('Large area', 1000),
  custom('Custom radius', null);

  final String label;
  final int? meters;
  const LocationRadiusPreset(this.label, this.meters);
}

class LocationZone {
  final double latitude, longitude, radiusMeters;
  const LocationZone(this.latitude, this.longitude, this.radiusMeters);

  bool get valid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      LocationRadiusPolicy.validRadius(radiusMeters);

  @override
  bool operator ==(Object other) =>
      other is LocationZone &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      radiusMeters == other.radiusMeters;
  @override
  int get hashCode => Object.hash(latitude, longitude, radiusMeters);
  @override
  String toString() => 'LocationZone(redacted)';
}

enum LocationZoneResult { accepted, invalid, stale, uncertainty, outside }

/// Country, region and city restrictions evaluated by the API using client IP.
class NetworkLocation {
  final String country, region, city;
  const NetworkLocation({this.country = '', this.region = '', this.city = ''});

  List<String> get parts => [
    for (final value in [country, region, city])
      if (value.trim().isNotEmpty) value.trim(),
  ];
  bool get enabled => parts.isNotEmpty;
  bool get valid => !parts.any(RegExp(r'[\x00-\x1f\x7f]').hasMatch);

  @override
  bool operator ==(Object other) =>
      other is NetworkLocation &&
      country.trim() == other.country.trim() &&
      region.trim() == other.region.trim() &&
      city.trim() == other.city.trim();

  @override
  int get hashCode => Object.hash(country.trim(), region.trim(), city.trim());

  @override
  String toString() => 'NetworkLocation(redacted)';
}

abstract final class LocationRadiusPolicy {
  static const double maximumUncertaintyMeters = 100;
  static const double earthRadiusMeters = 6371000;
  static bool validRadius(double radius) =>
      radius.isFinite && radius >= 10 && radius <= 10000;

  static bool acceptsDistance(
    double distance,
    double? uncertainty,
    double radius,
  ) =>
      validRadius(radius) &&
      distance.isFinite &&
      distance >= 0 &&
      uncertainty != null &&
      uncertainty.isFinite &&
      uncertainty >= 0 &&
      uncertainty <= maximumUncertaintyMeters &&
      distance + uncertainty <= radius;

  static double distanceMeters(LocationZone zone, LocationFix fix) {
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(fix.latitude - zone.latitude);
    final dLon = radians(fix.longitude - zone.longitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(radians(zone.latitude)) *
            math.cos(radians(fix.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  static LocationZoneResult evaluate(
    LocationZone? zone,
    LocationFix fix,
    DateTime started,
    DateTime now,
    Duration maxAge,
  ) {
    if (zone == null ||
        !zone.valid ||
        !fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180) {
      return LocationZoneResult.invalid;
    }
    if (!fix.freshFor(started, now, maxAge)) return LocationZoneResult.stale;
    final uncertainty = fix.horizontalAccuracyMeters;
    if (uncertainty == null ||
        !uncertainty.isFinite ||
        uncertainty < 0 ||
        uncertainty > maximumUncertaintyMeters) {
      return LocationZoneResult.uncertainty;
    }
    return acceptsDistance(
          distanceMeters(zone, fix),
          uncertainty,
          zone.radiusMeters,
        )
        ? LocationZoneResult.accepted
        : LocationZoneResult.outside;
  }
}

/// In-memory area draft for preview or owner editing. A draft never grants access.
class SenderLocationDraft {
  final bool enabled;
  final String latitude, longitude, customRadius;
  final LocationRadiusPreset preset;
  const SenderLocationDraft({
    this.enabled = false,
    this.latitude = '',
    this.longitude = '',
    this.customRadius = '',
    this.preset = LocationRadiusPreset.building,
  });

  factory SenderLocationDraft.forExistingArea(LocationZone? zone) {
    if (zone == null) return const SenderLocationDraft(enabled: true);
    final preset = LocationRadiusPreset.values.firstWhere(
      (value) => value.meters == zone.radiusMeters,
      orElse: () => LocationRadiusPreset.custom,
    );
    return SenderLocationDraft(
      enabled: true,
      latitude: zone.latitude.toString(),
      longitude: zone.longitude.toString(),
      preset: preset,
      customRadius: zone.radiusMeters.toString(),
    );
  }

  double? get radiusMeters =>
      preset.meters?.toDouble() ?? double.tryParse(customRadius.trim());
  LocationZone? get zone {
    final lat = double.tryParse(latitude.trim()),
        lon = double.tryParse(longitude.trim());
    final radius = radiusMeters;
    if (!enabled || lat == null || lon == null || radius == null) return null;
    final value = LocationZone(lat, lon, radius);
    return value.valid ? value : null;
  }

  bool get valid => !enabled || zone != null;
  SenderLocationDraft copyWith({
    bool? enabled,
    String? latitude,
    String? longitude,
    String? customRadius,
    LocationRadiusPreset? preset,
  }) => SenderLocationDraft(
    enabled: enabled ?? this.enabled,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    customRadius: customRadius ?? this.customRadius,
    preset: preset ?? this.preset,
  );
  @override
  String toString() => 'SenderLocationDraft(redacted)';
}
