import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/models/app_user.dart';
import 'package:morning_student_attendance/models/import_models.dart';
import 'package:morning_student_attendance/models/period_report.dart';
import 'package:morning_student_attendance/repositories/attendance_repository.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/class_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
import 'package:morning_student_attendance/repositories/report_repository.dart';
import 'package:morning_student_attendance/services/data_protection_service.dart';
import 'package:morning_student_attendance/services/import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late DataProtectionService protection;
  late StudentRepository students;
  late ClassRepository classes;
  late AttendanceRepository attendance;
  late AuthRepository auth;
  late ReportRepository reports;
  late String managerId;

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.createSchemaForTesting(db);
    database = AppDatabase(db);
    protection = DataProtectionService.forTesting(
      List<int>.generate(32, (index) => index),
    );
    students = StudentRepository(database, protection);
    classes = ClassRepository(database);
    attendance = AttendanceRepository(database);
    auth = AuthRepository(database, protection);
    reports = ReportRepository(database);
    managerId = (await auth.createInitialManager(
      name: 'مدير الاختبار',
      pin: '873421',
    )).id;
  });

  tearDown(() => database.close());

  test('يمنع تكرار السجل المدني في طبقة قاعدة البيانات', () async {
    await students.create(
      name: 'الطالب الأول',
      nationalId: '1023456789',
      userId: managerId,
    );

    expect(
      () => students.create(
        name: 'طالب مكرر',
        nationalId: '1023456789',
        userId: managerId,
      ),
      throwsA(isA<DuplicateStudentException>()),
    );
    expect((await students.getAll()).length, 1);
  });

  test('يفرض RBAC داخل طبقة البيانات وليس الواجهة فقط', () async {
    final attendanceOfficer = await auth.createUser(
      name: 'مسؤول الحضور',
      pin: '739184',
      role: UserRole.attendanceOfficer,
      actorId: managerId,
    );
    final studentAffairs = await auth.createUser(
      name: 'وكيل الطلاب',
      pin: '814739',
      role: UserRole.studentAffairs,
      actorId: managerId,
    );
    final student = await students.create(
      name: 'طالب الصلاحيات',
      nationalId: '1022222222',
      userId: managerId,
    );

    expect(
      () => students.create(
        name: 'إضافة ممنوعة',
        nationalId: '1033333333',
        userId: attendanceOfficer.id,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => classes.addGrade('صف ممنوع', userId: attendanceOfficer.id),
      throwsA(isA<StateError>()),
    );
    expect(
      () => auth.createUser(
        name: 'مستخدم غير مصرح',
        pin: '926481',
        role: UserRole.attendanceOfficer,
        actorId: attendanceOfficer.id,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => attendance.record(
        student: student,
        status: AttendanceStatus.present,
        userId: studentAffairs.id,
      ),
      throwsA(isA<StateError>()),
    );
    final saved = await attendance.record(
      student: student,
      status: AttendanceStatus.present,
      userId: attendanceOfficer.id,
    );
    expect(saved.wasExisting, isFalse);
    expect(
      () => attendance.closeDay(userId: attendanceOfficer.id),
      throwsA(isA<StateError>()),
    );
  });

  test('رمز QR آمن وفريد ويسترجع الطالب دون كشف السجل', () async {
    final student = await students.create(
      name: 'سلمان محمد',
      nationalId: '1098765432',
      userId: managerId,
    );

    expect(student.barcodeToken, startsWith('stu_'));
    expect(student.barcodeToken, isNot(contains(student.nationalId)));
    expect((await students.getByBarcode(student.barcodeToken))?.id, student.id);
  });

  test('يمنع تسجيل الطالب مرتين في اليوم', () async {
    final student = await students.create(
      name: 'أحمد علي',
      nationalId: '1011111111',
      userId: managerId,
    );
    final first = await attendance.record(
      student: student,
      status: AttendanceStatus.present,
      userId: managerId,
    );
    final second = await attendance.record(
      student: student,
      status: AttendanceStatus.absent,
      userId: managerId,
    );

    expect(first.wasExisting, isFalse);
    expect(second.wasExisting, isTrue);
    expect(second.record.status, AttendanceStatus.present);
    expect((await attendance.getDaily()).length, 1);
  });

  test('البحث الشامل وسجل النقل والحضور يحفظان التفاصيل', () async {
    final gradeId = await classes.addGrade('خامس', userId: managerId);
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
    final student = await students.create(
      name: 'تركي عبدالله',
      nationalId: '1076543210',
      academicNumber: 'AC-204',
      gradeId: gradeId,
      classId: firstClassId,
      userId: managerId,
    );

    expect((await students.getAll(query: '1076543210')).single.id, student.id);
    expect(
      (await students.getAll(query: student.barcodeToken)).single.id,
      student.id,
    );
    expect((await students.getAll(query: 'خامس')).single.id, student.id);
    expect(
      (await students.getAll(
        gradeId: gradeId,
        classId: firstClassId,
      )).single.id,
      student.id,
    );

    await students.transfer(student.id, secondClassId, userId: managerId);
    final transfers = await students.transferHistory(student.id);
    expect(transfers, hasLength(1));
    expect(transfers.single.oldClassLabel, 'خامس / 1');
    expect(transfers.single.newClassLabel, 'خامس / 2');
    expect(transfers.single.transferredBy, 'مدير الاختبار');

    final moved = (await students.getById(student.id))!;
    await attendance.record(
      student: moved,
      status: AttendanceStatus.excused,
      reason: 'موعد طبي',
      receiverName: 'ولي الأمر',
      userId: managerId,
      at: DateTime.utc(2026, 8, 18, 7, 30),
    );
    final history = await attendance.getStudentHistory(student.id);
    expect(history, hasLength(1));
    expect(history.single.status, AttendanceStatus.excused);
    expect(history.single.reason, 'موعد طبي');
    expect(history.single.receiverName, 'ولي الأمر');
    expect(history.single.classLabel, 'خامس / 2');

    await attendance.recordDeparture(
      recordId: history.single.id,
      userId: managerId,
      note: 'تم التسليم',
      at: DateTime.utc(2026, 8, 18, 9, 15),
    );
    final afterDeparture = await attendance.getStudentHistory(student.id);
    expect(afterDeparture.single.departureAt, DateTime.utc(2026, 8, 18, 9, 15));
    expect(afterDeparture.single.note, 'تم التسليم');
    final audit = await database.db.query(
      'audit_logs',
      where: "action = 'attendance_departure'",
    );
    expect(audit, hasLength(1));
  });

  test('يحوّل جدول PDF النصي للمعاينة ويرفض الملف المصوّر بوضوح', () async {
    final importer = StudentImportService(
      database: database,
      students: students,
      classes: classes,
    );
    final workbook = importer.workbookFromPdfText(
      'students.pdf',
      'اسم الطالب | السجل المدني | الصف | الفصل\n'
          'محمد أحمد | 1012345678 | رابع | 1\n'
          'خالد علي | 1098765432 | رابع | 2',
    );
    final preview = await importer.preview(workbook);
    expect(workbook.sourceType, 'pdf');
    expect(preview.validCount, 2);

    expect(
      () => importer.workbookFromPdfText('scan.pdf', 'صورة بلا بيانات'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('صورة ممسوحة'),
        ),
      ),
    );
  });

  test('التقرير الشهري يحسب أيام الدراسة والانضباط حسب النطاق', () async {
    final gradeId = await classes.addGrade('سادس', userId: managerId);
    final classId = await classes.addClass(gradeId, '1', userId: managerId);
    final student = await students.create(
      name: 'طالب التقرير',
      nationalId: '1088888888',
      gradeId: gradeId,
      classId: classId,
      userId: managerId,
    );
    await database.db.update(
      'students',
      {'created_at': '2026-08-17T05:00:00.000Z'},
      where: 'id = ?',
      whereArgs: [student.id],
    );
    await database.db.insert('school_days', {
      'day': '2026-08-18',
      'type': 'holiday',
      'note': 'إجازة اختبارية',
    });
    final reloaded = (await students.getById(student.id))!;
    await attendance.record(
      student: reloaded,
      status: AttendanceStatus.present,
      userId: managerId,
      at: DateTime.utc(2026, 8, 17, 7),
    );
    await attendance.record(
      student: reloaded,
      status: AttendanceStatus.absent,
      userId: managerId,
      at: DateTime.utc(2026, 8, 19, 7),
    );

    final report = await reports.periodReport(
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 20),
      scope: ReportScope(
        type: ReportScopeType.schoolClass,
        label: 'سادس / 1',
        id: classId,
      ),
    );
    expect(report.schoolDays, 3);
    expect(report.totalStudents, 1);
    expect(report.students.single.expectedDays, 3);
    expect(report.present, 1);
    expect(report.absent, 1);
    expect(report.attendanceRate, closeTo(1 / 3, .0001));

    final analytics = await reports.analytics(
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 20),
    );
    expect(analytics.mostAbsent.single.studentId, student.id);
    expect(analytics.bestClass?.label, 'سادس / 1');
  });

  test('إغلاق اليوم وإعادة فتحه محميان ومسجلان في Audit Log', () async {
    const date = '2026-08-19';
    final student = await students.create(
      name: 'طالب لم يسجل',
      nationalId: '1055555555',
      userId: managerId,
    );
    await attendance.closeDay(
      userId: managerId,
      date: date,
      markUnregisteredAbsent: true,
    );
    expect(await attendance.isDayClosed(date), isTrue);
    expect(
      (await attendance.getForStudent(student.id, date: date))?.status,
      AttendanceStatus.absent,
    );

    await attendance.reopenDay(userId: managerId, date: date);
    expect(await attendance.isDayClosed(date), isFalse);
    final logs = await database.db.query(
      'audit_logs',
      where: "action IN ('day_close', 'day_reopen')",
      orderBy: 'id',
    );
    expect(logs.map((row) => row['action']), ['day_close', 'day_reopen']);
  });

  test('يكتشف عناوين مرنة ويستورد 500 طالب بلا تكرار', () async {
    final rows = <List<String>>[
      ['شعار المدرسة'],
      [],
      ['كشف الطلاب للعام الدراسي'],
      ['اسم المتعلم', 'رقم الهوية', 'الصف الدراسي', 'الشعبة', 'رقم الطالب'],
      for (var index = 0; index < 500; index++)
        [
          'طالب رقم ${index + 1}',
          '10${index.toString().padLeft(8, '0')}',
          'رابع',
          '1',
          '${2000 + index}',
        ],
    ];
    final workbook = ImportWorkbook(
      fileName: 'students.xlsx',
      sourceType: 'xlsx',
      sheets: [ImportSheetData(name: 'الطلاب', rows: rows)],
    );
    final importer = StudentImportService(
      database: database,
      students: students,
      classes: classes,
    );
    final preview = await importer.preview(workbook);

    expect(preview.headerRowIndex, 3);
    expect(preview.validCount, 500);
    expect(preview.duplicateCount, 0);

    final result = await importer.import(preview, userId: managerId);
    final imported = await students.getAll();
    expect(result.imported, 500);
    expect(imported.length, 500);
    expect(imported.map((student) => student.barcodeToken).toSet().length, 500);

    for (final student in imported.take(30)) {
      await attendance.record(
        student: student,
        status: AttendanceStatus.present,
        userId: managerId,
      );
    }
    final schoolClass = (await classes.getClasses()).single;
    final summary = await attendance.summary(classId: schoolClass.id);
    expect(summary.totalStudents, 500);
    expect(summary.registered, 30);
    expect(summary.remaining, 470);
  });
}
