import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const _product = 'morning_student_attendance';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _usage();
    return;
  }

  final command = args.first;
  final options = _parseOptions(args.skip(1).toList());
  final secretFile = File(
    '${File.fromUri(Platform.script).parent.path}'
    '${Platform.pathSeparator}.activation_private_key',
  );

  switch (command) {
    case 'init':
      if (secretFile.existsSync()) {
        stderr.writeln(
          'Activation signing key already exists at ${secretFile.path}',
        );
        exitCode = 2;
        return;
      }
      final random = Random.secure();
      final seed = List<int>.generate(32, (_) => random.nextInt(256));
      secretFile.writeAsStringSync(_encode(seed), flush: true);
      stdout.writeln('Private signing key created outside Git tracking.');
      stdout.writeln('Public key: ${await _publicKey(seed)}');
      return;
    case 'public':
      final seed = _readSeed(secretFile);
      stdout.writeln(await _publicKey(seed));
      return;
    case 'issue':
      final device = _normalizeDevice(options['device'] ?? '');
      final licenseId = (options['license'] ?? '').trim();
      if (device.length != 20 || licenseId.isEmpty) {
        stderr.writeln(
          'issue requires --device XXXX-XXXX-XXXX-XXXX-XXXX '
          'and --license SCHOOL-ID',
        );
        exitCode = 2;
        return;
      }
      DateTime? expiresAt;
      if ((options['expires'] ?? '').isNotEmpty) {
        expiresAt = DateTime.tryParse(options['expires']!);
        if (expiresAt == null) {
          stderr.writeln('--expires must be an ISO date such as 2027-06-30');
          exitCode = 2;
          return;
        }
        expiresAt = DateTime.utc(
          expiresAt.year,
          expiresAt.month,
          expiresAt.day,
          23,
          59,
          59,
        );
      }
      final payload = <String, Object>{
        'v': 1,
        'product': _product,
        'licenseId': licenseId,
        'device': device,
        'issuedAt': DateTime.now().toUtc().toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      };
      final payloadBytes = utf8.encode(jsonEncode(payload));
      final seed = _readSeed(secretFile);
      final keyPair = await Ed25519().newKeyPairFromSeed(seed);
      final signature = await Ed25519().sign(payloadBytes, keyPair: keyPair);
      final token = '${_encode(payloadBytes)}.${_encode(signature.bytes)}';
      final output = options['out'];
      if (output != null && output.trim().isNotEmpty) {
        final file = File(output);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('$token\n', flush: true);
        stdout.writeln('Activation key written to ${file.path}');
      } else {
        stdout.writeln(token);
      }
      return;
    default:
      stderr.writeln('Unknown command: $command');
      _usage();
      exitCode = 2;
  }
}

List<int> _readSeed(File file) {
  if (!file.existsSync()) {
    throw StateError('Run `dart run tool/activation_key.dart init` first.');
  }
  final seed = _decode(file.readAsStringSync().trim());
  if (seed.length != 32) throw const FormatException('Invalid signing seed.');
  return seed;
}

Future<String> _publicKey(List<int> seed) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  return _encode(publicKey.bytes);
}

Map<String, String> _parseOptions(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final value = args[index];
    if (!value.startsWith('--') || index + 1 >= args.length) continue;
    result[value.substring(2)] = args[++index];
  }
  return result;
}

String _normalizeDevice(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

List<int> _decode(String value) {
  final padding = '=' * ((4 - value.length % 4) % 4);
  return base64Url.decode('$value$padding');
}

void _usage() {
  stdout.writeln('''
Offline activation key utility

  dart run tool/activation_key.dart init
  dart run tool/activation_key.dart public
  dart run tool/activation_key.dart issue --device XXXX-XXXX-XXXX-XXXX-XXXX \\
      --license SCHOOL-ID [--expires 2027-06-30] [--out activation.txt]

The private signing key is stored in tool/.activation_private_key and is
ignored by Git. Back it up securely; never commit or share it.
''');
}
