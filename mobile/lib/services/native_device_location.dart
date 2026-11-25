import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device_location.dart';

/// Uses OS measurements only. Callers must explicitly supply their accuracy
/// rule; an unconfigured adapter collects nothing. The recipient route supplies
/// the provisional ADR 0001 cap, independently of server authorization.
class NativeDeviceLocation
    with WidgetsBindingObserver
    implements ForegroundDeviceLocationSource, DeviceLocationPermissionStatus {
  static const channel = MethodChannel('aperture/device_location');
  static int _sequence = 0;
  final int _owner = ++_sequence;
  final double? approvedAccuracyLimitMeters;
  final Duration acquisitionTimeout;
  final DateTime Function() now;
  bool _closed = false;
  bool _usedNative = false;
  bool _foreground = true;
  int _generation = 0, _permissionGeneration = 0;
  Future<LocationReading>? _pending;
  Future<LocationPermissionState>? _permission;

  NativeDeviceLocation({
    this.approvedAccuracyLimitMeters,
    this.acquisitionTimeout = const Duration(seconds: 4),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  LocationPermissionState _permissionState(Object? value) => switch (value) {
    'granted' => LocationPermissionState.granted,
    'approximate' => LocationPermissionState.approximate,
    'notDetermined' => LocationPermissionState.notDetermined,
    'denied' => LocationPermissionState.denied,
    'permanentlyDenied' => LocationPermissionState.permanentlyDenied,
    _ => LocationPermissionState.unavailable,
  };

  @override
  Future<LocationPermissionState> readPermission() async {
    if (_closed || !_foreground) return LocationPermissionState.unavailable;
    final generation = _permissionGeneration;
    try {
      final result = await channel
          .invokeMethod<Object?>('permission')
          .timeout(const Duration(seconds: 1));
      return !_closed && _foreground && generation == _permissionGeneration
          ? _permissionState(result)
          : LocationPermissionState.unavailable;
    } catch (_) {
      return LocationPermissionState.unavailable;
    }
  }

  @override
  Future<LocationPermissionState> requestPermission() {
    if (_closed || !_foreground) {
      return Future.value(LocationPermissionState.unavailable);
    }
    if (_permission != null) return _permission!;
    final generation = _permissionGeneration;
    _usedNative = true;
    late final Future<LocationPermissionState> pending;
    // Human interaction intentionally has no location-acquisition deadline.
    pending = channel
        .invokeMethod<Object?>('requestPermission', {'owner_id': _owner})
        .then(
          (value) => !_closed && generation == _permissionGeneration
              ? _permissionState(value)
              : LocationPermissionState.unavailable,
        )
        .catchError((Object _) => LocationPermissionState.unavailable)
        .whenComplete(() {
          if (identical(_permission, pending)) _permission = null;
        });
    return _permission = pending;
  }

  @override
  Future<LocationReading> locate() {
    if (_closed || !_foreground) {
      return Future.value(const LocationReading(LocationStatus.unavailable));
    }
    final limit = approvedAccuracyLimitMeters;
    if (limit == null || !limit.isFinite || limit <= 0) {
      return Future.value(
        const LocationReading(LocationStatus.accuracyUnconfirmed),
      );
    }
    if (_pending != null) return _pending!;
    final generation = _generation;
    late final Future<LocationReading> pending;
    pending = _locate(generation, limit).whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    return _pending = pending;
  }

  Future<LocationReading> _locate(int generation, double limit) async {
    _usedNative = true;
    try {
      final permission = _permissionState(
        await channel
            .invokeMethod<Object?>('permission')
            .timeout(const Duration(seconds: 1)),
      );
      if (_closed || !_foreground || generation != _generation) {
        return const LocationReading(LocationStatus.cancelled);
      }
      final status = switch (permission) {
        LocationPermissionState.notDetermined =>
          LocationStatus.permissionRequired,
        LocationPermissionState.denied => LocationStatus.denied,
        LocationPermissionState.permanentlyDenied =>
          LocationStatus.permanentlyDenied,
        LocationPermissionState.approximate =>
          LocationStatus.insufficientAccuracy,
        LocationPermissionState.unavailable => LocationStatus.unavailable,
        LocationPermissionState.granted => LocationStatus.granted,
      };
      if (status != LocationStatus.granted) return LocationReading(status);
      final started = now().toUtc();
      final result = await channel
          .invokeMapMethod<String, Object?>('locate', {
            'owner_id': _owner,
            'request_id': ++_sequence,
            'timeout_ms': acquisitionTimeout.inMilliseconds,
            'max_accuracy_m': limit,
          })
          .timeout(acquisitionTimeout + const Duration(seconds: 1));
      if (_closed || !_foreground || generation != _generation) {
        return const LocationReading(LocationStatus.cancelled);
      }
      if (result?['status'] != 'granted') {
        return LocationReading(switch (result?['status']) {
          'denied' => LocationStatus.denied,
          'permanentlyDenied' => LocationStatus.permanentlyDenied,
          'permissionRequired' => LocationStatus.permissionRequired,
          'approximate' ||
          'insufficientAccuracy' => LocationStatus.insufficientAccuracy,
          'cancelled' => LocationStatus.cancelled,
          'stale' => LocationStatus.stale,
          _ => LocationStatus.unavailable,
        });
      }
      final latitude = result?['latitude'], longitude = result?['longitude'];
      final accuracy = result?['accuracy_m'],
          timestamp = result?['timestamp_ms'];
      if (latitude is! num ||
          longitude is! num ||
          accuracy is! num ||
          !accuracy.isFinite ||
          accuracy < 0 ||
          timestamp is! int ||
          timestamp <= 0) {
        return const LocationReading(LocationStatus.unavailable);
      }
      final fix = LocationFix(
        latitude.toDouble(),
        longitude.toDouble(),
        DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        horizontalAccuracyMeters: accuracy.toDouble(),
      );
      if (!fix.freshFor(started, now().toUtc(), acquisitionTimeout)) {
        return const LocationReading(LocationStatus.stale);
      }
      if (accuracy > limit) {
        return const LocationReading(LocationStatus.insufficientAccuracy);
      }
      return LocationReading(LocationStatus.granted, fix);
    } catch (_) {
      // A Dart timeout must also release the native sensor; a timed-out future
      // does not cancel its platform operation by itself.
      if (!_closed && generation == _generation) await cancelAcquisition();
      return const LocationReading(LocationStatus.unavailable);
    }
  }

  Future<void> _cancel(String method) async {
    if (!_usedNative) return;
    try {
      await channel
          .invokeMethod<void>(method, {'owner_id': _owner})
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      /* An unavailable bridge cannot provide a successful fix. */
    }
  }

  @override
  Future<void> cancelAcquisition() {
    ++_generation;
    _pending = null;
    return _cancel('cancelAcquisition');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) return;
    unawaited(cancelAcquisition());
    if (state != AppLifecycleState.inactive) {
      ++_permissionGeneration;
      _permission = null;
      unawaited(_cancel('close'));
    }
  }

  @override
  Future<void> close() {
    if (_closed) return Future.value();
    _closed = true;
    ++_generation;
    ++_permissionGeneration;
    _pending = null;
    _permission = null;
    WidgetsBinding.instance.removeObserver(this);
    return _cancel('close');
  }
}
