import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/period_report.dart';

class ReportRepository {
  ReportRepository(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();
  static final _dayFormat = DateFormat('yyyy-MM-dd');

  Future<PeriodReport> periodReport({
    required DateTime startDate,
    required DateTime endDate,
    required ReportScope scope,
  }) async {
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    if (end.isBefore(start)) {
      throw const FormatException('تاريخ النهاية يسبق تاريخ البداية.');
    }
    if (end.difference(start).inDays > 730) {
      throw const FormatException('الحد الأقصى للفترة هو سنتان.');
    }
    if (scope.type != ReportScopeType.school &&
        (scope.id == null || scope.id!.trim().isEmpty)) {
      throw const FormatException('يجب تحديد نطاق التقرير.');
    }
    final conditions = <String>["s.status IN ('active', 'inactive')"];
    final args = <Object?>[];
    if (scope.type == ReportScopeType.student) {
      conditions.add('s.id = ?');
      args.add(scope.id);
    }
    conditions.add('date(s.created_at) <= ?');
    args.add(_dayFormat.format(end));
    final studentRows = await _database.db.rawQuery('''
      SELECT s.id, s.name, s.created_at, s.deleted_at,
             s.grade_id, s.class_id, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN grades g ON g.id = s.grade_id
      LEFT JOIN classes c ON c.id = s.class_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY g.sort_order, c.sort_order, s.name
    ''', args);
    final attendanceRows = await _database.db.rawQuery(
      '''
      SELECT a.student_id, a.status, COUNT(*) AS count
      FROM attendance a
      LEFT JOIN classes attendance_class
        ON attendance_class.id = a.class_id_snapshot
      WHERE a.attendance_date BETWEEN ? AND ?
        ${_attendanceScopeSql(scope.type)}
      GROUP BY a.student_id, a.status
    ''',
      [
        _dayFormat.format(start),
        _dayFormat.format(end),
        if (scope.id != null) scope.id,
      ],
    );
    final attendanceByStudent = <String, Map<String, int>>{};
    for (final row in attendanceRows) {
      attendanceByStudent.putIfAbsent(
        row['student_id'] as String,
        () => {},
      )[row['status'] as String] = row['count'] as int;
    }
    final transferRows = await _database.db.query(
      'transfers',
      columns: ['student_id', 'old_class_id', 'new_class_id', 'transferred_at'],
      orderBy: 'student_id, transferred_at',
    );
    final transfersByStudent = _groupTransfers(transferRows);
    final classRows = await _database.db.query(
      'classes',
      columns: ['id', 'grade_id'],
    );
    final classGrades = {
      for (final row in classRows)
        row['id'] as String: row['grade_id'] as String,
    };
    final calendarRows = await _database.db.query(
      'school_days',
      where: 'day BETWEEN ? AND ?',
      whereArgs: [_dayFormat.format(start), _dayFormat.format(end)],
    );
    final calendar = {
      for (final row in calendarRows)
        row['day'] as String: row['type'] as String,
    };
    final standardSchoolDays = _expectedDays(start, end, start, calendar);
    final students = <StudentPeriodStat>[];
    for (final row in studentRows) {
      final id = row['id'] as String;
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final deletedAt = row['deleted_at'] == null
          ? null
          : DateTime.parse(row['deleted_at'] as String).toLocal();
      int count(String status) => attendanceByStudent[id]?[status] ?? 0;
      final expectedDays = _expectedDaysForScope(
        start: start,
        end: end,
        enrolledAt: createdAt,
        leftAt: deletedAt,
        calendar: calendar,
        scope: scope,
        currentGradeId: row['grade_id'] as String?,
        currentClassId: row['class_id'] as String?,
        transfers: transfersByStudent[id] ?? const [],
        classGrades: classGrades,
      );
      final present = count('present');
      final absent = count('absent');
      final excused = count('excused');
      if ((scope.type == ReportScopeType.grade ||
              scope.type == ReportScopeType.schoolClass) &&
          expectedDays == 0 &&
          present + absent + excused == 0) {
        continue;
      }
      students.add(
        StudentPeriodStat(
          studentId: id,
          studentName: row['name'] as String,
          classLabel:
              scope.type == ReportScopeType.grade ||
                  scope.type == ReportScopeType.schoolClass
              ? scope.label
              : [row['grade_name'], row['class_name']]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' / '),
          expectedDays: expectedDays,
          present: present,
          absent: absent,
          excused: excused,
        ),
      );
    }
    return PeriodReport(
      startDate: start,
      endDate: end,
      scope: scope,
      schoolDays: standardSchoolDays,
      students: students,
    );
  }

