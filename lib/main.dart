import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'services/app_error_logger.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      ErrorWidget.builder = buildSafeErrorWidget;
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          AppErrorLogger.record(
            details.exception,
            details.stack ?? StackTrace.current,
            category: 'flutter',
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          AppErrorLogger.record(error, stack, category: 'platform_async'),
        );
        return true;
      };
      runApp(const AttendanceBootstrap());
    },
    (error, stack) =>
        unawaited(AppErrorLogger.record(error, stack, category: 'root_zone')),
  );
}
