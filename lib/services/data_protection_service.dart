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
  String newBarcodeToken() =>
      'stu_${base64UrlEncode(_secureBytes(24)).replaceAll('=', '')}';

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
