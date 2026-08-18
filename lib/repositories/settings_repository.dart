import '../data/app_database.dart';
import 'package:sqflite/sqflite.dart';

class SettingsRepository {
  SettingsRepository(this._database);
  final AppDatabase _database;

  Future<String?> get(String key) async {
    final rows = await _database.db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<Map<String, String>> getAll() async {
    final rows = await _database.db.query('settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> set(String key, String value) async {
    await _database.db.rawInsert(
      '''
      INSERT INTO settings(key, value, updated_at) VALUES(?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
    ''',
      [key, value.trim(), DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<List<Map<String, Object?>>> getSchoolDays() =>
      _database.db.query('school_days', orderBy: 'day DESC');

  Future<void> setSchoolDay(String day, String type, String? note) async {
    await _database.db.insert('school_days', {
      'day': day,
      'type': type,
      'note': note,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSchoolDay(String day) => _database.db
      .delete('school_days', where: 'day = ?', whereArgs: [day])
      .then((_) {});
}
