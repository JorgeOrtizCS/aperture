import 'dart:convert';
import 'dart:typed_data';

import 'location_radius_policy.dart';

enum ContentDraftProblem {
  title,
  recipient,
  policy,
  unsupportedPolicy,
  missingFile,
  unsupportedImage,
  tooLarge,
}

class ContentDraftException implements Exception {
  final ContentDraftProblem problem;
  const ContentDraftException(this.problem);

  String get message => switch (problem) {
    ContentDraftProblem.title => 'Enter a title of at most 160 characters.',
    ContentDraftProblem.recipient =>
      'Enter a different account’s username (up to 100 characters).',
    ContentDraftProblem.policy =>
      'Review the viewing area, time window, and view limit.',
    ContentDraftProblem.unsupportedPolicy =>
      'This API cannot express the selected download or resharing permissions.',
    ContentDraftProblem.missingFile => 'Select a PNG before submitting.',
    ContentDraftProblem.unsupportedImage => 'Select a valid PNG image.',
    ContentDraftProblem.tooLarge => 'This PNG exceeds the file size limit.',
  };

  @override
  String toString() => 'ContentDraftException(${problem.name})';
}

/// The PNG subset of CreateContentRequest. This value contains metadata only;
/// the Base64 image is constructed at the transport boundary, never persisted.
class ContentCreateRequest {
  static const maxPngBytes = 5 * 1024 * 1024;
  static const _signature = [137, 80, 78, 71, 13, 10, 26, 10];
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  final String title, recipient;
  final DateTime? startTime, expiresAt;
  final int? maxViews;
  final bool requireTrustedDevice, screenshotRestriction;
  final LocationZone? location;
  final NetworkLocation networkLocation;

  const ContentCreateRequest._({
    required this.title,
    required this.recipient,
    required this.startTime,
    required this.expiresAt,
    required this.maxViews,
    required this.requireTrustedDevice,
    required this.screenshotRestriction,
    required this.location,
    required this.networkLocation,
  });

  factory ContentCreateRequest.validate({
    required String title,
    required String recipient,
    required String sender,
    required DateTime now,
    DateTime? startTime,
    DateTime? expiresAt,
    int? maxViews,
    bool requireTrustedDevice = false,
    required bool screenshotRestriction,
    LocationZone? location,
    NetworkLocation networkLocation = const NetworkLocation(),
  }) {
    title = title.trim();
    recipient = recipient.trim();
    if (title.isEmpty || title.length > 160 || _controls.hasMatch(title)) {
      throw const ContentDraftException(ContentDraftProblem.title);
    }
    if (!validRecipient(recipient, sender: sender)) {
      throw const ContentDraftException(ContentDraftProblem.recipient);
    }
    if ((maxViews != null && (maxViews < 1 || maxViews > 0x7fffffff)) ||
        (expiresAt != null && !expiresAt.isAfter(now)) ||
        (startTime != null &&
            expiresAt != null &&
            !expiresAt.isAfter(startTime)) ||
        (location != null && (!location.valid || networkLocation.enabled)) ||
        !networkLocation.valid) {
      throw const ContentDraftException(ContentDraftProblem.policy);
    }
    return ContentCreateRequest._(
      title: title,
      recipient: recipient,
      startTime: startTime?.toUtc(),
      expiresAt: expiresAt?.toUtc(),
      maxViews: maxViews,
      requireTrustedDevice: requireTrustedDevice,
      screenshotRestriction: screenshotRestriction,
      location: location,
      networkLocation: networkLocation,
    );
  }

  static bool validRecipient(String input, {required String sender}) {
    final username = input.trim();
    return username.isNotEmpty &&
        username.length <= 100 &&
        !_controls.hasMatch(username) &&
        username.toLowerCase() != sender.trim().toLowerCase();
  }

  /// Expects original bytes that have already passed the local PNG decoder.
  /// Check the wire limit and signature again before encoding.
  Map<String, Object> encode(Uint8List? png, {required int maxBytes}) {
    if (png == null || png.isEmpty) {
      throw const ContentDraftException(ContentDraftProblem.missingFile);
    }
    if (png.length > maxPngBytes || png.length > maxBytes) {
      throw const ContentDraftException(ContentDraftProblem.tooLarge);
    }
    if (png.length < _signature.length) {
      throw const ContentDraftException(ContentDraftProblem.unsupportedImage);
    }
    for (var i = 0; i < _signature.length; i++) {
      if (png[i] != _signature[i]) {
        throw const ContentDraftException(ContentDraftProblem.unsupportedImage);
      }
    }
    final zone = location;
    return {
      'Title': title,
      'Recipient': recipient,
      'FileType': 'image/png',
      'FileDataBase64': base64Encode(png),
      'ScreenshotRestriction': screenshotRestriction,
      'RequireTrustedDevice': requireTrustedDevice,
      if (startTime != null) 'StartTime': startTime!.toIso8601String(),
      if (expiresAt != null) 'ExpiresAt': expiresAt!.toIso8601String(),
      'MaxViews': ?maxViews,
      if (zone != null) ...{
        'Latitude': zone.latitude,
        'Longitude': zone.longitude,
        'RadiusMeters': zone.radiusMeters,
      },
      if (networkLocation.country.trim().isNotEmpty)
        'AllowedCountry': networkLocation.country.trim(),
      if (networkLocation.region.trim().isNotEmpty)
        'AllowedRegion': networkLocation.region.trim(),
      if (networkLocation.city.trim().isNotEmpty)
        'AllowedCity': networkLocation.city.trim(),
    };
  }

  @override
  String toString() => 'ContentCreateRequest(redacted)';
}
