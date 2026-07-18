import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

bool _startupPermissionsRequested = false;

/// Requests runtime permissions needed for host/connect on mobile.
///
/// Must run after the first frame so Android has an Activity to show dialogs.
Future<void> requestStartupPermissions() async {
  if (kIsWeb || _startupPermissionsRequested) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }

  _startupPermissionsRequested = true;

  final permissions = <Permission>[
    Permission.camera, // QR scanning in connect mode
  ];

  if (defaultTargetPlatform == TargetPlatform.android) {
    permissions.addAll([
      Permission.bluetooth,
      Permission.bluetoothConnect, // Android 12+ audio / BT headphone routing
      Permission.notification, // Android 13+ notification prompts
    ]);
  }

  try {
    final statuses = await permissions.request();
    debugPrint('Startup permissions: $statuses');
  } catch (error) {
    debugPrint('Startup permission request failed: $error');
  }
}
