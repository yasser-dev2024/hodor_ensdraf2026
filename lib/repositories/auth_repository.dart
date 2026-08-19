import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/app_user.dart';
import '../services/data_protection_service.dart';

enum CredentialKind { pin, password }

class AuthenticationResult {
  const AuthenticationResult._({this.user, this.message, this.lockedUntil});

  const AuthenticationResult.success(AppUser user) : this._(user: user);

  const AuthenticationResult.failure(String message) : this._(message: message);

  const AuthenticationResult.locked(DateTime until)
    : this._(
        message: 'تم إيقاف المحاولات مؤقتًا لحماية الحساب.',
        lockedUntil: until,
      );

  final AppUser? user;
  final String? message;
  final DateTime? lockedUntil;

  bool get isSuccess => user != null;
}

class AuthRepository {
  AuthRepository(this._database, this._protection);

  final AppDatabase _database;
  final DataProtectionService _protection;
  static const _uuid = Uuid();
  static const _setupSetting = 'auth_setup_complete';
  static const _maxFailedAttempts = 5;
  static const _lockDuration = Duration(minutes: 5);

  Future<bool> needsInitialSetup() async {
    final setting = await _database.db.query(
      'settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_setupSetting],
      limit: 1,
    );
    if (setting.isEmpty || setting.first['value'] != '1') return true;
    final managers = await _database.db.rawQuery(
      'SELECT COUNT(*) AS count FROM users WHERE active = 1 AND role = ?',
      [UserRole.manager.name],
    );
    return (managers.first['count'] as int) == 0;
  }

  Future<AppUser> setupInitialManager({
    required String name,
    required String password,
    String? pin,
  }) async {
    final normalizedName = _validateName(name);
    final effectivePin = _effectivePin(pin);
    _validatePassword(password);
    if (!await needsInitialSetup()) {
      throw StateError('تم إعداد مدير النظام مسبقًا.');
    }

    final pinSalt = _protection.newSalt();
    final passwordSalt = _protection.newSalt();
    final pinHash = await _protection.hashPin(effectivePin, pinSalt);
    final passwordHash = await _protection.hashPin(password, passwordSalt);
    final now = DateTime.now().toUtc().toIso8601String();
    final legacyManagers = await _database.db.query(
      'users',
      columns: const ['id'],
      where: 'active = 1 AND role = ?',
      whereArgs: [UserRole.manager.name],
      orderBy: 'created_at',
      limit: 1,
    );
    final id = legacyManagers.isEmpty
        ? _uuid.v4()
        : legacyManagers.first['id'] as String;

    await _database.db.transaction((txn) async {
      final values = <String, Object?>{
        'name': normalizedName,
        'role': UserRole.manager.name,
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'failed_attempts': 0,
        'locked_until': null,
        'biometric_enabled': 0,
        'active': 1,
      };
      if (legacyManagers.isEmpty) {
        await txn.insert('users', {'id': id, ...values, 'created_at': now});
      } else {
        await txn.update('users', values, where: 'id = ?', whereArgs: [id]);
      }
      await _writeSetting(txn, _setupSetting, '1', now);
      await _audit(
        txn,
        action: 'auth_setup',
        entityId: id,
        userId: id,
        at: now,
        newValue: {'name': normalizedName, 'role': UserRole.manager.name},
      );
    });
    return AppUser(id: id, name: normalizedName, role: UserRole.manager);
  }

