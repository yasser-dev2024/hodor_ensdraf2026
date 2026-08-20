import '../core/school_day_formatter.dart';
import '../data/app_database.dart';
import '../models/daily_preparation.dart';
import '../repositories/attendance_repository.dart';

class DailyPreparationService {
  DailyPreparationService(this._database, this._attendance);

  final AppDatabase _database;
  final AttendanceRepository _attendance;

  Future<DailyPreparationSnapshot> load(DateTime date) async {
    final day = SchoolDayFormatter.key(date);
    final summary = await _attendance.summary(date: day);
    final rows = await _database.db.rawQuery(
      '''
      SELECT
        c.id AS class_id,
        c.name AS class_name,
        c.grade_id AS grade_id,
        g.name AS grade_name,
        COUNT(DISTINCT s.id) AS total_students,
        COUNT(DISTINCT CASE WHEN a.id IS NOT NULL THEN s.id END) AS registered_students,
        COUNT(DISTINCT CASE WHEN a.status = 'present' THEN s.id END) AS present_students,
        COUNT(DISTINCT CASE WHEN a.status = 'absent' THEN s.id END) AS absent_students,
        COUNT(DISTINCT CASE WHEN a.status = 'excused' THEN s.id END) AS excused_students,
        COUNT(a.id) AS record_count,
        COUNT(DISTINCT CASE
          WHEN TRIM(s.name) = ''
            OR TRIM(s.national_id_encrypted) = ''
            OR TRIM(s.national_id_hash) = ''
            OR TRIM(s.barcode_token) = ''
            OR s.grade_id IS NULL
            OR s.class_id IS NULL
          THEN s.id END
        ) AS invalid_students,
        SUM(CASE
          WHEN a.id IS NOT NULL
            AND a.status NOT IN ('present', 'absent', 'excused')
          THEN 1 ELSE 0 END
        ) AS invalid_statuses,
        MAX(a.recorded_at) AS completed_at
      FROM classes c
      JOIN grades g ON g.id = c.grade_id
      LEFT JOIN students s
        ON s.class_id = c.id
        AND s.status = 'active'
        AND date(s.created_at) <= date(?)
      LEFT JOIN attendance a
        ON a.student_id = s.id
        AND a.attendance_date = ?
      GROUP BY c.id, c.name, c.grade_id, g.name, g.sort_order, c.sort_order
      ORDER BY g.sort_order, c.sort_order, c.name
      ''',
      [day, day],
    );

    final classes = rows
        .map((row) {
          final total = _asInt(row['total_students']);
          final registered = _asInt(row['registered_students']);
          final records = _asInt(row['record_count']);
          final invalidStudents = _asInt(row['invalid_students']);
          final invalidStatuses = _asInt(row['invalid_statuses']);
          final reasons = <String>[
            if (total == 0) 'لا يوجد طلاب نشطون في هذا الفصل',
            if (invalidStudents > 0)
              'بيانات أساسية ناقصة لدى $invalidStudents طالب',
            if (records > registered) 'توجد سجلات حضور مكررة',
            if (invalidStatuses > 0) 'توجد حالات حضور غير معروفة',
          ];
          final state = reasons.isNotEmpty
              ? ClassPreparationState.needsReview
              : registered >= total
              ? ClassPreparationState.complete
              : ClassPreparationState.incomplete;
          return ClassPreparationStatus(
            classId: row['class_id'] as String,
            gradeId: row['grade_id'] as String,
            gradeName: row['grade_name'] as String,
            className: row['class_name'] as String,
            totalStudents: total,
            registeredStudents: registered,
            presentStudents: _asInt(row['present_students']),
            absentStudents: _asInt(row['absent_students']),
            excusedStudents: _asInt(row['excused_students']),
            state: state,
            completedAt: state == ClassPreparationState.complete
                ? DateTime.tryParse(row['completed_at'] as String? ?? '')
                : null,
            reviewReason: reasons.isEmpty ? null : reasons.join('، '),
          );
        })
        .toList(growable: false);

    final unassignedRows = await _database.db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM students
      WHERE status = 'active'
        AND date(created_at) <= date(?)
        AND (class_id IS NULL OR grade_id IS NULL)
      ''',
      [day],
    );
    final unassigned = _asInt(unassignedRows.first['count']);
    final allClassesComplete =
        classes.isNotEmpty && classes.every((item) => item.isComplete);
    final allStudentsResolved = summary.remaining == 0 && unassigned == 0;
    final completedAt = allClassesComplete && allStudentsResolved
        ? _latestCompletion(classes)
        : null;

    return DailyPreparationSnapshot(
      date: SchoolDayFormatter.dateOnly(date),
      classes: classes,
      summary: summary,
      unassignedStudents: unassigned,
      completedAt: completedAt,
    );
  }

  Future<DailyReviewResult> review(DateTime date) async {
    final day = SchoolDayFormatter.key(date);
    final snapshot = await load(date);
    final issues = <DailyReviewIssue>[];

    if (snapshot.totalClasses == 0) {
      issues.add(
        const DailyReviewIssue(
          kind: DailyReviewIssueKind.missingBasicData,
          title: 'لا توجد فصول مضافة',
          details: 'أضف بيانات الصفوف والفصول قبل اعتماد تقرير اليوم.',
        ),
      );
    }

    for (final item in snapshot.classes) {
      if (item.state == ClassPreparationState.incomplete) {
        issues.add(
          DailyReviewIssue(
            kind: DailyReviewIssueKind.incompleteClass,
            title: 'الفصل ${item.label} لم يكتمل',
            details: '${item.remainingStudents} طالب دون حالة حضور محسومة.',
            classId: item.classId,
            classLabel: item.label,
          ),
        );
      } else if (item.state == ClassPreparationState.needsReview) {
        issues.add(
          DailyReviewIssue(
            kind: DailyReviewIssueKind.illogicalData,
            title: 'الفصل ${item.label} يحتاج مراجعة',
            details: item.reviewReason ?? 'توجد بيانات تستحق المراجعة.',
            classId: item.classId,
            classLabel: item.label,
          ),
        );
      }
    }

    final unresolvedRows = await _database.db.rawQuery(
      '''
      SELECT
        s.id AS student_id,
        s.name AS student_name,
        s.class_id AS class_id,
        c.name AS class_name,
        g.name AS grade_name
      FROM students s
      LEFT JOIN classes c ON c.id = s.class_id
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN attendance a
        ON a.student_id = s.id AND a.attendance_date = ?
      WHERE s.status = 'active'
        AND date(s.created_at) <= date(?)
        AND a.id IS NULL
      ORDER BY g.sort_order, c.sort_order, s.name COLLATE NOCASE
      ''',
      [day, day],
    );
    for (final row in unresolvedRows) {
      final classLabel = _classLabel(row);
      issues.add(
        DailyReviewIssue(
          kind: DailyReviewIssueKind.unresolvedStudent,
          title: 'لم تُحسم حالة ${row['student_name']}',
          details: classLabel.isEmpty
              ? 'الطالب بلا فصل محدد ولم تسجل حالته اليوم.'
              : 'لم تسجل حالة الطالب اليوم — $classLabel.',
          studentId: row['student_id'] as String,
          studentName: row['student_name'] as String,
          classId: row['class_id'] as String?,
          classLabel: classLabel.isEmpty ? null : classLabel,
        ),
      );
    }

    final duplicateRows = await _database.db.rawQuery(
      '''
      SELECT
        a.student_id,
        s.name AS student_name,
        s.class_id,
        c.name AS class_name,
        g.name AS grade_name,
        COUNT(*) AS record_count,
        COUNT(DISTINCT a.status) AS status_count
      FROM attendance a
      JOIN students s ON s.id = a.student_id
      LEFT JOIN classes c ON c.id = s.class_id
      LEFT JOIN grades g ON g.id = s.grade_id
      WHERE a.attendance_date = ?
      GROUP BY a.student_id, s.name, s.class_id, c.name, g.name
      HAVING COUNT(*) > 1
      ''',
      [day],
    );
    for (final row in duplicateRows) {
      final conflicting = _asInt(row['status_count']) > 1;
      final classLabel = _classLabel(row);
      issues.add(
        DailyReviewIssue(
          kind: conflicting
              ? DailyReviewIssueKind.conflictingStatuses
              : DailyReviewIssueKind.duplicateRecord,
          title: conflicting
              ? 'حالات متعارضة للطالب ${row['student_name']}'
              : 'سجل مكرر للطالب ${row['student_name']}',
          details: conflicting
              ? 'الطالب مسجل بأكثر من حالة في اليوم نفسه.'
              : 'يوجد ${row['record_count']} سجلات للطالب في اليوم نفسه.',
          studentId: row['student_id'] as String,
          studentName: row['student_name'] as String,
          classId: row['class_id'] as String?,
          classLabel: classLabel.isEmpty ? null : classLabel,
        ),
      );
    }

    final missingRows = await _database.db.rawQuery(
      '''
      SELECT
        s.id AS student_id,
        s.name AS student_name,
        s.class_id AS class_id,
        c.name AS class_name,
        g.name AS grade_name,
        CASE WHEN TRIM(s.name) = '' THEN 1 ELSE 0 END AS missing_name,
        CASE WHEN s.class_id IS NULL OR s.grade_id IS NULL THEN 1 ELSE 0 END AS missing_class,
        CASE
          WHEN TRIM(s.national_id_encrypted) = '' OR TRIM(s.national_id_hash) = ''
          THEN 1 ELSE 0 END AS missing_id,
        CASE WHEN TRIM(s.barcode_token) = '' THEN 1 ELSE 0 END AS missing_barcode
      FROM students s
      LEFT JOIN classes c ON c.id = s.class_id
      LEFT JOIN grades g ON g.id = s.grade_id
      WHERE s.status = 'active'
        AND date(s.created_at) <= date(?)
        AND (
          TRIM(s.name) = ''
          OR s.class_id IS NULL
          OR s.grade_id IS NULL
          OR TRIM(s.national_id_encrypted) = ''
          OR TRIM(s.national_id_hash) = ''
          OR TRIM(s.barcode_token) = ''
        )
      ''',
      [day],
    );
    for (final row in missingRows) {
      final missing = <String>[
        if (_asInt(row['missing_name']) == 1) 'الاسم',
        if (_asInt(row['missing_class']) == 1) 'الصف أو الفصل',
        if (_asInt(row['missing_id']) == 1) 'السجل المدني المحمي',
        if (_asInt(row['missing_barcode']) == 1) 'رمز QR',
      ];
      final classLabel = _classLabel(row);
      issues.add(
        DailyReviewIssue(
          kind: DailyReviewIssueKind.missingBasicData,
          title: 'بيانات أساسية ناقصة لدى ${row['student_name']}',
          details: 'الحقول المطلوب مراجعتها: ${missing.join('، ')}.',
          studentId: row['student_id'] as String,
          studentName: row['student_name'] as String,
          classId: row['class_id'] as String?,
          classLabel: classLabel.isEmpty ? null : classLabel,
        ),
      );
    }

    final illogicalRows = await _database.db.rawQuery(
      '''
      SELECT
        a.student_id,
        s.name AS student_name,
        s.class_id,
        c.name AS class_name,
        g.name AS grade_name,
        a.status,
        a.class_id_snapshot,
        a.departure_at
      FROM attendance a
      JOIN students s ON s.id = a.student_id
      LEFT JOIN classes c ON c.id = s.class_id
      LEFT JOIN grades g ON g.id = s.grade_id
      WHERE a.attendance_date = ?
        AND (
          a.status NOT IN ('present', 'absent', 'excused')
          OR a.class_id_snapshot IS NULL
          OR (a.departure_at IS NOT NULL AND a.status <> 'excused')
        )
      ''',
      [day],
    );
    for (final row in illogicalRows) {
      final reasons = <String>[
        if (!const {'present', 'absent', 'excused'}.contains(row['status']))
          'حالة حضور غير معروفة',
        if (row['class_id_snapshot'] == null) 'لم يُحفظ فصل الطالب وقت التسجيل',
        if (row['departure_at'] != null && row['status'] != 'excused')
          'وقت انصراف مع حالة لا تمثل الاستئذان',
      ];
      final classLabel = _classLabel(row);
      issues.add(
        DailyReviewIssue(
          kind: DailyReviewIssueKind.illogicalData,
          title: 'حالة تستحق المراجعة: ${row['student_name']}',
          details: '${reasons.join('، ')}.',
          studentId: row['student_id'] as String,
          studentName: row['student_name'] as String,
          classId: row['class_id'] as String?,
          classLabel: classLabel.isEmpty ? null : classLabel,
        ),
      );
    }

    return DailyReviewResult(
      date: SchoolDayFormatter.dateOnly(date),
      reviewedAt: DateTime.now(),
      issues: List.unmodifiable(issues),
    );
  }

  static int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;

  static String _classLabel(Map<String, Object?> row) => [
    row['grade_name'],
    row['class_name'],
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' / ');

  static DateTime? _latestCompletion(List<ClassPreparationStatus> classes) {
    DateTime? latest;
    for (final item in classes) {
      final value = item.completedAt;
      if (value != null && (latest == null || value.isAfter(latest))) {
        latest = value;
      }
    }
    return latest;
  }
}
