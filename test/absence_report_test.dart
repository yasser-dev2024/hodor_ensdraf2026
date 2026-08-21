import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/models/attendance_record.dart';
import 'package:morning_student_attendance/services/report_service.dart';

void main() {
  test('تقرير الغياب يستبعد الحاضرين والمستأذنين دائمًا', () {
    final records = [
      _record('1', 'طالب حاضر', AttendanceStatus.present),
      _record('2', 'طالب غائب', AttendanceStatus.absent),
      _record('3', 'طالب مستأذن', AttendanceStatus.excused),
      _record('4', 'طالب غائب آخر', AttendanceStatus.absent),
    ];

    final absentees = ReportService.absentOnly(records);

    expect(absentees.map((record) => record.studentName), [
      'طالب غائب',
      'طالب غائب آخر',
    ]);
    expect(
      absentees.every((record) => record.status == AttendanceStatus.absent),
      isTrue,
    );
  });
}

AttendanceRecord _record(
  String id,
  String studentName,
  AttendanceStatus status,
) => AttendanceRecord(
  id: id,
  studentId: 'student-$id',
  studentName: studentName,
  status: status,
  attendanceDate: '2026-08-21',
  recordedAt: DateTime.utc(2026, 8, 21, 6),
  recordedBy: 'المختبر',
  classLabel: 'الصف الأول / أ',
);
