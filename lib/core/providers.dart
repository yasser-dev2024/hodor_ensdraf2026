import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/app_database.dart';
import '../models/app_user.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/class_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/backup_service.dart';
import '../services/data_protection_service.dart';
import '../services/image_storage_service.dart';
import '../services/import_service.dart';
import '../services/report_service.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final dataProtectionProvider = Provider<DataProtectionService>(
  (ref) => throw UnimplementedError(),
);

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(
    ref.watch(databaseProvider),
    ref.watch(dataProtectionProvider),
  ),
);
final classRepositoryProvider = Provider<ClassRepository>(
  (ref) => ClassRepository(ref.watch(databaseProvider)),
);
final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(databaseProvider)),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(databaseProvider),
    ref.watch(dataProtectionProvider),
  ),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);
final imageStorageProvider = Provider<ImageStorageService>(
  (ref) => ImageStorageService(),
);
final reportServiceProvider = Provider<ReportService>((ref) => ReportService());
final importServiceProvider = Provider<StudentImportService>(
  (ref) => StudentImportService(
    database: ref.watch(databaseProvider),
    students: ref.watch(studentRepositoryProvider),
    classes: ref.watch(classRepositoryProvider),
  ),
);
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(databaseProvider),
    ref.watch(dataProtectionProvider),
  ),
);

final currentUserProvider = StateProvider<AppUser?>((ref) => null);
final dataRevisionProvider = StateProvider<int>((ref) => 0);

void refreshData(WidgetRef ref) {
  ref.read(dataRevisionProvider.notifier).state++;
}
