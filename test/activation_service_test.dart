import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:morning_student_attendance/repositories/key_value_store.dart';
import 'package:morning_student_attendance/services/activation_service.dart';
import 'package:morning_student_attendance/services/usage_policy_service.dart';
import 'package:test/test.dart';

void main() {
  late _MemoryStore store;
  late ActivationService activation;
  late SimpleKeyPair keyPair;

  setUp(() async {
    store = _MemoryStore();
    keyPair = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (index) => index),
    );
    final publicKey = await keyPair.extractPublicKey();
    activation = ActivationService(
      store,
      verificationKey: _encode(publicKey.bytes),
    );
  });

  test('يقبل مفتاحًا موقعًا ومربوطًا بالتثبيت ويحفظه', () async {
    final token = await _issue(
      keyPair: keyPair,
      device: await activation.deviceCode(),
      licenseId: 'SCHOOL-001',
    );

    final result = await activation.activate(token);

    expect(result.isValid, isTrue);
    expect(result.license?.licenseId, 'SCHOOL-001');
    expect((await activation.validStoredLicense())?.licenseId, 'SCHOOL-001');
  });

  test('يرفض مفتاح جهاز آخر والمفتاح المنتهي', () async {
    final otherDevice = await _issue(
      keyPair: keyPair,
      device: 'AAAA-BBBB-CCCC-DDDD-EEEE',
      licenseId: 'OTHER',
    );
    final expired = await _issue(
      keyPair: keyPair,
      device: await activation.deviceCode(),
      licenseId: 'EXPIRED',
      expiresAt: DateTime.utc(2020),
    );

    expect((await activation.activate(otherDevice)).isValid, isFalse);
    expect((await activation.activate(expired)).isValid, isFalse);
    expect(await activation.validStoredLicense(), isNull);
  });

  test('يحفظ قبول الإقرار لكل إصدار ويعيد طلبه عند تغير الإصدار', () async {
    final policy = UsagePolicyService(store);

    expect(await policy.isCurrentVersionAccepted(), isFalse);
    await policy.acceptCurrentVersion();
    expect(await policy.isCurrentVersionAccepted(), isTrue);

    await store.set(UsagePolicy.acceptedVersionKey, 'نسخة-قديمة');
    expect(await policy.isCurrentVersionAccepted(), isFalse);
  });
}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
  }
}

Future<String> _issue({
  required SimpleKeyPair keyPair,
  required String device,
  required String licenseId,
  DateTime? expiresAt,
}) async {
  final payload = <String, Object>{
    'v': 1,
    'product': ActivationService.productId,
    'licenseId': licenseId,
    'device': ActivationService.normalizeDeviceCode(device),
    'issuedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
  };
  final bytes = utf8.encode(jsonEncode(payload));
  final signature = await Ed25519().sign(bytes, keyPair: keyPair);
  return '${_encode(bytes)}.${_encode(signature.bytes)}';
}

String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
