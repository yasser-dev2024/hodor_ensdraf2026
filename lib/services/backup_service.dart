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
    await _addDirectoryToArchive(
      archive,
      photos,
      archivePrefix: 'assets/student_photos',
    );
    await _addDirectoryToArchive(
      archive,
      Directory(p.join(docs.path, 'report_archive')),
      archivePrefix: 'assets/report_archive',
    );
    final logoRows = await _database.db.query(
      'settings',
      columns: ['value'],
      where: "key = 'school_logo_path'",
      limit: 1,
    );
    if (logoRows.isNotEmpty) {
      final logo = File(logoRows.first['value'] as String);
      if (await logo.exists()) {
        final bytes = await logo.readAsBytes();
        archive.addFile(
          ArchiveFile(
            'assets/school_logo/${p.basename(logo.path)}',
            bytes.length,
            bytes,
          ),
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
    final backupSchemaVersion = manifest['schema_version'] as int?;
    if (manifest['format'] != _magic ||
        backupSchemaVersion == null ||
        backupSchemaVersion < 2 ||
        backupSchemaVersion > AppDatabase.schemaVersion) {
      throw const FormatException(
        'إصدار النسخة الاحتياطية غير متوافق مع التطبيق.',
      );
    }
    final dbBytes = Uint8List.fromList(List<int>.from(databaseFile.content));
    final restoredKey = List<int>.from(keyFile.content);
    if (restoredKey.length != 32) {
      throw const FormatException('مفتاح تشفير النسخة الاحتياطية غير صالح.');
    }
    final digest = await Sha256().hash(dbBytes);
    if (base64UrlEncode(digest.bytes) != manifest['database_sha256']) {
      throw const FormatException(
        'فشل التحقق من سلامة قاعدة البيانات داخل النسخة.',
      );
    }
    final temp = await getTemporaryDirectory();
    final restoreStamp = DateTime.now().microsecondsSinceEpoch;
    final candidate = File(
      p.join(temp.path, 'restore_candidate_$restoreStamp.sqlite'),
    );
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
      if (version != backupSchemaVersion) {
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
    final target = File(targetPath);
    final staged = File('$targetPath.restore_pending_$restoreStamp');
    final rollback = File('$targetPath.pre_restore_$restoreStamp');
    final oldKey = _protection.exportKeyForEncryptedBackup();
    var databaseWasSwapped = false;
    await candidate.copy(staged.path);
    try {
      await _database.db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await _database.db.close();
      if (!await target.exists()) {
        throw StateError('قاعدة البيانات الحالية غير موجودة.');
      }
      await target.rename(rollback.path);
      databaseWasSwapped = true;
      await _moveSidecarIfPresent('$targetPath-wal', '${rollback.path}-wal');
      await _moveSidecarIfPresent('$targetPath-shm', '${rollback.path}-shm');
      await staged.rename(targetPath);
      await _protection.importKeyFromEncryptedBackup(restoredKey);
      _database.db = await _openConfiguredDatabase(targetPath);
      final restoredIntegrity = await _database.db.rawQuery(
        'PRAGMA integrity_check',
      );
      if (restoredIntegrity.isEmpty ||
          restoredIntegrity.first.values.first.toString().toLowerCase() !=
              'ok') {
        throw const FormatException(
          'فشل فحص قاعدة البيانات بعد تثبيت النسخة المستعادة.',
        );
      }
      final protectedRows = await _database.db.query(
        'students',
        columns: ['national_id_encrypted'],
        limit: 1,
      );
      if (protectedRows.isNotEmpty) {
        await _protection.decrypt(
          protectedRows.first['national_id_encrypted'] as String,
        );
      }
      final docs = await getApplicationDocumentsDirectory();
      await _restoreManagedFiles(archive, docs);
      await _database.db.insert('audit_logs', {
        'action': 'backup_restore',
        'entity_type': 'system',
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'new_value': jsonEncode({
          'source': p.basename(backupPath),
          'safety_backup': safetyBackup.path,
        }),
      });
      await _deleteIfExists(rollback);
      await _deleteIfExists(File('${rollback.path}-wal'));
      await _deleteIfExists(File('${rollback.path}-shm'));
    } catch (_) {
      if (databaseWasSwapped) {
        if (_database.db.isOpen) await _database.db.close();
        await _deleteIfExists(target);
        await _deleteIfExists(File('$targetPath-wal'));
        await _deleteIfExists(File('$targetPath-shm'));
        if (await rollback.exists()) await rollback.rename(targetPath);
        await _moveSidecarIfPresent('${rollback.path}-wal', '$targetPath-wal');
        await _moveSidecarIfPresent('${rollback.path}-shm', '$targetPath-shm');
        await _protection.importKeyFromEncryptedBackup(oldKey);
      }
      if (!_database.db.isOpen) {
        _database.db = await _openConfiguredDatabase(targetPath);
      }
      rethrow;
    } finally {
      await _deleteIfExists(candidate);
      await _deleteIfExists(staged);
    }
    return safetyBackup;
  }

  Future<void> _restoreManagedFiles(Archive archive, Directory docs) async {
    final photosDirectory = Directory(p.join(docs.path, 'student_photos'));
    final reportsDirectory = Directory(p.join(docs.path, 'report_archive'));
    await photosDirectory.create(recursive: true);
    await reportsDirectory.create(recursive: true);
    String? restoredLogoPath;
    for (final entry in archive.files.where((entry) => entry.isFile)) {
      final safeName = p.basename(entry.name);
      if (safeName.isEmpty || safeName == '.' || safeName == '..') continue;
      File? destination;
      if (entry.name.startsWith('assets/student_photos/') ||
          entry.name.startsWith('photos/')) {
        destination = File(p.join(photosDirectory.path, safeName));
      } else if (entry.name.startsWith('assets/report_archive/')) {
        destination = File(p.join(reportsDirectory.path, safeName));
      } else if (entry.name.startsWith('assets/school_logo/')) {
        final extension = p.extension(safeName).toLowerCase();
        final safeExtension =
            {'.png', '.jpg', '.jpeg', '.webp'}.contains(extension)
            ? extension
            : '.png';
        destination = File(p.join(docs.path, 'school_logo$safeExtension'));
        restoredLogoPath = destination.path;
      }
      if (destination != null) {
        await destination.writeAsBytes(
          List<int>.from(entry.content),
          flush: true,
        );
      }
    }
    final photoRows = await _database.db.query(
      'students',
      columns: ['id', 'photo_path'],
      where: 'photo_path IS NOT NULL',
    );
    for (final row in photoRows) {
      final oldPath = row['photo_path'] as String;
      await _database.db.update(
        'students',
        {'photo_path': p.join(photosDirectory.path, p.basename(oldPath))},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    final reportRows = await _database.db.query(
      'report_archives',
      columns: ['id', 'file_path'],
    );
    for (final row in reportRows) {
      final oldPath = row['file_path'] as String;
      await _database.db.update(
        'report_archives',
        {'file_path': p.join(reportsDirectory.path, p.basename(oldPath))},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    if (restoredLogoPath != null) {
      await _database.db.rawInsert(
        '''
        INSERT INTO settings(key, value, updated_at) VALUES(?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        ''',
        [
          'school_logo_path',
          restoredLogoPath,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  }

  static Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory directory, {
    required String archivePrefix,
  }) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(
        ArchiveFile(
          '$archivePrefix/${p.basename(entity.path)}',
          bytes.length,
          bytes,
        ),
      );
    }
  }

  static Future<Database> _openConfiguredDatabase(String path) => openDatabase(
    path,
    version: AppDatabase.schemaVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
      await db.rawQuery('PRAGMA journal_mode = WAL');
    },
    onUpgrade: AppDatabase.upgradeSchemaForTesting,
  );

  static Future<void> _moveSidecarIfPresent(
    String sourcePath,
    String destinationPath,
  ) async {
    final source = File(sourcePath);
    if (await source.exists()) await source.rename(destinationPath);
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
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
