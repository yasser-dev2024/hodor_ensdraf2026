import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/features/splash/splash_screen.dart';

void main() {
  testWidgets('يعرض شاشة الوزارة ثم ينتقل إلى التطبيق بسلاسة', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(child: Scaffold(body: Text('واجهة التطبيق'))),
      ),
    );

    expect(find.text('نظام الحضور الصباحي'), findsOneWidget);
    expect(find.text('تهيئة بيانات المدرسة'), findsOneWidget);
    expect(find.text('واجهة التطبيق'), findsOneWidget);

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('نظام الحضور الصباحي'), findsNothing);
    expect(find.text('واجهة التطبيق'), findsOneWidget);
  });
}
