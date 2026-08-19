# إصدار iPhone وiPad

المشروع مضبوط على iOS 13 فأحدث، ويحتوي على أوصاف الكاميرا والصور وFace ID. لا يمكن توقيع نسخة Apple على Windows.

على جهاز macOS موثوق:

1. ثبّت Flutter 3.32.4 وXcode وCocoaPods.
2. شغّل `flutter pub get` ثم `cd ios && pod install`.
3. افتح `Runner.xcworkspace` وحدد فريق Apple وBundle ID تابعًا للمدرسة.
4. اختبر الكاميرا وFace ID واستيراد PDF على iPhone/iPad حقيقي.
5. شغّل `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist` بعد نسخ المثال وتخصيصه.
6. ارفع الأرشيف إلى App Store Connect ووزعه عبر TestFlight، ثم ضع رابط TestFlight الفعلي في صفحة التنزيل.

لا تُحفظ الشهادات أو ملفات provisioning أو مفاتيح App Store Connect داخل Git.