  Future<bool> hasUsers() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS count FROM users WHERE active = 1',
    );
    return (result.first['count'] as int) > 0;
  }

  Future<AppUser> createInitialManager({
    required String name,
    required String pin,
    String? password,
  }) async {
    if (await hasUsers()) throw StateError('تم إعداد مستخدم للنظام مسبقًا.');
    return createUser(
      name: name,
      pin: pin,
      password: password,
      role: UserRole.manager,
      actorId: null,
      markSetupComplete: true,
    );
  }

  Future<AppUser> createUser({
    required String name,
    String? pin,
    String? password,
    required UserRole role,
    required String? actorId,
    bool markSetupComplete = false,
  }) async {
    if (actorId == null) {
      if (role != UserRole.manager || await hasUsers()) {
        throw StateError('يلزم مدير نشط لإنشاء المستخدم.');
      }
    } else {
      await _requireManager(actorId);
    }
    final normalizedName = _validateName(name);
    final effectivePin = _effectivePin(pin);
    final normalizedPassword = password?.trim() ?? '';
    if (normalizedPassword.isNotEmpty) _validatePassword(normalizedPassword);
    final duplicate = await _database.db.query(
      'users',
      columns: const ['id'],
      where: 'active = 1 AND name = ? AND role = ?',
      whereArgs: [normalizedName, role.name],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw const FormatException('هذا المستخدم مضاف مسبقًا.');
    }

    final id = _uuid.v4();
    final pinSalt = _protection.newSalt();
    final pinHash = await _protection.hashPin(effectivePin, pinSalt);
    String? passwordSalt;
    String? passwordHash;
    if (normalizedPassword.isNotEmpty) {
      passwordSalt = _protection.newSalt();
      passwordHash = await _protection.hashPin(
        normalizedPassword,
        passwordSalt,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('users', {
        'id': id,
        'name': normalizedName,
        'role': role.name,
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'failed_attempts': 0,
        'locked_until': null,
        'biometric_enabled': 0,
        'active': 1,
        'created_at': now,
      });
      if (markSetupComplete) {
        await _writeSetting(txn, _setupSetting, '1', now);
      }
      await _audit(
        txn,
        action: 'user_create',
        entityId: id,
        userId: actorId ?? id,
        at: now,
        newValue: {'name': normalizedName, 'role': role.name},
      );
    });
    return AppUser(id: id, name: normalizedName, role: role);
  }

  Future<AuthenticationResult> authenticate({
    required String userId,
    required String secret,
    required CredentialKind kind,
  }) async {
    final rows = await _database.db.query(
      'users',
      where: 'id = ? AND active = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const AuthenticationResult.failure('الحساب غير متاح.');
    }
    final row = rows.first;
    final now = DateTime.now().toUtc();
    final lockedRaw = row['locked_until'] as String?;
    if (lockedRaw != null) {
      final lockedUntil = DateTime.tryParse(lockedRaw);
      if (lockedUntil != null && lockedUntil.isAfter(now)) {
        return AuthenticationResult.locked(lockedUntil);
      }
    }

    var hashColumn = kind == CredentialKind.pin ? 'pin_hash' : 'password_hash';
    var saltColumn = kind == CredentialKind.pin ? 'pin_salt' : 'password_salt';
    var expected = row[hashColumn] as String?;
    var salt = row[saltColumn] as String?;
    // Older local accounts may have been created before password support.
    // Let their previous PIN work in the single password field so an update
    // never locks the school out of its own data.
    if (kind == CredentialKind.password && (expected == null || salt == null)) {
      hashColumn = 'pin_hash';
      saltColumn = 'pin_salt';
      expected = row[hashColumn] as String?;
      salt = row[saltColumn] as String?;
    }
    if (expected == null || salt == null) {
      return const AuthenticationResult.failure(
        'لا توجد كلمة مرور لهذا الحساب. استخدم PIN أو اطلب من المدير تعيين كلمة مرور.',
      );
    }

    final actual = await _protection.hashPin(secret, salt);
    if (!_constantTimeEquals(actual, expected)) {
      final failures = (row['failed_attempts'] as int? ?? 0) + 1;
      final lockUntil = failures >= _maxFailedAttempts
          ? now.add(_lockDuration)
          : null;
      await _database.db.transaction((txn) async {
        await txn.update(
          'users',
          {
            'failed_attempts': lockUntil == null ? failures : 0,
            'locked_until': lockUntil?.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
        await _audit(
          txn,
          action: 'login_failure',
          entityId: userId,
          userId: userId,
          at: now.toIso8601String(),
          newValue: {'credential': kind.name, 'locked': lockUntil != null},
        );
      });
      if (lockUntil != null) return AuthenticationResult.locked(lockUntil);
      final remaining = _maxFailedAttempts - failures;
      return AuthenticationResult.failure(
        'بيانات الدخول غير صحيحة. تبقت $remaining محاولات.',
      );
    }

    await _database.db.transaction((txn) async {
      await txn.update(
        'users',
        {
          'failed_attempts': 0,
          'locked_until': null,
          'last_login_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      await _audit(
        txn,
        action: 'login_success',
        entityId: userId,
        userId: userId,
        at: now.toIso8601String(),
        newValue: {'credential': kind.name},
      );
    });
    return AuthenticationResult.success(_mapUser(row));
  }

  Future<AppUser?> loginUser({
    required String userId,
    required String pin,
  }) async {
    final result = await authenticate(
      userId: userId,
      secret: pin,
      kind: CredentialKind.pin,
    );
    return result.user;
  }

  Future<AppUser?> loginWithPassword({
    required String userId,
    required String password,
  }) async {
    final result = await authenticate(
      userId: userId,
      secret: password,
      kind: CredentialKind.password,
    );
    return result.user;
  }

  Future<List<AppUser>> getUsers({UserRole? role}) async {
    final rows = await _database.db.query(
      'users',
      where: role == null ? 'active = 1' : 'active = 1 AND role = ?',
      whereArgs: role == null ? null : [role.name],
      orderBy: 'name',
    );
    return rows.map(_mapUser).toList();
  }

  Future<AppUser?> getUserById(String id) async {
    final rows = await _database.db.query(
      'users',
      where: 'id = ? AND active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapUser(rows.first);
  }

  Future<AppUser?> getBiometricUser(String id) async {
    final rows = await _database.db.query(
      'users',
      where: 'id = ? AND active = 1 AND biometric_enabled = 1',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapUser(rows.first);
  }

  Future<void> setBiometricEnabled({
    required String userId,
    required bool enabled,
  }) async {
    await _database.db.update(
      'users',
      {'biometric_enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> resetCredentials({
    required String userId,
    String? pin,
    String? password,
    required String actorId,
  }) async {
    await _requireManager(actorId);
    final normalizedPassword = password?.trim() ?? '';
    final normalizedPin = pin?.trim() ?? '';
    if (normalizedPin.isEmpty && normalizedPassword.isEmpty) {
      throw const FormatException('أدخل كلمة مرور جديدة.');
    }
    if (normalizedPin.isNotEmpty) _validatePin(normalizedPin);
    if (normalizedPassword.isNotEmpty) _validatePassword(normalizedPassword);
    final values = <String, Object?>{
      'failed_attempts': 0,
      'locked_until': null,
    };
    if (normalizedPin.isNotEmpty) {
      final pinSalt = _protection.newSalt();
      values['pin_salt'] = pinSalt;
      values['pin_hash'] = await _protection.hashPin(normalizedPin, pinSalt);
    }
    if (normalizedPassword.isNotEmpty) {
      final passwordSalt = _protection.newSalt();
      values['password_salt'] = passwordSalt;
      values['password_hash'] = await _protection.hashPin(
        normalizedPassword,
        passwordSalt,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update('users', values, where: 'id = ?', whereArgs: [userId]);
      await _audit(
        txn,
        action: 'user_credentials_reset',
        entityId: userId,
        userId: actorId,
        at: now,
        newValue: {'password_changed': normalizedPassword.isNotEmpty},
      );
    });
  }

  Future<void> deactivateUser({
    required String userId,
    required String actorId,
  }) async {
    await _requireManager(actorId);
    if (userId == actorId) {
      throw StateError('لا يمكنك تعطيل حسابك الحالي.');
    }
    final target = await getUserById(userId);
    if (target == null) return;
    if (target.role == UserRole.manager) {
      final managers = await _database.db.rawQuery(
        'SELECT COUNT(*) AS count FROM users WHERE active = 1 AND role = ?',
        [UserRole.manager.name],
      );
      if ((managers.first['count'] as int) <= 1) {
        throw StateError('لا يمكن تعطيل آخر مدير للنظام.');
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update(
        'users',
        {'active': 0, 'biometric_enabled': 0},
        where: 'id = ?',
        whereArgs: [userId],
      );
      await _audit(
        txn,
        action: 'user_deactivate',
        entityId: userId,
        userId: actorId,
        at: now,
        oldValue: {'active': true},
        newValue: {'active': false},
      );
    });
  }

  static String _validateName(String name) {
    final normalized = name.trim();
    if (normalized.length < 2) {
      throw const FormatException('أدخل اسمًا صحيحًا للمستخدم.');
    }
    return normalized;
  }

  Future<void> _requireManager(String userId) async {
    final rows = await _database.db.query(
      'users',
      columns: const ['role'],
      where: 'id = ? AND active = 1',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['role'] != UserRole.manager.name) {
      throw StateError('هذه العملية متاحة للمدير فقط.');
    }
  }

  static void _validatePin(String pin) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('يجب أن يتكون رمز PIN من 6 إلى 12 رقمًا.');
    }
    if (_isWeakPin(pin)) {
      throw const FormatException('اختر رمز PIN أقوى وغير متسلسل.');
    }
  }

  static String _effectivePin(String? value) {
    final provided = value?.trim() ?? '';
    if (provided.isNotEmpty) {
      _validatePin(provided);
      return provided;
    }
    final random = Random.secure();
    while (true) {
      final generated = List.generate(12, (_) => random.nextInt(10)).join();
      if (!_isWeakPin(generated)) return generated;
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 8 ||
        !RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      throw const FormatException(
        'كلمة المرور يجب أن تكون 8 محارف على الأقل وتحتوي حرفًا ورقمًا.',
      );
    }
  }

  static bool _isWeakPin(String pin) {
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return true;
    const weak = {
      '123456',
      '654321',
      '012345',
      '1234567',
      '12345678',
      '87654321',
    };
    return weak.contains(pin);
  }

  static AppUser _mapUser(Map<String, Object?> row) => AppUser(
    id: row['id'] as String,
    name: row['name'] as String,
    role: UserRole.values.firstWhere((role) => role.name == row['role']),
  );

  static bool _constantTimeEquals(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var difference = left.length ^ right.length;
    for (var i = 0; i < left.length && i < right.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  static Future<void> _writeSetting(
    Transaction txn,
    String key,
    String value,
    String at,
  ) => txn.rawInsert(
    '''
      INSERT INTO settings(key, value, updated_at) VALUES(?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
    ''',
    [key, value, at],
  );

  static Future<void> _audit(
    Transaction txn, {
    required String action,
    required String entityId,
    required String userId,
    required String at,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
  }) => txn.insert('audit_logs', {
    'action': action,
    'entity_type': 'user',
    'entity_id': entityId,
    'user_id': userId,
    'occurred_at': at,
    'old_value': oldValue == null ? null : jsonEncode(oldValue),
    'new_value': newValue == null ? null : jsonEncode(newValue),
  });
}
