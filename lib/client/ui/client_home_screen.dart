import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/file_launcher.dart';
import '../../core/models/sync_message.dart';
import '../../core/file_transfer_service.dart';
import '../client_sync_service.dart';
import '../../transport/sync_transport.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';

// ──────────────────────────────────────────
// Radar Sweep Painter
// ──────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final Color color;
  final int dotCount;

  _RadarPainter({required this.sweepAngle, required this.color, this.dotCount = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;

    // Concentric rings
    for (int i = 1; i <= 3; i++) {
      final r = radius * i / 3;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Cross lines
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      Paint()..color = color.withValues(alpha: 0.06)..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      Paint()..color = color.withValues(alpha: 0.06)..strokeWidth = 1,
    );

    // Sweep gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.6,
        endAngle: sweepAngle,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.3),
        ],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = color);
    canvas.drawCircle(
      center,
      8,
      Paint()..color = color.withValues(alpha: 0.2),
    );

    // Random dots for discovered devices
    final rng = Random(42);
    for (int i = 0; i < dotCount; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final dist = radius * 0.3 + rng.nextDouble() * radius * 0.5;
      final dotCenter = Offset(
        center.dx + cos(angle) * dist,
        center.dy + sin(angle) * dist,
      );
      canvas.drawCircle(dotCenter, 4, Paint()..color = const Color(0xFF7EE787));
      canvas.drawCircle(dotCenter, 8, Paint()..color = const Color(0xFF7EE787).withValues(alpha: 0.2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.sweepAngle != sweepAngle || old.dotCount != dotCount;
}

// ──────────────────────────────────────────
// QR Scanner Sheet
// ──────────────────────────────────────────
class _QrScannerSheet extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onScanned;
  const _QrScannerSheet({required this.onScanned});

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  MobileScannerController? _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // Guard against the scanner firing multiple times for the same code, which
    // previously caused duplicate connect attempts / double Navigator.pop.
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _handled = true;
          widget.onScanned(decoded);
          return;
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 480,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF58A6FF)),
              const SizedBox(width: 8),
              Text(
                'اسکن کد QR سرور',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MobileScanner(
                controller: _controller!,
                onDetect: _onDetect,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: const Color(0xFF0D1117),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.no_photography_rounded, color: Color(0xFFFF7B72), size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'دوربین در دسترس نیست',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'مطمئن شوید برنامه دیگری از دوربین استفاده نمی‌کند.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'کد QR نمایش داده شده روی نسخه ویندوز را اسکن کنید.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class ClientHomeScreen extends StatefulWidget {
  final ClientSyncService service;
  const ClientHomeScreen({super.key, required this.service});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List<DiscoveredServer> _servers = [];
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.');
  final TextEditingController _portController = TextEditingController(text: '8080');
  final TextEditingController _textInputController = TextEditingController();

  StreamSubscription<List<DiscoveredServer>>? _discoverySubscription;
  StreamSubscription<ClientState>? _stateSubscription;
  StreamSubscription<Map<String, dynamic>>? _textSubscription;
  StreamSubscription<List<Map<String, String>>>? _otpSubscription;
  List<Map<String, String>> _otpHistory = [];

  bool _isPairingDialogShowing = false;
  bool _isAutoPairing = false;
  bool _isBatteryOptimized = false;
  SyncScope _selectedScope = SyncScope.both;
  final List<Map<String, dynamic>> _textHistory = [];

  TabController? _tabController;
  late AnimationController _radarController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _checkBatteryOptimization();

    _discoverySubscription = widget.service.discovery.discoveredServers.listen((servers) {
      if (mounted) {
        setState(() => _servers = servers);
      }
    });

    _stateSubscription = widget.service.stateStream.listen((state) {
      if (mounted) setState(() {});
      if (state == ClientState.pairing &&
          !_isPairingDialogShowing &&
          !_isAutoPairing &&
          !widget.service.autoPairingInProgress) {
        _showPairingDialog();
      }
      if (state != ClientState.pairing && state != ClientState.connecting) {
        _isAutoPairing = false;
      }
    });

    _textSubscription = widget.service.textMessagesStream.listen((data) {
      if (mounted) {
        setState(() => _textHistory.insert(0, data));
      }
    });

    _otpSubscription = widget.service.otpHistoryStream.listen((list) {
      if (mounted) {
        setState(() => _otpHistory = list);
      }
    });

    widget.service.loadSavedDeviceName();
    widget.service.startDiscovery();

    // Restore the previously selected sync mode and try to reconnect to the
    // last paired server (personal single-device convenience).
    widget.service.autoReconnectIfSaved().then((_) {
      if (mounted) setState(() => _selectedScope = widget.service.scope);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Pause battery-draining clipboard polling in background
      widget.service.pauseClipboardMonitoring();
    } else if (state == AppLifecycleState.resumed) {
      // Resume clipboard polling when returning to foreground
      widget.service.resumeClipboardMonitoring();
      _checkBatteryOptimization();
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (Platform.isAndroid) {
      final isIgnoring = await widget.service.nativeBridge.isIgnoringBatteryOptimizations();
      if (mounted) {
        setState(() {
          _isBatteryOptimized = !isIgnoring;
        });
      }
    }
  }

  Future<void> _requestBatteryWhitelist() async {
    await widget.service.nativeBridge.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(seconds: 1));
    await _checkBatteryOptimization();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discoverySubscription?.cancel();
    _stateSubscription?.cancel();
    _textSubscription?.cancel();
    _otpSubscription?.cancel();
    _pinController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _textInputController.dispose();
    _tabController?.dispose();
    _radarController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _showPairingDialog() {
    if (_isPairingDialogShowing) return;
    _isPairingDialogShowing = true;
    _pinController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Gradient header icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF58A6FF), Color(0xFFD2A8FF)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.phonelink_setup_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pair & Sync',
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the 4-digit PIN from Windows',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                  ),
                  const SizedBox(height: 20),
                  // PIN Input
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF0883E),
                      letterSpacing: 12,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '• • • •',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 28,
                        color: Colors.white.withValues(alpha: 0.15),
                        letterSpacing: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Scope selector
                  Text(
                    'Sync Mode',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  _buildScopeOption(
                    scope: SyncScope.textFiles,
                    title: 'Text & Files',
                    icon: Icons.file_present_rounded,
                    color: const Color(0xFFD2A8FF),
                    selectedScope: _selectedScope,
                    onSelect: (s) => setSheetState(() => _selectedScope = s),
                  ),
                  _buildScopeOption(
                    scope: SyncScope.smsSim,
                    title: 'SMS & SIM Cards',
                    icon: Icons.sms_rounded,
                    color: const Color(0xFF58A6FF),
                    selectedScope: _selectedScope,
                    onSelect: (s) => setSheetState(() => _selectedScope = s),
                  ),
                  _buildScopeOption(
                    scope: SyncScope.both,
                    title: 'Full Sync (All)',
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFF7EE787),
                    selectedScope: _selectedScope,
                    onSelect: (s) => setSheetState(() => _selectedScope = s),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _isPairingDialogShowing = false;
                            Navigator.pop(context);
                            widget.service.startDiscovery();
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Connect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F6FEB),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            final pin = _pinController.text.trim();
                            if (pin.length != 4 || int.tryParse(pin) == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('لطفاً PIN چهار رقمی را وارد کنید')),
                              );
                              return;
                            }

                            _isPairingDialogShowing = false;
                            Navigator.pop(context);
                            try {
                              await widget.service.sendPairRequest(pin, scope: _selectedScope);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('خطا در ارسال PIN: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => _isPairingDialogShowing = false);
  }

  Widget _buildScopeOption({
    required SyncScope scope,
    required String title,
    required IconData icon,
    required Color color,
    required SyncScope selectedScope,
    required ValueChanged<SyncScope> onSelect,
  }) {
    final isSelected = selectedScope == scope;
    return GestureDetector(
      onTap: () => onSelect(scope),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? color : Colors.white54,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _showQrScannerDialog() async {
    // Request camera permission explicitly so a denial shows a clear message
    // instead of a silent black camera preview.
    if (Platform.isAndroid || Platform.isIOS) {
      var status = await Permission.camera.status;
      if (status.isDenied || status.isRestricted) {
        status = await Permission.camera.request();
      }
      if (!status.isGranted) {
        if (mounted) {
          final permanentlyDenied = status.isPermanentlyDenied;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permanentlyDenied
                    ? 'دسترسی دوربین غیرفعال است. لطفاً آن را از تنظیمات فعال کنید.'
                    : 'برای اسکن کد QR به دسترسی دوربین نیاز است.',
              ),
              action: permanentlyDenied
                  ? SnackBarAction(
                      label: 'تنظیمات',
                      onPressed: () => openAppSettings(),
                    )
                  : null,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _QrScannerSheet(
        onScanned: (data) {
          final address = data['address']?.toString();
          final port = data['port'] is num ? (data['port'] as num).toInt() : 8080;
          final pin = data['pin']?.toString();
          if (address == null || pin == null || pin.isEmpty) return;

          _isAutoPairing = true;
          Navigator.pop(context);
          widget.service
              .connectToServer(
                DiscoveredServer(name: 'Scanned PC', address: address, port: port),
              )
              .then((_) {
            if (widget.service.state == ClientState.pairing) {
              widget.service.sendPairRequest(pin, scope: _selectedScope).catchError((Object e) {
                debugPrint('Failed to send QR pair request: $e');
              });
            }
          })
              .catchError((Object e) {
            debugPrint('QR connect failed: $e');
          });
        },
      ),
    );
  }

  void _showManualConnectDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 12,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Manual Connect', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.url,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                hintText: '192.168.1.100',
                prefixIcon: Icon(Icons.language_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      final ip = _ipController.text.trim();
                      final port = int.tryParse(_portController.text.trim()) ?? 8080;
                      if (ip.isNotEmpty) {
                        widget.service.connectToServer(
                          DiscoveredServer(name: 'Manual', address: ip, port: port),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeviceNameDialog() async {
    final controller = TextEditingController(text: widget.service.deviceName);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نام دستگاه'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(hintText: 'مثلاً: گوشی شخصی من'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(context);
              if (name.isNotEmpty) {
                widget.service.setDeviceName(name).then((_) {
                  if (mounted) setState(() {});
                });
              }
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    try {
      await widget.service.sendFile(File(result.files.single.path!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل برای کامپیوتر ارسال شد'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ارسال فایل: $e')),
        );
      }
    }
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildClientIntroCard() {
    final state = widget.service.state;
    final isConnected = state == ClientState.synced;
    final accent = isConnected ? const Color(0xFF7EE787) : const Color(0xFF58A6FF);
    final title = isConnected ? 'همگام‌سازی فعال است' : 'گوشی را به کامپیوتر وصل کنید';
    final subtitle = isConnected
        ? 'پیامک‌ها، متن‌ها و فایل‌ها در شبکه محلی شما آماده‌اند.'
        : 'دستگاه‌های اطراف را پیدا کنید یا با QR سریع جفت شوید.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: 0.16), const Color(0xFF161B22)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                isConnected ? Icons.verified_rounded : Icons.phonelink_rounded,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      title,
                      key: ValueKey(title),
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryOptimizationBanner() {
    if (!_isBatteryOptimized || !Platform.isAndroid) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0883E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0883E).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0883E).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.battery_saver_rounded, color: Color(0xFFF0883E), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'بهینه‌سازی باتری فعال است',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFF0883E)),
                ),
                const SizedBox(height: 2),
                Text(
                  'جهت جلوگیری از قطع اتصال در پس‌زمینه، محدودیت باتری را غیرفعال کنید.',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0883E),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            onPressed: _requestBatteryWhitelist,
            child: const Text('رفع محدودیت'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // SMS Synced Tab
  // ──────────────────────────────────────────
  Widget _buildSmsTab() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          color: const Color(0xFF58A6FF),
          onRefresh: () => widget.service.manualRefreshSync(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBatteryOptimizationBanner(),
                  if (widget.service.lastSyncTime != null) _buildSyncSummary(),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF238636), Color(0xFF7EE787)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF7EE787).withValues(alpha: 0.2), blurRadius: 30, spreadRadius: 5),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'SMS & SIM Auto-Sync Active',
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'پیامک‌های جدید بدون تاخیر و به صورت لحظه‌ای به کامپیوتر ارسال می‌شوند',
                    style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7EE787).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF7EE787).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF7EE787),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'سینک لحظه‌ای و کم‌مصرف',
                              style: GoogleFonts.inter(color: const Color(0xFF7EE787), fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.service.manualRefreshSync();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('همگام‌سازی پیامک‌ها و سیم‌کارت انجام شد'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF58A6FF)),
                        label: Text('همگام‌سازی دستی', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF58A6FF))),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF58A6FF).withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  if (_otpHistory.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildOtpHistorySection(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncSummary() {
    final time = widget.service.lastSyncTime!;
    final count = widget.service.lastSyncedSmsCount;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF58A6FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF58A6FF).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.history_rounded, size: 18, color: Color(0xFF58A6FF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'آخرین همگام‌سازی: $hh:$mm — $count پیامک',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
          ),
        ),
      ]),
    );
  }

  Widget _buildOtpHistorySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.key_rounded, size: 16, color: Color(0xFF7EE787)),
            const SizedBox(width: 8),
            Text('کدهای پویای اخیر', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
          ]),
          const SizedBox(height: 10),
          ..._otpHistory.take(5).map((item) {
            final otp = item['otp'] ?? '';
            final sender = item['sender'] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '$otp  •  $sender',
                    style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF58A6FF)),
                  label: const Text('کپی'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF58A6FF),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: otp));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('کد کپی شد'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ]),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // Text Tab
  // ──────────────────────────────────────────
  Widget _buildTextTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _textInputController,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type or paste text...',
                    suffixIcon: IconButton(
                      icon: Icon(Icons.paste_rounded, color: Colors.white.withValues(alpha: 0.4)),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _textInputController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.assignment_return_rounded, size: 16, color: Color(0xFF58A6FF)),
                        label: Text('ارسال کلیپ‌بورد به کامپیوتر', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF58A6FF))),
                        onPressed: () async {
                          final text = await widget.service.clipboardService.getText();
                          if (text == null || text.isEmpty) return;
                          try {
                            await widget.service.sendRawText(text);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('متن کلیپ‌بورد به کامپیوتر ارسال شد'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطا در ارسال متن: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _textInputController.clear(),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send'),
                      onPressed: () async {
                        final text = _textInputController.text.trim();
                        if (text.isEmpty) return;
                        try {
                          await widget.service.sendRawText(text);
                          _textInputController.clear();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطا در ارسال متن: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _textHistory.isEmpty
              ? Center(
                  child: Text('No text exchanged yet', style: GoogleFonts.inter(color: Colors.white30)),
                )
              : ListView.builder(
                  itemCount: _textHistory.length,
                  itemBuilder: (context, index) {
                    final item = _textHistory[index];
                    final text = item['text'] ?? '';
                    final sender = item['sender'] ?? 'Remote';
                    final date = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] ?? 0);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, height: 1.5),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _miniChip(sender, const Color(0xFFD2A8FF)),
                                const SizedBox(width: 8),
                                Text(
                                  '${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white30),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(Icons.copy_rounded, size: 16, color: Colors.white.withValues(alpha: 0.3)),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: text));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Copied!', style: GoogleFonts.inter(fontSize: 13)),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // File Tab
  // ──────────────────────────────────────────
  Widget _buildFileTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF1F6FEB),
              ),
              icon: const Icon(Icons.upload_file_rounded, size: 22),
              label: Text('Send File', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
              onPressed: _pickAndSendFile,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FileTransferItem>>(
            stream: widget.service.fileTransfer.transfersStream,
            initialData: widget.service.fileTransfer.activeTransfers,
            builder: (context, snapshot) {
              final transfers = snapshot.data ?? [];
              if (transfers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.03),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Icon(Icons.folder_open_rounded, size: 40, color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      const SizedBox(height: 14),
                      Text('No file transfers', style: GoogleFonts.inter(color: Colors.white30, fontSize: 14)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: transfers.length,
                itemBuilder: (context, index) {
                  final item = transfers[index];
                  final sizeMb = (item.fileSize / (1024 * 1024)).toStringAsFixed(2);
                  final pct = (item.progress * 100).toInt();
                  final isUp = item.isOutgoing;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isUp ? const Color(0xFF58A6FF) : const Color(0xFF7EE787)).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isUp ? Icons.upload_rounded : Icons.download_rounded,
                                  color: isUp ? const Color(0xFF58A6FF) : const Color(0xFF7EE787),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('$sizeMb MB', style: GoogleFonts.inter(color: Colors.white30, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              color: item.isCompleted ? const Color(0xFF7EE787) : const Color(0xFF58A6FF),
                              minHeight: 3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.isCompleted ? '✓ Complete' : item.isFailed ? '✗ Failed' : '$pct%',
                                style: GoogleFonts.inter(
                                  color: item.isCompleted
                                      ? const Color(0xFF7EE787)
                                      : (item.isFailed ? const Color(0xFFFF7B72) : const Color(0xFF58A6FF)),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (item.isCompleted && item.localPath != null && !item.isOutgoing)
                                TextButton.icon(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                  label: Text('Open', style: GoogleFonts.inter(fontSize: 12)),
                                  onPressed: () => FileLauncher.openFile(item.localPath!),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // Scanning / Browsing View
  // ──────────────────────────────────────────
  Widget _buildScanningView() {
    return Column(
      children: [
        _buildClientIntroCard(),
        _buildBatteryOptimizationBanner(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _RadarPainter(
                          sweepAngle: _radarController.value * 2 * pi,
                          color: const Color(0xFF58A6FF),
                          dotCount: _servers.length,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _servers.isEmpty ? 'در حال جستجوی کامپیوترها...' : '${_servers.length} کامپیوتر پیدا شد',
                    key: ValueKey(_servers.length),
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Make sure the Windows app is running',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white30),
                ),
              ],
            ),
          ),
        ),
        // Server list
        if (_servers.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Material(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => widget.service.connectToServer(server),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF58A6FF).withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1F6FEB), Color(0xFF58A6FF)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.desktop_windows_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.name,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 15),
                                  ),
                                  Text(
                                    '${server.address}:${server.port}',
                                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white38),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F6FEB).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF58A6FF)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // QR Scanner & Manual connect buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text('اسکن کد QR'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF1F6FEB),
                  ),
                  onPressed: _showQrScannerDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('آدرس IP'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _showManualConnectDialog,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // Status bar
  // ──────────────────────────────────────────
  Widget _buildStatusBar(ClientState? state) {
    Color accentColor;
    String statusText;
    IconData statusIcon;

    switch (state) {
      case ClientState.synced:
        accentColor = const Color(0xFF7EE787);
        statusText = 'Connected • ${widget.service.scope.name}';
        statusIcon = Icons.link_rounded;
        break;
      case ClientState.syncing:
        accentColor = const Color(0xFF58A6FF);
        statusText = 'Syncing...';
        statusIcon = Icons.sync_rounded;
        break;
      case ClientState.pairing:
        accentColor = const Color(0xFFF0883E);
        statusText = 'Awaiting PIN verification';
        statusIcon = Icons.key_rounded;
        break;
      case ClientState.connecting:
        accentColor = const Color(0xFF58A6FF);
        statusText = 'Connecting...';
        statusIcon = Icons.connect_without_contact_rounded;
        break;
      case ClientState.browsing:
        accentColor = const Color(0xFF58A6FF);
        statusText = 'Scanning network...';
        statusIcon = Icons.wifi_find_rounded;
        break;
      case ClientState.error:
        accentColor = const Color(0xFFFF7B72);
        statusText = 'Connection Error';
        statusIcon = Icons.error_outline_rounded;
        break;
      default:
        accentColor = Colors.white38;
        statusText = 'Idle';
        statusIcon = Icons.power_settings_new_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.1),
            accentColor.withValues(alpha: 0.03),
          ],
        ),
        border: Border(bottom: BorderSide(color: accentColor.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, _) {
              final pulse = 0.5 + 0.5 * sin(_radarController.value * 2 * pi);
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                  boxShadow: [
                    BoxShadow(color: accentColor.withValues(alpha: pulse * 0.6), blurRadius: 8, spreadRadius: 2),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Icon(statusIcon, color: accentColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: GoogleFonts.inter(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (state == ClientState.syncing || state == ClientState.synced || state == ClientState.pairing)
            OutlinedButton.icon(
              onPressed: () => widget.service.disconnect(),
              icon: const Icon(Icons.link_off_rounded, size: 14, color: Color(0xFFFF7B72)),
              label: Text('Disconnect', style: GoogleFonts.inter(color: const Color(0xFFFF7B72), fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF7B72)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.service.state;
    final isSynced = state == ClientState.synced;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF58A6FF), Color(0xFF7EE787)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sync_rounded, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SMS Sync', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18, height: 1.05)),
                Text(
                  widget.service.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.drive_file_rename_outline_rounded, color: Colors.white.withValues(alpha: 0.5), size: 22),
            tooltip: 'تغییر نام دستگاه',
            onPressed: _showDeviceNameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF58A6FF), size: 22),
            tooltip: 'Scan QR Code',
            onPressed: _showQrScannerDialog,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: Colors.white.withValues(alpha: 0.65), size: 23),
            tooltip: 'ابزارهای اتصال',
            onSelected: (action) {
              switch (action) {
                case 'rescan':
                  widget.service.startDiscovery();
                  break;
                case 'manual':
                  _showManualConnectDialog();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'rescan',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded, color: Color(0xFF58A6FF)),
                  title: Text('جستجوی دوباره'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_link_rounded, color: Color(0xFFD2A8FF)),
                  title: Text('اتصال با آدرس IP'),
                ),
              ),
            ],
          ),
        ],
        bottom: isSynced
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.sms_rounded, size: 18), text: 'SMS'),
                  Tab(icon: Icon(Icons.text_snippet_rounded, size: 18), text: 'Text'),
                  Tab(icon: Icon(Icons.folder_rounded, size: 18), text: 'Files'),
                ],
              )
            : null,
      ),
      body: StreamBuilder<ClientState>(
        stream: widget.service.stateStream,
        initialData: widget.service.state,
        builder: (context, snapshot) {
          final currentState = snapshot.data;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(
              key: ValueKey(currentState),
              child: Column(
                children: [
              _buildStatusBar(currentState),

              if (currentState == ClientState.synced)
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSmsTab(),
                      _buildTextTab(),
                      _buildFileTab(),
                    ],
                  ),
                ),

              if (currentState == ClientState.connecting)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Color(0xFF58A6FF),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Connecting...', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70)),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: () => widget.service.startDiscovery(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),

              if (currentState == ClientState.browsing || currentState == ClientState.idle)
                Expanded(child: _buildScanningView()),

              if (currentState == ClientState.pairing)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFFF0883E), Color(0xFFD29922)]),
                          ),
                          child: const Icon(Icons.key_rounded, size: 40, color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        Text('Connected', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('Enter PIN to pair', style: GoogleFonts.inter(fontSize: 14, color: Colors.white38)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text('Enter PIN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F6FEB),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          ),
                          onPressed: _showPairingDialog,
                        ),
                      ],
                    ),
                  ),
                ),

              if (currentState == ClientState.error)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF7B72).withValues(alpha: 0.1),
                            border: Border.all(color: const Color(0xFFFF7B72).withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.error_outline_rounded, color: Color(0xFFFF7B72), size: 40),
                        ),
                        const SizedBox(height: 20),
                        Text('Connection Failed', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () => widget.service.startDiscovery(),
                              child: const Text('Retry Scan'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _showManualConnectDialog,
                              child: const Text('Manual IP'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
