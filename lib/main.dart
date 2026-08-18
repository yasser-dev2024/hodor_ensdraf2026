import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/app_database.dart';
import 'services/data_protection_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final database = await AppDatabase.open();
  final dataProtection = await DataProtectionService.create();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        dataProtectionProvider.overrideWithValue(dataProtection),
      ],
      child: const AttendanceApp(),
    ),
  );
}
