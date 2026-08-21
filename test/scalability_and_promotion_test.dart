import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/models/import_models.dart';
import 'package:morning_student_attendance/models/period_report.dart';
import 'package:morning_student_attendance/models/student.dart';
import 'package:morning_student_attendance/repositories/attendance_repository.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/class_repository.dart';
import 'package:morning_student_attendance/repositories/report_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:morning_student_attendance/services/import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'يتحمل 5000 طالب ويحفظهم بعد إعادة الفتح ثم يرحلهم ويعطلهم دون فقد',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'attendance_stress_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final path = '${directory.path}${Platform.pathSeparator}stress.sqlite';
      var rawDb = await databaseFactoryFfi.openDatabase(path);
      await rawDb.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.createSchemaForTesting(rawDb);
      var database = AppDatabase(rawDb, path: path);
      final protection = DataProtectionService.forTesting(
        List<int>.generate(32, (index) => 255 - index),
      );
      var students = StudentRepository(database, protection);
      var classes = ClassRepository(database);
      var attendance = AttendanceRepository(database);
      final auth = AuthRepository(database, protection);
      final managerId = (await auth.createInitialManager(
        name: 'مدير اختبار الضغط',
        pin: '946281',
      )).id;

      final fourthId = await classes.addGrade('رابع', userId: managerId);
      final fifthId = await classes.addGrade('خامس', userId: managerId);
      final fourthClasses = <String>[];
      final fifthClasses = <String>[];
      for (var index = 1; index <= 5; index++) {
        fourthClasses.add(
          await classes.addClass(fourthId, '$index', userId: managerId),
        );
        fifthClasses.add(
          await classes.addClass(fifthId, '$index', userId: managerId),
        );
      }

      final stopwatch = Stopwatch()..start();
      final importer = StudentImportService(
        database: database,
        students: students,
        classes: classes,
      );
      final workbook = ImportWorkbook(
        fileName: 'stress_5000.xlsx',
        sourceType: 'xlsx',
        sheets: [
          ImportSheetData(
            name: 'خمسة آلاف طالب',
            rows: [
              ['كشف كبير لاختبار التحمل'],
              [
                'اسم المتعلم',
                'رقم الهوية',
                'المرحلة',
                'الصف',
                'الفصل',
                'رقم الطالب',
              ],
              for (var index = 0; index < 5000; index++)
                [
                  index % 100 == 0
                      ? 'طالب ذو اسم عربي طويل للاختبار ${'متعدد المقاطع ' * 6}${index + 1}'
                      : 'طالب اختبار الضغط ${index + 1}',
                  '2${index.toString().padLeft(9, '0')}',
                  'المرحلة الابتدائية',
                  'رابع',
                  '${(index % 5) + 1}',
                  'A-${100000 + index}',
                ],
            ],
          ),
        ],
      );
      final preview = await importer.preview(workbook);
      expect(preview.validCount, 5000);
      expect(preview.duplicateCount, 0);
      final created = await importer.import(preview, userId: managerId);
      /*
       * يمر الاختبار عبر نفس مسار المعاينة والاستيراد المستخدم في الواجهة،
       * وليس عبر إدخال مباشر مخصص للاختبار.
       */
      expect(created.imported, 5000);
      expect(created.duplicates, 0);
      expect(created.errors, 0);
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 90)));
      await database.db.update('students', {
        'created_at': '2026-08-16T04:00:00.000Z',
      });

      final beforeRestart = await students.getAll();
      expect(beforeRestart, hasLength(5000));
      expect(
        beforeRestart.map((student) => student.barcodeToken).toSet(),
        hasLength(5000),
      );
      final protectedToken = beforeRestart.first.barcodeToken;
      final protectedStudentId = beforeRestart.first.id;
      await attendance.record(
        student: beforeRestart.first,
        status: AttendanceStatus.present,
        userId: managerId,
        at: DateTime(2026, 8, 16, 7),
      );

      await database.close();
      rawDb = await databaseFactoryFfi.openDatabase(path);
      await rawDb.execute('PRAGMA foreign_keys = ON');
      database = AppDatabase(rawDb, path: path);
      students = StudentRepository(database, protection);
      classes = ClassRepository(database);
      attendance = AttendanceRepository(database);
      final reports = ReportRepository(database);

      expect(await students.getAll(), hasLength(5000));
      expect(
        (await students.getById(protectedStudentId))?.barcodeToken,
        protectedToken,
      );
      expect(await students.getByBarcode(protectedToken), isNotNull);
      expect(
        await attendance.getStudentHistory(protectedStudentId),
        hasLength(1),
      );

      final promotionTimer = Stopwatch()..start();
      final promotion = await students.promoteGrade(
        sourceGradeId: fourthId,
        targetGradeId: fifthId,
        classMapping: {
          for (var index = 0; index < fourthClasses.length; index++)
            fourthClasses[index]: fifthClasses[index],
        },
        userId: managerId,
        at: DateTime(2026, 8, 19, 12),
      );
      promotionTimer.stop();
      expect(promotion.promoted, 5000);
      expect(promotionTimer.elapsed, lessThan(const Duration(seconds: 90)));
      expect(await students.activeCount(gradeId: fourthId), 0);
      expect(await students.activeCount(gradeId: fifthId), 5000);
      expect(
        (await database.db.rawQuery(
          'SELECT COUNT(*) AS count FROM transfers',
        )).single['count'],
        5000,
      );
      expect(
        (await students.getById(protectedStudentId))?.barcodeToken,
        protectedToken,
      );
      expect(
        await attendance.getStudentHistory(protectedStudentId),
        hasLength(1),
      );
      final oldGradeReport = await reports.periodReport(
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 8, 18),
        scope: ReportScope(
          type: ReportScopeType.grade,
          id: fourthId,
          label: 'رابع',
        ),
      );
      final newGradeReport = await reports.periodReport(
        startDate: DateTime(2026, 8, 19),
        endDate: DateTime(2026, 8, 20),
        scope: ReportScope(
          type: ReportScopeType.grade,
          id: fifthId,
          label: 'خامس',
        ),
      );
      expect(oldGradeReport.totalStudents, 5000);
      expect(oldGradeReport.present, 1);
      expect(oldGradeReport.expectedEntries, 15000);
      expect(newGradeReport.totalStudents, 5000);
      expect(newGradeReport.expectedEntries, 10000);

      final deactivated = await students.deactivateBatch(
        gradeId: fifthId,
        userId: managerId,
      );
      expect(deactivated, 5000);
      expect(await students.getAll(), isEmpty);
      expect(await students.getAll(includeInactive: true), hasLength(5000));
      expect(
        await attendance.getStudentHistory(protectedStudentId),
        hasLength(1),
      );

      await students.reactivate(protectedStudentId, userId: managerId);
      expect(await students.getAll(), hasLength(1));
      expect(
        await students.deactivateBatch(
          stage: 'المرحلة الابتدائية',
          userId: managerId,
        ),
        1,
      );
      final restoreTimer = Stopwatch()..start();
      final disabledBatches = await students.disabledBatchCounts();
      expect(disabledBatches.byGrade[fifthId], 5000);
      expect(
        await students.reactivateBatch(gradeId: fifthId, userId: managerId),
        5000,
      );
      restoreTimer.stop();
      expect(restoreTimer.elapsed, lessThan(const Duration(seconds: 90)));
      expect(await students.activeCount(gradeId: fifthId), 5000);
      final integrity = await database.db.rawQuery('PRAGMA integrity_check');
      expect(integrity.single.values.single, 'ok');
      await database.close();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('فشل خريطة الترحيل يلغي العملية كلها بلا نقل جزئي', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final source = await fixture.classes.addGrade(
      'رابع',
      userId: fixture.managerId,
    );
    final target = await fixture.classes.addGrade(
      'خامس',
      userId: fixture.managerId,
    );
    final sourceClass = await fixture.classes.addClass(
      source,
      '1',
      userId: fixture.managerId,
    );
    await fixture.classes.addClass(target, '1', userId: fixture.managerId);
    await fixture.students.create(
      name: 'طالب ثابت',
      nationalId: '2111111111',
      gradeId: source,
      classId: sourceClass,
      userId: fixture.managerId,
    );

    expect(
      () => fixture.students.promoteGrade(
        sourceGradeId: source,
        targetGradeId: target,
        classMapping: const {},
        userId: fixture.managerId,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await fixture.students.activeCount(gradeId: source), 1);
    expect(await fixture.students.activeCount(gradeId: target), 0);
    expect(await fixture.database.db.query('transfers'), isEmpty);
  });

  test('يخفي خريجي السادس ويحفظ العام ثم يبقي ترحيل الخامس يدويًا', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final fifth = await fixture.classes.addGrade(
      'الخامس',
      userId: fixture.managerId,
    );
    final sixth = await fixture.classes.addGrade(
      'السادس',
      userId: fixture.managerId,
    );
    final fifthClass = await fixture.classes.addClass(
      fifth,
      '1',
      userId: fixture.managerId,
    );
    final sixthClass = await fixture.classes.addClass(
      sixth,
      '1',
      userId: fixture.managerId,
    );
    final graduate = await fixture.students.create(
      name: 'خريج الصف السادس',
      nationalId: '2555555555',
      gradeId: sixth,
      classId: sixthClass,
      userId: fixture.managerId,
    );
    final promoted = await fixture.students.create(
      name: 'طالب الصف الخامس',
      nationalId: '2666666666',
      gradeId: fifth,
      classId: fifthClass,
      userId: fixture.managerId,
    );
    await fixture.attendance.record(
      student: graduate,
      status: AttendanceStatus.present,
      userId: fixture.managerId,
    );
    await fixture.students.setCurrentAcademicYear(
      label: '1447 / 1448 هـ',
      userId: fixture.managerId,
    );

    final graduation = await fixture.students.graduateGrade(
      sourceGradeId: sixth,
      userId: fixture.managerId,
    );
    expect(graduation.graduated, 1);
    expect(await fixture.students.getAll(includeInactive: true), [
      isA<Student>().having((student) => student.id, 'id', promoted.id),
    ]);
    expect(await fixture.students.getByBarcode(graduate.barcodeToken), isNull);
    expect((await fixture.students.getById(graduate.id))?.status, 'graduated');
    expect(
      await fixture.attendance.getStudentHistory(graduate.id),
      hasLength(1),
    );
    expect(
      await fixture.database.db.query('student_graduations'),
      hasLength(1),
    );

    final manualPromotion = await fixture.students.promoteGrade(
      sourceGradeId: fifth,
      targetGradeId: sixth,
      classMapping: {fifthClass: sixthClass},
      userId: fixture.managerId,
    );
    expect(manualPromotion.promoted, 1);
    expect(await fixture.students.activeCount(gradeId: fifth), 0);
    expect(await fixture.students.activeCount(gradeId: sixth), 1);

    await fixture.students.rolloverAcademicYear(
      nextLabel: '1448 / 1449 هـ',
      userId: fixture.managerId,
    );
    final years = await fixture.students.getAcademicYears();
    expect(years, hasLength(2));
    expect(years.first.label, '1448 / 1449 هـ');
    expect(years.first.isCurrent, isTrue);
    expect(years.last.label, '1447 / 1448 هـ');
    expect(years.last.isCurrent, isFalse);
    expect(years.last.graduatedStudents, 1);
  });

  test('الإحصاءات ترتب أفضل طالب وأكثر غياب واستئذان وأفضل فصل بدقة', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gradeId = await fixture.classes.addGrade(
      'سادس',
      userId: fixture.managerId,
    );
    final bestClassId = await fixture.classes.addClass(
      gradeId,
      '1',
      userId: fixture.managerId,
    );
    final otherClassId = await fixture.classes.addClass(
      gradeId,
      '2',
      userId: fixture.managerId,
    );
    final best = await fixture.students.create(
      name: 'الطالب الأفضل',
      nationalId: '2222222222',
      gradeId: gradeId,
      classId: bestClassId,
      userId: fixture.managerId,
    );
    final absent = await fixture.students.create(
      name: 'الأكثر غيابًا',
      nationalId: '2333333333',
      gradeId: gradeId,
      classId: otherClassId,
      userId: fixture.managerId,
    );
    final excused = await fixture.students.create(
      name: 'الأكثر استئذانًا',
      nationalId: '2444444444',
      gradeId: gradeId,
      classId: otherClassId,
      userId: fixture.managerId,
    );
    await fixture.database.db.update('students', {
      'created_at': '2026-08-16T04:00:00.000Z',
    });
    for (var day = 16; day <= 20; day++) {
      final at = DateTime(2026, 8, day, 7);
      await fixture.attendance.record(
        student: best,
        status: AttendanceStatus.present,
        userId: fixture.managerId,
        at: at,
      );
      await fixture.attendance.record(
        student: absent,
        status: day <= 18 ? AttendanceStatus.absent : AttendanceStatus.present,
        userId: fixture.managerId,
        at: at,
      );
      await fixture.attendance.record(
        student: excused,
        status: day <= 19 ? AttendanceStatus.excused : AttendanceStatus.present,
        userId: fixture.managerId,
        at: at,
      );
    }

    final analytics = await fixture.reports.analytics(
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 8, 20),
    );
    expect(analytics.report.schoolDays, 5);
    expect(analytics.mostDisciplined.first.studentName, 'الطالب الأفضل');
    expect(analytics.mostDisciplined.first.disciplineRate, 1);
    expect(analytics.mostAbsent.first.studentName, 'الأكثر غيابًا');
    expect(analytics.mostAbsent.first.absent, 3);
    expect(analytics.mostExcused.first.studentName, 'الأكثر استئذانًا');
    expect(analytics.mostExcused.first.excused, 4);
    expect(analytics.bestClass?.label, 'سادس / 1');
    expect(analytics.mostAbsentClass?.label, 'سادس / 2');
  });
}

class _Fixture {
  const _Fixture({
    required this.database,
    required this.students,
    required this.classes,
    required this.attendance,
    required this.reports,
    required this.managerId,
  });

  final AppDatabase database;
  final StudentRepository students;
  final ClassRepository classes;
  final AttendanceRepository attendance;
  final ReportRepository reports;
  final String managerId;

  static Future<_Fixture> create() async {
    final rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await rawDb.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(rawDb);
    final database = AppDatabase(rawDb);
    final protection = DataProtectionService.forTesting(
      List<int>.generate(32, (index) => index),
    );
    final auth = AuthRepository(database, protection);
    final managerId = (await auth.createInitialManager(
      name: 'مدير الاختبار',
      pin: '873421',
    )).id;
    return _Fixture(
      database: database,
      students: StudentRepository(database, protection),
      classes: ClassRepository(database),
      attendance: AttendanceRepository(database),
      reports: ReportRepository(database),
      managerId: managerId,
    );
  }

  Future<void> close() => database.close();
}
