import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/app_user.dart';
import '../services/data_protection_service.dart';

class AuthRepository {
  AuthRepository(this._database, this._protection);

  final AppDatabase _database;
  final DataProtectionService _protection;
  static const _uuid = Uuid();

  Future<bool> hasUsers() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS count FROM users WHERE active = 1',
    );
    return (result.first['count'] as int) > 0;
  }

  Future<AppUser> createInitialManager({
    required String name,
    required String pin,
  }) async {
    if (await hasUsers()) throw StateError('تم إعداد مستخدم للنظام مسبقًا.');
    return createUser(
      name: name,
      pin: pin,
      role: UserRole.manager,
      actorId: null,
    );
  }

  Future<AppUser> createUser({
    required String name,
    required String pin,
    required UserRole role,
    required String? actorId,
  }) async {
    _validatePin(pin);
    final id = _uuid.v4();
    final salt = _protection.newSalt();
    final hash = await _protection.hashPin(pin, salt);
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('users', {
        'id': id,
        'name': name.trim(),
        'role': role.name,
        'pin_hash': hash,
        'pin_salt': salt,
        'active': 1,
        'created_at': now,
      });
      await txn.insert('audit_logs', {
        'action': 'user_create',
        'entity_type': 'user',
        'entity_id': id,
        'user_id': actorId ?? id,
        'occurred_at': now,
        'new_value': jsonEncode({'name': name.trim(), 'role': role.name}),
      });
    });
    return AppUser(id: id, name: name.trim(), role: role);
  }

  Future<AppUser?> login(String pin) async {
    final rows = await _database.db.query(
      'users',
      where: 'active = 1',
      orderBy: 'created_at',
    );
    for (final row in rows) {
      final actual = await _protection.hashPin(pin, row['pin_salt'] as String);
      if (_constantTimeEquals(actual, row['pin_hash'] as String)) {
        await _database.db.update(
          'users',
          {'last_login_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        return AppUser(
          id: row['id'] as String,
          name: row['name'] as String,
          role: UserRole.values.firstWhere((role) => role.name == row['role']),
        );
      }
    }
    return null;
  }

  Future<List<AppUser>> getUsers() async {
    final rows = await _database.db.query(
      'users',
      where: 'active = 1',
      orderBy: 'name',
    );
    return rows
        .map(
          (row) => AppUser(
            id: row['id'] as String,
            name: row['name'] as String,
            role: UserRole.values.firstWhere(
              (role) => role.name == row['role'],
            ),
          ),
        )
        .toList();
  }

  Future<AppUser?> getUserById(String id) async {
    final rows = await _database.db.query(
      'users',
      where: 'id = ? AND active = 1',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return AppUser(
      id: row['id'] as String,
      name: row['name'] as String,
      role: UserRole.values.firstWhere((role) => role.name == row['role']),
    );
  }

  static void _validatePin(String pin) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('يجب أن يتكون رمز PIN من 6 إلى 12 رقمًا.');
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin) ||
        pin == '123456' ||
        pin == '654321') {
      throw const FormatException('اختر رمز PIN أقوى وغير متسلسل.');
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var difference = left.length ^ right.length;
    for (var i = 0; i < left.length && i < right.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
