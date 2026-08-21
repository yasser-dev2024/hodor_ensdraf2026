import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/repositories/attendance_repository.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/class_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late ClassRepository classes;
  late StudentRepository students;
  late AttendanceRepository attendance;
  late String managerId;

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(db);
    database = AppDatabase(db);
    final protection = DataProtectionService.forTesting(
      List<int>.generate(32, (index) => index + 3),
    );
    classes = ClassRepository(database);
    students = StudentRepository(database, protection);
    attendance = AttendanceRepository(database);
    managerId = (await AuthRepository(
      database,
      protection,
    ).createInitialManager(name: 'مدير الاختبار', pin: '739184')).id;
  });

  tearDown(() => database.close());

  test(
    'يحذف الفصل وبياناته التابعة فقط ويمكن إنشاء الفصل والطالب مجددًا',
    () async {
      final gradeId = await classes.addGrade('الرابع', userId: managerId);
      final deletedClassId = await classes.addClass(
        gradeId,
        '1',
        userId: managerId,
      );
      final survivingClassId = await classes.addClass(
        gradeId,
        '2',
        userId: managerId,
      );
      final deletedStudent = await students.create(
        name: 'طالب الفصل المحذوف',
        nationalId: '1012345678',
        gradeId: gradeId,
        classId: deletedClassId,
        stage: 'ابتدائي',
        userId: managerId,
      );
      final survivor = await students.create(
        name: 'طالب باقٍ',
        nationalId: '1023456789',
        gradeId: gradeId,
        classId: survivingClassId,
        stage: 'ابتدائي',
        userId: managerId,
      );
      final movedStudent = await students.create(
        name: 'طالب منقول',
        nationalId: '1034567890',
        gradeId: gradeId,
        classId: deletedClassId,
        stage: 'ابتدائي',
        userId: managerId,
      );
      await students.transfer(
        movedStudent.id,
        survivingClassId,
        userId: managerId,
      );
      final day = attendance.dayKey(DateTime.now());
      await attendance.record(
        student: deletedStudent,
        status: AttendanceStatus.absent,
        attendanceDate: day,
        userId: managerId,
      );
      await attendance.record(
        student: survivor,
        status: AttendanceStatus.present,
        attendanceDate: day,
        userId: managerId,
      );
      await attendance.closeDay(userId: managerId, date: day);
      await database.db.insert('student_graduations', {
        'id': 'graduation-in-deleted-class',
        'student_id': deletedStudent.id,
        'grade_id': gradeId,
        'class_id': deletedClassId,
        'academic_year_label': '1447 / 1448 هـ',
        'graduated_at': DateTime.now().toUtc().toIso8601String(),
        'graduated_by': managerId,
      });
      await database.db.insert('report_archives', {
        'id': 'class-report',
        'report_type': 'custom',
        'period_start': day,
        'period_end': day,
        'scope_type': 'schoolClass',
        'scope_id': deletedClassId,
        'file_path': 'missing-class-report.pdf',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'created_by': managerId,
      });

      final preview = await classes.classDeletionImpact(deletedClassId);
      expect(preview.classes, 1);
      expect(preview.students, 1);
      expect(preview.attendanceRecords, 1);
      expect(preview.transferRecords, 1);
      expect(preview.graduationRecords, 1);
      expect(preview.reportArchives, 1);

      final deleted = await classes.deleteClass(
        deletedClassId,
        userId: managerId,
      );
      expect(deleted.students, preview.students);
      expect(await students.getById(deletedStudent.id), isNull);
      expect(await students.getById(survivor.id), isNotNull);
      expect(await students.getById(movedStudent.id), isNotNull);
      expect(
        await database.db.query(
          'classes',
          where: 'id = ?',
          whereArgs: [deletedClassId],
        ),
        isEmpty,
      );
      expect(
        await database.db.query(
          'classes',
          where: 'id = ?',
          whereArgs: [survivingClassId],
        ),
        hasLength(1),
      );
      expect(await database.db.query('transfers'), isEmpty);
      expect(await database.db.query('student_graduations'), isEmpty);
      expect(await database.db.query('report_archives'), isEmpty);
      final snapshotRow = (await database.db.query(
        'closed_days',
        where: 'attendance_date = ?',
        whereArgs: [day],
      )).single;
      final snapshot =
          jsonDecode(snapshotRow['snapshot_json'] as String) as Map;
      final records = snapshot['records'] as List;
      expect(records, hasLength(1));
      expect((records.single as Map)['student_id'], survivor.id);
      expect((snapshot['summary'] as Map)['total'], 2);
      expect(await database.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final recreatedClassId = await classes.addClass(
        gradeId,
        '1',
        userId: managerId,
      );
      final recreatedStudent = await students.create(
        name: 'طالب الفصل المعاد',
        nationalId: '1012345678',
        gradeId: gradeId,
        classId: recreatedClassId,
        stage: 'ابتدائي',
        userId: managerId,
      );
      expect(recreatedStudent.id, isNot(deletedStudent.id));
    },
  );

  test('يحذف الصف بجميع فصوله وبياناته دون المساس بصف آخر', () async {
    final deletedGradeId = await classes.addGrade('الخامس', userId: managerId);
    final survivorGradeId = await classes.addGrade('السادس', userId: managerId);
    final firstClass = await classes.addClass(
      deletedGradeId,
      '1',
      userId: managerId,
    );
    final secondClass = await classes.addClass(
      deletedGradeId,
      '2',
      userId: managerId,
    );
    final survivorClass = await classes.addClass(
      survivorGradeId,
      '1',
      userId: managerId,
    );
    final firstStudent = await students.create(
      name: 'طالب أول',
      nationalId: '1045678901',
      gradeId: deletedGradeId,
      classId: firstClass,
      userId: managerId,
    );
    final secondStudent = await students.create(
      name: 'طالب ثانٍ',
      nationalId: '1056789012',
      gradeId: deletedGradeId,
      classId: secondClass,
      userId: managerId,
    );
    final survivor = await students.create(
      name: 'طالب الصف الباقي',
      nationalId: '1067890123',
      gradeId: survivorGradeId,
      classId: survivorClass,
      userId: managerId,
    );
    await attendance.record(
      student: firstStudent,
      status: AttendanceStatus.present,
      attendanceDate: '2026-08-21',
      userId: managerId,
    );
    await students.softDelete(secondStudent.id, userId: managerId);
    await database.db.insert('report_archives', {
      'id': 'grade-report',
      'report_type': 'monthly',
      'period_start': '2026-08-01',
      'period_end': '2026-08-31',
      'scope_type': 'grade',
      'scope_id': deletedGradeId,
      'file_path': 'missing-grade-report.pdf',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'created_by': managerId,
    });

    final impact = await classes.deleteGrade(deletedGradeId, userId: managerId);
    expect(impact.classes, 2);
    expect(impact.students, 2);
    expect(impact.attendanceRecords, 1);
    expect(impact.reportArchives, 1);
    expect(await students.getById(firstStudent.id), isNull);
    expect(await students.getById(secondStudent.id), isNull);
    expect(await students.getById(survivor.id), isNotNull);
    expect(await classes.getGrades(), hasLength(1));
    expect((await classes.getGrades()).single.id, survivorGradeId);
    expect(await classes.getClasses(), hasLength(1));
    expect((await classes.getClasses()).single.id, survivorClass);
    expect(await database.db.query('report_archives'), isEmpty);
    expect(await database.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('إعادة الدفعة لا تعيد طالبًا عُطّل فرديًا', () async {
    final gradeId = await classes.addGrade('الثالث', userId: managerId);
    final classId = await classes.addClass(gradeId, '1', userId: managerId);
    final individual = await students.create(
      name: 'معطل فرديًا',
      nationalId: '1078901234',
      gradeId: gradeId,
      classId: classId,
      stage: 'ابتدائي',
      userId: managerId,
    );
    final firstBatch = await students.create(
      name: 'دفعة أول',
      nationalId: '1089012345',
      gradeId: gradeId,
      classId: classId,
      stage: 'ابتدائي',
      userId: managerId,
    );
    final secondBatch = await students.create(
      name: 'دفعة ثانٍ',
      nationalId: '1090123456',
      gradeId: gradeId,
      classId: classId,
      stage: 'ابتدائي',
      userId: managerId,
    );
    await students.softDelete(individual.id, userId: managerId);
    expect(
      await students.deactivateBatch(gradeId: gradeId, userId: managerId),
      2,
    );
    final disabled = await students.disabledBatchCounts();
    expect(disabled.byGrade[gradeId], 2);
    expect(disabled.byStage['ابتدائي'], 2);

    expect(
      await students.reactivateBatch(gradeId: gradeId, userId: managerId),
      2,
    );
    expect((await students.getById(individual.id))?.status, 'inactive');
    expect((await students.getById(firstBatch.id))?.status, 'active');
    expect((await students.getById(secondBatch.id))?.status, 'active');
    expect((await students.disabledBatchCounts()).byGrade, isEmpty);

    expect(
      await students.deactivateBatch(gradeId: gradeId, userId: managerId),
      2,
    );
    expect(
      await students.reactivateBatch(stage: 'ابتدائي', userId: managerId),
      2,
    );
    final reopenedRepository = StudentRepository(
      database,
      DataProtectionService.forTesting(
        List<int>.generate(32, (index) => index + 3),
      ),
    );
    expect(
      (await reopenedRepository.getById(individual.id))?.status,
      'inactive',
    );
    expect((await reopenedRepository.getById(firstBatch.id))?.status, 'active');
    expect(
      (await reopenedRepository.getById(secondBatch.id))?.status,
      'active',
    );
  });
}
