import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/student.dart';
import '../services/data_protection_service.dart';

class DuplicateStudentException implements Exception {
  const DuplicateStudentException();
  @override
  String toString() => 'يوجد طالب مسجل بنفس السجل المدني.';
}

class StudentRepository {
  StudentRepository(this._database, this._protection);

  final AppDatabase _database;
  final DataProtectionService _protection;
  static const _uuid = Uuid();

  Future<List<Student>> getAll({
    String query = '',
    String? classId,
    bool includeInactive = false,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (!includeInactive) conditions.add("s.status = 'active'");
    if (classId != null) {
      conditions.add('s.class_id = ?');
      args.add(classId);
    }
    final cleaned = query.trim();
    if (cleaned.isNotEmpty) {
      conditions.add(
        '(s.name LIKE ? OR s.academic_number LIKE ? OR s.national_id_last4 LIKE ?)',
      );
      args.addAll(['%$cleaned%', '%$cleaned%', '%$cleaned%']);
    }
    final rows = await _database.db.rawQuery('''
      SELECT s.*, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
      ORDER BY g.sort_order, c.sort_order, s.name COLLATE NOCASE
    ''', args);
    return Future.wait(rows.map(_fromRow));
  }

  Future<Student?> getById(String id) async {
    final rows = await _database.db.rawQuery(
      '''
      SELECT s.*, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      WHERE s.id = ? LIMIT 1
    ''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Student?> getByBarcode(String token) async {
    final rows = await _database.db.rawQuery(
      '''
      SELECT s.*, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      WHERE s.barcode_token = ? AND s.status = 'active' LIMIT 1
    ''',
      [token.trim()],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<bool> nationalIdExists(
    String nationalId, {
    String? excludingId,
  }) async {
    final hash = await _protection.searchableHash(nationalId);
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS count FROM students WHERE national_id_hash = ? ${excludingId == null ? '' : 'AND id <> ?'}',
      [hash, if (excludingId != null) excludingId],
    );
    return (result.first['count'] as int) > 0;
  }

  Future<Student> create({
    required String name,
    required String nationalId,
    required String userId,
    String stage = '',
    String? gradeId,
    String? classId,
    String? academicNumber,
    String? photoPath,
    String? forcedId,
  }) async {
    final normalized = DataProtectionService.normalizeNationalId(nationalId);
    if (normalized.length < 4) {
      throw const FormatException('السجل المدني غير صالح.');
    }
    final now = DateTime.now().toUtc();
    final id = forcedId ?? _uuid.v4();
    final row = await _studentRow(
      id: id,
      name: name,
      nationalId: normalized,
      stage: stage,
      gradeId: gradeId,
      classId: classId,
      academicNumber: academicNumber,
      photoPath: photoPath,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _database.db.transaction((txn) async {
        await txn.insert(
          'students',
          row,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await _audit(txn, 'student_create', 'student', id, userId, null, {
          'name': name,
          'national_id': '***${normalized.substring(normalized.length - 4)}',
        });
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateStudentException();
      }
      rethrow;
    }
    return (await getById(id))!;
  }

  Future<void> update(Student student, {required String userId}) async {
    final normalized = DataProtectionService.normalizeNationalId(
      student.nationalId,
    );
    final old = await getById(student.id);
    if (old == null) throw StateError('الطالب غير موجود.');
    final encrypted = await _protection.encrypt(normalized);
    final hash = await _protection.searchableHash(normalized);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _database.db.transaction((txn) async {
        await txn.update(
          'students',
          {
            'name': student.name.trim(),
            'national_id_encrypted': encrypted,
            'national_id_hash': hash,
            'national_id_last4': normalized.substring(normalized.length - 4),
            'stage': student.stage.trim(),
            'grade_id': student.gradeId,
            'class_id': student.classId,
            'academic_number': _emptyToNull(student.academicNumber),
            'photo_path': _emptyToNull(student.photoPath),
            'status': student.status,
            'transfer_status': student.transferStatus,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [student.id],
        );
        await _audit(
          txn,
          'student_update',
          'student',
          student.id,
          userId,
          {'name': old.name, 'class_id': old.classId},
          {'name': student.name, 'class_id': student.classId},
        );
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateStudentException();
      }
      rethrow;
    }
  }

  Future<void> softDelete(String id, {required String userId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'students',
        {'status': 'inactive', 'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _audit(txn, 'student_deactivate', 'student', id, userId, null, {
        'status': 'inactive',
      });
    });
  }

  Future<void> transfer(
    String studentId,
    String newClassId, {
    required String userId,
  }) async {
    final student = await getById(studentId);
    if (student == null) throw StateError('الطالب غير موجود.');
    if (student.classId == newClassId) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('transfers', {
        'id': _uuid.v4(),
        'student_id': studentId,
        'old_class_id': student.classId,
        'new_class_id': newClassId,
        'transferred_at': now,
        'transferred_by': userId,
      });
      await txn.update(
        'students',
        {
          'class_id': newClassId,
          'transfer_status': 'transferred',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [studentId],
      );
      await _audit(
        txn,
        'student_transfer',
        'student',
        studentId,
        userId,
        {'class_id': student.classId},
        {'class_id': newClassId},
      );
    });
  }

  Future<Map<String, Object?>> _studentRow({
    required String id,
    required String name,
    required String nationalId,
    required String stage,
    required String? gradeId,
    required String? classId,
    required String? academicNumber,
    required String? photoPath,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    return {
      'id': id,
      'name': name.trim(),
      'national_id_encrypted': await _protection.encrypt(nationalId),
      'national_id_hash': await _protection.searchableHash(nationalId),
      'national_id_last4': nationalId.substring(nationalId.length - 4),
      'stage': stage.trim(),
      'grade_id': gradeId,
      'class_id': classId,
      'academic_number': _emptyToNull(academicNumber),
      'barcode_token': _protection.newBarcodeToken(),
      'photo_path': _emptyToNull(photoPath),
      'status': 'active',
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Future<Student> _fromRow(Map<String, Object?> row) async {
    return Student(
      id: row['id'] as String,
      name: row['name'] as String,
      nationalId: await _protection.decrypt(
        row['national_id_encrypted'] as String,
      ),
      barcodeToken: row['barcode_token'] as String,
      stage: row['stage'] as String? ?? '',
      gradeId: row['grade_id'] as String?,
      gradeName: row['grade_name'] as String?,
      classId: row['class_id'] as String?,
      className: row['class_name'] as String?,
      academicNumber: row['academic_number'] as String?,
      photoPath: row['photo_path'] as String?,
      status: row['status'] as String,
      transferStatus: row['transfer_status'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.parse(row['deleted_at'] as String),
    );
  }

  static Future<void> _audit(
    DatabaseExecutor db,
    String action,
    String entityType,
    String? entityId,
    String? userId,
    Object? oldValue,
    Object? newValue,
  ) {
    return db
        .insert('audit_logs', {
          'action': action,
          'entity_type': entityType,
          'entity_id': entityId,
          'user_id': userId,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'old_value': oldValue == null ? null : jsonEncode(oldValue),
          'new_value': newValue == null ? null : jsonEncode(newValue),
        })
        .then((_) {});
  }

  static String? _emptyToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
