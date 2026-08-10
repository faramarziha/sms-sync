import 'dart:math';

class PairingService {
  String? _currentPin;
  bool _isPaired = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  bool get isPaired => _isPaired;
  String? get currentPin => _currentPin;

  String generatePin() {
    final random = Random();
    _currentPin = (random.nextInt(9000) + 1000).toString();
    _isPaired = false;
    _failedAttempts = 0;
    _lockoutUntil = null;
    return _currentPin!;
  }

  bool verifyPin(String pin) {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return false;
    }

    if (_currentPin != null && pin == _currentPin) {
      _isPaired = true;
      _failedAttempts = 0;
      _lockoutUntil = null;
      return true;
    }

    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return false;
  }

  void reset() {
    _currentPin = null;
    _isPaired = false;
    _failedAttempts = 0;
    _lockoutUntil = null;
  }
}
