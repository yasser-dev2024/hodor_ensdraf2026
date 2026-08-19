import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/student.dart';
import '../models/student_transfer.dart';
import '../services/data_protection_service.dart';

class DuplicateStudentException implements Exception {
  const DuplicateStudentException();
  @override
  String toString() => 'يوجد طالب مسجل بنفس السجل المدني.';
}

class GradePromotionResult {
  const GradePromotionResult({required this.promoted});

  final int promoted;
}

class StudentCreateDraft {
  const StudentCreateDraft({
    required this.name,
    required this.nationalId,
    this.stage = '',
    this.gradeId,
    this.classId,
    this.academicNumber,
    this.photoPath,
  });

  final String name;
  final String nationalId;
  final String stage;
  final String? gradeId;
  final String? classId;
  final String? academicNumber;
  final String? photoPath;
}

class BulkStudentCreateResult {
  const BulkStudentCreateResult({
    required this.created,
    required this.duplicates,
  });

  final int created;
  final int duplicates;
}

class StudentRepository {
  StudentRepository(this._database, this._protection);

  final AppDatabase _database;
  final DataProtectionService _protection;
  static const _uuid = Uuid();

  Future<List<Student>> getAll({
    String query = '',
    String? gradeId,
    String? classId,
    bool includeInactive = false,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (!includeInactive) conditions.add("s.status = 'active'");
    if (classId != null) {
      conditions.add('s.class_id = ?');
      args.add(classId);
    } else if (gradeId != null) {
      conditions.add('s.grade_id = ?');
      args.add(gradeId);
    }
    final rawQuery = query.trim();
    final cleaned = rawQuery.length > 120
        ? rawQuery.substring(0, 120)
        : rawQuery;
    if (cleaned.isNotEmpty) {
      final normalizedId = DataProtectionService.normalizeNationalId(cleaned);
      final searchConditions = <String>[
        's.name LIKE ?',
        's.academic_number LIKE ?',
        's.national_id_last4 LIKE ?',
        'g.name LIKE ?',
        'c.name LIKE ?',
        's.barcode_token = ?',
      ];
      args.addAll([
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        cleaned,
      ]);
      // البحث بالسجل الكامل يتم بواسطة Hash ثابت، ولا يفك تشفير سجلات الطلاب.
      if (normalizedId.length >= 4 && RegExp(r'^\d+$').hasMatch(normalizedId)) {
        searchConditions.add('s.national_id_hash = ?');
        args.add(await _protection.searchableHash(normalizedId));
      }
      conditions.add('(${searchConditions.join(' OR ')})');
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
    final cleaned = token.trim();
    if (!RegExp(r'^stu_[A-Za-z0-9_-]{20,80}$').hasMatch(cleaned)) return null;
    final rows = await _database.db.rawQuery(
      '''
      SELECT s.*, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      WHERE s.barcode_token = ? AND s.status = 'active' LIMIT 1
    ''',
      [cleaned],
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

  Future<Set<String>> existingNationalIds(Iterable<String> nationalIds) async {
    final normalized = nationalIds
        .map(DataProtectionService.normalizeNationalId)
        .where((value) => RegExp(r'^\d{10}$').hasMatch(value))
        .toSet()
        .toList();
    final hashToNationalId = <String, String>{};
    const cryptoBatchSize = 256;
    for (
      var offset = 0;
      offset < normalized.length;
      offset += cryptoBatchSize
    ) {
      final end = (offset + cryptoBatchSize).clamp(0, normalized.length);
      final batch = normalized.sublist(offset, end);
      final hashes = await Future.wait(batch.map(_protection.searchableHash));
      for (var index = 0; index < batch.length; index++) {
        hashToNationalId[hashes[index]] = batch[index];
      }
    }
    final existing = <String>{};
    final hashes = hashToNationalId.keys.toList();
    const sqliteBatchSize = 400;
    for (var offset = 0; offset < hashes.length; offset += sqliteBatchSize) {
      final end = (offset + sqliteBatchSize).clamp(0, hashes.length);
      final batch = hashes.sublist(offset, end);
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await _database.db.rawQuery(
        'SELECT national_id_hash FROM students WHERE national_id_hash IN ($placeholders)',
        batch,
      );
      for (final row in rows) {
        final nationalId = hashToNationalId[row['national_id_hash'] as String];
        if (nationalId != null) existing.add(nationalId);
      }
    }
    return existing;
  }

  Future<BulkStudentCreateResult> createBatch(
    List<StudentCreateDraft> drafts, {
    required String userId,
  }) async {
    await _requireManager(userId);
    if (drafts.isEmpty) {
      return const BulkStudentCreateResult(created: 0, duplicates: 0);
    }
    for (final draft in drafts) {
      _validateStudentInput(
        name: draft.name,
        nationalId: DataProtectionService.normalizeNationalId(draft.nationalId),
        stage: draft.stage,
        academicNumber: draft.academicNumber,
      );
    }
    final prepared = <Map<String, Object?>>[];
    const preparationBatchSize = 128;
    for (
      var offset = 0;
      offset < drafts.length;
      offset += preparationBatchSize
    ) {
      final end = (offset + preparationBatchSize).clamp(0, drafts.length);
      final batch = drafts.sublist(offset, end);
      prepared.addAll(
        await Future.wait(
          batch.map((draft) {
            final now = DateTime.now().toUtc();
            return _studentRow(
              id: _uuid.v4(),
              name: draft.name,
              nationalId: DataProtectionService.normalizeNationalId(
                draft.nationalId,
              ),
              stage: draft.stage,
              gradeId: draft.gradeId,
              classId: draft.classId,
              academicNumber: draft.academicNumber,
              photoPath: draft.photoPath,
              createdAt: now,
              updatedAt: now,
            );
          }),
        ),
      );
    }
    var created = 0;
    var duplicates = 0;
    await _database.db.transaction((txn) async {
      for (final row in prepared) {
        final inserted = await txn.insert(
          'students',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (inserted == 0) {
          duplicates++;
          continue;
        }
        created++;
        final last4 = row['national_id_last4'] as String;
        await _audit(
          txn,
          'student_create',
          'student',
          row['id'] as String,
          userId,
          null,
          {'name': row['name'], 'national_id': '***$last4', 'batch': true},
        );
      }
    });
    return BulkStudentCreateResult(created: created, duplicates: duplicates);
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
    await _requireManager(userId);
    final normalized = DataProtectionService.normalizeNationalId(nationalId);
    _validateStudentInput(
      name: name,
      nationalId: normalized,
      stage: stage,
      academicNumber: academicNumber,
    );
    if (normalized.length != 10) {
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
    await _requireManager(userId);
    final normalized = DataProtectionService.normalizeNationalId(
      student.nationalId,
    );
    _validateStudentInput(
      name: student.name,
      nationalId: normalized,
      stage: student.stage,
      academicNumber: student.academicNumber,
    );
    final old = await getById(student.id);
    if (old == null) throw StateError('الطالب غير موجود.');
    final classChanged = old.classId != student.classId;
    var resolvedGradeId = student.gradeId;
    if (classChanged) {
      if (student.classId == null) {
        throw const FormatException(
          'لا يمكن إزالة الفصل من طالب مسجل. اختر فصلًا جديدًا ليُحفظ سجل النقل.',
        );
      }
      final targetClass = await _database.db.query(
        'classes',
        columns: ['grade_id'],
        where: 'id = ?',
        whereArgs: [student.classId],
        limit: 1,
      );
      if (targetClass.isEmpty) throw StateError('الفصل الجديد غير موجود.');
      resolvedGradeId = targetClass.first['grade_id'] as String;
    } else if (student.classId != null && old.gradeId != student.gradeId) {
      throw const FormatException(
        'لا يمكن تغيير الصف مع إبقاء الفصل القديم. استخدم الترحيل السنوي.',
      );
    }
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
            'grade_id': resolvedGradeId,
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
        if (classChanged) {
          await txn.insert('transfers', {
            'id': _uuid.v4(),
            'student_id': student.id,
            'old_class_id': old.classId,
            'new_class_id': student.classId,
            'transferred_at': now,
            'transferred_by': userId,
          });
          await _audit(
            txn,
            'student_transfer',
            'student',
            student.id,
            userId,
            {'grade_id': old.gradeId, 'class_id': old.classId},
            {'grade_id': resolvedGradeId, 'class_id': student.classId},
          );
        }
        await _audit(
          txn,
          'student_update',
          'student',
          student.id,
          userId,
          {'name': old.name, 'class_id': old.classId},
          {
            'name': student.name,
            'grade_id': resolvedGradeId,
            'class_id': student.classId,
          },
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
    await _requireManager(userId);
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

  Future<void> reactivate(String id, {required String userId}) async {
    await _requireManager(userId);
    final old = await getById(id);
    if (old == null) throw StateError('الطالب غير موجود.');
    if (old.status == 'active') return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'students',
        {'status': 'active', 'deleted_at': null, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _audit(
        txn,
        'student_reactivate',
        'student',
        id,
        userId,
        {'status': old.status},
        {'status': 'active'},
      );
    });
  }

  Future<List<String>> getActiveStages() async {
    final rows = await _database.db.rawQuery('''
      SELECT DISTINCT TRIM(stage) AS stage
      FROM students
      WHERE status = 'active' AND TRIM(stage) <> ''
      ORDER BY stage COLLATE NOCASE
    ''');
    return rows.map((row) => row['stage'] as String).toList();
  }

  Future<int> activeCount({String? gradeId, String? stage}) async {
    if ((gradeId == null) == (stage == null)) {
      throw ArgumentError('حدد صفًا أو مرحلة واحدة فقط.');
    }
    final result = await _database.db.rawQuery(
      "SELECT COUNT(*) AS count FROM students WHERE status = 'active' AND ${gradeId != null ? 'grade_id = ?' : 'TRIM(stage) = ?'}",
      [gradeId ?? stage!.trim()],
    );
    return result.first['count'] as int;
  }

  Future<int> deactivateBatch({
    String? gradeId,
    String? stage,
    required String userId,
  }) async {
    await _requireManager(userId);
    if ((gradeId == null) == (stage == null)) {
      throw ArgumentError('حدد صفًا أو مرحلة واحدة فقط.');
    }
    final condition = gradeId != null ? 'grade_id = ?' : 'TRIM(stage) = ?';
    final value = gradeId ?? stage!.trim();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.db.transaction((txn) async {
      final rows = await txn.query(
        'students',
        columns: ['id'],
        where: "status = 'active' AND $condition",
        whereArgs: [value],
      );
      if (rows.isEmpty) return 0;
      await txn.update(
        'students',
        {'status': 'inactive', 'deleted_at': now, 'updated_at': now},
        where: "status = 'active' AND $condition",
        whereArgs: [value],
      );
      for (final row in rows) {
        await _audit(
          txn,
          'student_deactivate',
          'student',
          row['id'] as String,
          userId,
          {'status': 'active'},
          {'status': 'inactive', 'batch': true},
        );
      }
      await _audit(
        txn,
        'student_batch_deactivate',
        'student_batch',
        value,
        userId,
        null,
        {
          'scope': gradeId != null ? 'grade' : 'stage',
          'scope_id': value,
          'count': rows.length,
        },
      );
      return rows.length;
    });
  }

  Future<GradePromotionResult> promoteGrade({
    required String sourceGradeId,
    required String targetGradeId,
    required Map<String, String> classMapping,
    required String userId,
    DateTime? at,
  }) async {
    await _requireManager(userId);
    if (sourceGradeId == targetGradeId) {
      throw const FormatException('يجب اختيار صف جديد مختلف عن الصف الحالي.');
    }
    if (classMapping.isEmpty) {
      throw const FormatException('حدد الفصل الجديد لكل فصل حالي.');
    }
    final sourceClasses = await _database.db.query(
      'classes',
      columns: ['id'],
      where: 'grade_id = ?',
      whereArgs: [sourceGradeId],
    );
    final validSourceIds = sourceClasses
        .map((row) => row['id'] as String)
        .toSet();
    final targetClasses = await _database.db.query(
      'classes',
      columns: ['id'],
      where: 'grade_id = ?',
      whereArgs: [targetGradeId],
    );
    final validTargetIds = targetClasses
        .map((row) => row['id'] as String)
        .toSet();
    if (!classMapping.keys.every(validSourceIds.contains) ||
        !classMapping.values.every(validTargetIds.contains)) {
      throw const FormatException('خريطة الفصول لا تطابق الصفين المحددين.');
    }
    final students = await _database.db.query(
      'students',
      columns: ['id', 'class_id'],
      where: "status = 'active' AND grade_id = ?",
      whereArgs: [sourceGradeId],
    );
    if (students.isEmpty) return const GradePromotionResult(promoted: 0);
    final unassigned = students.where((row) => row['class_id'] == null).length;
    final unmapped = students.where((row) {
      final classId = row['class_id'] as String?;
      return classId != null && !classMapping.containsKey(classId);
    }).length;
    if (unassigned > 0 || unmapped > 0) {
      throw FormatException(
        'تعذر الترحيل: $unassigned طالب بلا فصل و$unmapped طالب في فصل غير مربوط.',
      );
    }
    final now = (at ?? DateTime.now()).toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      for (final row in students) {
        final studentId = row['id'] as String;
        final oldClassId = row['class_id'] as String;
        final newClassId = classMapping[oldClassId]!;
        await txn.insert('transfers', {
          'id': _uuid.v4(),
          'student_id': studentId,
          'old_class_id': oldClassId,
          'new_class_id': newClassId,
          'transferred_at': now,
          'transferred_by': userId,
        });
        await txn.update(
          'students',
          {
            'grade_id': targetGradeId,
            'class_id': newClassId,
            'transfer_status': 'promoted',
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
          {'grade_id': sourceGradeId, 'class_id': oldClassId},
          {
            'grade_id': targetGradeId,
            'class_id': newClassId,
            'annual_promotion': true,
          },
        );
      }
      await _audit(
        txn,
        'grade_promotion',
        'student_batch',
        sourceGradeId,
        userId,
        {'grade_id': sourceGradeId},
        {
          'grade_id': targetGradeId,
          'count': students.length,
          'class_mapping': classMapping,
        },
      );
    });
    return GradePromotionResult(promoted: students.length);
  }

  Future<void> transfer(
    String studentId,
    String newClassId, {
    required String userId,
  }) async {
    await _requireManager(userId);
    final student = await getById(studentId);
    if (student == null) throw StateError('الطالب غير موجود.');
    if (student.classId == newClassId) return;
    final targetRows = await _database.db.query(
      'classes',
      columns: ['grade_id'],
      where: 'id = ?',
      whereArgs: [newClassId],
      limit: 1,
    );
    if (targetRows.isEmpty || targetRows.first['grade_id'] != student.gradeId) {
      throw const FormatException('يمكن نقل الطالب بين فصول الصف نفسه فقط.');
    }
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

  Future<List<StudentTransfer>> transferHistory(String studentId) async {
    final rows = await _database.db.rawQuery(
      '''
      SELECT t.*,
             old_c.name AS old_class_name, old_g.name AS old_grade_name,
             new_c.name AS new_class_name, new_g.name AS new_grade_name,
             u.name AS user_name
      FROM transfers t
      LEFT JOIN classes old_c ON old_c.id = t.old_class_id
      LEFT JOIN grades old_g ON old_g.id = old_c.grade_id
      JOIN classes new_c ON new_c.id = t.new_class_id
      JOIN grades new_g ON new_g.id = new_c.grade_id
      JOIN users u ON u.id = t.transferred_by
      WHERE t.student_id = ?
      ORDER BY t.transferred_at DESC
    ''',
      [studentId],
    );
    return rows
        .map(
          (row) => StudentTransfer(
            id: row['id'] as String,
            studentId: row['student_id'] as String,
            oldClassLabel: _classLabel(
              row['old_grade_name'] as String?,
              row['old_class_name'] as String?,
              fallback: 'غير محدد',
            ),
            newClassLabel: _classLabel(
              row['new_grade_name'] as String?,
              row['new_class_name'] as String?,
              fallback: 'غير محدد',
            ),
            transferredAt: DateTime.parse(row['transferred_at'] as String),
            transferredBy: row['user_name'] as String,
          ),
        )
        .toList();
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

  static void _validateStudentInput({
    required String name,
    required String nationalId,
    required String stage,
    required String? academicNumber,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.length < 2 || normalizedName.length > 150) {
      throw const FormatException('اسم الطالب يجب أن يكون بين 2 و150 حرفًا.');
    }
    if (nationalId.length != 10 || !RegExp(r'^\d{10}$').hasMatch(nationalId)) {
      throw const FormatException('السجل المدني يجب أن يتكون من 10 أرقام.');
    }
    if (stage.trim().length > 100) {
      throw const FormatException('اسم المرحلة طويل جدًا.');
    }
    if ((academicNumber?.trim().length ?? 0) > 100) {
      throw const FormatException('الرقم الأكاديمي طويل جدًا.');
    }
  }

  static String _classLabel(
    String? grade,
    String? schoolClass, {
    required String fallback,
  }) {
    final parts = [
      grade,
      schoolClass,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? fallback : parts.join(' / ');
  }
}
