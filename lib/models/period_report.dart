enum ReportScopeType {
  school('المدرسة'),
  grade('صف'),
  schoolClass('فصل'),
  student('طالب');

  const ReportScopeType(this.label);
  final String label;
}

class ReportScope {
  const ReportScope({required this.type, required this.label, this.id});

  const ReportScope.school()
    : type = ReportScopeType.school,
      label = 'المدرسة كاملة',
      id = null;

  final ReportScopeType type;
  final String label;
  final String? id;
}

class StudentPeriodStat {
  const StudentPeriodStat({
    required this.studentId,
    required this.studentName,
    required this.classLabel,
    required this.expectedDays,
    required this.present,
    required this.absent,
    required this.excused,
  });

  final String studentId;
  final String studentName;
  final String classLabel;
  final int expectedDays;
  final int present;
  final int absent;
  final int excused;

  int get registered => present + absent + excused;
  double get disciplineRate => expectedDays == 0 ? 0 : present / expectedDays;
}

class PeriodReport {
  const PeriodReport({
    required this.startDate,
    required this.endDate,
    required this.scope,
    required this.schoolDays,
    required this.students,
  });

  final DateTime startDate;
  final DateTime endDate;
  final ReportScope scope;
  final int schoolDays;
  final List<StudentPeriodStat> students;

  int get totalStudents => students.length;
  int get expectedEntries =>
      students.fold(0, (sum, item) => sum + item.expectedDays);
  int get present => students.fold(0, (sum, item) => sum + item.present);
  int get absent => students.fold(0, (sum, item) => sum + item.absent);
  int get excused => students.fold(0, (sum, item) => sum + item.excused);
  double get attendanceRate =>
      expectedEntries == 0 ? 0 : present / expectedEntries;
}

class ClassPeriodStat {
  const ClassPeriodStat({
    required this.label,
    required this.expectedEntries,
    required this.present,
    required this.absent,
  });

  final String label;
  final int expectedEntries;
  final int present;
  final int absent;
  double get attendanceRate =>
      expectedEntries == 0 ? 0 : present / expectedEntries;
}

class AttendanceAnalytics {
  const AttendanceAnalytics({
    required this.report,
    required this.mostAbsent,
    required this.mostDisciplined,
    required this.mostExcused,
    required this.bestClass,
    required this.mostAbsentClass,
  });

  final PeriodReport report;
  final List<StudentPeriodStat> mostAbsent;
  final List<StudentPeriodStat> mostDisciplined;
  final List<StudentPeriodStat> mostExcused;
  final ClassPeriodStat? bestClass;
  final ClassPeriodStat? mostAbsentClass;
}

class ReportArchiveEntry {
  const ReportArchiveEntry({
    required this.id,
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    required this.scopeType,
    required this.scopeId,
    required this.filePath,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String reportType;
  final String periodStart;
  final String periodEnd;
  final String scopeType;
  final String? scopeId;
  final String filePath;
  final DateTime createdAt;
  final String createdBy;
}
