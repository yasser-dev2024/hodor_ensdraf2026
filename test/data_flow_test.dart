import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/data/app_database.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/models/import_models.dart';
import 'package:morning_student_attendance/repositories/attendance_repository.dart';
import 'package:morning_student_attendance/repositories/auth_repository.dart';
import 'package:morning_student_attendance/repositories/class_repository.dart';
import 'package:morning_student_attendance/repositories/student_repository.dart';
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
