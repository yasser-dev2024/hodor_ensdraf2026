import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/school_day_formatter.dart';
import '../data/app_database.dart';
import '../models/attendance_record.dart';
import '../models/student.dart';

class ClosedAttendanceDayException implements Exception {
  const ClosedAttendanceDayException();
  @override
  String toString() => 'تم إغلاق الحضور لهذا اليوم. يلزم مدير لإعادة فتحه.';
}

class AttendanceRepository {
  AttendanceRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();
  String dayKey([DateTime? date]) => SchoolDayFormatter.key(date);

  Future<AttendanceSaveResult> record({
    required Student student,
    required AttendanceStatus status,
    required String userId,
    String? reason,
    String? note,
    String? receiverName,
    DateTime? departureAt,
    DateTime? at,
    String? attendanceDate,
  }) async {
    await _requireAttendanceWriter(userId);
    final now = (at ?? DateTime.now()).toUtc();
    final date = attendanceDate == null
        ? dayKey(at)
        : _validatedDayKey(attendanceDate);
    if (await isDayClosed(date)) throw const ClosedAttendanceDayException();
    final existing = await getForStudent(student.id, date: date);
    if (existing != null) {
      return AttendanceSaveResult(record: existing, wasExisting: true);
    }
    final id = _uuid.v4();
    await _database.db.transaction((txn) async {
      await txn.insert('attendance', {
        'id': id,
        'student_id': student.id,
        'status': status.name,
        'attendance_date': date,
        'recorded_at': now.toIso8601String(),
        'recorded_by': userId,
        'class_id_snapshot': student.classId,
        'reason': _emptyToNull(reason),
        'note': _emptyToNull(note),
        'receiver_name': _emptyToNull(receiverName),
        'departure_at': departureAt?.toUtc().toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await txn.insert('audit_logs', {
        'action': 'attendance_create',
        'entity_type': 'attendance',
        'entity_id': id,
        'user_id': userId,
        'occurred_at': now.toIso8601String(),
        'new_value': jsonEncode({
          'student_id': student.id,
          'status': status.name,
          'date': date,
        }),
      });
    });
    return AttendanceSaveResult(
      record: AttendanceRecord(
        id: id,
        studentId: student.id,
        studentName: student.name,
        status: status,
        attendanceDate: date,
        recordedAt: now,
        recordedBy: userId,
        classLabel: student.classLabel,
        reason: reason,
        note: note,
        receiverName: receiverName,
        departureAt: departureAt,
      ),
      wasExisting: false,
    );
  }

  Future<void> updateStatus({
    required String recordId,
    required AttendanceStatus status,
    required String userId,
  }) async {
    await _requireAttendanceWriter(userId);
    final rows = await _database.db.query(
      'attendance',
      where: 'id = ?',
      whereArgs: [recordId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('سجل الحضور غير موجود.');
    final old = rows.first['status'] as String;
    final date = rows.first['attendance_date'] as String;
    if (await isDayClosed(date)) throw const ClosedAttendanceDayException();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'attendance',
        {'status': status.name, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [recordId],
      );
      await txn.insert('audit_logs', {
        'action': 'attendance_update',
        'entity_type': 'attendance',
        'entity_id': recordId,
        'user_id': userId,
        'occurred_at': now,
        'old_value': jsonEncode({'status': old}),
        'new_value': jsonEncode({'status': status.name}),
      });
    });
  }

  Future<void> recordDeparture({
    required String recordId,
    required String userId,
    String? reason,
    String? note,
    String? receiverName,
    DateTime? at,
  }) async {
    await _requireAttendanceWriter(userId);
    final rows = await _database.db.query(
      'attendance',
      where: 'id = ?',
      whereArgs: [recordId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('سجل الحضور غير موجود.');
    final old = rows.first;
    final date = old['attendance_date'] as String;
    if (await isDayClosed(date)) throw const ClosedAttendanceDayException();
    final departure = (at ?? DateTime.now()).toUtc().toIso8601String();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'attendance',
        {
          'status': AttendanceStatus.excused.name,
          'reason': _emptyToNull(reason) ?? old['reason'],
          'note': _emptyToNull(note) ?? old['note'],
          'receiver_name': _emptyToNull(receiverName) ?? old['receiver_name'],
          'departure_at': departure,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );
      await txn.insert('audit_logs', {
        'action': 'attendance_departure',
        'entity_type': 'attendance',
        'entity_id': recordId,
        'user_id': userId,
        'occurred_at': now,
        'old_value': jsonEncode({
          'status': old['status'],
          'departure_at': old['departure_at'],
        }),
        'new_value': jsonEncode({
          'status': AttendanceStatus.excused.name,
          'departure_at': departure,
        }),
      });
    });
  }

  Future<AttendanceRecord?> getForStudent(
    String studentId, {
    String? date,
  }) async {
    final rows = await _database.db.rawQuery(
      '''
      SELECT a.*, s.name AS student_name, u.name AS user_name,
             g.name AS grade_name, c.name AS class_name
      FROM attendance a
      JOIN students s ON s.id = a.student_id
      JOIN users u ON u.id = a.recorded_by
      LEFT JOIN classes c ON c.id = a.class_id_snapshot
      LEFT JOIN grades g ON g.id = c.grade_id
      WHERE a.student_id = ? AND a.attendance_date = ? LIMIT 1
    ''',
      [studentId, date ?? dayKey()],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<AttendanceRecord>> getDaily({
    String? date,
    String? classId,
  }) async {
    final conditions = ['a.attendance_date = ?'];
    final args = <Object?>[date ?? dayKey()];
    if (classId != null) {
      conditions.add('a.class_id_snapshot = ?');
      args.add(classId);
    }
    final rows = await _database.db.rawQuery('''
      SELECT a.*, s.name AS student_name, u.name AS user_name,
             g.name AS grade_name, c.name AS class_name
      FROM attendance a
      JOIN students s ON s.id = a.student_id
      JOIN users u ON u.id = a.recorded_by
      LEFT JOIN classes c ON c.id = a.class_id_snapshot
      LEFT JOIN grades g ON g.id = c.grade_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY g.sort_order, c.sort_order, s.name
    ''', args);
    return rows.map(_fromRow).toList();
  }

  Future<List<AttendanceRecord>> getStudentHistory(
    String studentId, {
    String? startDate,
    String? endDate,
    int? limit,
  }) async {
    final conditions = <String>['a.student_id = ?'];
    final args = <Object?>[studentId];
    if (startDate != null) {
      conditions.add('a.attendance_date >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      conditions.add('a.attendance_date <= ?');
      args.add(endDate);
    }
    final safeLimit = limit == null ? '' : 'LIMIT ${limit.clamp(1, 10000)}';
    final rows = await _database.db.rawQuery('''
      SELECT a.*, s.name AS student_name, u.name AS user_name,
             g.name AS grade_name, c.name AS class_name
      FROM attendance a
      JOIN students s ON s.id = a.student_id
      JOIN users u ON u.id = a.recorded_by
      LEFT JOIN classes c ON c.id = a.class_id_snapshot
      LEFT JOIN grades g ON g.id = c.grade_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY a.attendance_date DESC, a.recorded_at DESC
      $safeLimit
    ''', args);
    return rows.map(_fromRow).toList();
  }

  Future<DailySummary> summary({String? date, String? classId}) async {
    final targetDate = date ?? dayKey();
    if (classId == null) {
      final closedRows = await _database.db.query(
        'closed_days',
        columns: const ['snapshot_json'],
        where: 'attendance_date = ? AND reopened_at IS NULL',
        whereArgs: [targetDate],
        limit: 1,
      );
      if (closedRows.isNotEmpty) {
        try {
          final snapshot =
              jsonDecode(closedRows.first['snapshot_json'] as String)
                  as Map<String, dynamic>;
          final value = snapshot['summary'] as Map<String, dynamic>;
          return DailySummary(
            totalStudents: value['total'] as int,
            registered: value['registered'] as int,
            present: value['present'] as int,
            absent: value['absent'] as int,
            excused: value['excused'] as int,
          );
        } catch (_) {
          // Older or damaged snapshots fall back to the live rows below.
        }
      }
    }
    final totalResult = await _database.db.rawQuery(
      "SELECT COUNT(*) AS count FROM students WHERE status = 'active' AND date(created_at) <= date(?) ${classId == null ? '' : 'AND class_id = ?'}",
      [targetDate, if (classId != null) classId],
    );
    final statusRows = await _database.db.rawQuery(
      '''
      SELECT status, COUNT(*) AS count FROM attendance
      WHERE attendance_date = ? ${classId == null ? '' : 'AND class_id_snapshot = ?'}
      GROUP BY status
    ''',
      [targetDate, if (classId != null) classId],
    );
    final counts = {
      for (final row in statusRows)
        row['status'] as String: row['count'] as int,
    };
    final present = counts['present'] ?? 0;
    final absent = counts['absent'] ?? 0;
    final excused = counts['excused'] ?? 0;
    return DailySummary(
      totalStudents: totalResult.first['count'] as int,
      registered: present + absent + excused,
      present: present,
      absent: absent,
      excused: excused,
    );
  }

  Future<List<Map<String, Object?>>> unregistered({
    String? date,
    String? classId,
  }) async {
    final targetDate = date ?? dayKey();
    return _database.db.rawQuery(
      '''
      SELECT s.id, s.name, s.class_id, g.name AS grade_name, c.name AS class_name
      FROM students s
      LEFT JOIN classes c ON c.id = s.class_id
      LEFT JOIN grades g ON g.id = s.grade_id
      WHERE s.status = 'active'
        ${classId == null ? '' : 'AND s.class_id = ?'}
        AND date(s.created_at) <= date(?)
        AND NOT EXISTS (
          SELECT 1 FROM attendance a
          WHERE a.student_id = s.id AND a.attendance_date = ?
        )
      ORDER BY g.sort_order, c.sort_order, s.name
    ''',
      [if (classId != null) classId, targetDate, targetDate],
    );
  }

  Future<Map<AttendanceStatus, int>> studentStats(String studentId) async {
    final rows = await _database.db.rawQuery(
      'SELECT status, COUNT(*) AS count FROM attendance WHERE student_id = ? GROUP BY status',
      [studentId],
    );
    return {
      for (final status in AttendanceStatus.values)
        status:
            rows
                .where((row) => row['status'] == status.name)
                .map((row) => row['count'] as int)
                .firstOrNull ??
            0,
    };
  }

  Future<List<String>> availableDates() async {
    final days = await availableDays();
    return days.map((day) => day.date).toList();
  }

  Future<List<AttendanceDayOverview>> availableDays() async {
    final rows = await _database.db.rawQuery('''
      SELECT days.attendance_date,
             COUNT(a.id) AS record_count,
             cd.closed_at,
             cd.reopened_at,
             u.name AS closed_by_name
      FROM (
        SELECT attendance_date FROM attendance
        UNION SELECT attendance_date FROM closed_days
      ) days
      LEFT JOIN attendance a ON a.attendance_date = days.attendance_date
      LEFT JOIN closed_days cd ON cd.attendance_date = days.attendance_date
      LEFT JOIN users u ON u.id = cd.closed_by
      GROUP BY days.attendance_date, cd.closed_at, cd.reopened_at, u.name
      ORDER BY days.attendance_date DESC
    ''');
    return rows.map(_dayOverviewFromRow).toList();
  }

  Future<AttendanceDayOverview> dayOverview(String date) async {
    final target = _validatedDayKey(date);
    final rows = await _database.db.rawQuery(
      '''
      SELECT ? AS attendance_date,
             COUNT(a.id) AS record_count,
             cd.closed_at,
             cd.reopened_at,
             u.name AS closed_by_name
      FROM (SELECT 1) seed
      LEFT JOIN attendance a ON a.attendance_date = ?
      LEFT JOIN closed_days cd ON cd.attendance_date = ?
      LEFT JOIN users u ON u.id = cd.closed_by
      GROUP BY cd.closed_at, cd.reopened_at, u.name
      ''',
      [target, target, target],
    );
    return _dayOverviewFromRow(rows.single);
  }

  Future<bool> isDayClosed(String date) async {
    final rows = await _database.db.query(
      'closed_days',
      columns: ['reopened_at'],
      where: 'attendance_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['reopened_at'] == null;
  }

  Future<void> reopenDay({required String userId, required String date}) async {
    await _requireManager(userId);
    final rows = await _database.db.query(
      'closed_days',
      where: 'attendance_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['reopened_at'] != null) {
      throw StateError('هذا اليوم غير مغلق.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'closed_days',
        {'reopened_at': now, 'reopened_by': userId},
        where: 'attendance_date = ?',
        whereArgs: [date],
      );
      await txn.insert('audit_logs', {
        'action': 'day_reopen',
        'entity_type': 'attendance_day',
        'entity_id': date,
        'user_id': userId,
        'occurred_at': now,
        'old_value': jsonEncode({'closed': true}),
        'new_value': jsonEncode({'closed': false}),
      });
    });
  }

  Future<void> closeDay({
    required String userId,
    String? date,
    bool markUnregisteredPresent = false,
  }) async {
    await _requireManager(userId);
    final target = date ?? dayKey();
    if (await isDayClosed(target)) {
      throw StateError('هذا اليوم مغلق مسبقًا.');
    }
    if (markUnregisteredPresent) {
      final remaining = await unregistered(date: target);
      final now = DateTime.now().toUtc().toIso8601String();
      await _database.db.transaction((txn) async {
        for (final student in remaining) {
          await txn.insert('attendance', {
            'id': _uuid.v4(),
            'student_id': student['id'],
            'status': AttendanceStatus.present.name,
            'attendance_date': target,
            'recorded_at': now,
            'recorded_by': userId,
            'class_id_snapshot': student['class_id'],
            'note': 'حضور تلقائي عند إغلاق اليوم بعد تسجيل الغياب والاستئذان',
            'updated_at': now,
          });
        }
        await txn.insert('audit_logs', {
          'action': 'attendance_bulk_present',
          'entity_type': 'attendance_day',
          'entity_id': target,
          'user_id': userId,
          'occurred_at': now,
          'new_value': jsonEncode({'count': remaining.length}),
        });
      });
    }
    final report = await getDaily(date: target);
    final summaryValue = await summary(date: target);
    final snapshot = jsonEncode({
      'summary': {
        'total': summaryValue.totalStudents,
        'registered': summaryValue.registered,
        'present': summaryValue.present,
        'absent': summaryValue.absent,
        'excused': summaryValue.excused,
      },
      'records': report
          .map(
            (r) => {
              'student_id': r.studentId,
              'student_name': r.studentName,
              'status': r.status.name,
              'recorded_at': r.recordedAt.toIso8601String(),
              'recorded_by': r.recordedBy,
            },
          )
          .toList(),
    });
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('closed_days', {
        'attendance_date': target,
        'closed_at': now,
        'closed_by': userId,
        'snapshot_json': snapshot,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('audit_logs', {
        'action': 'day_close',
        'entity_type': 'attendance_day',
        'entity_id': target,
        'user_id': userId,
        'occurred_at': now,
        'new_value': snapshot,
      });
    });
  }

  AttendanceRecord _fromRow(Map<String, Object?> row) => AttendanceRecord(
    id: row['id'] as String,
    studentId: row['student_id'] as String,
    studentName: row['student_name'] as String,
    status: AttendanceStatus.fromDb(row['status'] as String),
    attendanceDate: row['attendance_date'] as String,
    recordedAt: DateTime.parse(row['recorded_at'] as String),
    recordedBy: row['user_name'] as String,
    classLabel: [
      row['grade_name'],
      row['class_name'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' / '),
    reason: row['reason'] as String?,
    note: row['note'] as String?,
    receiverName: row['receiver_name'] as String?,
    departureAt: row['departure_at'] == null
        ? null
        : DateTime.parse(row['departure_at'] as String),
  );

  static String? _emptyToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  AttendanceDayOverview _dayOverviewFromRow(Map<String, Object?> row) {
    final closedAt = row['closed_at'] as String?;
    return AttendanceDayOverview(
      date: row['attendance_date'] as String,
      recordCount: row['record_count'] as int,
      isClosed: closedAt != null && row['reopened_at'] == null,
      closedAt: closedAt == null ? null : DateTime.parse(closedAt),
      closedBy: row['closed_by_name'] as String?,
    );
  }

  String _validatedDayKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('تاريخ يوم الحضور غير صالح.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || SchoolDayFormatter.key(parsed) != value) {
      throw const FormatException('تاريخ يوم الحضور غير صالح.');
    }
    return value;
  }

  Future<void> _requireAttendanceWriter(String userId) async {
    final rows = await _database.db.query(
      'users',
      columns: const ['role'],
      where: 'id = ? AND active = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty ||
        !const {'manager', 'attendanceOfficer'}.contains(rows.first['role'])) {
      throw StateError('لا يملك المستخدم صلاحية تسجيل أو تعديل الحضور.');
    }
  }

  Future<void> _requireManager(String userId) async {
    final rows = await _database.db.query(
      'users',
      columns: const ['role'],
      where: 'id = ? AND active = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['role'] != 'manager') {
      throw StateError('هذه العملية متاحة للمدير فقط.');
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
