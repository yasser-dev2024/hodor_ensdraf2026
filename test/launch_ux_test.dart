import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/features/launch/launch_gate.dart';

void main() {
  testWidgets('لا يعرض أي واجهة تفعيل أو مفتاح دخول', (tester) async {
    const deviceCode = 'ABCD-EFGH-IJKL-MNOP-QRST';
    await tester.pumpWidget(
      MaterialApp(home: UsageAgreementScreen(onAccepted: _done)),
    );
    await tester.pump();

    expect(find.text(deviceCode), findsNothing);
    expect(find.text('تفعيل التطبيق'), findsNothing);
    expect(find.text('مفتاح التفعيل'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('أوافق وأتابع'), findsOneWidget);
  });
}

Future<void> _done() async {}
