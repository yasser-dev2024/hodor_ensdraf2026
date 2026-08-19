import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/services/official_student_pdf_parser.dart';

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
}
