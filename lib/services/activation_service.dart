import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../repositories/key_value_store.dart';

class ActivationLicense {
  const ActivationLicense({
    required this.licenseId,
    required this.deviceCode,
    required this.issuedAt,
    this.expiresAt,
  });

  final String licenseId;
  final String deviceCode;
  final DateTime issuedAt;
  final DateTime? expiresAt;
}

class ActivationResult {
  const ActivationResult._({this.license, this.error});

  const ActivationResult.valid(ActivationLicense value)
    : this._(license: value);
  const ActivationResult.invalid(String message) : this._(error: message);

  final ActivationLicense? license;
  final String? error;
  bool get isValid => license != null;
}

class ActivationService {
  ActivationService(
    this._settings, {
    String verificationKey = _defaultPublicKey,
  }) : _verificationKey = verificationKey;

  final KeyValueStore _settings;
  final String _verificationKey;

  static const productId = 'morning_student_attendance';
  static const _installationIdKey = 'installation_id';
  static const _activationTokenKey = 'activation_token';

  // Ed25519 public verification key. Its private signing key remains only in
  // tool/.activation_private_key, which is excluded from Git.
  static const _defaultPublicKey =
      'fXGZmiwb0lUC3kzGccgOfn2XepBSpVX397O8ViHLSjY';

  Future<String> deviceCode() async {
    var installationId = await _settings.get(_installationIdKey);
    if (installationId == null || installationId.trim().isEmpty) {
      installationId = const Uuid().v4();
      await _settings.set(_installationIdKey, installationId);
    }
    final digest = await Sha256().hash(
      utf8.encode('$productId|${installationId.trim()}'),
    );
    final compact = digest.bytes
        .take(10)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return [
      for (var index = 0; index < compact.length; index += 4)
        compact.substring(index, index + 4),
    ].join('-');
  }

  Future<ActivationLicense?> validStoredLicense() async {
    final token = await _settings.get(_activationTokenKey);
    if (token == null || token.isEmpty) return null;
    final result = await verify(token);
    return result.license;
  }

  Future<ActivationResult> activate(String token) async {
    final cleaned = token.replaceAll(RegExp(r'\s+'), '');
    final result = await verify(cleaned);
    if (result.isValid) await _settings.set(_activationTokenKey, cleaned);
    return result;
  }

  Future<ActivationResult> verify(String token) async {
    try {
      if (token.length > 4096) {
        return const ActivationResult.invalid('مفتاح التفعيل طويل وغير صالح.');
      }
      final parts = token.replaceAll(RegExp(r'\s+'), '').split('.');
      if (parts.length != 2) {
        return const ActivationResult.invalid('صيغة مفتاح التفعيل غير صحيحة.');
      }
      final payloadBytes = _decode(parts[0]);
      final signatureBytes = _decode(parts[1]);
      final verified = await Ed25519().verify(
        payloadBytes,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(
            _decode(_verificationKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      if (!verified) {
        return const ActivationResult.invalid(
          'تعذر التحقق من توقيع مفتاح التفعيل.',
        );
      }

      final decoded = jsonDecode(utf8.decode(payloadBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['v'] != 1 ||
          decoded['product'] != productId) {
        return const ActivationResult.invalid(
          'مفتاح التفعيل غير مخصص لهذا التطبيق.',
        );
      }
      final licenseId = decoded['licenseId'];
      final tokenDevice = normalizeDeviceCode('${decoded['device'] ?? ''}');
      final issuedAt = DateTime.tryParse('${decoded['issuedAt'] ?? ''}');
      if (licenseId is! String ||
          licenseId.trim().isEmpty ||
          tokenDevice.length != 20 ||
          issuedAt == null) {
        return const ActivationResult.invalid(
          'بيانات مفتاح التفعيل ناقصة أو غير صالحة.',
        );
      }
      final currentDevice = normalizeDeviceCode(await deviceCode());
      if (tokenDevice != currentDevice) {
        return const ActivationResult.invalid(
          'مفتاح التفعيل مرتبط بجهاز آخر. أرسل رمز هذا الجهاز للمصمم.',
        );
      }
      DateTime? expiresAt;
      final expiresValue = decoded['expiresAt'];
      if (expiresValue != null) {
        expiresAt = DateTime.tryParse('$expiresValue')?.toUtc();
        if (expiresAt == null) {
          return const ActivationResult.invalid(
            'تاريخ انتهاء مفتاح التفعيل غير صالح.',
          );
        }
        if (DateTime.now().toUtc().isAfter(expiresAt)) {
          return const ActivationResult.invalid(
            'انتهت صلاحية مفتاح التفعيل. اطلب مفتاحًا جديدًا من المصمم.',
          );
        }
      }
      return ActivationResult.valid(
        ActivationLicense(
          licenseId: licenseId.trim(),
          deviceCode: await deviceCode(),
          issuedAt: issuedAt.toUtc(),
          expiresAt: expiresAt,
        ),
      );
    } on FormatException {
      return const ActivationResult.invalid('صيغة مفتاح التفعيل غير صحيحة.');
    } catch (_) {
      return const ActivationResult.invalid('تعذر التحقق من مفتاح التفعيل.');
    }
  }

  static String normalizeDeviceCode(String value) =>
      value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  static List<int> _decode(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }
}
