import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morning_student_attendance/app.dart';
import 'package:morning_student_attendance/bootstrap.dart';
import 'package:morning_student_attendance/core/providers.dart';
import 'package:morning_student_attendance/services/startup_permission_service.dart';
import 'package:morning_student_attendance/services/usage_policy_service.dart';

void main() {
  enableFlutterDriverExtension();
  runApp(const _DriverBootstrap());
}

class _DriverBootstrap extends StatefulWidget {
  const _DriverBootstrap();

  @override
  State<_DriverBootstrap> createState() => _DriverBootstrapState();
}

class _DriverBootstrapState extends State<_DriverBootstrap> {
  late final Future<BootstrapServices> _initialization = _initialize();

  Future<BootstrapServices> _initialize() async {
    final services = await initializeAttendanceApp();
    final database = services.database;

    // The integration script changes the copied app's applicationId to a
    // dedicated acceptance package, so this cleanup cannot touch the release.
    await database.db.delete('audit_logs');
    await database.db.delete('report_archives');
    await database.db.delete('closed_days');
    await database.db.delete('attendance');
    await database.db.delete('transfers');
    await database.db.delete('students');
    await database.db.delete('classes');
    await database.db.delete('grades');
    await database.db.delete('users');
    await database.db.delete('school_days');
    await database.db.delete('saved_mappings');
    await database.db.delete('settings');
    await database.db.insert('settings', {
      'key': UsagePolicy.acceptedVersionKey,
      'value': UsagePolicy.version,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return services;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BootstrapServices>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: Text('تعذر تهيئة اختبار القبول'))),
        );
      }
      if (!snapshot.hasData) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      final services = snapshot.requireData;
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(services.database),
          dataProtectionProvider.overrideWithValue(services.dataProtection),
          startupPermissionServiceProvider.overrideWithValue(
            _GrantedStartupPermissionService(),
          ),
        ],
        child: const AttendanceApp(),
      );
    },
  );
}

class _GrantedStartupPermissionService extends StartupPermissionService {
  @override
  Future<List<StartupPermissionItem>> statuses() async => const [];

  @override
  Future<List<StartupPermissionItem>> requestAll() async => const [];
}
