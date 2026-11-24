import 'package:flutter/material.dart';

import '../services/device_registration.dart';

class DeviceRegistrationPanel extends StatelessWidget {
  final DeviceRegistration registration;
  const DeviceRegistrationPanel({super.key, required this.registration});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: registration,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            registration.deviceKeyConfigured
                ? registration.message
                : 'A device key must be configured before registering.',
            key: const ValueKey('device-registration-status'),
          ),
        ),
        TextButton(
          onPressed: registration.pending || !registration.canRegister
              ? null
              : () => registration.register('Aperture mobile device'),
          child: Text(
            registration.pending
                ? 'Registering device…'
                : registration.trusted == null
                ? 'Register this device'
                : 'Check device approval again',
          ),
        ),
        if (registration.pending)
          TextButton(
            onPressed: registration.cancel,
            child: const Text('Cancel registration wait'),
          ),
      ],
    ),
  );
}
