import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/core/guardian_absence_message.dart';

void main() {
  test(
    'default guardian message includes name, date, school and excuse alert',
    () {
      final text = GuardianAbsenceMessage.render(
        template: null,
        studentName: 'محمد أحمد',
        date: '1448/03/26 هـ — 2026/09/08 م',
        schoolName: 'مدرسة الاختبار',
      );

      expect(text, contains('ابنكم محمد أحمد غائب لهذا اليوم'));
      expect(text, contains('1448/03/26'));
      expect(text, contains('عذر رسمي'));
      expect(text, contains('مدرسة الاختبار'));
    },
  );

  test('custom guardian message replaces all supported placeholders', () {
    final text = GuardianAbsenceMessage.render(
      template: 'تنبيه {student} | {date} | {school}',
      studentName: 'طالب',
      date: 'اليوم',
      schoolName: 'المدرسة',
    );

    expect(text, 'تنبيه طالب | اليوم | المدرسة');
  });
}
