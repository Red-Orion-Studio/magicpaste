// Helpers for the manual-send path and photo permission.
//
// Automatic background detection now lives in native Kotlin (WorkManager +
// MediaStore URI trigger). This file only provides the image-permission
// request and the ScreenshotInfo value type used by the manual "send latest"
// button while the app is open.

import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

class ScreenshotInfo {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool isPng;
  final String name;
  const ScreenshotInfo({
    required this.bytes,
    required this.width,
    required this.height,
    required this.isPng,
    required this.name,
  });
}

class ScreenshotMonitor {
  /// Request image-only photo permission. Only requests image access — the
  /// default (RequestType.common) also asks for video permission, which we
  /// don't declare; on Android 13+ that makes the whole request come back as
  /// denied.
  static Future<bool> requestImagePermission() async {
    final ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    return ps.isAuth || ps.hasAccess;
  }
}
