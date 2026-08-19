import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/file_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/file_transfer_service.dart';
import '../../transport/sync_transport.dart';
import '../server_sync_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ──────────────────────────────────────────
// Animated gradient border painter
// ──────────────────────────────────────────
class _GlowBorderPainter extends CustomPainter {
  final double progress;
  final Color color;

  _GlowBorderPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: progress * 2 * pi,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class ServerHomeScreen extends StatefulWidget {
  final ServerSyncService service;
  const ServerHomeScreen({super.key, required this.service});

  @override
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _sims = [];
  List<Map<String, dynamic>> _rawTexts = [];
  List<DiscoveredServer> _discoveredClients = [];
  List<Map<String, dynamic>> _conversations = [];
  Map<String, dynamic> _stats = {};
  bool _refreshInFlight = false;

  String? _selectedDeviceId;
  String _smsSearchQuery = '';
  bool _conversationMode = false;
  String? _activeConversationAddress;
  int _smsTypeFilter = 0; // 0 = all, 1 = received, 2 = sent
  bool _starredOnly = false;

  StreamSubscription<ServerState>? _stateSubscription;
  StreamSubscription<void>? _dataSubscription;
  StreamSubscription<List<DiscoveredServer>>? _discoveredClientsSubscription;
  StreamSubscription<Map<String, String>>? _otpSubscription;

  final TextEditingController _textSendController = TextEditingController();
  final TextEditingController _smsSearchController = TextEditingController();
  TabController? _tabController;

  // Animations
  late AnimationController _glowController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _startServer();
    _refreshData();

    _stateSubscription = widget.service.stateStream.listen((_) {
      if (mounted) setState(() {});
    });

    _dataSubscription = widget.service.dataUpdated.listen((_) {
      if (mounted) _refreshData();
    });

    _discoveredClientsSubscription = widget.service.discovery.discoveredServers.listen((clients) {
      if (mounted) {
        setState(() {
          _discoveredClients = clients;
        });
      }
    });

    _otpSubscription = widget.service.otpNotificationStream.listen((otpData) {
      if (mounted) {
        final otp = otpData['otp'] ?? '';
        final sender = otpData['sender'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.mark_email_read_rounded, color: Color(0xFF7EE787)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'کد پویا ($otp) از $sender در کلیپ‌بورد کپی شد!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF161B22),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  void _showQrCodeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: Color(0xFF58A6FF)),
              const SizedBox(width: 10),
              Text('QR Code جفت‌سازی', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: widget.service.qrPairingPayload,
                  version: QrVersions.auto,
                  size: 220.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'این کد را با دوربین برنامه اندروید اسکن کنید تا اتصال برقرار شود.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'PIN: ${widget.service.currentPin ?? "---"}',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF58A6FF)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _dataSubscription?.cancel();
    _discoveredClientsSubscription?.cancel();
    _otpSubscription?.cancel();
    _textSendController.dispose();
    _smsSearchController.dispose();
    _tabController?.dispose();
    _glowController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      await widget.service.startServer();
    } catch (e) {
      debugPrint('Failed to start server: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final results = await Future.wait<Object?>([
        widget.service.db.getAllSms(deviceId: _selectedDeviceId),
        widget.service.db.getAllSims(deviceId: _selectedDeviceId),
        widget.service.db.getAllRawTexts(deviceId: _selectedDeviceId),
        widget.service.db.getConversations(deviceId: _selectedDeviceId),
        widget.service.db.getStats(deviceId: _selectedDeviceId),
      ]);

      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(results[0] as List);
        _sims = List<Map<String, dynamic>>.from(results[1] as List);
        _rawTexts = List<Map<String, dynamic>>.from(results[2] as List);
        _conversations = List<Map<String, dynamic>>.from(results[3] as List);
        _stats = Map<String, dynamic>.from(results[4] as Map);
      });
    } catch (e) {
      debugPrint('Failed to refresh desktop data: $e');
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    try {
      await widget.service.sendFile(File(result.files.single.path!));
      if (mounted) _showSnack('فایل برای گوشی ارسال شد');
    } catch (e) {
      if (mounted) _showSnack('خطا در ارسال فایل: $e');
    }
  }

  Future<void> _openDownloadsFolder() async {
    Directory? dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      dir = Directory(p.join(downloadsDir?.path ?? Directory.current.path, 'SMS_Sync'));
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await FileLauncher.openFile(dir.path);
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF7EE787), size: 18),
            const SizedBox(width: 10),
            Text('$label copied!', style: GoogleFonts.inter(fontSize: 13)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMessageDetail(Map<String, dynamic> msg) {
    final date = DateTime.fromMillisecondsSinceEpoch(msg['date'] ?? 0);
    final typeLabel = _smsTypeLabel(msg['type']);
    final deviceName = (msg['device_name'] ?? 'Android Phone').toString();
    final isReceived = msg['type'] == 1;
    final id = msg['id']?.toString() ?? '';
    final address = (msg['address'] ?? '').toString();
    final body = (msg['body'] ?? '').toString();
    bool starred = msg['is_starred'] == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isReceived
                              ? [const Color(0xFF1F6FEB), const Color(0xFF58A6FF)]
                              : [const Color(0xFF238636), const Color(0xFF7EE787)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isReceived ? Icons.call_received_rounded : Icons.call_made_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            address.isEmpty ? 'Unknown' : address,
                            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _miniChip(deviceName, const Color(0xFF58A6FF)),
                              const SizedBox(width: 8),
                              _miniChip(typeLabel, isReceived ? const Color(0xFF58A6FF) : const Color(0xFF7EE787)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        starred ? Icons.star_rounded : Icons.star_border_rounded,
                        color: starred ? const Color(0xFFE3B341) : Colors.white30,
                      ),
                      tooltip: starred ? 'حذف ستاره' : 'ستاره‌دار',
                      onPressed: () async {
                        final s = await widget.service.db.toggleSmsStarred(id);
                        if (mounted) {
                          setDialogState(() => starred = s);
                          _refreshData();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  '
                  '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
                Divider(height: 24, color: Colors.white.withValues(alpha: 0.08)),
                // Body
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      body,
                      style: GoogleFonts.inter(fontSize: 14, height: 1.7, color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('کپی متن'),
                      onPressed: () => _copyToClipboard(body, 'Message'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF7EE787)),
                      label: const Text('کپی شماره'),
                      onPressed: () => _copyToClipboard(address, 'Number'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFFF7B72)),
                      label: const Text('حذف', style: TextStyle(color: Color(0xFFFF7B72))),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deleteMessage(id);
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  String _smsTypeLabel(int? type) {
    switch (type) {
      case 1: return 'Received';
      case 2: return 'Sent';
      case 3: return 'Draft';
      case 5: return 'Failed';
      default: return 'Unknown';
    }
  }

  // ──────────────────────────────────────────
  // Device Selector Bar
  // ──────────────────────────────────────────
  Widget _buildDeviceSelectorBar() {
    final devices = widget.service.connectedDevices.values.toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_rounded, size: 18, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _deviceChip(
                    label: 'All (${devices.length})',
                    isSelected: _selectedDeviceId == null,
                    icon: Icons.all_inclusive_rounded,
                    onTap: () {
                      setState(() => _selectedDeviceId = null);
                      _refreshData();
                    },
                  ),
                  const SizedBox(width: 6),
                  ...devices.map((device) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _deviceChip(
                        label: device.deviceName,
                        isSelected: _selectedDeviceId == device.deviceId,
                        icon: Icons.smartphone_rounded,
                        onTap: () {
                          setState(() => _selectedDeviceId = device.deviceId);
                          _refreshData();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Desktop-first dashboard hero.
  Widget _buildDesktopHero() {
    final state = widget.service.state;
    final isConnected = state == ServerState.paired;
    final accent = isConnected ? const Color(0xFF7EE787) : const Color(0xFF58A6FF);
    final deviceCount = widget.service.connectedClientCount;
    final status = isConnected
        ? '$deviceCount دستگاه متصل و آماده همگام‌سازی'
        : 'برای شروع، گوشی را از طریق QR یا شبکه محلی متصل کنید';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.16),
              const Color(0xFF161B22),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _showQrCodeDialog,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                  label: const Text('نمایش QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD2A8FF),
                    side: BorderSide(color: const Color(0xFFD2A8FF).withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _refreshData,
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('به‌روزرسانی'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            );

            final heading = Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isConnected ? Icons.wifi_rounded : Icons.radar_rounded,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مرکز کنترل SMS Sync',
                        style: GoogleFonts.inter(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          status,
                          key: ValueKey(status),
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 16), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // Feature Control Bar (OTP Toggle, Clipboard, QR)
  // ──────────────────────────────────────────
  // Responsive controls for the desktop console.
  Widget _buildFeatureControlBar() {
    final isOtpEnabled = widget.service.isOtpExtractionEnabled;
    final isClipEnabled = widget.service.isClipboardSyncEnabled;
    final otps = widget.service.otpHistory;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDesktopHero(),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              // 1. Auto OTP Extractor Toggle Switch
              SizedBox(
                width: 360,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOtpEnabled
                        ? const Color(0xFF7EE787).withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOtpEnabled
                          ? const Color(0xFF7EE787).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.key_rounded,
                        color: isOtpEnabled ? const Color(0xFF7EE787) : Colors.white38,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'استخراج کدهای پویا',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isOtpEnabled ? Colors.white : Colors.white54,
                              ),
                            ),
                            Text(
                              isOtpEnabled ? 'کپی خودکار کدهای ورود روی ویندوز' : 'غیرفعال',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isOtpEnabled,
                        activeThumbColor: const Color(0xFF7EE787),
                        onChanged: (val) {
                          widget.service.setOtpExtractionEnabled(val);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // 2. Shared Clipboard Sync Toggle
              SizedBox(
                width: 360,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isClipEnabled
                        ? const Color(0xFF58A6FF).withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isClipEnabled
                          ? const Color(0xFF58A6FF).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_turned_in_rounded,
                        color: isClipEnabled ? const Color(0xFF58A6FF) : Colors.white38,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'کلیپ‌بورد هم‌گام',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isClipEnabled ? Colors.white : Colors.white54,
                              ),
                            ),
                            Text(
                              isClipEnabled ? 'همگام‌سازی دوطرفه کلیپ‌بورد' : 'غیرفعال',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isClipEnabled,
                        activeThumbColor: const Color(0xFF58A6FF),
                        onChanged: (val) {
                          widget.service.setClipboardSyncEnabled(val);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // 3. QR Pairing Button
              OutlinedButton.icon(
                onPressed: _showQrCodeDialog,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFFD2A8FF)),
                label: Text('کد QR', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFD2A8FF))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD2A8FF)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ],
          ),

          // 4. OTP Recent History Bar (if any OTPs captured)
          if (otps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.history_toggle_off_rounded, size: 14, color: Color(0xFF7EE787)),
                const SizedBox(width: 6),
                Text(
                  'آخرین کدهای پویا دریافت شده:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: otps.take(6).map((item) {
                  final otp = item['otp'] ?? '';
                  final sender = item['sender'] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: const Color(0xFF21262D),
                      avatar: const Icon(Icons.key_rounded, size: 14, color: Color(0xFF7EE787)),
                      label: Text('$otp ($sender)', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white)),
                      onPressed: () => _copyToClipboard(otp, 'کد پویا $otp'),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceChip({
    required String label,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isSelected ? const Color(0xFF1F6FEB).withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? const Color(0xFF58A6FF) : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: isSelected ? const Color(0xFF58A6FF) : Colors.white54),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? const Color(0xFF58A6FF) : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // SIM Cards Section
  // ──────────────────────────────────────────
  Widget _buildSimCardsSection() {
    final Map<String, Map<String, dynamic>> uniqueSimsMap = {};
    for (var sim in _sims) {
      final key = "${sim['device_id']}_${sim['sim_slot']}";
      uniqueSimsMap[key] = sim;
    }
    final displaySims = uniqueSimsMap.values.toList()
      ..sort((a, b) => ((a['sim_slot'] as int?) ?? 0).compareTo((b['sim_slot'] as int?) ?? 0));

    if (displaySims.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sim_card_outlined, color: Colors.white.withValues(alpha: 0.2), size: 20),
            const SizedBox(width: 8),
            Text('Waiting for SIM card data...', style: GoogleFonts.inter(color: Colors.white30, fontSize: 13)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(displaySims.length, (index) {
          final sim = displaySims[index];
          final slotNumber = ((sim['sim_slot'] as int?) ?? index) + 1;
          final phoneNum = sim['phone_number'] ?? 'No Number';
          final carrier = sim['carrier_name'] ?? 'Unknown';
          final devName = sim['device_name'] ?? 'Phone';

          final gradientColors = slotNumber == 1
              ? [const Color(0xFF1F6FEB), const Color(0xFF388BFD)]
              : [const Color(0xFF238636), const Color(0xFF2EA043)];

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: index > 0 ? 10 : 0),
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return CustomPaint(
                    foregroundPainter: _GlowBorderPainter(
                      progress: _glowController.value,
                      color: gradientColors[0],
                    ),
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.15),
                        gradientColors[1].withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: gradientColors[0].withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradientColors),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sim_card_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SIM $slotNumber',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    color: gradientColors[0],
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(devName, style: GoogleFonts.inter(color: Colors.white30, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _copyToClipboard(phoneNum, 'SIM $slotNumber'),
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      phoneNum,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.3), size: 14),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(carrier, style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ──────────────────────────────────────────
  // Discovered Clients
  // ──────────────────────────────────────────
  Widget _buildDiscoveredClientsSection() {
    if (_discoveredClients.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFD2A8FF).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD2A8FF).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _glowController.value * 2 * pi,
                    child: child,
                  );
                },
                child: const Icon(Icons.wifi_find_rounded, color: Color(0xFFD2A8FF), size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Discovered Devices',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFFD2A8FF), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _discoveredClients.map((client) {
              return Material(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.service.connectToDiscoveredClient(client),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD2A8FF).withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smartphone_rounded, size: 16, color: Color(0xFFD2A8FF)),
                        const SizedBox(width: 8),
                        Text(
                          '${client.name} (${client.address})',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white30),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // Empty state widget
  // ──────────────────────────────────────────
  Widget _buildEmptyState(IconData icon, String text) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Icon(icon, size: 48, color: Colors.white.withValues(alpha: 0.15)),
            ),
            const SizedBox(height: 16),
            Text(text, style: GoogleFonts.inter(color: Colors.white30, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // SMS Tab
  // ──────────────────────────────────────────
  Widget _buildSmsTab() {
    final filtered = _filteredMessages();
    final showThread = _activeConversationAddress != null && !_conversationMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeviceSelectorBar(),
        _buildSimCardsSection(),
        _buildDiscoveredClientsSection(),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        _buildSmsToolbar(),
        _buildSmsFilterChips(),
        if (showThread) _buildThreadHeader(_activeConversationAddress!),
        Expanded(
          child: _conversationMode ? _buildConversationsList() : _buildMessageList(filtered),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filteredMessages() {
    var list = _messages;
    if (_activeConversationAddress != null) {
      list = list.where((m) => m['address'] == _activeConversationAddress).toList();
    }
    if (_smsSearchQuery.isNotEmpty) {
      final q = _smsSearchQuery.toLowerCase();
      list = list.where((m) {
        final body = (m['body'] ?? '').toString().toLowerCase();
        final address = (m['address'] ?? '').toString().toLowerCase();
        return body.contains(q) || address.contains(q);
      }).toList();
    }
    if (_starredOnly) {
      list = list.where((m) => m['is_starred'] == 1).toList();
    }
    if (_smsTypeFilter != 0) {
      list = list.where((m) => m['type'] == _smsTypeFilter).toList();
    }
    return list;
  }

  Widget _buildSmsToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smsSearchController,
                  onChanged: (v) => setState(() => _smsSearchQuery = v.trim()),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'جستجو در پیام‌ها...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF58A6FF)),
                    suffixIcon: _smsSearchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                            onPressed: () {
                              _smsSearchController.clear();
                              setState(() => _smsSearchQuery = '');
                            },
                          ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share_rounded, color: Color(0xFFD2A8FF), size: 22),
                tooltip: 'خروجی و پشتیبان‌گیری',
                onSelected: _handleDataAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'csv',
                    child: Row(children: [
                      Icon(Icons.table_chart_rounded, size: 18, color: Color(0xFF7EE787)),
                      SizedBox(width: 10),
                      Text('خروجی CSV'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'json',
                    child: Row(children: [
                      Icon(Icons.backup_rounded, size: 18, color: Color(0xFF58A6FF)),
                      SizedBox(width: 10),
                      Text('پشتیبان‌گیری JSON'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: Row(children: [
                      Icon(Icons.restore_rounded, size: 18, color: Color(0xFFD2A8FF)),
                      SizedBox(width: 10),
                      Text('بازیابی از JSON'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(children: [
                      Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFFF0883E)),
                      SizedBox(width: 10),
                      Text('باز کردن پوشه داده‌ها'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatsBar(),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final total = (_stats['total'] as num?)?.toInt() ?? 0;
    final received = (_stats['received'] as num?)?.toInt() ?? 0;
    final sent = (_stats['sent'] as num?)?.toInt() ?? 0;
    final contacts = (_stats['contacts'] as num?)?.toInt() ?? 0;
    final starred = (_stats['starred'] as num?)?.toInt() ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _statChip('کل', total, Icons.sms_rounded, const Color(0xFF58A6FF)),
        _statChip('دریافتی', received, Icons.call_received_rounded, const Color(0xFF7EE787)),
        _statChip('ارسالی', sent, Icons.call_made_rounded, const Color(0xFFD2A8FF)),
        _statChip('مخاطب', contacts, Icons.people_rounded, const Color(0xFFF0883E)),
        _statChip('ستاره', starred, Icons.star_rounded, const Color(0xFFE3B341)),
      ]),
    );
  }

  Widget _statChip(String label, int value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$value', style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white54)),
      ]),
    );
  }

  Widget _buildSmsFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        _filterChip('همه', _smsTypeFilter == 0, () => setState(() => _smsTypeFilter = 0)),
        _filterChip('دریافتی', _smsTypeFilter == 1, () => setState(() => _smsTypeFilter = 1)),
        _filterChip('ارسالی', _smsTypeFilter == 2, () => setState(() => _smsTypeFilter = 2)),
        _filterChip('ستاره‌دار', _starredOnly, () => setState(() => _starredOnly = !_starredOnly)),
        _filterChip('گفتگوها', _conversationMode, () => setState(() {
          _conversationMode = !_conversationMode;
          _activeConversationAddress = null;
        })),
      ]),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: selected ? const Color(0xFF58A6FF) : Colors.white60),
        backgroundColor: const Color(0xFF21262D),
        selectedColor: const Color(0xFF1F6FEB).withValues(alpha: 0.25),
        side: BorderSide(
          color: selected ? const Color(0xFF58A6FF).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _buildThreadHeader(String address) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF161B22),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF58A6FF)),
          tooltip: 'بازگشت',
          onPressed: () => setState(() => _activeConversationAddress = null),
        ),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, color: Colors.white54),
          tooltip: 'کپی شماره',
          onPressed: () => _copyToClipboard(address, 'Number'),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF7B72)),
          tooltip: 'حذف گفتگو',
          onPressed: () => _deleteConversation(address),
        ),
      ]),
    );
  }

  Widget _buildConversationsList() {
    if (_conversations.isEmpty) {
      return _buildEmptyState(Icons.forum_rounded, 'No conversations yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final c = _conversations[index];
        final address = (c['address'] ?? 'Unknown').toString();
        final count = c['count'] ?? 0;
        final lastDate = DateTime.fromMillisecondsSinceEpoch((c['last_date'] as int?) ?? 0);
        final lastBody = (c['last_body'] ?? '').toString();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Material(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _activeConversationAddress = address;
                _conversationMode = false;
              }),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1F6FEB), Color(0xFF58A6FF)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              address,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('$count', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF58A6FF))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          lastBody,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${lastDate.hour.toString().padLeft(2, '0')}:${lastDate.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white30),
                      ),
                      Text(
                        '${lastDate.month}/${lastDate.day}',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return _buildEmptyState(Icons.inbox_rounded, 'No messages found');
    }

    final children = <Widget>[];
    DateTime? lastDay;
    for (final msg in list) {
      final date = DateTime.fromMillisecondsSinceEpoch(msg['date'] ?? 0);
      final day = DateTime(date.year, date.month, date.day);
      if (lastDay == null || day != lastDay) {
        children.add(_buildDateHeader(day));
        lastDay = day;
      }
      children.add(_buildMessageRow(msg));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _buildDateHeader(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'امروز'
        : (diff == 1
            ? 'دیروز'
            : '${day.year}/${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(children: [
        const Icon(Icons.calendar_today_rounded, size: 13, color: Colors.white38),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white54)),
      ]),
    );
  }

  Widget _buildMessageRow(Map<String, dynamic> msg) {
    final date = DateTime.fromMillisecondsSinceEpoch(msg['date'] ?? 0);
    final body = (msg['body'] ?? '').toString();
    final address = (msg['address'] ?? 'Unknown').toString();
    final isReceived = msg['type'] == 1;
    final devName = (msg['device_name'] ?? 'Phone').toString();
    final starred = msg['is_starred'] == 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showMessageDetail(msg),
          onLongPress: () => _copyToClipboard(body, 'Message'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isReceived ? const Color(0xFF58A6FF) : const Color(0xFF7EE787),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (starred) ...[
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFE3B341)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              address,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _miniChip(devName, const Color(0xFF58A6FF)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white30),
                    ),
                    Text(
                      '${date.month}/${date.day}',
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                  onSelected: (a) => _handleMessageAction(a, msg),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'star',
                      child: Row(children: [
                        Icon(starred ? Icons.star_border_rounded : Icons.star_rounded, size: 18, color: const Color(0xFFE3B341)),
                        const SizedBox(width: 10),
                        Text(starred ? 'حذف ستاره' : 'ستاره‌دار'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'copy',
                      child: Row(children: [
                        Icon(Icons.copy_rounded, size: 18, color: Color(0xFF58A6FF)),
                        SizedBox(width: 10),
                        Text('کپی متن'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'copyNumber',
                      child: Row(children: [
                        Icon(Icons.phone_rounded, size: 18, color: Color(0xFF7EE787)),
                        SizedBox(width: 10),
                        Text('کپی شماره'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFF7B72)),
                        SizedBox(width: 10),
                        Text('حذف'),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleMessageAction(String action, Map<String, dynamic> msg) async {
    final id = msg['id']?.toString() ?? '';
    final address = (msg['address'] ?? '').toString();
    final body = (msg['body'] ?? '').toString();

    switch (action) {
      case 'star':
        await widget.service.db.toggleSmsStarred(id);
        await _refreshData();
        break;
      case 'copy':
        _copyToClipboard(body, 'Message');
        break;
      case 'copyNumber':
        _copyToClipboard(address, 'Number');
        break;
      case 'delete':
        await _deleteMessage(id);
        break;
    }
  }

  Future<void> _deleteMessage(String id) async {
    final ok = await _confirm('حذف پیام', 'این پیام برای همیشه حذف شود؟');
    if (ok == true) {
      await widget.service.db.deleteSms(id);
      await _refreshData();
    }
  }

  Future<void> _deleteConversation(String address) async {
    final ok = await _confirm('حذف گفتگو', 'تمام پیام‌های $address حذف شوند؟');
    if (ok == true) {
      await widget.service.db.deleteSmsByAddress(address, deviceId: _selectedDeviceId);
      if (mounted) setState(() => _activeConversationAddress = null);
      await _refreshData();
    }
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDA3633)),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.inter(fontSize: 13))),
    );
  }

  Future<void> _handleDataAction(String action) async {
    try {
      switch (action) {
        case 'csv':
          final csv = await widget.service.backupService.exportCsv();
          if (mounted) _showSnack('خروجی CSV ساخته شد: ${csv.path}');
          break;
        case 'json':
          final jsonFile = await widget.service.backupService.exportJson();
          if (mounted) _showSnack('پشتیبان JSON ساخته شد: ${jsonFile.path}');
          break;
        case 'import':
          await _importJson();
          break;
        case 'open':
          await _openDownloadsFolder();
          break;
      }
    } catch (e) {
      if (mounted) _showSnack('خطا: $e');
    }
  }

  Future<void> _importJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    try {
      final count = await widget.service.backupService.importJson(File(path));
      await _refreshData();
      if (mounted) _showSnack('بازیابی انجام شد ($count پیام)');
    } catch (e) {
      if (mounted) _showSnack('خطا در بازیابی: $e');
    }
  }

  // ──────────────────────────────────────────
  // Text Tab
  // ──────────────────────────────────────────
  Widget _buildTextTab() {
    return Column(
      children: [
        _buildDeviceSelectorBar(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _textSendController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type or paste text to send...',
                    suffixIcon: IconButton(
                      icon: Icon(Icons.paste_rounded, color: Colors.white.withValues(alpha: 0.4)),
                      tooltip: 'Paste',
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _textSendController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _textSendController.clear(),
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Clear'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send'),
                      onPressed: () async {
                        final text = _textSendController.text.trim();
                        if (text.isEmpty) return;
                        try {
                          await widget.service.sendRawText(text);
                          _textSendController.clear();
                        } catch (e) {
                          if (mounted) _showSnack('خطا در ارسال متن: $e');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 18, color: Color(0xFFD2A8FF)),
              const SizedBox(width: 8),
              Text(
                'History (${_rawTexts.length})',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _rawTexts.isEmpty
              ? _buildEmptyState(Icons.text_snippet_outlined, 'No text exchanged yet')
              : ListView.builder(
                  itemCount: _rawTexts.length,
                  itemBuilder: (context, index) {
                    final item = _rawTexts[index];
                    final text = item['text'] ?? '';
                    final sender = item['sender'] ?? 'Remote';
                    final date = DateTime.fromMillisecondsSinceEpoch(item['created_at'] ?? 0);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
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
                            SelectableText(
                              text,
                              maxLines: 5,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, height: 1.5),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _miniChip(sender, const Color(0xFFD2A8FF)),
                                const SizedBox(width: 8),
                                Text(
                                  '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white30),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.3), size: 16),
                                  tooltip: 'Copy',
                                  onPressed: () => _copyToClipboard(text, 'Text'),
                                  visualDensity: VisualDensity.compact,
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
        _buildDeviceSelectorBar(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF1F6FEB),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 22),
                  label: Text('Send File to Phone', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  onPressed: _pickAndSendFile,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                label: const Text('Downloads'),
                onPressed: _openDownloadsFolder,
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FileTransferItem>>(
            stream: widget.service.fileTransfer.transfersStream,
            initialData: widget.service.fileTransfer.activeTransfers,
            builder: (context, snapshot) {
              final transfers = snapshot.data ?? [];
              if (transfers.isEmpty) {
                return _buildEmptyState(Icons.folder_shared_rounded, 'No file transfers yet');
              }

              return ListView.builder(
                itemCount: transfers.length,
                itemBuilder: (context, index) {
                  final item = transfers[index];
                  final sizeMb = (item.fileSize / (1024 * 1024)).toStringAsFixed(2);
                  final pct = (item.progress * 100).toInt();
                  final isUp = item.isOutgoing;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(16),
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
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('$sizeMb MB', style: GoogleFonts.inter(color: Colors.white30, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              color: item.isCompleted ? const Color(0xFF7EE787) : const Color(0xFF58A6FF),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.isCompleted
                                    ? '✓ Complete'
                                    : item.isFailed
                                        ? '✗ Failed'
                                        : '$pct%',
                                style: GoogleFonts.inter(
                                  color: item.isCompleted
                                      ? const Color(0xFF7EE787)
                                      : (item.isFailed ? const Color(0xFFFF7B72) : const Color(0xFF58A6FF)),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (item.isCompleted && item.localPath != null)
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
  // Status Bar
  // ──────────────────────────────────────────
  Widget _buildStatusBar() {
    final state = widget.service.state;
    final pin = widget.service.currentPin;
    final scope = widget.service.clientScope;
    final count = widget.service.connectedClientCount;

    Color accentColor;
    String statusText;
    IconData statusIcon;

    switch (state) {
      case ServerState.paired:
        accentColor = const Color(0xFF7EE787);
        statusText = 'Connected • $count Devices • ${scope.name}';
        statusIcon = Icons.link_rounded;
        break;
      case ServerState.connected:
        accentColor = const Color(0xFFF0883E);
        statusText = 'Device Connected ($count) — Awaiting PIN';
        statusIcon = Icons.lock_open_rounded;
        break;
      case ServerState.advertising:
        accentColor = const Color(0xFF58A6FF);
        statusText = 'Listening for devices...';
        statusIcon = Icons.wifi_rounded;
        break;
      default:
        accentColor = Colors.white38;
        statusText = 'Server Idle';
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
        border: Border(
          bottom: BorderSide(color: accentColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Animated glowing dot
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final pulse = 0.5 + 0.5 * sin(_glowController.value * 2 * pi);
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
          Icon(statusIcon, color: accentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (pin != null && (state == ServerState.advertising || state == ServerState.connected))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.key_rounded, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Text(
                    pin,
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF0883E),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
          if (pin != null)
            IconButton(
              icon: const Icon(Icons.casino_rounded, color: Color(0xFFF0883E)),
              tooltip: 'تغییر PIN',
              onPressed: () async {
                await widget.service.regeneratePin();
                if (mounted) setState(() {});
              },
            ),
          if (pin != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF58A6FF)),
              tooltip: 'Show QR Code',
              onPressed: _showQrCodeDialog,
            ),
          if (state == ServerState.paired || state == ServerState.connected)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: OutlinedButton.icon(
                onPressed: () => widget.service.disconnectClient(),
                icon: const Icon(Icons.link_off_rounded, size: 16, color: Color(0xFFFF7B72)),
                label: Text('Disconnect', style: GoogleFonts.inter(color: const Color(0xFFFF7B72), fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF7B72)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(Icons.sync_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('SMS Sync', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Colors.white.withValues(alpha: 0.5)),
            tooltip: 'Refresh',
            onPressed: _refreshData,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withValues(alpha: 0.5)),
            tooltip: 'Clear All Data',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Data?'),
                  content: const Text('This will delete all synced SMS, text, and SIM data.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDA3633),
                      ),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await widget.service.db.clearAllData();
                _refreshData();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.sms_rounded, size: 20), text: 'SMS & SIM'),
            Tab(icon: Icon(Icons.text_snippet_rounded, size: 20), text: 'Text Share'),
            Tab(icon: Icon(Icons.folder_shared_rounded, size: 20), text: 'Files'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusBar(),
          _buildFeatureControlBar(),
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
        ],
      ),
    );
  }
}
