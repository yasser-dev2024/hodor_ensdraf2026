import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/school_class.dart';

class ClassRepository {
  ClassRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<List<SchoolGrade>> getGrades() async {
    final rows = await _database.db.query(
      'grades',
      orderBy: 'sort_order, name',
    );
    return rows
        .map(
          (row) => SchoolGrade(
            id: row['id'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
          ),
        )
        .toList();
  }

  Future<List<SchoolClass>> getClasses({String? gradeId}) async {
    final rows = await _database.db.rawQuery(
      '''
      SELECT c.*, g.name AS grade_name
      FROM classes c JOIN grades g ON g.id = c.grade_id
      ${gradeId == null ? '' : 'WHERE c.grade_id = ?'}
      ORDER BY g.sort_order, c.sort_order, c.name
    ''',
      [if (gradeId != null) gradeId],
    );
    return rows
        .map(
          (row) => SchoolClass(
            id: row['id'] as String,
            gradeId: row['grade_id'] as String,
            gradeName: row['grade_name'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
          ),
        )
        .toList();
  }

  Future<String> addGrade(String name, {required String userId}) async {
    final id = _uuid.v4();
    final count =
        (await _database.db.rawQuery(
              'SELECT COUNT(*) AS count FROM grades',
            )).first['count']
            as int;
    await _database.db.transaction((txn) async {
      await txn.insert('grades', {
        'id': id,
        'name': name.trim(),
        'sort_order': count,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.insert(
        'audit_logs',
        _audit('grade_create', 'grade', id, userId, {'name': name.trim()}),
      );
    });
    return id;
  }

  Future<String> addClass(
    String gradeId,
    String name, {
    required String userId,
  }) async {
    final id = _uuid.v4();
    final count =
        (await _database.db.rawQuery(
              'SELECT COUNT(*) AS count FROM classes WHERE grade_id = ?',
              [gradeId],
            )).first['count']
            as int;
    await _database.db.transaction((txn) async {
      await txn.insert('classes', {
        'id': id,
        'grade_id': gradeId,
        'name': name.trim(),
        'sort_order': count,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.insert(
        'audit_logs',
        _audit('class_create', 'class', id, userId, {
          'name': name.trim(),
          'grade_id': gradeId,
        }),
      );
    });
    return id;
  }

  Future<SchoolGrade> ensureGrade(
    String gradeName, {
    required String userId,
  }) async {
    final normalized = gradeName.trim();
    var grade = (await getGrades())
        .where((item) => item.name.trim() == normalized)
        .firstOrNull;
    if (grade != null) return grade;
    final id = await addGrade(normalized, userId: userId);
    return SchoolGrade(id: id, name: normalized, sortOrder: 999);
  }

  Future<SchoolClass> ensureClass(
    String gradeName,
    String className, {
    required String userId,
  }) async {
    final grade = await ensureGrade(gradeName, userId: userId);
    var schoolClass = (await getClasses(
      gradeId: grade.id,
    )).where((c) => c.name.trim() == className.trim()).firstOrNull;
    if (schoolClass == null) {
      final id = await addClass(grade.id, className, userId: userId);
      schoolClass = SchoolClass(
        id: id,
        gradeId: grade.id,
        gradeName: grade.name,
        name: className.trim(),
        sortOrder: 999,
      );
    }
    return schoolClass;
  }

  Future<void> deleteClass(String id, {required String userId}) async {
    await _database.db.transaction((txn) async {
      await txn.delete('classes', where: 'id = ?', whereArgs: [id]);
      await txn.insert(
        'audit_logs',
        _audit('class_delete', 'class', id, userId, null),
      );
    });
  }

  Future<void> renameGrade(
    String id,
    String name, {
    required String userId,
  }) async {
    await _database.db.transaction((txn) async {
      await txn.update(
        'grades',
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit('grade_update', 'grade', id, userId, {'name': name.trim()}),
      );
    });
  }

  Future<void> renameClass(
    String id,
    String name, {
    required String userId,
  }) async {
    await _database.db.transaction((txn) async {
      await txn.update(
        'classes',
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit('class_update', 'class', id, userId, {'name': name.trim()}),
      );
    });
  }

  Future<void> deleteGrade(String id, {required String userId}) async {
    await _database.db.transaction((txn) async {
      await txn.delete('grades', where: 'id = ?', whereArgs: [id]);
      await txn.insert(
        'audit_logs',
        _audit('grade_delete', 'grade', id, userId, null),
      );
    });
  }

  Future<void> updateGradeOrder(String id, int sortOrder) => _database.db
      .update(
        'grades',
        {'sort_order': sortOrder},
        where: 'id = ?',
        whereArgs: [id],
      )
      .then((_) {});

  Future<void> updateClassOrder(String id, int sortOrder) => _database.db
      .update(
        'classes',
        {'sort_order': sortOrder},
        where: 'id = ?',
        whereArgs: [id],
      )
      .then((_) {});

  static Map<String, Object?> _audit(
    String action,
    String type,
    String id,
    String userId,
    Object? value,
  ) => {
    'action': action,
    'entity_type': type,
    'entity_id': id,
    'user_id': userId,
    'occurred_at': DateTime.now().toUtc().toIso8601String(),
    'new_value': value == null ? null : jsonEncode(value),
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