  Future<AttendanceAnalytics> analytics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final report = await periodReport(
      startDate: startDate,
      endDate: endDate,
      scope: const ReportScope.school(),
    );
    final eligible = report.students
        .where((item) => item.expectedDays > 0)
        .toList();
    final mostAbsent = [...eligible.where((item) => item.absent > 0)]
      ..sort((a, b) => b.absent.compareTo(a.absent));
    final mostDisciplined = [...eligible]
      ..sort((a, b) {
        final rate = b.disciplineRate.compareTo(a.disciplineRate);
        return rate != 0 ? rate : b.present.compareTo(a.present);
      });
    final mostExcused = [...eligible.where((item) => item.excused > 0)]
      ..sort((a, b) => b.excused.compareTo(a.excused));
    final classes = await _classPeriodStats(
      start: _dateOnly(startDate),
      end: _dateOnly(endDate),
    );
    final byAttendance = [...classes]
      ..sort((a, b) => b.attendanceRate.compareTo(a.attendanceRate));
    final byAbsence = [...classes]
      ..sort((a, b) => b.absent.compareTo(a.absent));
    return AttendanceAnalytics(
      report: report,
      mostAbsent: mostAbsent.take(5).toList(),
      mostDisciplined: mostDisciplined.take(5).toList(),
      mostExcused: mostExcused.take(5).toList(),
      bestClass: byAttendance.firstOrNull,
      mostAbsentClass: byAbsence.firstOrNull,
    );
  }

  Future<ReportArchiveEntry> archiveFile({
    required File source,
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required ReportScope scope,
    required String userId,
  }) async {
    final id = _uuid.v4();
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'report_archive'));
    await directory.create(recursive: true);
    final extension = p.extension(source.path).toLowerCase();
    final destination = File(p.join(directory.path, '$id$extension'));
    await source.copy(destination.path);
    final now = DateTime.now().toUtc();
    await _database.db.transaction((txn) async {
      await txn.insert('report_archives', {
        'id': id,
        'report_type': reportType,
        'period_start': _dayFormat.format(periodStart),
        'period_end': _dayFormat.format(periodEnd),
        'scope_type': scope.type.name,
        'scope_id': scope.id,
        'file_path': destination.path,
        'created_at': now.toIso8601String(),
        'created_by': userId,
      });
      await txn.insert('audit_logs', {
        'action': 'report_archive_create',
        'entity_type': 'report_archive',
        'entity_id': id,
        'user_id': userId,
        'occurred_at': now.toIso8601String(),
        'new_value':
            '{"type":"$reportType","start":"${_dayFormat.format(periodStart)}","end":"${_dayFormat.format(periodEnd)}"}',
      });
    });
    return ReportArchiveEntry(
      id: id,
      reportType: reportType,
      periodStart: _dayFormat.format(periodStart),
      periodEnd: _dayFormat.format(periodEnd),
      scopeType: scope.type.name,
      scopeId: scope.id,
      filePath: destination.path,
      createdAt: now,
      createdBy: userId,
    );
  }

  Future<List<ReportArchiveEntry>> archives({
    String query = '',
    String? reportType,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (reportType != null) {
      conditions.add('r.report_type = ?');
      args.add(reportType);
    }
    if (query.trim().isNotEmpty) {
      conditions.add(
        '(r.period_start LIKE ? OR r.period_end LIKE ? OR r.scope_type LIKE ? OR COALESCE(g.name, c.name, s.name, \'\') LIKE ?)',
      );
      args.addAll(List<Object?>.filled(4, '%${query.trim()}%'));
    }
    final rows = await _database.db.rawQuery('''
      SELECT r.*, u.name AS user_name
      FROM report_archives r
      JOIN users u ON u.id = r.created_by
      LEFT JOIN grades g ON r.scope_type = 'grade' AND g.id = r.scope_id
      LEFT JOIN classes c ON r.scope_type = 'schoolClass' AND c.id = r.scope_id
      LEFT JOIN students s ON r.scope_type = 'student' AND s.id = r.scope_id
      ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
      ORDER BY r.created_at DESC
    ''', args);
    return rows
        .map(
          (row) => ReportArchiveEntry(
            id: row['id'] as String,
            reportType: row['report_type'] as String,
            periodStart: row['period_start'] as String,
            periodEnd: row['period_end'] as String,
            scopeType: row['scope_type'] as String,
            scopeId: row['scope_id'] as String?,
            filePath: row['file_path'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            createdBy: row['user_name'] as String,
          ),
        )
        .toList();
  }

  Future<List<ClassPeriodStat>> _classPeriodStats({
    required DateTime start,
    required DateTime end,
  }) async {
    final classRows = await _database.db.rawQuery('''
      SELECT c.id, c.grade_id, c.name AS class_name, g.name AS grade_name
      FROM classes c
      JOIN grades g ON g.id = c.grade_id
      ORDER BY g.sort_order, c.sort_order, c.name
    ''');
    final classLabels = {
      for (final row in classRows)
        row['id'] as String:
            '${row['grade_name'] as String} / ${row['class_name'] as String}',
    };
    final studentRows = await _database.db.query(
      'students',
      columns: ['id', 'class_id', 'created_at', 'deleted_at'],
      where: "status IN ('active', 'inactive') AND date(created_at) <= ?",
      whereArgs: [_dayFormat.format(end)],
    );
    final transferRows = await _database.db.query(
      'transfers',
      columns: ['student_id', 'old_class_id', 'new_class_id', 'transferred_at'],
      orderBy: 'student_id, transferred_at',
    );
    final transfersByStudent = _groupTransfers(transferRows);
    final calendarRows = await _database.db.query(
      'school_days',
      where: 'day BETWEEN ? AND ?',
      whereArgs: [_dayFormat.format(start), _dayFormat.format(end)],
    );
    final calendar = {
      for (final row in calendarRows)
        row['day'] as String: row['type'] as String,
    };
    final expectedByClass = <String, int>{};
    for (final row in studentRows) {
      _visitExpectedSchoolDays(
        start: start,
        end: end,
        enrolledAt: DateTime.parse(row['created_at'] as String).toLocal(),
        leftAt: row['deleted_at'] == null
            ? null
            : DateTime.parse(row['deleted_at'] as String).toLocal(),
        calendar: calendar,
        currentClassId: row['class_id'] as String?,
        transfers:
            transfersByStudent[row['id'] as String] ?? const <_TransferPoint>[],
        onSchoolDay: (classId) {
          if (classId != null && classLabels.containsKey(classId)) {
            expectedByClass[classId] = (expectedByClass[classId] ?? 0) + 1;
          }
        },
      );
    }
    final attendanceRows = await _database.db.rawQuery(
      '''
      SELECT class_id_snapshot, status, COUNT(*) AS count
      FROM attendance
      WHERE attendance_date BETWEEN ? AND ? AND class_id_snapshot IS NOT NULL
      GROUP BY class_id_snapshot, status
      ''',
      [_dayFormat.format(start), _dayFormat.format(end)],
    );
    final attendanceByClass = <String, Map<String, int>>{};
    for (final row in attendanceRows) {
      attendanceByClass.putIfAbsent(
        row['class_id_snapshot'] as String,
        () => {},
      )[row['status'] as String] = row['count'] as int;
    }
    final result = <ClassPeriodStat>[];
    for (final entry in classLabels.entries) {
      final expected = expectedByClass[entry.key] ?? 0;
      final counts = attendanceByClass[entry.key] ?? const <String, int>{};
      final present = counts['present'] ?? 0;
      final absent = counts['absent'] ?? 0;
      if (expected == 0 && present == 0 && absent == 0) continue;
      result.add(
        ClassPeriodStat(
          label: entry.value,
          expectedEntries: expected,
          present: present,
          absent: absent,
        ),
      );
    }
    return result;
  }

  static String _attendanceScopeSql(ReportScopeType type) => switch (type) {
    ReportScopeType.school => '',
    ReportScopeType.grade => 'AND attendance_class.grade_id = ?',
    ReportScopeType.schoolClass => 'AND a.class_id_snapshot = ?',
    ReportScopeType.student => 'AND a.student_id = ?',
  };

  static Map<String, List<_TransferPoint>> _groupTransfers(
    List<Map<String, Object?>> rows,
  ) {
    final result = <String, List<_TransferPoint>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['student_id'] as String, () => [])
          .add(
            _TransferPoint(
              oldClassId: row['old_class_id'] as String?,
              newClassId: row['new_class_id'] as String,
              day: _dateOnly(
                DateTime.parse(row['transferred_at'] as String).toLocal(),
              ),
            ),
          );
    }
    return result;
  }

  static int _expectedDaysForScope({
    required DateTime start,
    required DateTime end,
    required DateTime enrolledAt,
    required DateTime? leftAt,
    required Map<String, String> calendar,
    required ReportScope scope,
    required String? currentGradeId,
    required String? currentClassId,
    required List<_TransferPoint> transfers,
    required Map<String, String> classGrades,
  }) {
    var count = 0;
    _visitExpectedSchoolDays(
      start: start,
      end: end,
      enrolledAt: enrolledAt,
      leftAt: leftAt,
      calendar: calendar,
      currentClassId: currentClassId,
      transfers: transfers,
      onSchoolDay: (classId) {
        final matches = switch (scope.type) {
          ReportScopeType.school => true,
          ReportScopeType.student => true,
          ReportScopeType.schoolClass => classId == scope.id,
          ReportScopeType.grade =>
            classId == null
                ? transfers.isEmpty && currentGradeId == scope.id
                : classGrades[classId] == scope.id,
        };
        if (matches) count++;
      },
    );
    return count;
  }

  static void _visitExpectedSchoolDays({
    required DateTime start,
    required DateTime end,
    required DateTime enrolledAt,
    required DateTime? leftAt,
    required Map<String, String> calendar,
    required String? currentClassId,
    required List<_TransferPoint> transfers,
    required void Function(String? classId) onSchoolDay,
  }) {
    var cursor = enrolledAt.isAfter(start) ? _dateOnly(enrolledAt) : start;
    final lastRegisteredDay = leftAt == null ? end : _dateOnly(leftAt);
    final effectiveEnd = lastRegisteredDay.isBefore(end)
        ? lastRegisteredDay
        : end;
    if (cursor.isAfter(effectiveEnd)) return;
    var classId = transfers.isEmpty
        ? currentClassId
        : transfers.first.oldClassId;
    var transferIndex = 0;
    while (!cursor.isAfter(effectiveEnd)) {
      while (transferIndex < transfers.length &&
          !transfers[transferIndex].day.isAfter(cursor)) {
        classId = transfers[transferIndex].newClassId;
        transferIndex++;
      }
      if (_isSchoolDay(cursor, calendar)) onSchoolDay(classId);
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  static bool _isSchoolDay(DateTime day, Map<String, String> calendar) {
    final override = calendar[_dayFormat.format(day)];
    final defaultSchoolDay =
        day.weekday != DateTime.friday && day.weekday != DateTime.saturday;
    return override == 'school' ||
        override == 'exam' ||
        (override == null && defaultSchoolDay);
  }

  static int _expectedDays(
    DateTime start,
    DateTime end,
    DateTime enrolledAt,
    Map<String, String> calendar, {
    DateTime? leftAt,
  }) {
    var cursor = enrolledAt.isAfter(start) ? _dateOnly(enrolledAt) : start;
    final lastRegisteredDay = leftAt == null ? end : _dateOnly(leftAt);
    final effectiveEnd = lastRegisteredDay.isBefore(end)
        ? lastRegisteredDay
        : end;
    if (cursor.isAfter(effectiveEnd)) return 0;
    var count = 0;
    while (!cursor.isAfter(effectiveEnd)) {
      if (_isSchoolDay(cursor, calendar)) count++;
      cursor = cursor.add(const Duration(days: 1));
    }
    return count;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _TransferPoint {
  const _TransferPoint({
    required this.oldClassId,
    required this.newClassId,
    required this.day,
  });

  final String? oldClassId;
  final String newClassId;
  final DateTime day;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
