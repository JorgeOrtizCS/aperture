import '../models/content_create_request.dart';
import '../widgets/content_restrictions_section.dart';

ContentCreateRequest buildShareUploadDraft({
  required String title,
  required String recipient,
  required String sender,
  required ContentRestrictions restrictions,
  required DateTime now,
}) {
  if (!restrictions.locationArea.valid) {
    throw const ContentDraftException(ContentDraftProblem.policy);
  }
  // The existing create DTO has no download/reshare permission fields. A real
  // verified contract must also guarantee the default deny policy is enforced.
  if (restrictions.allowDownload || restrictions.allowResharing) {
    throw const ContentDraftException(ContentDraftProblem.unsupportedPolicy);
  }
  final duration = switch (restrictions.accessDuration) {
    AccessDuration.twelveHours => const Duration(hours: 12),
    AccessDuration.oneDay => const Duration(days: 1),
    AccessDuration.twoDays => const Duration(days: 2),
    AccessDuration.oneWeek => const Duration(days: 7),
  };
  final utcNow = now.toUtc();
  return ContentCreateRequest.validate(
    title: title,
    recipient: recipient,
    sender: sender,
    now: utcNow,
    startTime: restrictions.viewingStartsAt,
    expiresAt: utcNow.add(duration),
    maxViews: restrictions.viewLimit,
    requireTrustedDevice: restrictions.requireTrustedDevice,
    screenshotRestriction: restrictions.restrictScreenshots,
    location: restrictions.locationArea.zone,
    networkLocation: restrictions.networkLocation,
  );
}
