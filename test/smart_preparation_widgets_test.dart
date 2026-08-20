import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/features/dashboard/smart_preparation_section.dart';
import 'package:morning_student_attendance/features/reports/daily_review_sheet.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/models/daily_preparation.dart';

void main() {
  test('الرادار ينتقل للفصل التالي غير المكتمل ويتجاوز المكتمل والمراجعة', () {
    ClassPreparationStatus item(String id, ClassPreparationState state) =>
        ClassPreparationStatus(
          classId: id,
          gradeId: 'g1',
          gradeName: 'السادس',
          className: id,
          totalStudents: 10,
          registeredStudents: state == ClassPreparationState.complete ? 10 : 0,
          state: state,
        );
    final snapshot = DailyPreparationSnapshot(
      date: DateTime(2026, 8, 21),
      classes: [
        item('c1', ClassPreparationState.complete),
        item('c2', ClassPreparationState.needsReview),
        item('c3', ClassPreparationState.incomplete),
        item('c4', ClassPreparationState.incomplete),
      ],
      summary: const DailySummary(
        totalStudents: 40,
        registered: 10,
        present: 10,
        absent: 0,
        excused: 0,
      ),
      unassignedStudents: 0,
    );

    expect(snapshot.nextIncompleteAfter('c1')?.classId, 'c3');
    expect(snapshot.nextIncompleteAfter('c3')?.classId, 'c4');
    expect(snapshot.nextIncompleteAfter('c4')?.classId, 'c3');
  });

  testWidgets('الواجهة الذكية وبصمة اليوم لا تسببان overflow على هاتف ضيق', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = 0;
    final date = DateTime(2026, 8, 21, 7, 41);
    final snapshot = DailyPreparationSnapshot(
      date: date,
      classes: [
        ClassPreparationStatus(
          classId: 'c1',
          gradeId: 'g1',
          gradeName: 'السادس',
          className: '1',
          totalStudents: 25,
          registeredStudents: 25,
          presentStudents: 23,
          absentStudents: 1,
          excusedStudents: 1,
          state: ClassPreparationState.complete,
          completedAt: date,
        ),
        ClassPreparationStatus(
          classId: 'c2',
          gradeId: 'g1',
          gradeName: 'السادس',
          className: '2',
          totalStudents: 25,
          registeredStudents: 25,
          state: ClassPreparationState.complete,
          completedAt: date,
        ),
      ],
      summary: const DailySummary(
        totalStudents: 50,
        registered: 50,
        present: 47,
        absent: 2,
        excused: 1,
      ),
      unassignedStudents: 0,
      completedAt: date,
    );

    for (final size in const [Size(320, 700), Size(375, 812), Size(430, 932)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _TestApp(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SmartPreparationSection(
                snapshot: snapshot,
                now: date,
                onClassTap: (_) => tapped++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'مقاس $size');
    }

    expect(find.text('رادار الفصول'), findsOneWidget);
    expect(
      find.textContaining('سجّل الغائبين والمستأذنين فقط'),
      findsOneWidget,
    );
    expect(find.text('الغياب 1 • الاستئذان 1'), findsOneWidget);
    expect(find.text('بصمة اليوم'), findsOneWidget);
    expect(find.text('حفظ PNG'), findsOneWidget);
    expect(find.text('مشاركة البطاقة'), findsOneWidget);
    final captureFinder = find.byKey(
      const ValueKey('daily-fingerprint-capture'),
    );
    await tester.ensureVisible(captureFinder);
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(captureFinder);
    final pngBytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    expect(pngBytes, isNotNull);
    expect(pngBytes!.take(4), [137, 80, 78, 71]);
    await tester.ensureVisible(find.text('السادس / 1'));
    await tester.tap(find.text('السادس / 1'));
    expect(tapped, 1);
  });

  testWidgets('مراجعة اليوم تعرض النجاح والتنبيه دون أزرار تصحيح تلقائي', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = DailyReviewResult(
      date: DateTime(2026, 8, 21),
      reviewedAt: DateTime(2026, 8, 21, 7, 30),
      issues: const [
        DailyReviewIssue(
          kind: DailyReviewIssueKind.unresolvedStudent,
          title: 'لم تُحسم حالة طالب الاختبار',
          details: 'لم تسجل حالة الطالب اليوم — السادس / 1.',
          studentId: 'student-1',
          studentName: 'طالب الاختبار',
          classId: 'class-1',
          classLabel: 'السادس / 1',
        ),
      ],
    );
    DailyReviewIssue? selected;

    await tester.pumpWidget(
      _TestApp(
        child: Scaffold(
          body: DailyReviewSheet(
            result: result,
            onIssueTap: (issue) => selected = issue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('لم يتم تعديل أو حذف أي سجل'), findsOneWidget);
    expect(find.text('لم تُحسم حالة طالب الاختبار'), findsOneWidget);
    expect(find.textContaining('تصحيح تلقائي'), findsNothing);
    await tester.tap(find.text('لم تُحسم حالة طالب الاختبار'));
    expect(selected?.studentId, 'student-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('مراجعة اليوم تعرض رسالة السلامة عند عدم وجود تعارضات', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: DailyReviewSheet(
          result: DailyReviewResult(
            date: DateTime(2026, 8, 21),
            reviewedAt: DateTime(2026, 8, 21, 7, 30),
            issues: const [],
          ),
          onIssueTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('تمت مراجعة بيانات اليوم — لا توجد تعارضات'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}
