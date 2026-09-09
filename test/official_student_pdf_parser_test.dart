import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/services/official_student_pdf_parser.dart';
import 'package:morning_student_attendance/services/student_guidance_workbook_parser.dart';

void main() {
  test('يقرأ سجل الطلاب الرسمي مع التفاف السطور وصيغ الحروف العربية', () {
    final rows = OfficialStudentPdfParser.parsePages([
      '44AD1171498759'
          'ا\ufe91\ufeaeا\u06be\ufbff\ufee2 '
          '\ufee3\ufe8e\ufee7\ufeca '
          '\ufecb\ufee0\ufef0 '
          'ا\ufedf\ufecc\ufeb4\ufbff\ufeaeي'
          'IBRAHIM MANA ALI ALASSIRI'
          '1171498759'
          'منتظمالسادس\n'
          'الابتدائي\n'
          'التعليم\n'
          'العام1مرفقمدقق\n'
          'مستمر في الدراسة\n'
          '0160233424'
          'ريان صادق عبده سعيد'
          'RAYEN SADG ABDOH SAYD'
          '4824817516'
          'منتظمالخامس\n'
          'الابتدائي\n'
          'التعليم\n'
          'العام2مرفقمدقق\n'
          'مستمر في الدراسة',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(3));
    expect(rows!.first, OfficialStudentPdfParser.headers);
    expect(rows[1], ['ابراهيم مانع على العسيري', '1171498759', 'السادس', '1']);
    expect(rows[2], ['ريان صادق عبده سعيد', '4824817516', 'الخامس', '2']);
  });

  test('يفك ترميز Arial CID المكسور في كشف بيانات الطلاب', () {
    final rows = OfficialStudentPdfParser.parsePages([
      "Student's Name\n"
          '1180687772\n'
          'رقم الهوية\n'
          'السعودية\n'
          '\u03f2\u03c5\u03d4\u03a3\u03df\u038d\u0003'
          '\u03d6\u03df\u038e\u03a7\u03df\u038d\u03a9\u0391\u03cb\u0003'
          '\u0bcc\u03a9\u0391\u03cb\u0003\u03ad\u03b3\u0381\n'
          '1\n'
          '06/12/2016\n'
          'Saudi\n'
          'ASIR ABDULLAH ABDULKHALIQ ALHIFTHI\n'
          '1179036049\n'
          'رقم الهوية\n'
          'السعودية\n'
          '\u03f2\u03e7\u038e\u03c1\u03a3\u03d8\u03df\u038d\u0003'
          '\u03ad\u03d3\u038e\u03c5\u0003\u03f2\u03e0\u03cb\u0003'
          '\u02ef\u038d\u03ad\u0391\u03df\u038d\n'
          '2\n'
          '21/07/2016\n'
          'Saudi\n'
          'ALBARAA ALI DHAFER ALQAHTANI\n'
          '4824817516\n'
          'رقم جواز سفر\n'
          'اليمنية\n'
          '\u03a9\u03f3\u03cc\u03b3\u0003\u03e9\u03a9\u0391\u03cb\u0003'
          '\u03d5\u03a9\u038e\u03bb\u0003\u03e5\u038e\u03f3\u03ad\n'
          '3\n'
          '12/08/2016\n'
          'Yemeni\n'
          'RAYEN SADG ABDOH SAYD\n'
          'الصف\n'
          'الرابع الابتدائي\n'
          'القسم\n'
          'التعليم العام\n'
          'الفصل\n'
          '1',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(4));
    expect(rows![1], [
      'آسر عبدالله عبدالخالق الحفظي',
      '1180687772',
      'الرابع',
      '1',
    ]);
    expect(rows[2], ['البراء علي ظافر القحطاني', '1179036049', 'الرابع', '1']);
    expect(rows[3], ['ريان صادق عبده سعيد', '4824817516', 'الرابع', '1']);
  });

  test('يفك ترميز كشف الطلاب العربي حتى دون عناوين إنجليزية', () {
    final normalized = OfficialStudentPdfParser.normalizeExtractedText(
      '\u0003ϝ΍ϭΟ\u0003ϡϗέ\n'
      'ΏϟΎρϟ΍\n'
      '\u0003ϥ΍ϭϧϫ\n'
      'Ώϳέϗϟ΍\n'
      '\u0003Ώϳέϗ\u0003ϡγ΍\n'
      'ΏϟΎρϟ΍\n'
      'ϝϡϋϠϟ΍\u0003ϡϤΎϫ\n'
      '21/04/1438\nReportID: test',
    );

    expect(normalized, contains('رقم جوال'));
    expect(normalized, contains('الطالب'));
  });

  test('يقرأ تجميع أعمدة PDFBox وتقسيم الهوية في تصدير الوزارة', () {
    final rows = OfficialStudentPdfParser.parsePages([
      'رقم جوال الطالب\n'
          '966557171\n'
          '919 ابها علي ناصر\n'
          'علي ناصر ال ماطر\n'
          'عسيري 1 118134814\n'
          '3 السعودية 21/04/1438 السعودية مستمر في\n'
          'الدراسة\n'
          'أسامه علي\n'
          'ناصر عسيري 1\n'
          '966572311\n'
          '047 رايف بندر\n'
          'صغير 1 09/04/1448 426525934\n'
          '3 اليمن 26/11/1436 السعودية مستمر في\n'
          'الدراسة\n'
          'اياد بندر حسن\n'
          'عمر 2\n'
          'التعليم العامالقسم\n'
          'الرابع الابتدائيالصف\n'
          '1الفصل',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(3));
    expect(rows![1], ['أسامه علي ناصر عسيري', '1181348143', 'الرابع', '1']);
    expect(rows[2], ['اياد بندر حسن عمر', '4265259343', 'الرابع', '1']);
  });

  test('يجمع طلاب كشف الوزارة عبر الصفحات المستمرة', () {
    final rows = OfficialStudentPdfParser.parsePages([
      'حالة القيد\n'
          'اسم الطالب\n'
          '1\n123456789\n0\nالسعودية\n01/01/1438\n'
          'مستمر في\nالدراسة\nالطالب الأول\n1\n'
          'الصف\nالرابع الابتدائي\nالفصل\n1',
      '1\n223456789\n0\nالسعودية\n02/01/1438\n'
          'مستمر في\nالدراسة\nالطالب الثاني\n2',
      '2\n323456789\n0\nالسعودية\n03/01/1438\n'
          'مستمر في الدراسة\nالطالب الثالث\n1\n'
          'الصف\nالرابع الابتدائي\nالفصل\n2',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(4));
    expect(rows![1], ['الطالب الأول', '1234567890', 'الرابع', '1']);
    expect(rows[2], ['الطالب الثاني', '2234567890', 'الرابع', '1']);
    expect(rows[3], ['الطالب الثالث', '3234567890', 'الرابع', '2']);
  });

  test('يجمع أوراق Excel الوزارية في جدول واحد', () {
    final rows = OfficialStudentPdfParser.parseWorkbookSheets([
      [
        ['الرابع الابتدائي', ':', 'الصف'],
        ['1', ':', 'الفصل'],
        ['رقم رخصة الاقامة', 'الفصل', 'حالة القيد', 'اسم الطالب'],
        ['1234567890', '1', 'مستمر في الدراسة', 'طالب أول'],
      ],
      [
        ['الرابع الابتدائي', ':', 'الصف'],
        ['2', ':', 'الفصل'],
        ['رقم رخصة الإقامة', 'الفصل', 'حالة القيد', 'اسم الطالب'],
        ['2234567890', '2', 'مستمر في الدراسة', 'طالب ثانٍ'],
      ],
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(3));
    expect(rows![1], [
      'طالب أول',
      '1234567890',
      'الرابع',
      '1',
      'المرحلة الابتدائية',
    ]);
    expect(rows[2][0], 'طالب ثانٍ');
    expect(rows[2][3], '2');
  });

  test('يحوّل نموذج الإرشاد إلى تحديث جوالات دون خلط رقم الطالب', () {
    final rows = StudentGuidanceWorkbookParser.parseSheets([
      [
        ['', 'Student Info Table'],
        ['', 'الجوال', 'الفصل', 'رقم الصف', 'اسم الطالب', 'رقم الطالب'],
        ['', '0501234567', '2', '0430', 'طالب تجريبي', '1234567890'],
      ],
    ]);

    expect(rows, isNotNull);
    expect(rows!.first, StudentGuidanceWorkbookParser.headers);
    expect(rows[1], [
      'طالب تجريبي',
      '1234567890',
      'الرابع',
      '2',
      'المرحلة الابتدائية',
      '966501234567',
    ]);
  });

  test('يقرأ كشف التحضير الصباحي PDF كتحديث جوالات فقط', () {
    final rows = OfficialStudentPdfParser.parseGuardianContactPages([
      '1448 هجري السنة الدراسية:\n'
          'بيانات برنامج التحضير الصباحي للطالب\n'
          'رقم الجوال الفصل رقم الهوية اسم الطالب م\n'
          '966533092156 الصف الخامس 1 1179134208 أحمد علي عبدالله القحطاني 1\n'
          '966535677372 الصف الخامس 1 1179863962 أحمد ناصر احمد عسيري 2',
    ]);

    expect(rows, isNotNull);
    expect(rows!.first, OfficialStudentPdfParser.guardianContactHeaders);
    expect(rows, hasLength(3));
    expect(rows[1], [
      'أحمد علي عبدالله القحطاني',
      '1179134208',
      'الخامس',
      '1',
      'المرحلة الابتدائية',
      '966533092156',
    ]);
  });

  test('يقرأ صفوف كشف التحضير الملتصقة والمعكوسة من محرك الجوال', () {
    final rows = OfficialStudentPdfParser.parseGuardianContactPages([
      'بيانات برنامج التحضير الصباحي للطالب\n'
          'رقم الجوالالفصلرقم الهويةاسم الطالبم\n'
          '966533092156الصف الخامس 11791342081أحمد علي عبدالله القحطاني1\n'
          'يان سعيد محمد عسيري10 966549893379الصف الخامس 11814215691ر\n'
          '540668670الصف الرابع 11847712004محمد عبدالله محمد آل مسلط26',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(4));
    expect(rows![1][0], 'أحمد علي عبدالله القحطاني');
    expect(rows[1][5], '966533092156');
    expect(rows[2][0], 'ريان سعيد محمد عسيري');
    expect(rows[2][1], '1181421569');
    expect(rows[3][5], '966540668670');
  });

  test('يجمع جوال ولي الأمر المقسوم داخل كشف الوزارة PDF', () {
    final rows = OfficialStudentPdfParser.parseGuardianContactPages([
      'كشف الطلاب\n'
          'رقم جوال الطالب\n'
          '966557171\n'
          '919 ابها علي ناصر\n'
          'علي ناصر ال ماطر\n'
          'عسيري 1 118134814\n'
          '3 السعودية 21/04/1438 السعودية مستمر في\n'
          'الدراسة\n'
          'أسامه علي\n'
          'ناصر عسيري 1\n'
          'الرابع الابتدائيالصف\n'
          '1الفصل',
    ]);

    expect(rows, isNotNull);
    expect(rows, hasLength(2));
    expect(rows![1], [
      'أسامه علي ناصر عسيري',
      '1181348143',
      'الرابع',
      '1',
      'المرحلة الابتدائية',
      '966557171919',
    ]);
  });
}
