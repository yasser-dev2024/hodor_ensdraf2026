import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/academic_year.dart';
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
    await _ensureStableBarcodeTokens();
    final conditions = <String>[];
    final args = <Object?>[];
    conditions.add(
      includeInactive ? "s.status <> 'graduated'" : "s.status = 'active'",
    );
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
        'EXISTS (SELECT 1 FROM student_barcode_aliases ba WHERE ba.student_id = s.id AND ba.token = ?)',
      ];
      args.addAll([
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        '%$cleaned%',
        cleaned,
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
    await _ensureStableBarcodeTokens();
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
    await _ensureStableBarcodeTokens();
    final cleaned = token.trim();
    if (!RegExp(r'^stu_[A-Za-z0-9_-]{20,80}$').hasMatch(cleaned)) return null;
    final rows = await _database.db.rawQuery(
      '''
      SELECT s.*, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      WHERE s.status = 'active'
        AND (
          s.barcode_token = ? OR EXISTS (
            SELECT 1 FROM student_barcode_aliases ba
            WHERE ba.student_id = s.id AND ba.token = ?
          )
        )
      LIMIT 1
    ''',
      [cleaned, cleaned],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Student> bindLegacyBarcode({
    required String token,
    required String nationalId,
    required String userId,
  }) async {
    await _requireManager(userId);
    await _ensureStableBarcodeTokens();
    final cleanedToken = token.trim();
    if (!DataProtectionService.isLegacyBarcodeToken(cleanedToken)) {
      throw const FormatException('هذا الرمز ليس باركودًا قديمًا صالحًا.');
    }
    final normalizedId = DataProtectionService.normalizeNationalId(nationalId);
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedId)) {
      throw const FormatException('أدخل السجل المدني المكون من 10 أرقام.');
    }
    final idHash = await _protection.searchableHash(normalizedId);
    final studentRows = await _database.db.query(
      'students',
      columns: const ['id'],
      where: "national_id_hash = ? AND status = 'active'",
      whereArgs: [idHash],
      limit: 1,
    );
    if (studentRows.isEmpty) {
      throw StateError('لم يوجد طالب نشط بهذا السجل المدني.');
    }
    final studentId = studentRows.first['id'] as String;
    final existing = await getByBarcode(cleanedToken);
    if (existing != null) {
      if (existing.id != studentId) {
        throw StateError('هذا الباركود مرتبط بطالب آخر بالفعل.');
      }
      return existing;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _database.db.transaction((txn) async {
        await txn.insert('student_barcode_aliases', {
          'token': cleanedToken,
          'student_id': studentId,
          'source': 'manual',
          'created_at': now,
          'created_by': userId,
        });
        await _audit(
          txn,
          'student_barcode_bind',
          'student',
          studentId,
          userId,
          null,
          {'source': 'legacy_card'},
        );
      });
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError()) rethrow;
      final resolved = await getByBarcode(cleanedToken);
      if (resolved == null || resolved.id != studentId) {
        throw StateError('هذا الباركود مرتبط بطالب آخر بالفعل.');
      }
      return resolved;
    }
    return (await getById(studentId))!;
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
    final barcodeToken = await _protection.stableBarcodeToken(normalized);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _database.db.transaction((txn) async {
        if (old.barcodeToken != barcodeToken) {
          await txn.insert('student_barcode_aliases', {
            'token': old.barcodeToken,
            'student_id': student.id,
            'source': 'national_id_change',
            'created_at': now,
            'created_by': userId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
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
            'barcode_token': barcodeToken,
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
    if (old.status == 'graduated') {
      throw StateError('الطالب متخرج ومحفوظ في سجل الخريجين ولا يعاد تفعيله.');
    }
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

  Future<List<AcademicYearRecord>> getAcademicYears() async {
    final activeResult = await _database.db.rawQuery(
      "SELECT COUNT(*) AS count FROM students WHERE status = 'active'",
    );
    final currentActive = activeResult.first['count'] as int;
    final rows = await _database.db.rawQuery('''
      SELECT ay.*, u.name AS closed_by_name,
             (
               SELECT COUNT(*) FROM student_graduations sg
               WHERE sg.academic_year_label = ay.label
             ) AS graduated_count
      FROM academic_years ay
      LEFT JOIN users u ON u.id = ay.closed_by
      ORDER BY CASE ay.status WHEN 'current' THEN 0 ELSE 1 END,
               ay.ended_at DESC,
               ay.created_at DESC
    ''');
    return rows.map((row) {
      final isCurrent = row['status'] == 'current';
      Map<String, dynamic> summary = const {};
      final encoded = row['summary_json'] as String?;
      if (encoded != null) {
        try {
          summary = jsonDecode(encoded) as Map<String, dynamic>;
        } catch (_) {
          summary = const {};
        }
      }
      return AcademicYearRecord(
        id: row['id'] as String,
        label: row['label'] as String,
        isCurrent: isCurrent,
        startedAt: DateTime.parse(row['started_at'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        endedAt: row['ended_at'] == null
            ? null
            : DateTime.parse(row['ended_at'] as String),
        closedBy: row['closed_by_name'] as String?,
        activeStudents: isCurrent
            ? currentActive
            : (summary['active_students'] as int? ?? 0),
        graduatedStudents: row['graduated_count'] as int,
      );
    }).toList();
  }

  Future<void> setCurrentAcademicYear({
    required String label,
    required String userId,
  }) async {
    await _requireManager(userId);
    final normalized = _validateAcademicYearLabel(label);
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      final current = await txn.query(
        'academic_years',
        where: "status = 'current'",
        limit: 1,
      );
      if (current.isEmpty) {
        final existing = await txn.query(
          'academic_years',
          columns: const ['id'],
          where: 'label = ?',
          whereArgs: [normalized],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          throw const FormatException(
            'هذا العام موجود في السجل السابق ولا يمكن جعله عامًا حاليًا مرة أخرى.',
          );
        }
        await txn.insert('academic_years', {
          'id': _uuid.v4(),
          'label': normalized,
          'status': 'current',
          'started_at': now,
          'created_at': now,
        });
      } else {
        final oldLabel = current.first['label'] as String;
        if (oldLabel != normalized) {
          final duplicate = await txn.query(
            'academic_years',
            columns: const ['id'],
            where: 'label = ? AND id <> ?',
            whereArgs: [normalized, current.first['id']],
            limit: 1,
          );
          if (duplicate.isNotEmpty) {
            throw const FormatException(
              'اسم العام الجديد موجود مسبقًا في سجل الأعوام.',
            );
          }
          await txn.update(
            'academic_years',
            {'label': normalized},
            where: 'id = ?',
            whereArgs: [current.first['id']],
          );
          await txn.update(
            'student_graduations',
            {'academic_year_label': normalized},
            where: 'academic_year_label = ?',
            whereArgs: [oldLabel],
          );
        }
      }
      await _setSetting(txn, 'academic_year', normalized, now);
      await _audit(
        txn,
        'academic_year_set',
        'academic_year',
        normalized,
        userId,
        null,
        {'label': normalized, 'status': 'current'},
      );
    });
  }

  Future<void> rolloverAcademicYear({
    required String nextLabel,
    required String userId,
    DateTime? at,
  }) async {
    await _requireManager(userId);
    final normalized = _validateAcademicYearLabel(nextLabel);
    final now = (at ?? DateTime.now()).toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      final currentRows = await txn.query(
        'academic_years',
        where: "status = 'current'",
        limit: 1,
      );
      if (currentRows.isEmpty) {
        throw StateError('حدد العام الدراسي الحالي من الإعدادات أولًا.');
      }
      final current = currentRows.single;
      final currentLabel = current['label'] as String;
      if (currentLabel == normalized) {
        throw const FormatException(
          'العام الدراسي الجديد يجب أن يختلف عن الحالي.',
        );
      }
      final duplicate = await txn.query(
        'academic_years',
        columns: const ['id'],
        where: 'label = ?',
        whereArgs: [normalized],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw const FormatException('هذا العام موجود مسبقًا في سجل الأعوام.');
      }
      final active = await txn.rawQuery(
        "SELECT COUNT(*) AS count FROM students WHERE status = 'active'",
      );
      final graduated = await txn.rawQuery(
        '''
        SELECT COUNT(*) AS count FROM student_graduations
        WHERE academic_year_label = ?
        ''',
        [currentLabel],
      );
      final summary = {
        'active_students': active.first['count'] as int,
        'graduated_students': graduated.first['count'] as int,
      };
      await txn.update(
        'academic_years',
        {
          'status': 'archived',
          'ended_at': now,
          'closed_by': userId,
          'summary_json': jsonEncode(summary),
        },
        where: 'id = ?',
        whereArgs: [current['id']],
      );
      await txn.insert('academic_years', {
        'id': _uuid.v4(),
        'label': normalized,
        'status': 'current',
        'started_at': now,
        'created_at': now,
      });
      await _setSetting(txn, 'academic_year', normalized, now);
      await _audit(
        txn,
        'academic_year_rollover',
        'academic_year',
        current['id'] as String,
        userId,
        {'label': currentLabel, 'status': 'current'},
        {
          'label': normalized,
          'status': 'current',
          'archived_year': currentLabel,
          'summary': summary,
        },
      );
    });
  }

  Future<GradeGraduationResult> graduateGrade({
    required String sourceGradeId,
    required String userId,
    DateTime? at,
  }) async {
    await _requireManager(userId);
    final yearRows = await _database.db.query(
      'academic_years',
      columns: const ['label'],
      where: "status = 'current'",
      limit: 1,
    );
    if (yearRows.isEmpty) {
      throw StateError('حدد العام الدراسي الحالي من الإعدادات قبل التخريج.');
    }
    final academicYear = yearRows.single['label'] as String;
    final students = await _database.db.query(
      'students',
      columns: const ['id', 'class_id'],
      where: "status = 'active' AND grade_id = ?",
      whereArgs: [sourceGradeId],
    );
    if (students.isEmpty) {
      return const GradeGraduationResult(graduated: 0);
    }
    final now = (at ?? DateTime.now()).toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      for (final row in students) {
        final studentId = row['id'] as String;
        await txn.insert('student_graduations', {
          'id': _uuid.v4(),
          'student_id': studentId,
          'grade_id': sourceGradeId,
          'class_id': row['class_id'],
          'academic_year_label': academicYear,
          'graduated_at': now,
          'graduated_by': userId,
        });
        await txn.update(
          'students',
          {
            'status': 'graduated',
            'transfer_status': 'graduated',
            'deleted_at': now,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [studentId],
        );
        await _audit(
          txn,
          'student_graduate',
          'student',
          studentId,
          userId,
          {'status': 'active', 'grade_id': sourceGradeId},
          {'status': 'graduated', 'academic_year': academicYear},
        );
      }
      await _audit(
        txn,
        'grade_graduation',
        'student_batch',
        sourceGradeId,
        userId,
        {'grade_id': sourceGradeId},
        {
          'status': 'graduated',
          'academic_year': academicYear,
          'count': students.length,
        },
      );
    });
    return GradeGraduationResult(graduated: students.length);
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
      'barcode_token': await _protection.stableBarcodeToken(nationalId),
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

  Future<void> _ensureStableBarcodeTokens() => _migrateLegacyBarcodeTokens();

  Future<void> _migrateLegacyBarcodeTokens() async {
    final rows = await _database.db.query(
      'students',
      columns: const ['id', 'national_id_encrypted', 'barcode_token'],
      where: "barcode_token NOT LIKE 'stu_v2_%'",
    );
    if (rows.isEmpty) return;
    final prepared = <(String, String, String)>[];
    const batchSize = 128;
    for (var offset = 0; offset < rows.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, rows.length);
      final batch = rows.sublist(offset, end);
      prepared.addAll(
        await Future.wait(
          batch.map((row) async {
            final nationalId = await _protection.decrypt(
              row['national_id_encrypted'] as String,
            );
            return (
              row['id'] as String,
              row['barcode_token'] as String,
              await _protection.stableBarcodeToken(nationalId),
            );
          }),
        ),
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      for (final item in prepared) {
        await txn.insert('student_barcode_aliases', {
          'token': item.$2,
          'student_id': item.$1,
          'source': 'migration',
          'created_at': now,
          'created_by': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.update(
          'students',
          {'barcode_token': item.$3},
          where: 'id = ? AND barcode_token = ?',
          whereArgs: [item.$1, item.$2],
        );
      }
    });
  }

  static String _validateAcademicYearLabel(String value) {
    final normalized = value.trim();
    if (normalized.length < 3 || normalized.length > 40) {
      throw const FormatException(
        'اسم العام الدراسي يجب أن يكون بين 3 و40 حرفًا.',
      );
    }
    return normalized;
  }

  static Future<void> _setSetting(
    DatabaseExecutor db,
    String key,
    String value,
    String updatedAt,
  ) async {
    await db.rawInsert(
      '''
      INSERT INTO settings(key, value, updated_at) VALUES(?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
      ''',
      [key, value, updatedAt],
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
