import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:morning_student_attendance/core/school_day_formatter.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  test('يعرض اليوم بالتاريخ الميلادي والهجري وفق تقويم أم القرى', () {
    final date = DateTime(2025, 3, 1);

    expect(SchoolDayFormatter.key(date), '2025-03-01');
    expect(SchoolDayFormatter.gregorianLong(date), contains('2025'));
    expect(SchoolDayFormatter.hijriLong(date), '1 رمضان 1446 هـ');
    expect(SchoolDayFormatter.dualInline(date), contains('رمضان'));
  });

  test('يرفض مفتاح تاريخ غير موجود عند تحويله', () {
    expect(
      () => SchoolDayFormatter.parseKey('not-a-date'),
      throwsA(isA<FormatException>()),
    );
  });
}
