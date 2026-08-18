import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import 'data_protection_service.dart';

class BackupService {
  BackupService(this._database, this._protection);
  final AppDatabase _database;
  final DataProtectionService _protection;

  static const _magic = 'MSAB1';

  Future<File> createBackup({
    required String password,
    String prefix = 'attendance_backup',
  }) async {
    _validatePassword(password);
    final databasePath = _database.path;
    if (databasePath == null) throw StateError('مسار قاعدة البيانات غير متاح.');
    await _database.db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final dbBytes = await File(databasePath).readAsBytes();
    final keyBytes = _protection.exportKeyForEncryptedBackup();
    final digest = await Sha256().hash(dbBytes);
    final archive = Archive();
    final manifest = jsonEncode({
      'format': _magic,
      'schema_version': AppDatabase.schemaVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'database_sha256': base64UrlEncode(digest.bytes),
    });
    archive.addFile(
      ArchiveFile(
        'manifest.json',
        utf8.encode(manifest).length,
        utf8.encode(manifest),
      ),
    );
    archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
    archive.addFile(ArchiveFile('data_key.bin', keyBytes.length, keyBytes));
    final docs = await getApplicationDocumentsDirectory();
    final photos = Directory(p.join(docs.path, 'student_photos'));
    if (await photos.exists()) {
      await for (final entity in photos.list(followLinks: false)) {
        if (entity is! File) continue;
        final bytes = await entity.readAsBytes();
        archive.addFile(
          ArchiveFile('photos/${p.basename(entity.path)}', bytes.length, bytes),
        );
      }
    }
    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw StateError('تعذر ضغط النسخة الاحتياطية.');
    final protected = await _encrypt(Uint8List.fromList(zip), password);
    final backupDirectory = Directory(p.join(docs.path, 'backups'));
    await backupDirectory.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(backupDirectory.path, '${prefix}_$stamp.msab'));
    await file.writeAsBytes(protected, flush: true);
    return file;
  }

  Future<File> restoreBackup({
    required String backupPath,
    required String password,
  }) async {
    _validatePassword(password);
    final source = File(backupPath);
    if (!await source.exists()) {
      throw const FormatException('ملف النسخة الاحتياطية غير موجود.');
    }
    final clear = await _decrypt(await source.readAsBytes(), password);
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(clear, verify: true);
    } catch (_) {
      throw const FormatException(
        'النسخة الاحتياطية تالفة أو كلمة المرور غير صحيحة.',
      );
    }
    final manifestFile = archive.findFile('manifest.json');
    final databaseFile = archive.findFile('database.sqlite');
    final keyFile = archive.findFile('data_key.bin');
    if (manifestFile == null || databaseFile == null || keyFile == null) {
      throw const FormatException('مكونات النسخة الاحتياطية غير مكتملة.');
    }
    final manifest =
        jsonDecode(utf8.decode(List<int>.from(manifestFile.content)))
            as Map<String, dynamic>;
    if (manifest['format'] != _magic ||
        manifest['schema_version'] != AppDatabase.schemaVersion) {
      throw const FormatException(
        'إصدار النسخة الاحتياطية غير متوافق مع التطبيق.',
      );
    }
    final dbBytes = Uint8List.fromList(List<int>.from(databaseFile.content));
    final digest = await Sha256().hash(dbBytes);
    if (base64UrlEncode(digest.bytes) != manifest['database_sha256']) {
      throw const FormatException(
        'فشل التحقق من سلامة قاعدة البيانات داخل النسخة.',
      );
    }
    final temp = await getTemporaryDirectory();
    final candidate = File(p.join(temp.path, 'restore_candidate.sqlite'));
    await candidate.writeAsBytes(dbBytes, flush: true);
    final checkDb = await openReadOnlyDatabase(candidate.path);
    try {
      final integrity = await checkDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw const FormatException('قاعدة البيانات داخل النسخة غير سليمة.');
      }
      final version =
          (await checkDb.rawQuery('PRAGMA user_version')).first.values.first
              as int;
      if (version != AppDatabase.schemaVersion) {
        throw const FormatException('إصدار مخطط قاعدة البيانات غير متوافق.');
      }
    } finally {
      await checkDb.close();
    }
    final safetyBackup = await createBackup(
      password: password,
      prefix: 'before_restore',
    );
    final targetPath = _database.path;
    if (targetPath == null) throw StateError('مسار قاعدة البيانات غير متاح.');
    await _database.db.close();
    try {
      await _protection.importKeyFromEncryptedBackup(
        List<int>.from(keyFile.content),
      );
      await candidate.copy(targetPath);
      final docs = await getApplicationDocumentsDirectory();
      final photosDirectory = Directory(p.join(docs.path, 'student_photos'));
      await photosDirectory.create(recursive: true);
      for (final file in archive.files.where(
        (file) => file.isFile && file.name.startsWith('photos/'),
      )) {
        final safeName = p.basename(file.name);
        if (safeName.isEmpty) continue;
        await File(
          p.join(photosDirectory.path, safeName),
        ).writeAsBytes(List<int>.from(file.content), flush: true);
      }
      _database.db = await openDatabase(
        targetPath,
        version: AppDatabase.schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
      );
      final photoRows = await _database.db.query(
        'students',
        columns: ['id', 'photo_path'],
        where: 'photo_path IS NOT NULL',
      );
      for (final row in photoRows) {
        final oldPath = row['photo_path'] as String;
        final newPath = p.join(photosDirectory.path, p.basename(oldPath));
        await _database.db.update(
          'students',
          {'photo_path': newPath},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await _database.db.insert('audit_logs', {
        'action': 'backup_restore',
        'entity_type': 'system',
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'new_value': jsonEncode({
          'source': p.basename(backupPath),
          'safety_backup': safetyBackup.path,
        }),
      });
    } catch (_) {
      _database.db = await openDatabase(
        targetPath,
        version: AppDatabase.schemaVersion,
      );
      rethrow;
    }
    return safetyBackup;
  }

  Future<Uint8List> _encrypt(Uint8List clear, String password) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> _decrypt(Uint8List protected, String password) async {
    if (protected.length < 49 ||
        utf8.decode(protected.sublist(0, 5)) != _magic) {
      throw const FormatException('صيغة النسخة الاحتياطية غير صالحة.');
    }
    final salt = protected.sublist(5, 21);
    final nonce = protected.sublist(21, 33);
    final cipherText = protected.sublist(33, protected.length - 16);
    final mac = Mac(protected.sublist(protected.length - 16));
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: await _deriveKey(password, salt),
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      throw const FormatException('كلمة مرور النسخة غير صحيحة أو الملف تالف.');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 200000,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static void _validatePassword(String value) {
    if (value.length < 8) {
      throw const FormatException('استخدم كلمة مرور للنسخة لا تقل عن 8 أحرف.');
    }
  }
}
