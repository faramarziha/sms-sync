/// Utility class for extracting One-Time Passwords (OTP) / Verification Codes
/// from SMS text messages (supporting Persian, English, and WebOTP formats).
class OtpExtractor {
  /// Converts Persian (۰-۹) and Arabic (٠-٩) digits to English digits (0-9).
  static String normalizeDigits(String input) {
    const persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    const arabicDigits  = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String output = input;
    for (int i = 0; i < 10; i++) {
      output = output.replaceAll(persianDigits[i], '$i');
      output = output.replaceAll(arabicDigits[i], '$i');
    }
    return output;
  }

  /// List of keywords that indicate an SMS is an OTP message.
  static final List<RegExp> _otpKeywords = [
    RegExp(r'\bcode\b', caseSensitive: false),
    RegExp(r'\botp\b', caseSensitive: false),
    RegExp(r'کد', caseSensitive: false),
    RegExp(r'رمز', caseSensitive: false),
    RegExp(r'تایید', caseSensitive: false),
    RegExp(r'ورود', caseSensitive: false),
    RegExp(r'فعالسازی', caseSensitive: false),
  ];

  /// Checks if the SMS content appears to be an OTP message.
  static bool isOtpMessage(String text) {
    final normalized = normalizeDigits(text);
    return _otpKeywords.any((keyword) => keyword.hasMatch(normalized));
  }

  /// Extracts the OTP code string (4-8 digits) from an SMS text message.
  /// Returns `null` if no OTP code is found.
  static String? extractOtp(String text) {
    if (text.trim().isEmpty) return null;

    final normalized = normalizeDigits(text);

    // Rule 1: "code: 12345" or "Code: 72345" or "code 1234"
    final codeColonMatch = RegExp(
      r'(?:code|Code|CODE)\s*[:\-=]?\s*(?<!\d)(\d{4,8})(?!\d)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (codeColonMatch != null) {
      return codeColonMatch.group(1);
    }

    // Rule 2: WebOTP format e.g. "@domain #12345" or "#123456"
    final webOtpMatch = RegExp(r'#(?<!\d)(\d{4,8})(?!\d)').firstMatch(normalized);
    if (webOtpMatch != null) {
      return webOtpMatch.group(1);
    }

    // Rule 3: Persian phrase keywords followed by/near 4-8 digit numbers
    // e.g. "کد ورود: 1234", "رمز پویا: 987654", "کد اختصاصی شما برای ورود 12345"
    // Skip numbers adjacent to asterisks (like card number 6037********1234)
    final persianPhraseMatches = RegExp(
      r'(?:کد\s*ورود|کد\s*تایید|کد\s*پویا|کد\s*اختصاصی|کد\s*فعالسازی|رمز\s*پویا|رمز\s*ورود|رمز|کد)\D*?(?<!\d)(\d{4,8})(?!\d)',
      caseSensitive: false,
    ).allMatches(normalized);

    for (final match in persianPhraseMatches) {
      final code = match.group(1);
      if (code != null) {
        // Check surrounding text in normalized to ensure it's not part of a masked card number like 6037****
        final startPos = match.start + match.group(0)!.indexOf(code);
        final endPos = startPos + code.length;
        final isFollowedByAsterisk = endPos < normalized.length && (normalized[endPos] == '*' || normalized[endPos] == 'x');
        final isPrecededByAsterisk = startPos > 0 && (normalized[startPos - 1] == '*' || normalized[startPos - 1] == 'x');
        if (!isFollowedByAsterisk && !isPrecededByAsterisk) {
          return code;
        }
      }
    }

    // Rule 4: If text contains OTP keywords, look for standalone 4-8 digit numbers not attached to asterisks
    if (isOtpMessage(normalized)) {
      final standaloneMatches = RegExp(r'(?<!\d)(\d{4,8})(?!\d)').allMatches(normalized);
      for (final match in standaloneMatches) {
        final code = match.group(1)!;
        final startPos = match.start;
        final endPos = match.end;
        final isCardNum = (endPos < normalized.length && (normalized[endPos] == '*' || normalized[endPos] == 'x')) ||
            (startPos > 0 && (normalized[startPos - 1] == '*' || normalized[startPos - 1] == 'x'));
        if (!isCardNum) {
          return code;
        }
      }
    }

    return null;
  }
}
