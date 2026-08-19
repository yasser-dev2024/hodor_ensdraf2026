import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('قبول Android الفعلي', () {
    late FlutterDriver driver;

    setUpAll(() async {
      driver = await FlutterDriver.connect(timeout: const Duration(minutes: 2));
    });

    tearDownAll(() async {
      await driver.close();
    });

    test(
      'إعداد المدير وفتح الرئيسية والتقارير والترحيل دون شاشة فارغة',
      () async {
        const wait = Duration(seconds: 60);
        await driver.waitFor(
          find.byValueKey('setup_manager_name'),
          timeout: wait,
        );
        await _enter(driver, 'setup_manager_name', 'مدير اختبار الجهاز');
        await _enter(driver, 'setup_password', 'Integration@2026');
        await driver.tap(find.byValueKey('setup_submit'));

        await driver.waitFor(find.byValueKey('nav_home'), timeout: wait);
        await driver.waitFor(find.text('بدء تسجيل الحضور'), timeout: wait);

        await driver.tap(find.byValueKey('nav_reports'));
        await driver.waitFor(find.text('تقرير اليوم الحالي'), timeout: wait);
        await driver.waitFor(
          find.text('التقارير الأسبوعية والشهرية والفصلية'),
          timeout: wait,
        );
        await driver.waitFor(find.text('تقرير يوم سابق'), timeout: wait);
        await driver.waitFor(find.text('أرشيف ملفات التقارير'), timeout: wait);

        await driver.tap(find.text('التقارير الأسبوعية والشهرية والفصلية'));
        await driver.waitFor(
          find.text('لوحة الأفضل والأكثر — المدرسة كاملة'),
          timeout: wait,
        );
        await driver.tap(find.byTooltip('رجوع'));

        await driver.tap(find.byValueKey('nav_more'));
        await driver.waitFor(
          find.text('الترحيل السنوي وإدارة الدفعات'),
          timeout: wait,
        );
        await driver.tap(find.text('الترحيل السنوي وإدارة الدفعات'));
        await driver.waitFor(find.text('الترحيل السنوي'), timeout: wait);
        await driver.waitFor(find.text('تعطيل دفعة كاملة'), timeout: wait);
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

Future<void> _enter(FlutterDriver driver, String key, String value) async {
  await driver.tap(find.byValueKey(key));
  await driver.enterText(value);
}
