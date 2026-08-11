import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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

class ClientHomeScreen extends StatefulWidget {
  final ClientSyncService service;
  const ClientHomeScreen({super.key, required this.service});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with TickerProviderStateMixin {
  List<DiscoveredServer> _servers = [];
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.');
  final TextEditingController _portController = TextEditingController(text: '8080');
  final TextEditingController _textInputController = TextEditingController();

  StreamSubscription<List<DiscoveredServer>>? _discoverySubscription;
  StreamSubscription<ClientState>? _stateSubscription;
  StreamSubscription<Map<String, dynamic>>? _textSubscription;

  bool _isPairingDialogShowing = false;
  SyncScope _selectedScope = SyncScope.both;
  final List<Map<String, dynamic>> _textHistory = [];

  TabController? _tabController;
  late AnimationController _radarController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
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

    _discoverySubscription = widget.service.discovery.discoveredServers.listen((servers) {
      if (mounted) {
        setState(() => _servers = servers);
      }
    });

    _stateSubscription = widget.service.stateStream.listen((state) {
      if (mounted) setState(() {});
      if (state == ClientState.pairing && !_isPairingDialogShowing) {
        _showPairingDialog();
      }
    });

    _textSubscription = widget.service.textMessagesStream.listen((data) {
      if (mounted) {
        setState(() => _textHistory.insert(0, data));
      }
    });

    widget.service.startDiscovery();
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _stateSubscription?.cancel();
    _textSubscription?.cancel();
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
                          onPressed: () {
                            _isPairingDialogShowing = false;
                            widget.service.sendPairRequest(_pinController.text, scope: _selectedScope);
                            Navigator.pop(context);
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

  void _showQrScannerDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
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
                  Text('اسکن کد QR سرور', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    onDetect: (capture) async {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          try {
                            final data = jsonDecode(raw) as Map<String, dynamic>;
                            final address = data['address'] as String?;
                            final port = data['port'] as int? ?? 8080;
                            final pin = data['pin'] as String?;

                            if (address != null && pin != null) {
                              Navigator.pop(context);
                              await widget.service.connectToServer(
                                DiscoveredServer(name: 'Scanned PC', address: address, port: port),
                              );
                              await widget.service.sendPairRequest(pin);
                              break;
                            }
                          } catch (_) {}
                        }
                      }
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
      },
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

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      await widget.service.sendFile(file);
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

  // ──────────────────────────────────────────
  // SMS Synced Tab
  // ──────────────────────────────────────────
  Widget _buildSmsTab() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
              'Messages and SIM cards are syncing to your PC',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7EE787).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
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
                    'Background Sync Active',
                    style: GoogleFonts.inter(color: const Color(0xFF7EE787), fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                          if (text != null && text.isNotEmpty) {
                            widget.service.sendRawText(text);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('متن کلیپ‌بورد به کامپیوتر ارسال شد'),
                                duration: Duration(seconds: 2),
                              ),
                            );
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
                      onPressed: () {
                        if (_textInputController.text.isNotEmpty) {
                          widget.service.sendRawText(_textInputController.text);
                          _textInputController.clear();
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
                Text(
                  _servers.isEmpty ? 'Scanning for servers...' : '${_servers.length} server(s) found',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
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
            Text('SMS Sync', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF58A6FF), size: 22),
            tooltip: 'Scan QR Code',
            onPressed: _showQrScannerDialog,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Colors.white.withValues(alpha: 0.5), size: 22),
            tooltip: 'Rescan',
            onPressed: () => widget.service.startDiscovery(),
          ),
          IconButton(
            icon: Icon(Icons.add_link_rounded, color: Colors.white.withValues(alpha: 0.5), size: 22),
            tooltip: 'Manual IP',
            onPressed: _showManualConnectDialog,
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

          return Column(
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
          );
        },
      ),
    );
  }
}
