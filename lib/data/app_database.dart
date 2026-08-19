import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase(this.db, {this.path});

  Database db;
  final String? path;
  static const schemaVersion = 2;

  static Future<AppDatabase> open() async {
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, 'morning_attendance.db'),
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // journal_mode returns a result row, so Android's SQLite driver
        // requires rawQuery instead of execute (notably on Android 16).
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: _upgradeSchema,
    );
    return AppDatabase(database, path: p.join(root, 'morning_attendance.db'));
  }

  static Future<void> createSchemaForTesting(Database db) => _createSchema(db);

  static Future<void> upgradeSchemaForTesting(
    Database db,
    int oldVersion,
    int newVersion,
  ) => _upgradeSchema(db, oldVersion, newVersion);

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE users ADD COLUMN password_hash TEXT');
        await txn.execute('ALTER TABLE users ADD COLUMN password_salt TEXT');
        await txn.execute(
          'ALTER TABLE users ADD COLUMN failed_attempts INTEGER NOT NULL DEFAULT 0',
        );
        await txn.execute('ALTER TABLE users ADD COLUMN locked_until TEXT');
        await txn.execute(
          'ALTER TABLE users ADD COLUMN biometric_enabled INTEGER NOT NULL DEFAULT 0',
        );
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS report_archives (
            id TEXT PRIMARY KEY,
            report_type TEXT NOT NULL,
            period_start TEXT NOT NULL,
            period_end TEXT NOT NULL,
            scope_type TEXT NOT NULL,
            scope_id TEXT,
            file_path TEXT NOT NULL,
            created_at TEXT NOT NULL,
            created_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
          )
        ''');
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_transfers_student ON transfers(student_id, transferred_at)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_report_archives_period ON report_archives(report_type, period_start, period_end)',
        );
      });
    }
  }

  static Future<void> _createSchema(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE grades (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        CREATE TABLE classes (
          id TEXT PRIMARY KEY,
          grade_id TEXT NOT NULL REFERENCES grades(id) ON DELETE RESTRICT,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          UNIQUE(grade_id, name)
        )
      ''');
      await txn.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          role TEXT NOT NULL,
          pin_hash TEXT NOT NULL,
          pin_salt TEXT NOT NULL,
          password_hash TEXT,
          password_salt TEXT,
          failed_attempts INTEGER NOT NULL DEFAULT 0,
          locked_until TEXT,
          biometric_enabled INTEGER NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          last_login_at TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE students (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          national_id_encrypted TEXT NOT NULL,
          national_id_hash TEXT NOT NULL UNIQUE,
          national_id_last4 TEXT NOT NULL,
          stage TEXT NOT NULL DEFAULT '',
          grade_id TEXT REFERENCES grades(id) ON DELETE RESTRICT,
          class_id TEXT REFERENCES classes(id) ON DELETE RESTRICT,
          academic_number TEXT,
          barcode_token TEXT NOT NULL UNIQUE,
          photo_path TEXT,
          status TEXT NOT NULL DEFAULT 'active',
          transfer_status TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE attendance (
          id TEXT PRIMARY KEY,
          student_id TEXT NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
          status TEXT NOT NULL CHECK(status IN ('present','absent','excused')),
          attendance_date TEXT NOT NULL,
          recorded_at TEXT NOT NULL,
          recorded_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
          class_id_snapshot TEXT,
          reason TEXT,
          note TEXT,
          receiver_name TEXT,
          departure_at TEXT,
          updated_at TEXT NOT NULL,
          UNIQUE(student_id, attendance_date)
        )
      ''');
      await txn.execute('''
        CREATE TABLE transfers (
          id TEXT PRIMARY KEY,
          student_id TEXT NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
          old_class_id TEXT REFERENCES classes(id) ON DELETE RESTRICT,
          new_class_id TEXT NOT NULL REFERENCES classes(id) ON DELETE RESTRICT,
          transferred_at TEXT NOT NULL,
          transferred_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
        )
      ''');
      await txn.execute('''
        CREATE TABLE audit_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT,
          user_id TEXT,
          occurred_at TEXT NOT NULL,
          old_value TEXT,
          new_value TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE closed_days (
          attendance_date TEXT PRIMARY KEY,
          closed_at TEXT NOT NULL,
          closed_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
          snapshot_json TEXT NOT NULL,
          reopened_at TEXT,
          reopened_by TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE school_days (
          day TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          note TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        CREATE TABLE saved_mappings (
          normalized_header TEXT PRIMARY KEY,
          target_field TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        CREATE TABLE report_archives (
          id TEXT PRIMARY KEY,
          report_type TEXT NOT NULL,
          period_start TEXT NOT NULL,
          period_end TEXT NOT NULL,
          scope_type TEXT NOT NULL,
          scope_id TEXT,
          file_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          created_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
        )
      ''');
      await txn.execute('CREATE INDEX idx_students_name ON students(name)');
      await txn.execute(
        'CREATE INDEX idx_students_class_id ON students(class_id)',
      );
      await txn.execute(
        'CREATE INDEX idx_students_national_id_hash ON students(national_id_hash)',
      );
      await txn.execute(
        'CREATE INDEX idx_students_barcode_token ON students(barcode_token)',
      );
      await txn.execute(
        'CREATE INDEX idx_attendance_student_id ON attendance(student_id)',
      );
      await txn.execute(
        'CREATE INDEX idx_attendance_date ON attendance(attendance_date)',
      );
      await txn.execute(
        'CREATE INDEX idx_attendance_class_date ON attendance(class_id_snapshot, attendance_date)',
      );
      await txn.execute(
        'CREATE INDEX idx_transfers_student ON transfers(student_id, transferred_at)',
      );
      await txn.execute(
        'CREATE INDEX idx_report_archives_period ON report_archives(report_type, period_start, period_end)',
      );
    });
  }

  Future<void> close() => db.close();
}
