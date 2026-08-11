import 'package:flutter_test/flutter_test.dart';
import 'package:sms_sync/core/utils/otp_extractor.dart';

void main() {
  group('OtpExtractor — User Sample Tests', () {
    test('Sample 1 — Tapsi OTP (code: 60581)', () {
      const sms = '''
code: 60581
این کد را به هیچ عنوان در اختیار دیگران قرار ندهید.
تپسی
''';
      expect(OtpExtractor.isOtpMessage(sms), isTrue);
      expect(OtpExtractor.extractOtp(sms), '60581');
    });

    test('Sample 2 — Okala OTP (Code: 72345 & WebOTP #72345)', () {
      const sms = '''
Code: 72345
کد ورود اکالا

@www.okala.com #72345
cj3JHGrrFi7
''';
      expect(OtpExtractor.isOtpMessage(sms), isTrue);
      expect(OtpExtractor.extractOtp(sms), '72345');
    });

    test('Sample 3 — Snapp OTP (Code: 460404 & WebOTP #460404)', () {
      const sms = '''
Code: 460404
کد ورود اسنپ
برای دیگران نفرستید

@app.snapp.taxi #460404
''';
      expect(OtpExtractor.isOtpMessage(sms), isTrue);
      expect(OtpExtractor.extractOtp(sms), '460404');
    });

    test('Sample 4 — SnappFood OTP (code: 12103)', () {
      const sms = '''
code: 12103

کد اختصاصی شما برای ورود
اسنپ فود
''';
      expect(OtpExtractor.isOtpMessage(sms), isTrue);
      expect(OtpExtractor.extractOtp(sms), '12103');
    });
  });

  group('OtpExtractor — Additional Cases', () {
    test('Persian digits conversion (code: ۶۰۵۸۱)', () {
      const sms = 'رمز پویا شما: ۶۰۵۸۱ - بانک ملی';
      expect(OtpExtractor.extractOtp(sms), '60581');
    });

    test('Bank Ramz Pouya format', () {
      const sms = 'رمز پویای کارت 6037********1234: 987654. اعتبار 120 ثانیه';
      expect(OtpExtractor.isOtpMessage(sms), isTrue);
      expect(OtpExtractor.extractOtp(sms), '987654');
    });

    test('Non-OTP regular message returns null', () {
      const sms = 'سلام فردا ساعت ۵ عصر همو می‌بینیم.';
      expect(OtpExtractor.extractOtp(sms), isNull);
    });

    test('Empty text returns null', () {
      expect(OtpExtractor.extractOtp(''), isNull);
    });
  });
}
