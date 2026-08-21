import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
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
    await _requireManager(userId);
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
    await _requireManager(userId);
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

  Future<DeletionImpact> classDeletionImpact(String id) async {
    final rows = await _database.db.query(
      'classes',
      columns: const ['id', 'grade_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('الفصل غير موجود.');
    return _deletionImpact(
      _database.db,
      _DeletionScope.classId(id, rows.single['grade_id'] as String),
    );
  }

  Future<DeletionImpact> gradeDeletionImpact(String id) async {
    final rows = await _database.db.query(
      'grades',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('الصف غير موجود.');
    return _deletionImpact(_database.db, _DeletionScope.gradeId(id));
  }

  Future<DeletionImpact> deleteClass(
    String id, {
    required String userId,
  }) async {
    await _requireManager(userId);
    final work = await _database.db.transaction((txn) async {
      final current = await txn.query(
        'classes',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty) throw StateError('الفصل غير موجود.');
      final scope = _DeletionScope.classId(
        id,
        current.single['grade_id'] as String,
      );
      return _hardDeleteScope(
        txn,
        scope,
        userId: userId,
        auditAction: 'class_hard_delete',
        auditType: 'class',
        auditId: id,
        deletedLabel: current.single['name'] as String,
      );
    });
    await _deleteFiles(work.filePaths);
    return work.impact;
  }

  Future<void> renameGrade(
    String id,
    String name, {
    required String userId,
  }) async {
    await _requireManager(userId);
    await _database.db.transaction((txn) async {
      final current = await txn.query(
        'grades',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.update(
        'grades',
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit(
          'grade_update',
          'grade',
          id,
          userId,
          {'name': name.trim()},
          oldValue: current.isEmpty ? null : current.first,
        ),
      );
    });
  }

  Future<void> renameClass(
    String id,
    String name, {
    required String userId,
  }) async {
    await _requireManager(userId);
    await _database.db.transaction((txn) async {
      final current = await txn.query(
        'classes',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.update(
        'classes',
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit(
          'class_update',
          'class',
          id,
          userId,
          {'name': name.trim()},
          oldValue: current.isEmpty ? null : current.first,
        ),
      );
    });
  }

  Future<DeletionImpact> deleteGrade(
    String id, {
    required String userId,
  }) async {
    await _requireManager(userId);
    final work = await _database.db.transaction((txn) async {
      final current = await txn.query(
        'grades',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty) throw StateError('الصف غير موجود.');
      return _hardDeleteScope(
        txn,
        _DeletionScope.gradeId(id),
        userId: userId,
        auditAction: 'grade_hard_delete',
        auditType: 'grade',
        auditId: id,
        deletedLabel: current.single['name'] as String,
      );
    });
    await _deleteFiles(work.filePaths);
    return work.impact;
  }

  Future<_DeletionWork> _hardDeleteScope(
    Transaction txn,
    _DeletionScope scope, {
    required String userId,
    required String auditAction,
    required String auditType,
    required String auditId,
    required String deletedLabel,
  }) async {
    final impact = await _deletionImpact(txn, scope);
    final studentRows = await txn.query(
      'students',
      columns: const ['id', 'photo_path'],
      where: scope.studentWhere,
      whereArgs: scope.studentArgs,
    );
    final studentIds = studentRows.map((row) => row['id'] as String).toSet();
    final attendanceRows = await txn.query(
      'attendance',
      columns: const ['id', 'student_id', 'attendance_date'],
      where: scope.attendanceWhere,
      whereArgs: scope.attendanceArgs,
    );
    final attendanceIds = attendanceRows
        .map((row) => row['id'] as String)
        .toSet();
    final archiveRows = await txn.query(
      'report_archives',
      columns: const ['id', 'file_path'],
      where: scope.archiveWhere,
      whereArgs: scope.archiveArgs,
    );
    final archiveIds = archiveRows.map((row) => row['id'] as String).toSet();
    final filePaths = <String>{
      for (final row in studentRows)
        if ((row['photo_path'] as String?)?.trim().isNotEmpty ?? false)
          (row['photo_path'] as String).trim(),
      for (final row in archiveRows)
        if ((row['file_path'] as String?)?.trim().isNotEmpty ?? false)
          (row['file_path'] as String).trim(),
    };

    await _scrubClosedDaySnapshots(
      txn,
      deletedStudentIds: studentIds,
      deletedAttendanceRows: attendanceRows,
    );
    await _deleteAuditEntities(txn, {
      auditId,
      ...studentIds,
      ...attendanceIds,
      ...archiveIds,
    });
    await _deleteScopeAuditReferences(txn, scope);

    await txn.delete(
      'report_archives',
      where: scope.archiveWhere,
      whereArgs: scope.archiveArgs,
    );
    await txn.delete(
      'student_barcode_aliases',
      where:
          'student_id IN (SELECT id FROM students WHERE ${scope.studentWhere})',
      whereArgs: scope.studentArgs,
    );
    await txn.delete(
      'attendance',
      where: scope.attendanceWhere,
      whereArgs: scope.attendanceArgs,
    );
    await txn.delete(
      'transfers',
      where: scope.transferWhere,
      whereArgs: scope.transferArgs,
    );
    await txn.delete(
      'student_graduations',
      where: scope.graduationWhere,
      whereArgs: scope.graduationArgs,
    );
    await txn.delete(
      'students',
      where: scope.studentWhere,
      whereArgs: scope.studentArgs,
    );
    if (scope.classId case final classId?) {
      await txn.delete('classes', where: 'id = ?', whereArgs: [classId]);
      await _normalizeClassOrder(txn, scope.parentGradeId!);
    } else {
      await txn.delete(
        'classes',
        where: 'grade_id = ?',
        whereArgs: [scope.gradeId],
      );
      await txn.delete('grades', where: 'id = ?', whereArgs: [scope.gradeId]);
      await _normalizeGradeOrder(txn);
    }
    await txn.insert(
      'audit_logs',
      _audit(auditAction, auditType, auditId, userId, {
        'label': deletedLabel,
        'hard_delete': true,
        'classes': impact.classes,
        'students': impact.students,
        'attendance_records': impact.attendanceRecords,
        'transfer_records': impact.transferRecords,
        'graduation_records': impact.graduationRecords,
        'report_archives': impact.reportArchives,
      }),
    );
    return _DeletionWork(impact: impact, filePaths: filePaths);
  }

  Future<DeletionImpact> _deletionImpact(
    DatabaseExecutor db,
    _DeletionScope scope,
  ) async => DeletionImpact(
    classes: scope.classId == null
        ? await _count(
            db,
            'classes',
            where: 'grade_id = ?',
            args: [scope.gradeId],
          )
        : 1,
    students: await _count(
      db,
      'students',
      where: scope.studentWhere,
      args: scope.studentArgs,
    ),
    attendanceRecords: await _count(
      db,
      'attendance',
      where: scope.attendanceWhere,
      args: scope.attendanceArgs,
    ),
    transferRecords: await _count(
      db,
      'transfers',
      where: scope.transferWhere,
      args: scope.transferArgs,
    ),
    graduationRecords: await _count(
      db,
      'student_graduations',
      where: scope.graduationWhere,
      args: scope.graduationArgs,
    ),
    reportArchives: await _count(
      db,
      'report_archives',
      where: scope.archiveWhere,
      args: scope.archiveArgs,
    ),
  );

  static Future<int> _count(
    DatabaseExecutor db,
    String table, {
    required String where,
    required List<Object?> args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE $where',
      args,
    );
    return rows.single['count'] as int;
  }

  static Future<void> _scrubClosedDaySnapshots(
    DatabaseExecutor db, {
    required Set<String> deletedStudentIds,
    required List<Map<String, Object?>> deletedAttendanceRows,
  }) async {
    final removedByDay = <String, Set<String>>{};
    for (final row in deletedAttendanceRows) {
      final day = row['attendance_date'] as String;
      (removedByDay[day] ??= <String>{}).add(row['student_id'] as String);
    }
    final closedDays = await db.query(
      'closed_days',
      columns: const ['attendance_date', 'snapshot_json'],
    );
    for (final row in closedDays) {
      try {
        final day = row['attendance_date'] as String;
        final snapshot = Map<String, dynamic>.from(
          jsonDecode(row['snapshot_json'] as String) as Map,
        );
        final records = (snapshot['records'] as List? ?? const [])
            .whereType<Map>()
            .map((record) => Map<String, dynamic>.from(record))
            .toList();
        final dayIds = removedByDay[day] ?? const <String>{};
        final remaining = records.where((record) {
          final studentId = record['student_id'] as String?;
          return studentId == null ||
              (!deletedStudentIds.contains(studentId) &&
                  !dayIds.contains(studentId));
        }).toList();
        if (remaining.length == records.length) continue;
        final oldSummary = Map<String, dynamic>.from(
          snapshot['summary'] as Map? ?? const {},
        );
        final oldTotal =
            (oldSummary['total'] as num?)?.toInt() ?? records.length;
        final oldRegistered =
            (oldSummary['registered'] as num?)?.toInt() ?? records.length;
        final unregistered = oldTotal > oldRegistered
            ? oldTotal - oldRegistered
            : 0;
        int countStatus(String status) =>
            remaining.where((record) => record['status'] == status).length;
        snapshot['records'] = remaining;
        snapshot['summary'] = {
          'total': remaining.length + unregistered,
          'registered': remaining.length,
          'present': countStatus('present'),
          'absent': countStatus('absent'),
          'excused': countStatus('excused'),
        };
        final encoded = jsonEncode(snapshot);
        await db.update(
          'closed_days',
          {'snapshot_json': encoded},
          where: 'attendance_date = ?',
          whereArgs: [day],
        );
        await db.update(
          'audit_logs',
          {'new_value': encoded},
          where:
              "action = 'day_close' AND entity_type = 'attendance_day' AND entity_id = ?",
          whereArgs: [day],
        );
      } catch (_) {
        // لا نوقف الحذف بسبب لقطة قديمة تالفة؛ سجلاتها الحية تحذف أدناه.
      }
    }
  }

  static Future<void> _deleteAuditEntities(
    DatabaseExecutor db,
    Set<String> ids,
  ) async {
    final values = ids.where((id) => id.isNotEmpty).toList();
    for (var start = 0; start < values.length; start += 400) {
      final end = (start + 400 < values.length) ? start + 400 : values.length;
      final chunk = values.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.delete(
        'audit_logs',
        where: 'entity_id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  static Future<void> _deleteScopeAuditReferences(
    DatabaseExecutor db,
    _DeletionScope scope,
  ) async {
    if (scope.classId case final classId?) {
      await db.delete(
        'audit_logs',
        where:
            "entity_id LIKE ? OR COALESCE(old_value, '') LIKE ? OR COALESCE(new_value, '') LIKE ?",
        whereArgs: ['%:$classId', '%$classId%', '%$classId%'],
      );
      return;
    }
    final gradeId = scope.gradeId!;
    await db.rawDelete(
      '''
      DELETE FROM audit_logs
      WHERE COALESCE(old_value, '') LIKE ?
         OR COALESCE(new_value, '') LIKE ?
         OR EXISTS (
           SELECT 1 FROM classes c
           WHERE c.grade_id = ? AND (
             audit_logs.entity_id LIKE '%:' || c.id
             OR COALESCE(audit_logs.old_value, '') LIKE '%' || c.id || '%'
             OR COALESCE(audit_logs.new_value, '') LIKE '%' || c.id || '%'
           )
         )
      ''',
      ['%$gradeId%', '%$gradeId%', gradeId],
    );
  }

  static Future<void> _normalizeClassOrder(
    DatabaseExecutor db,
    String gradeId,
  ) async {
    final rows = await db.query(
      'classes',
      columns: const ['id'],
      where: 'grade_id = ?',
      whereArgs: [gradeId],
      orderBy: 'sort_order, name',
    );
    for (var index = 0; index < rows.length; index++) {
      await db.update(
        'classes',
        {'sort_order': index},
        where: 'id = ?',
        whereArgs: [rows[index]['id']],
      );
    }
  }

  static Future<void> _normalizeGradeOrder(DatabaseExecutor db) async {
    final rows = await db.query(
      'grades',
      columns: const ['id'],
      orderBy: 'sort_order, name',
    );
    for (var index = 0; index < rows.length; index++) {
      await db.update(
        'grades',
        {'sort_order': index},
        where: 'id = ?',
        whereArgs: [rows[index]['id']],
      );
    }
  }

  static Future<void> _deleteFiles(Set<String> paths) async {
    for (final path in paths) {
      try {
        final normalized = p.normalize(path);
        final managedParent = p.basename(p.dirname(normalized));
        if (managedParent != 'student_photos' &&
            managedParent != 'report_archive') {
          continue;
        }
        final file = File(normalized);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // بيانات قاعدة التطبيق حذفت بأمان؛ لا نفشل العملية بسبب ملف مفقود.
      }
    }
  }

  Future<void> updateGradeOrder(
    String id,
    int sortOrder, {
    required String userId,
  }) async {
    await _requireManager(userId);
    await _database.db.transaction((txn) async {
      final current = await txn.query(
        'grades',
        columns: ['sort_order'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty || current.first['sort_order'] == sortOrder) return;
      final oldOrder = current.first['sort_order'];
      await txn.update(
        'grades',
        {'sort_order': sortOrder},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit(
          'grade_reorder',
          'grade',
          id,
          userId,
          {'sort_order': sortOrder},
          oldValue: {'sort_order': oldOrder},
        ),
      );
    });
  }

  Future<void> updateClassOrder(
    String id,
    int sortOrder, {
    required String userId,
  }) async {
    await _requireManager(userId);
    await _database.db.transaction((txn) async {
      final current = await txn.query(
        'classes',
        columns: ['sort_order'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty || current.first['sort_order'] == sortOrder) return;
      final oldOrder = current.first['sort_order'];
      await txn.update(
        'classes',
        {'sort_order': sortOrder},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        'audit_logs',
        _audit(
          'class_reorder',
          'class',
          id,
          userId,
          {'sort_order': sortOrder},
          oldValue: {'sort_order': oldOrder},
        ),
      );
    });
  }

  static Map<String, Object?> _audit(
    String action,
    String type,
    String id,
    String userId,
    Object? value, {
    Object? oldValue,
  }) => {
    'action': action,
    'entity_type': type,
    'entity_id': id,
    'user_id': userId,
    'occurred_at': DateTime.now().toUtc().toIso8601String(),
    'old_value': oldValue == null ? null : jsonEncode(oldValue),
    'new_value': value == null ? null : jsonEncode(value),
  };

  Future<void> _requireManager(String userId) async {
    final rows = await _database.db.query(
      'users',
      columns: const ['role'],
      where: 'id = ? AND active = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['role'] != 'manager') {
      throw StateError('هذه العملية متاحة للمدير فقط.');
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class DeletionImpact {
  const DeletionImpact({
    required this.classes,
    required this.students,
    required this.attendanceRecords,
    required this.transferRecords,
    required this.graduationRecords,
    required this.reportArchives,
  });

  final int classes;
  final int students;
  final int attendanceRecords;
  final int transferRecords;
  final int graduationRecords;
  final int reportArchives;
}

class _DeletionWork {
  const _DeletionWork({required this.impact, required this.filePaths});

  final DeletionImpact impact;
  final Set<String> filePaths;
}

class _DeletionScope {
  const _DeletionScope._({this.gradeId, this.classId, this.parentGradeId});

  factory _DeletionScope.gradeId(String id) => _DeletionScope._(gradeId: id);

  factory _DeletionScope.classId(String id, String parentGradeId) =>
      _DeletionScope._(classId: id, parentGradeId: parentGradeId);

  final String? gradeId;
  final String? classId;
  final String? parentGradeId;

  String get studentWhere => classId == null
      ? '(grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?))'
      : 'class_id = ?';
  List<Object?> get studentArgs =>
      classId == null ? [gradeId, gradeId] : [classId];

  String get attendanceWhere => classId == null
      ? 'student_id IN (SELECT id FROM students WHERE grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?)) OR class_id_snapshot IN (SELECT id FROM classes WHERE grade_id = ?)'
      : 'student_id IN (SELECT id FROM students WHERE class_id = ?) OR class_id_snapshot = ?';
  List<Object?> get attendanceArgs =>
      classId == null ? [gradeId, gradeId, gradeId] : [classId, classId];

  String get transferWhere => classId == null
      ? 'student_id IN (SELECT id FROM students WHERE grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?)) OR old_class_id IN (SELECT id FROM classes WHERE grade_id = ?) OR new_class_id IN (SELECT id FROM classes WHERE grade_id = ?)'
      : 'student_id IN (SELECT id FROM students WHERE class_id = ?) OR old_class_id = ? OR new_class_id = ?';
  List<Object?> get transferArgs => classId == null
      ? [gradeId, gradeId, gradeId, gradeId]
      : [classId, classId, classId];

  String get graduationWhere => classId == null
      ? 'student_id IN (SELECT id FROM students WHERE grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?)) OR grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?)'
      : 'student_id IN (SELECT id FROM students WHERE class_id = ?) OR class_id = ?';
  List<Object?> get graduationArgs => classId == null
      ? [gradeId, gradeId, gradeId, gradeId]
      : [classId, classId];

  String get archiveWhere => classId == null
      ? "(scope_type = 'grade' AND scope_id = ?) OR (scope_type = 'schoolClass' AND scope_id IN (SELECT id FROM classes WHERE grade_id = ?)) OR (scope_type = 'student' AND scope_id IN (SELECT id FROM students WHERE grade_id = ? OR class_id IN (SELECT id FROM classes WHERE grade_id = ?)))"
      : "(scope_type = 'schoolClass' AND scope_id = ?) OR (scope_type = 'student' AND scope_id IN (SELECT id FROM students WHERE class_id = ?))";
  List<Object?> get archiveArgs => classId == null
      ? [gradeId, gradeId, gradeId, gradeId]
      : [classId, classId];
}
