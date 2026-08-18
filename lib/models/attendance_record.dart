enum AttendanceStatus {
  present('حاضر'),
  absent('غائب'),
  excused('مستأذن');

  const AttendanceStatus(this.label);
  final String label;

  static AttendanceStatus fromDb(String value) =>
      AttendanceStatus.values.firstWhere((item) => item.name == value);
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.attendanceDate,
    required this.recordedAt,
    required this.recordedBy,
    this.classLabel = '',
    this.reason,
    this.note,
    this.receiverName,
    this.departureAt,
  });
  final String id;
  final String studentId;
  final String studentName;
  final AttendanceStatus status;
  final String attendanceDate;
  final DateTime recordedAt;
  final String recordedBy;
  final String classLabel;
  final String? reason;
  final String? note;
  final String? receiverName;
  final DateTime? departureAt;
}

class DailySummary {
  const DailySummary({
    required this.totalStudents,
    required this.registered,
    required this.present,
    required this.absent,
    required this.excused,
  });
  final int totalStudents;
  final int registered;
  final int present;
  final int absent;
  final int excused;
  int get remaining => (totalStudents - registered).clamp(0, totalStudents);
  double get attendanceRate => totalStudents == 0 ? 0 : present / totalStudents;
}

class AttendanceSaveResult {
  const AttendanceSaveResult({required this.record, required this.wasExisting});
  final AttendanceRecord record;
  final bool wasExisting;
}
