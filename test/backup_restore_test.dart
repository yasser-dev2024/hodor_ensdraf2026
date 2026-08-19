import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
import 'package:morning_student_attendance/services/backup_service.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late PathProviderPlatform originalPathProvider;
  late AppDatabase database;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('attendance-backup-test-');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    FlutterSecureStorage.setMockInitialValues({});

    final databasePath = p.join(root.path, 'live.sqlite');
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(db);
    await db.execute('PRAGMA user_version = ${AppDatabase.schemaVersion}');
    database = AppDatabase(db, path: databasePath);
  });

  tearDown(() async {
    if (database.db.isOpen) await database.close();
    PathProviderPlatform.instance = originalPathProvider;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('ينشئ نسخة مشفرة ويستعيد البيانات والمفتاح دون فقد', () async {
    final protection = DataProtectionService.forTesting(
      List<int>.generate(32, (index) => index + 1),
    );
    final auth = AuthRepository(database, protection);
    final students = StudentRepository(database, protection);
    final manager = await auth.createInitialManager(
      name: 'مدير النسخ',
      pin: '837294',
    );
    final original = await students.create(
      name: 'طالب محفوظ في النسخة',
      nationalId: '1087654321',
      userId: manager.id,
    );

    final service = BackupService(database, protection);
    final backup = await service.createBackup(password: 'Backup@2026');
    expect(await backup.exists(), isTrue);
    expect(
      String.fromCharCodes(await backup.readAsBytes()),
      isNot(contains('1087654321')),
    );

    await students.create(
      name: 'طالب أضيف بعد النسخة',
      nationalId: '1098765432',
      userId: manager.id,
    );
    expect(await students.getAll(), hasLength(2));

    final safety = await service.restoreBackup(
      backupPath: backup.path,
      password: 'Backup@2026',
    );
    expect(await safety.exists(), isTrue);
    expect(
      (await database.db.rawQuery(
        'PRAGMA integrity_check',
      )).single.values.single,
      'ok',
    );

    final restored = await StudentRepository(database, protection).getAll();
    expect(restored, hasLength(1));
    expect(restored.single.id, original.id);
    expect(restored.single.nationalId, '1087654321');
    expect(
      await database.db.query('audit_logs', where: "action = 'backup_restore'"),
      hasLength(1),
    );
  });

  test('يرفض كلمة المرور الخاطئة ويبقي البيانات الحالية سليمة', () async {
    final protection = DataProtectionService.forTesting(
      List<int>.filled(32, 7),
    );
    final auth = AuthRepository(database, protection);
    final students = StudentRepository(database, protection);
    final manager = await auth.createInitialManager(
      name: 'مدير السلامة',
      pin: '729184',
    );
    await students.create(
      name: 'طالب لا يفقد',
      nationalId: '1077777777',
      userId: manager.id,
    );
    final service = BackupService(database, protection);
    final backup = await service.createBackup(password: 'Correct@2026');

    await expectLater(
      service.restoreBackup(backupPath: backup.path, password: 'Wrong@2026'),
      throwsA(isA<FormatException>()),
    );
    expect(await students.getAll(), hasLength(1));
    expect(
      (await database.db.rawQuery(
        'PRAGMA integrity_check',
      )).single.values.single,
      'ok',
    );
  });
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final directory = Directory(p.join(root, 'documents'));
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    final directory = Directory(p.join(root, 'temporary'));
    await directory.create(recursive: true);
    return directory.path;
  }
}
