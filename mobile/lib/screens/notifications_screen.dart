import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/access_status.dart';
import '../services/api_session.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, this.account});

  final ApiSession? account;

  @override
  Widget build(BuildContext context) {
    final session = account;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: session == null
          ? const Center(child: Text('Sign in to see access status.'))
          : ListenableBuilder(
              listenable: Listenable.merge([session, session.accessStatuses]),
              builder: (context, _) {
                if (!session.authenticated) {
                  return const Center(
                    child: Text('Sign in to see access status.'),
                  );
                }
                final statuses = <AccessStatus>{
                  ...session.accessStatuses.entries,
                  for (final item in session.items)
                    if (item.status == 'Revoked')
                      (
                        kind: AccessStatusKind.contentRevoked,
                        source: AccessStatusSource.serverMetadata,
                      )
                    else if (item.policyStatus == 'Paused')
                      (
                        kind: AccessStatusKind.contentPaused,
                        source: AccessStatusSource.serverMetadata,
                      )
                    else if (item.expiresAt?.isAfter(session.now().toUtc()) ==
                        false)
                      (
                        kind: AccessStatusKind.viewingWindowExpired,
                        source: AccessStatusSource.serverMetadata,
                      ),
                  if (session.error?.kind
                      case ApiFailure.network || ApiFailure.timeout)
                    (
                      kind: AccessStatusKind.networkInterrupted,
                      source: AccessStatusSource.device,
                    ),
                };
                return SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text('Access status observed in this app'),
                      if (session.api.isFixture)
                        const Text('Sample account data'),
                      const SizedBox(height: 12),
                      if (statuses.isEmpty)
                        const Text('No access updates yet.'),
                      for (final status in statuses)
                        _StatusTile(
                          status: status,
                          fixture: session.api.isFixture,
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.fixture});

  final AccessStatus status;
  final bool fixture;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = switch (status.kind) {
      AccessStatusKind.accessGranted => (
        'Access granted',
        'The server approved recipient access at the last check. Device checks still apply.',
      ),
      AccessStatusKind.accessDenied => (
        'Access denied',
        'The server refused this viewing request.',
      ),
      AccessStatusKind.sessionSuspended => (
        'Viewing suspended',
        'The server suspended access. Start a fresh viewing session to request access again.',
      ),
      AccessStatusKind.sessionEnded => (
        'Viewing session ended',
        status.source == AccessStatusSource.device
            ? 'A device security check ended the session. Review the viewing requirements before opening it again.'
            : 'The server reported the session ended. Open the item again to request a new session.',
      ),
      AccessStatusKind.contentPaused => (
        'Content paused',
        'The current content listing shows a paused viewing policy.',
      ),
      AccessStatusKind.contentRevoked => (
        'Access revoked',
        'The current content listing shows revoked recipient access.',
      ),
      AccessStatusKind.viewingWindowExpired => (
        'Viewing window expired',
        'The end time in the content listing has passed according to this device.',
      ),
      AccessStatusKind.locationDenied => (
        'Location permission denied',
        'Allow precise location in the prompt or in the app’s system settings, then recheck viewing conditions.',
      ),
      AccessStatusKind.locationBlocked => (
        'Location permission blocked',
        'Enable precise location for Aperture in system settings, then return and recheck.',
      ),
      AccessStatusKind.locationApproximate => (
        'Precise location required',
        'Enable precise location for Aperture in system settings, then recheck.',
      ),
      AccessStatusKind.locationUnavailable => (
        'Location unavailable',
        'Check that Location Services are on, then recheck viewing conditions.',
      ),
      AccessStatusKind.cameraDenied => (
        'Camera permission denied',
        'Retry the camera check or allow Camera for Aperture in system settings.',
      ),
      AccessStatusKind.cameraBlocked => (
        'Camera permission blocked',
        'Allow Camera for Aperture in system settings and check any device restrictions, then recheck.',
      ),
      AccessStatusKind.cameraUnavailable => (
        'Camera protection unavailable',
        'Make sure the camera is available, then retry camera protection.',
      ),
      AccessStatusKind.biometricUnavailable => (
        'Biometrics unavailable',
        'Check enrollment, device permissions or lockout, then verify identity again.',
      ),
      AccessStatusKind.biometricCancelled => (
        'Biometric verification cancelled',
        'Verify identity again when ready.',
      ),
      AccessStatusKind.networkInterrupted => (
        'Connection interrupted',
        'Check your connection, then refresh the list or recheck viewing conditions.',
      ),
      AccessStatusKind.securityUnavailable => (
        'Required security checks unavailable',
        'Review the requirements on the viewing screen and recheck eligible conditions.',
      ),
    };
    final source = switch (status.source) {
      AccessStatusSource.serverResponse =>
        fixture ? 'Sample response' : 'Server response',
      AccessStatusSource.serverMetadata =>
        fixture ? 'Sample content listing' : 'Content listing',
      AccessStatusSource.device => 'Device status',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text('$source\n$detail'),
    );
  }
}
