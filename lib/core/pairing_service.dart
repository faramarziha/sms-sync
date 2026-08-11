import 'dart:math';

/// Handles PIN generation, verification, and brute-force lockout.
///
/// **Security note**: This service does NOT track which devices are paired.
/// Per-device pairing state is managed by the caller (e.g. ServerSyncService)
/// via a `Set<String> _pairedDeviceIds`. This prevents a global boolean from
/// granting access to all connected devices after a single successful pairing.
class PairingService {
  String? _currentPin;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  String? get currentPin => _currentPin;
  int get failedAttempts => _failedAttempts;
  DateTime? get lockoutUntil => _lockoutUntil;

  String generatePin() {
    final random = Random();
    _currentPin = (random.nextInt(9000) + 1000).toString();
    _failedAttempts = 0;
    _lockoutUntil = null;
    return _currentPin!;
  }

  bool verifyPin(String pin) {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return false;
    }

    if (_currentPin != null && pin == _currentPin) {
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
    _failedAttempts = 0;
    _lockoutUntil = null;
  }
}
