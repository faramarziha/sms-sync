import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/file_launcher.dart';
import '../../core/models/sync_message.dart';
import '../../core/file_transfer_service.dart';
import '../client_sync_service.dart';
import '../../transport/sync_transport.dart';

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
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );

    _discoverySubscription = widget.service.discovery.discoveredServers.listen((servers) {
      if (mounted) {
        setState(() {
          _servers = servers;
        });
      }
    });

    _stateSubscription = widget.service.stateStream.listen((state) {
      if (state == ClientState.pairing && !_isPairingDialogShowing) {
        _showPairingDialog();
      }
    });

    _textSubscription = widget.service.textMessagesStream.listen((data) {
      if (mounted) {
        setState(() {
          _textHistory.insert(0, data);
        });
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
    _pulseController?.dispose();
    super.dispose();
  }

  void _showPairingDialog() {
    if (_isPairingDialogShowing) return;
    _isPairingDialogShowing = true;
    _pinController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.phonelink_setup, color: Colors.blue),
                SizedBox(width: 8),
                Text('Pairing & Sync Scope'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter 4-digit PIN from Windows Server:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 6),
                    decoration: const InputDecoration(
                      hintText: 'PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Choose Connection Purpose:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  _buildScopeTile(
                    scope: SyncScope.textFiles,
                    title: 'فایل و متن (Text & Files)',
                    subtitle: 'Quick text copy/paste & file transfer',
                    icon: Icons.file_present,
                    color: Colors.purple,
                    selectedScope: _selectedScope,
                    onSelect: (s) => setDialogState(() => _selectedScope = s),
                  ),
                  _buildScopeTile(
                    scope: SyncScope.smsSim,
                    title: 'پیامک و شماره تلفن (SMS & SIM)',
                    subtitle: 'Sync SMS messages and SIM card numbers',
                    icon: Icons.sms,
                    color: Colors.blue,
                    selectedScope: _selectedScope,
                    onSelect: (s) => setDialogState(() => _selectedScope = s),
                  ),
                  _buildScopeTile(
                    scope: SyncScope.both,
                    title: 'هر دو (Full Sync)',
                    subtitle: 'All features: Text, Files, SMS & SIM cards',
                    icon: Icons.bolt,
                    color: Colors.green,
                    selectedScope: _selectedScope,
                    onSelect: (s) => setDialogState(() => _selectedScope = s),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _isPairingDialogShowing = false;
                  Navigator.pop(context);
                  widget.service.startDiscovery();
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Pair Now'),
                onPressed: () {
                  _isPairingDialogShowing = false;
                  widget.service.sendPairRequest(_pinController.text, scope: _selectedScope);
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      ),
    ).then((_) {
      _isPairingDialogShowing = false;
    });
  }

  Widget _buildScopeTile({
    required SyncScope scope,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required SyncScope selectedScope,
    required ValueChanged<SyncScope> onSelect,
  }) {
    final isSelected = selectedScope == scope;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? color : Colors.black87)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: isSelected ? Icon(Icons.check_circle, color: color) : null,
        onTap: () => onSelect(scope),
      ),
    );
  }

  void _showManualConnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Connect via IP Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                hintText: 'e.g. 192.168.1.100',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final ip = _ipController.text.trim();
              final port = int.tryParse(_portController.text.trim()) ?? 8080;
              if (ip.isNotEmpty) {
                widget.service.connectToServer(
                  DiscoveredServer(name: 'Manual Server', address: ip, port: port),
                );
              }
            },
            child: const Text('Connect'),
          ),
        ],
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

  Widget _buildTextTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              TextField(
                controller: _textInputController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Type or paste formatted text here...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste, color: Colors.blue),
                    tooltip: 'Paste from Clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _textInputController.text = data!.text!;
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _textInputController.clear(),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Send Text'),
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
        const Divider(height: 1),
        Expanded(
          child: _textHistory.isEmpty
              ? const Center(
                  child: Text('No text sent or received yet', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: _textHistory.length,
                  itemBuilder: (context, index) {
                    final item = _textHistory[index];
                    final text = item['text'] ?? '';
                    final sender = item['sender'] ?? 'Remote';
                    final date = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] ?? 0);

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(text, maxLines: 5, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$sender • ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          tooltip: 'Copy Text',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Text copied to clipboard!'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.upload_file, size: 24),
            label: const Text('Select File to Send', style: TextStyle(fontSize: 16)),
            onPressed: _pickAndSendFile,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<FileTransferItem>>(
            stream: widget.service.fileTransfer.transfersStream,
            initialData: widget.service.fileTransfer.activeTransfers,
            builder: (context, snapshot) {
              final transfers = snapshot.data ?? [];
              if (transfers.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No file transfers yet', style: TextStyle(color: Colors.grey)),
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

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                item.isOutgoing ? Icons.upload : Icons.download,
                                color: item.isOutgoing ? Colors.blue : Colors.green,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('$sizeMb MB', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: item.progress,
                            backgroundColor: Colors.grey[200],
                            color: item.isCompleted ? Colors.green : Colors.blue,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.isCompleted
                                    ? '✓ Complete'
                                    : item.isFailed
                                        ? '✗ Failed'
                                        : '$pct%',
                                style: TextStyle(
                                  color: item.isCompleted ? Colors.green : (item.isFailed ? Colors.red : Colors.blue),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              if (item.isCompleted && item.localPath != null && !item.isOutgoing)
                                TextButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 14),
                                  label: const Text('Open File'),
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

  Widget _buildSmsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation!,
            child: const Icon(Icons.check_circle, size: 80, color: Colors.green),
          ),
          const SizedBox(height: 16),
          const Text('SMS & SIM Auto-Sync Active', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Messages and SIM card numbers are continuously synced to your PC.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text('Persistent Background Sync Active', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
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
        title: const Text('SMS Sync Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan Servers',
            onPressed: () => widget.service.startDiscovery(),
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Manual IP Connect',
            onPressed: _showManualConnectDialog,
          ),
        ],
        bottom: widget.service.state == ClientState.synced
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.sms), text: 'SMS & SIM'),
                  Tab(icon: Icon(Icons.short_text), text: 'Text Share'),
                  Tab(icon: Icon(Icons.folder), text: 'File Share'),
                ],
              )
            : null,
      ),
      body: StreamBuilder<ClientState>(
        stream: widget.service.stateStream,
        initialData: widget.service.state,
        builder: (context, snapshot) {
          final state = snapshot.data;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: _getStatusColor(state),
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation!,
                      child: const Icon(Icons.sync, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getStatusText(state),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (state == ClientState.syncing || state == ClientState.synced || state == ClientState.pairing)
                      ElevatedButton.icon(
                        onPressed: () => widget.service.disconnect(),
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('Disconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              if (state == ClientState.synced)
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

              if (state == ClientState.connecting)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        const Text('Connecting to Server...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 20),
                        OutlinedButton(onPressed: () => widget.service.startDiscovery(), child: const Text('Cancel')),
                      ],
                    ),
                  ),
                ),

              if (state == ClientState.browsing || state == ClientState.idle)
                Expanded(
                  child: _servers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                scale: _pulseAnimation!,
                                child: const Icon(Icons.wifi_find, size: 64, color: Colors.blue),
                              ),
                              const SizedBox(height: 16),
                              const Text('Searching for Windows Server on Wi-Fi...'),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _showManualConnectDialog,
                                icon: const Icon(Icons.edit),
                                label: const Text('Connect via IP Manually'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _servers.length,
                          itemBuilder: (context, index) {
                            final server = _servers[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: const Icon(Icons.desktop_windows, color: Colors.blue),
                                title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${server.address}:${server.port}'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () => widget.service.connectToServer(server),
                              ),
                            );
                          },
                        ),
                ),

              if (state == ClientState.pairing)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock, size: 64, color: Colors.orange),
                        const SizedBox(height: 16),
                        const Text('Connected — Enter PIN to pair'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _showPairingDialog,
                          child: const Text('Choose Scope & Enter PIN'),
                        ),
                      ],
                    ),
                  ),
                ),

              if (state == ClientState.error)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 64),
                          const SizedBox(height: 16),
                          const Text('Connection Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(onPressed: () => widget.service.startDiscovery(), child: const Text('Retry Scan')),
                              const SizedBox(width: 12),
                              OutlinedButton(onPressed: _showManualConnectDialog, child: const Text('Manual IP')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _getStatusColor(ClientState? state) {
    switch (state) {
      case ClientState.synced:
        return Colors.green[700]!;
      case ClientState.syncing:
        return Colors.blue[700]!;
      case ClientState.pairing:
        return Colors.orange[800]!;
      case ClientState.connecting:
        return Colors.blue[700]!;
      case ClientState.error:
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  String _getStatusText(ClientState? state) {
    switch (state) {
      case ClientState.synced:
        return '✓ Connected & Background Sync Active (${widget.service.scope.name})';
      case ClientState.syncing:
        return '↑ Initializing connection...';
      case ClientState.pairing:
        return '🔐 Waiting for PIN verification';
      case ClientState.connecting:
        return '⏳ Connecting...';
      case ClientState.browsing:
        return '📡 Scanning for servers...';
      case ClientState.error:
        return '✗ Connection Error';
      default:
        return 'Idle';
    }
  }
}
