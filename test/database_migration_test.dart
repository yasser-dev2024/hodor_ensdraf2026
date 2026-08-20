import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('يرقي قاعدة v1 إلى v2 دون فقد المستخدمين', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_salt TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        last_login_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transfers (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        transferred_at TEXT NOT NULL
      )
    ''');
    await db.insert('users', {
      'id': 'legacy-manager',
      'name': 'إدارة النظام',
      'role': 'manager',
      'pin_hash': 'legacy-hash',
      'pin_salt': 'legacy-salt',
      'active': 1,
      'created_at': DateTime.utc(2026).toIso8601String(),
    });

    await AppDatabase.upgradeSchemaForTesting(db, 1, 2);

    final columns = await db.rawQuery('PRAGMA table_info(users)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(<String>{
        'password_hash',
        'password_salt',
        'failed_attempts',
        'locked_until',
        'biometric_enabled',
      }),
    );
    expect(await db.query('users'), hasLength(1));
    expect((await db.query('users')).single['id'], 'legacy-manager');
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'report_archives'",
      ),
      isNotEmpty,
    );
  });

  test('يرقي قاعدة v2 إلى v3 ويحفظ العام الحالي في سجل الأعوام', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE grades (id TEXT PRIMARY KEY)
    ''');
    await db.execute('''
      CREATE TABLE classes (id TEXT PRIMARY KEY)
    ''');
    await db.execute('''
      CREATE TABLE students (id TEXT PRIMARY KEY)
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('settings', {
      'key': 'academic_year',
      'value': '1447 / 1448 هـ',
      'updated_at': '2026-08-20T05:00:00.000Z',
    });

    await AppDatabase.upgradeSchemaForTesting(db, 2, 3);

    final years = await db.query('academic_years');
    expect(years, hasLength(1));
    expect(years.single['label'], '1447 / 1448 هـ');
    expect(years.single['status'], 'current');
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'student_graduations'",
      ),
      isNotEmpty,
    );
  });
}
