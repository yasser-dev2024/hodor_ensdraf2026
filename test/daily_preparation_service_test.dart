import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/models/daily_preparation.dart';
import 'package:morning_student_attendance/repositories/attendance_repository.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/class_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
import 'package:morning_student_attendance/services/daily_preparation_service.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late DataProtectionService protection;
  late StudentRepository students;
  late ClassRepository classes;
  late AttendanceRepository attendance;
  late DailyPreparationService preparation;
  late String managerId;
  late Directory tempDirectory;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'daily-preparation-test-',
    );
    databasePath = p.join(tempDirectory.path, 'attendance.db');
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(db);
    database = AppDatabase(db, path: databasePath);
    protection = DataProtectionService.forTesting(
      List<int>.generate(32, (index) => index),
    );
    students = StudentRepository(database, protection);
    classes = ClassRepository(database);
    attendance = AttendanceRepository(database);
    preparation = DailyPreparationService(database, attendance);
    managerId = (await AuthRepository(
      database,
      protection,
    ).createInitialManager(name: 'مدير الاختبار', pin: '873421')).id;
  });

  tearDown(() async {
    if (database.db.isOpen) await database.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('يتتبع اكتمال الفصول من سجلات الحضور الحالية فقط', () async {
    final gradeId = await classes.addGrade('الصف السادس', userId: managerId);
    final firstClassId = await classes.addClass(
      gradeId,
      '1',
      userId: managerId,
    );
    final secondClassId = await classes.addClass(
      gradeId,
      '2',
      userId: managerId,
    );
    final firstStudent = await students.create(
      name: 'الطالب الأول',
      nationalId: '1011111111',
      gradeId: gradeId,
      classId: firstClassId,
      userId: managerId,
    );
    final secondStudent = await students.create(
      name: 'الطالب الثاني',
      nationalId: '1022222222',
      gradeId: gradeId,
      classId: secondClassId,
      userId: managerId,
    );
    final now = DateTime.now();
    final day = attendance.dayKey(now);

    final initial = await preparation.load(now);
    expect(initial.totalClasses, 2);
    expect(initial.completedClasses, 0);
    expect(initial.isComplete, isFalse);

    final reviewBefore = await preparation.review(now);
    expect(
      reviewBefore.issues.where(
        (issue) => issue.kind == DailyReviewIssueKind.incompleteClass,
      ),
      hasLength(2),
    );
    expect(
      reviewBefore.issues.where(
        (issue) => issue.kind == DailyReviewIssueKind.unresolvedStudent,
      ),
      hasLength(2),
    );

    await attendance.record(
      student: firstStudent,
      status: AttendanceStatus.present,
      userId: managerId,
      attendanceDate: day,
      at: now,
    );
    final halfway = await preparation.load(now);
    expect(halfway.completedClasses, 1);
    expect(halfway.completionRate, .5);
    expect(halfway.isComplete, isFalse);

    final finalRecordTime = now.add(const Duration(minutes: 11));
    await attendance.record(
      student: secondStudent,
      status: AttendanceStatus.absent,
      userId: managerId,
      attendanceDate: day,
      at: finalRecordTime,
    );
    final complete = await preparation.load(now);
    expect(complete.completedClasses, 2);
    expect(complete.isComplete, isTrue);
    expect(complete.summary.totalStudents, 2);
    expect(complete.summary.present, 1);
    expect(complete.summary.absent, 1);
    expect(complete.completedAt, finalRecordTime.toUtc());
    expect(complete.classes.last.absentStudents, 1);
    expect((await preparation.review(now)).isClean, isTrue);
  });

  test(
    'اعتماد فصل الرادار يحتسب بقية الفصل حضورًا دون لمس الفصول الأخرى',
    () async {
      final gradeId = await classes.addGrade('الصف الثالث', userId: managerId);
      final firstClassId = await classes.addClass(
        gradeId,
        '1',
        userId: managerId,
      );
      final secondClassId = await classes.addClass(
        gradeId,
        '2',
        userId: managerId,
      );
      final absentStudent = await students.create(
        name: 'طالب غائب',
        nationalId: '1066666666',
        gradeId: gradeId,
        classId: firstClassId,
        userId: managerId,
      );
      await students.create(
        name: 'طالب حاضر أول',
        nationalId: '1077777777',
        gradeId: gradeId,
        classId: firstClassId,
        userId: managerId,
      );
      await students.create(
        name: 'طالب حاضر ثان',
        nationalId: '1088888888',
        gradeId: gradeId,
        classId: firstClassId,
        userId: managerId,
      );
      await students.create(
        name: 'طالب الفصل التالي',
        nationalId: '1099999999',
        gradeId: gradeId,
        classId: secondClassId,
        userId: managerId,
      );
      final now = DateTime.now();
      final day = attendance.dayKey(now);
      await attendance.record(
        student: absentStudent,
        status: AttendanceStatus.absent,
        userId: managerId,
        attendanceDate: day,
        at: now,
      );

      final markedPresent = await attendance.completeClassWithRemainingPresent(
        userId: managerId,
        date: day,
        classId: firstClassId,
      );

      expect(markedPresent, 2);
      final firstSummary = await attendance.summary(
        date: day,
        classId: firstClassId,
      );
      expect(firstSummary.registered, 3);
      expect(firstSummary.present, 2);
      expect(firstSummary.absent, 1);
      expect(
        await attendance.unregistered(date: day, classId: firstClassId),
        isEmpty,
      );
      expect(
        await attendance.unregistered(date: day, classId: secondClassId),
        hasLength(1),
      );
      expect(await attendance.isDayClosed(day), isFalse);

      final snapshot = await preparation.load(now);
      expect(snapshot.classes.first.state, ClassPreparationState.complete);
      expect(snapshot.classes.first.presentStudents, 2);
      expect(snapshot.classes.first.absentStudents, 1);
      expect(snapshot.classes.last.state, ClassPreparationState.incomplete);

      expect(
        await attendance.completeClassWithRemainingPresent(
          userId: managerId,
          date: day,
          classId: firstClassId,
        ),
        0,
      );
      expect(
        await attendance.getDaily(date: day, classId: firstClassId),
        hasLength(3),
      );
      final audits = await database.db.query(
        'audit_logs',
        where: 'action = ?',
        whereArgs: ['attendance_class_complete'],
      );
      expect(audits, hasLength(2));
    },
  );

  test('المراجعة تقرأ فقط وتكشف الطالب بلا فصل ودون حالة', () async {
    final gradeId = await classes.addGrade('الصف الخامس', userId: managerId);
    final classId = await classes.addClass(gradeId, '1', userId: managerId);
    final assigned = await students.create(
      name: 'طالب مكتمل البيانات',
      nationalId: '1033333333',
      gradeId: gradeId,
      classId: classId,
      userId: managerId,
    );
    await students.create(
      name: 'طالب بلا فصل',
      nationalId: '1044444444',
      userId: managerId,
    );
    final now = DateTime.now();
    await attendance.record(
      student: assigned,
      status: AttendanceStatus.present,
      userId: managerId,
      attendanceDate: attendance.dayKey(now),
      at: now,
    );

    final attendanceBefore = await database.db.query('attendance');
    final studentsBefore = await database.db.query('students');
    final auditBefore = await database.db.query('audit_logs');

    final result = await preparation.review(now);

    expect(result.isClean, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.kind == DailyReviewIssueKind.missingBasicData,
      ),
      isTrue,
    );
    expect(
      result.issues.any(
        (issue) => issue.kind == DailyReviewIssueKind.unresolvedStudent,
      ),
      isTrue,
    );
    expect((await preparation.load(now)).isComplete, isFalse);
    expect(await database.db.query('attendance'), attendanceBefore);
    expect(await database.db.query('students'), studentsBefore);
    expect(await database.db.query('audit_logs'), auditBefore);
  });

  test('تظل مؤشرات الاكتمال صحيحة بعد إغلاق القاعدة وإعادة فتحها', () async {
    final gradeId = await classes.addGrade('الصف الرابع', userId: managerId);
    final classId = await classes.addClass(gradeId, '1', userId: managerId);
    final student = await students.create(
      name: 'طالب الاستمرارية',
      nationalId: '1055555555',
      gradeId: gradeId,
      classId: classId,
      userId: managerId,
    );
    final now = DateTime.now();
    await attendance.record(
      student: student,
      status: AttendanceStatus.present,
      userId: managerId,
      attendanceDate: attendance.dayKey(now),
      at: now,
    );
    expect((await preparation.load(now)).isComplete, isTrue);

    await database.db.close();
    database.db = await databaseFactoryFfi.openDatabase(databasePath);
    await database.db.execute('PRAGMA foreign_keys = ON');
    final afterReopen = await DailyPreparationService(
      database,
      AttendanceRepository(database),
    ).load(now);

    expect(afterReopen.isComplete, isTrue);
    expect(afterReopen.completedClasses, 1);
    expect(afterReopen.summary.present, 1);
    expect(afterReopen.completedAt, isNotNull);
  });
}
