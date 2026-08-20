import 'attendance_record.dart';

enum ClassPreparationState { complete, incomplete, needsReview }

class ClassPreparationStatus {
  const ClassPreparationStatus({
    required this.classId,
    required this.gradeId,
    required this.gradeName,
    required this.className,
    required this.totalStudents,
    required this.registeredStudents,
    required this.state,
    this.completedAt,
    this.reviewReason,
  });

  final String classId;
  final String gradeId;
  final String gradeName;
  final String className;
  final int totalStudents;
  final int registeredStudents;
  final ClassPreparationState state;
  final DateTime? completedAt;
  final String? reviewReason;

  String get label => '$gradeName / $className';
  int get remainingStudents =>
      (totalStudents - registeredStudents).clamp(0, totalStudents);
  bool get isComplete => state == ClassPreparationState.complete;
  double get completionRate =>
      totalStudents == 0 ? 0 : (registeredStudents / totalStudents).clamp(0, 1);
}

class DailyPreparationSnapshot {
  const DailyPreparationSnapshot({
    required this.date,
    required this.classes,
    required this.summary,
    required this.unassignedStudents,
    this.completedAt,
  });

  final DateTime date;
  final List<ClassPreparationStatus> classes;
  final DailySummary summary;
  final int unassignedStudents;
  final DateTime? completedAt;

  int get totalClasses => classes.length;
  int get completedClasses => classes.where((item) => item.isComplete).length;
  int get remainingClasses => totalClasses - completedClasses;
  double get completionRate =>
      totalClasses == 0 ? 0 : completedClasses / totalClasses;
  bool get hasStarted => summary.registered > 0;
  bool get isComplete =>
      totalClasses > 0 &&
      completedClasses == totalClasses &&
      summary.remaining == 0 &&
      unassignedStudents == 0;
}

enum DailyReviewIssueKind {
  incompleteClass,
  unresolvedStudent,
  conflictingStatuses,
  duplicateRecord,
  missingBasicData,
  illogicalData,
}

class DailyReviewIssue {
  const DailyReviewIssue({
    required this.kind,
    required this.title,
    required this.details,
    this.classId,
    this.classLabel,
    this.studentId,
    this.studentName,
  });

  final DailyReviewIssueKind kind;
  final String title;
  final String details;
  final String? classId;
  final String? classLabel;
  final String? studentId;
  final String? studentName;

  bool get canNavigate => classId != null || studentId != null;
}

class DailyReviewResult {
  const DailyReviewResult({
    required this.date,
    required this.reviewedAt,
    required this.issues,
  });

  final DateTime date;
  final DateTime reviewedAt;
  final List<DailyReviewIssue> issues;

  bool get isClean => issues.isEmpty;
}
