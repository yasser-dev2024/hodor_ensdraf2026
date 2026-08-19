import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/app_user.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AuthRepository auth;

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(db);
    database = AppDatabase(db);
    auth = AuthRepository(
      database,
      DataProtectionService.forTesting(
        List<int>.generate(32, (index) => index),
      ),
    );
  });

  tearDown(() => database.close());

  test('لا ينشئ مديرًا سريًا ويطلب إعداد المدير أول مرة', () async {
    expect(await auth.needsInitialSetup(), isTrue);
    expect(await auth.getUsers(), isEmpty);

    final manager = await auth.setupInitialManager(
      name: 'مدير المدرسة',
      password: 'مدير@2026آمن',
    );

    expect(manager.role, UserRole.manager);
    expect(await auth.needsInitialSetup(), isFalse);
    expect(await auth.getUsers(), hasLength(1));
    expect(
      (await auth.authenticate(
        userId: manager.id,
        secret: 'مدير@2026آمن',
        kind: CredentialKind.password,
      )).isSuccess,
      isTrue,
    );
  });

  test('يدعم PIN وكلمة المرور المشفرين للمستخدم نفسه', () async {
    final manager = await auth.setupInitialManager(
      name: 'مدير المدرسة',
      pin: '873421',
      password: 'مدير@2026آمن',
    );
    final employee = await auth.createUser(
      name: 'مسؤول الحضور',
      pin: '739184',
      password: 'حضور@2026آمن',
      role: UserRole.attendanceOfficer,
      actorId: manager.id,
    );

    expect(
      (await auth.authenticate(
        userId: employee.id,
        secret: '739184',
        kind: CredentialKind.pin,
      )).user?.role,
      UserRole.attendanceOfficer,
    );
    expect(
      (await auth.authenticate(
        userId: employee.id,
        secret: 'حضور@2026آمن',
        kind: CredentialKind.password,
      )).isSuccess,
      isTrue,
    );
  });

  test('يقفل الحساب مؤقتًا بعد خمس محاولات فاشلة', () async {
    final manager = await auth.setupInitialManager(
      name: 'مدير المدرسة',
      pin: '873421',
      password: 'مدير@2026آمن',
    );

    AuthenticationResult? result;
    for (var attempt = 0; attempt < 5; attempt++) {
      result = await auth.authenticate(
        userId: manager.id,
        secret: '000000',
        kind: CredentialKind.pin,
      );
    }

    expect(result?.lockedUntil, isNotNull);
    final correctWhileLocked = await auth.authenticate(
      userId: manager.id,
      secret: '873421',
      kind: CredentialKind.pin,
    );
    expect(correctWhileLocked.isSuccess, isFalse);
    expect(correctWhileLocked.lockedUntil, isNotNull);
  });

  test('يرفض PIN وكلمة المرور الضعيفين والتكرار', () async {
    final manager = await auth.setupInitialManager(
      name: 'مدير المدرسة',
      pin: '873421',
      password: 'مدير@2026آمن',
    );
    await auth.createUser(
      name: 'ناصر محمد',
      pin: '739184',
      password: 'ناصر@2026آمن',
      role: UserRole.attendanceOfficer,
      actorId: manager.id,
    );

    expect(
      () => auth.createUser(
        name: 'ناصر محمد',
        pin: '814739',
        password: 'موظف@2026آمن',
        role: UserRole.attendanceOfficer,
        actorId: manager.id,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => auth.createUser(
        name: 'مستخدم ضعيف',
        pin: '123456',
        password: '1234567890',
        role: UserRole.studentAffairs,
        actorId: manager.id,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
