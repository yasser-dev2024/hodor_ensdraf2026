import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/bootstrap.dart';

void main() {
  testWidgets('يعرض خطأ تهيئة واضحًا بدل الشاشة الفارغة', (tester) async {
    await tester.pumpWidget(
      AttendanceBootstrap(
        initialize: () async => throw StateError('bootstrap failed'),
      ),
    );
    await tester.pump();

    expect(find.text('تعذر تشغيل التطبيق'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}
