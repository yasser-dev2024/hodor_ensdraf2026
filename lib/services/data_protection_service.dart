import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DataProtectionService {
  DataProtectionService._(this._keyBytes);

  static const _keyName = 'morning_attendance_data_key_v1';
  Uint8List _keyBytes;
  final _cipher = AesGcm.with256bits();
  final _hmac = Hmac.sha256();
  // This namespace key is intentionally installation-independent and must
  // never be rotated: changing it would invalidate every printed v2 card.
  // It keeps the civil ID out of the QR payload, while the per-installation
  // key above continues to protect the stored student data.
  static final SecretKey _barcodeDerivationKey = SecretKey(
    utf8.encode('sa.school.attendance.permanent-student-card.v2.2026'),
  );

  static Future<DataProtectionService> create() async {
    const storage = FlutterSecureStorage();
    var encoded = await storage.read(key: _keyName);
    if (encoded == null) {
      final bytes = _secureBytes(32);
      encoded = base64UrlEncode(bytes);
      await storage.write(key: _keyName, value: encoded);
    }
    return DataProtectionService._(base64Url.decode(encoded));
  }

  factory DataProtectionService.forTesting(List<int> bytes) =>
      DataProtectionService._(Uint8List.fromList(bytes));

  static Uint8List _secureBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<String> encrypt(String value) async {
    final nonce = _secureBytes(12);
    final box = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: SecretKey(_keyBytes),
      nonce: nonce,
    );
    return base64UrlEncode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> decrypt(String encoded) async {
    final bytes = base64Url.decode(encoded);
    if (bytes.length < 29) {
      throw const FormatException('Invalid protected value');
    }
    final nonce = bytes.sublist(0, 12);
    final mac = Mac(bytes.sublist(bytes.length - 16));
    final cipherText = bytes.sublist(12, bytes.length - 16);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: SecretKey(_keyBytes),
    );
    return utf8.decode(clear);
  }

  Future<String> searchableHash(String value) async {
    final mac = await _hmac.calculateMac(
      utf8.encode(normalizeNationalId(value)),
      secretKey: SecretKey(_keyBytes),
    );
    return base64UrlEncode(mac.bytes);
  }

  Future<String> hashPin(String pin, String salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: pin,
      nonce: base64Url.decode(salt),
    );
    return base64UrlEncode(await key.extractBytes());
  }

  String newSalt() => base64UrlEncode(_secureBytes(16));
  Future<String> stableBarcodeToken(String nationalId) async {
    final normalized = normalizeNationalId(nationalId);
    if (!RegExp(r'^\d{10}$').hasMatch(normalized)) {
      throw const FormatException('السجل المدني غير صالح لإنشاء الباركود.');
    }
    final mac = await _hmac.calculateMac(
      utf8.encode('student:$normalized'),
      secretKey: _barcodeDerivationKey,
    );
    return 'stu_v2_${base64UrlEncode(mac.bytes).replaceAll('=', '')}';
  }

  static bool isStableBarcodeToken(String value) =>
      RegExp(r'^stu_v2_[A-Za-z0-9_-]{43}$').hasMatch(value.trim());

  static bool isLegacyBarcodeToken(String value) {
    final token = value.trim();
    return !isStableBarcodeToken(token) &&
        RegExp(r'^stu_[A-Za-z0-9_-]{20,80}$').hasMatch(token);
  }

  Uint8List exportKeyForEncryptedBackup() => Uint8List.fromList(_keyBytes);

  Future<void> importKeyFromEncryptedBackup(List<int> bytes) async {
    if (bytes.length != 32) {
      throw const FormatException('مفتاح النسخة الاحتياطية غير صالح.');
    }
    _keyBytes = Uint8List.fromList(bytes);
    const storage = FlutterSecureStorage();
    await storage.write(key: _keyName, value: base64UrlEncode(_keyBytes));
  }

  static String normalizeNationalId(String value) => value
      .replaceAll(RegExp(r'[^0-9٠-٩]'), '')
      .replaceAllMapped(
        RegExp('[٠-٩]'),
        (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m.group(0)!)}',
      );
}
