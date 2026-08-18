import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class StartupPermissionItem {
  const StartupPermissionItem({
    required this.permission,
    required this.title,
    required this.description,
    required this.status,
  });

  final Permission permission;
  final String title;
  final String description;
  final PermissionStatus status;

  bool get isGranted => status.isGranted || status.isLimited;
  bool get isPermanentlyDenied => status.isPermanentlyDenied;
}

class StartupPermissionService {
  Future<List<StartupPermissionItem>> statuses() async {
    if (!Platform.isAndroid && !Platform.isIOS) return const [];
    final items = <StartupPermissionItem>[
      StartupPermissionItem(
        permission: Permission.camera,
        title: 'الكاميرا',
        description: 'لمسح رمز الطالب والتقاط صورته عند الحاجة.',
        status: await Permission.camera.status,
      ),
    ];
    if (Platform.isIOS) {
      items.add(
        StartupPermissionItem(
          permission: Permission.photos,
          title: 'مكتبة الصور',
          description: 'لاختيار صورة الطالب أو شعار المدرسة من الجهاز.',
          status: await Permission.photos.status,
        ),
      );
    }
    return items;
  }

  Future<List<StartupPermissionItem>> requestAll() async {
    final current = await statuses();
    for (final item in current.where((item) => !item.isGranted)) {
      await item.permission.request();
    }
    return statuses();
  }

  Future<bool> openSettings() => openAppSettings();
}
