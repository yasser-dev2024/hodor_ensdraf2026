class AcademicYearRecord {
  const AcademicYearRecord({
    required this.id,
    required this.label,
    required this.isCurrent,
    required this.startedAt,
    required this.createdAt,
    this.endedAt,
    this.closedBy,
    this.activeStudents = 0,
    this.graduatedStudents = 0,
  });

  final String id;
  final String label;
  final bool isCurrent;
  final DateTime startedAt;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String? closedBy;
  final int activeStudents;
  final int graduatedStudents;
}

class GradeGraduationResult {
  const GradeGraduationResult({required this.graduated});

  final int graduated;
}
