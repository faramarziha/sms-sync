import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/file_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/models/sync_message.dart';
import '../../core/file_transfer_service.dart';
import '../../transport/sync_transport.dart';
import '../server_sync_service.dart';

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

  String? _selectedDeviceId; // null = All Devices

  StreamSubscription<ServerState>? _stateSubscription;
  StreamSubscription<void>? _dataSubscription;
  StreamSubscription<List<DiscoveredServer>>? _discoveredClientsSubscription;

  final TextEditingController _textSendController = TextEditingController();
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
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _dataSubscription?.cancel();
    _discoveredClientsSubscription?.cancel();
    _textSendController.dispose();
    _tabController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    await widget.service.startServer();
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    final sms = await widget.service.db.getAllSms(deviceId: _selectedDeviceId);
    final sims = await widget.service.db.getAllSims(deviceId: _selectedDeviceId);
    final texts = await widget.service.db.getAllRawTexts(deviceId: _selectedDeviceId);

    if (mounted) {
      setState(() {
        _messages = sms;
        _sims = sims;
        _rawTexts = texts;
      });
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      await widget.service.sendFile(file);
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
            const Icon(Icons.check_circle, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Text('$label copied to clipboard!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showMessageDetail(Map<String, dynamic> msg) {
    final date = DateTime.fromMillisecondsSinceEpoch(msg['date'] ?? 0);
    final typeLabel = _smsTypeLabel(msg['type']);
    final deviceName = msg['device_name'] ?? 'Android Phone';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              msg['type'] == 1 ? Icons.call_received : Icons.call_made,
              color: msg['type'] == 1 ? Colors.blue : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg['address'] ?? 'Unknown',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smartphone, size: 14, color: Colors.indigo),
                    const SizedBox(width: 4),
                    Text(deviceName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  '
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Chip(
                      label: Text(typeLabel, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: msg['type'] == 1 ? Colors.blue : Colors.green,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const Divider(height: 20),
                SelectableText(
                  msg['body'] ?? '',
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.blue),
            tooltip: 'Copy Message Body',
            onPressed: () => _copyToClipboard(msg['body'] ?? '', 'Message'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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

  Widget _buildDeviceSelectorBar() {
    final devices = widget.service.connectedDevices.values.toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: Row(
        children: [
          const Icon(Icons.devices, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text('Filter Device:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.all_inclusive, size: 16),
                    label: Text('All Devices (${devices.length})'),
                    selected: _selectedDeviceId == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedDeviceId = null;
                        });
                        _refreshData();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ...devices.map((device) {
                    final isSelected = _selectedDeviceId == device.deviceId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.smartphone, size: 16),
                        label: Text(device.deviceName),
                        selected: isSelected,
                        selectedColor: Colors.blue[100],
                        onSelected: (selected) {
                          setState(() {
                            _selectedDeviceId = selected ? device.deviceId : null;
                          });
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
        padding: const EdgeInsets.all(16),
        child: const Row(
          children: [
            Icon(Icons.sim_card_outlined, color: Colors.grey),
            SizedBox(width: 8),
            Text('No SIM info received yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(displaySims.length, (index) {
          final sim = displaySims[index];
          final slotNumber = ((sim['sim_slot'] as int?) ?? index) + 1;
          final phoneNum = sim['phone_number'] ?? 'No Number';
          final carrier = sim['carrier_name'] ?? 'Unknown Carrier';
          final devName = sim['device_name'] ?? 'Phone';

          return Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: slotNumber == 1
                        ? [Colors.blue[700]!, Colors.blue[900]!]
                        : [Colors.teal[700]!, Colors.teal[900]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sim_card, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SIM $slotNumber',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                devName,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () => _copyToClipboard(phoneNum, 'SIM $slotNumber Number'),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    phoneNum,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.copy, color: Colors.white70, size: 16),
                              ],
                            ),
                          ),
                          Text(
                            carrier,
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDiscoveredClientsSection() {
    if (_discoveredClients.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScaleTransition(
                scale: _pulseAnimation!,
                child: const Icon(Icons.wifi_find, color: Colors.indigo),
              ),
              const SizedBox(width: 8),
              const Text(
                'Auto-Discovered Devices on Local Wi-Fi Network',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _discoveredClients.map((client) {
              return ActionChip(
                avatar: const Icon(Icons.smartphone, size: 18, color: Colors.indigo),
                label: Text('${client.name} (${client.address})'),
                backgroundColor: Colors.white,
                elevation: 2,
                onPressed: () {
                  widget.service.connectToDiscoveredClient(client);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeviceSelectorBar(),
        _buildSimCardsSection(),
        _buildDiscoveredClientsSection(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.sms, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'SMS Messages (${_messages.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No messages received yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _messages.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final date = DateTime.fromMillisecondsSinceEpoch(msg['date'] ?? 0);
                    final body = msg['body'] ?? '';
                    final isReceived = msg['type'] == 1;
                    final devName = msg['device_name'] ?? 'Android Phone';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isReceived ? Colors.blue[100] : Colors.green[100],
                        child: Icon(
                          isReceived ? Icons.call_received : Icons.call_made,
                          color: isReceived ? Colors.blue : Colors.green,
                          size: 18,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              msg['address'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          Text(
                            devName,
                            style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      trailing: Text(
                        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}\n'
                        '${date.month}/${date.day}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        textAlign: TextAlign.right,
                      ),
                      onTap: () => _showMessageDetail(msg),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTextTab() {
    return Column(
      children: [
        _buildDeviceSelectorBar(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: [
                  TextField(
                    controller: _textSendController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type or paste formatted text to send to Android phone...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste, color: Colors.blue),
                        tooltip: 'Paste from Clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            _textSendController.text = data!.text!;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _textSendController.clear(),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.send),
                        label: const Text('Send Text to Phone'),
                        onPressed: () {
                          if (_textSendController.text.isNotEmpty) {
                            widget.service.sendRawText(_textSendController.text);
                            _textSendController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.history, size: 20, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'Text Clipboard History (${_rawTexts.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rawTexts.isEmpty
              ? const Center(
                  child: Text('No formatted text sent/received yet', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: _rawTexts.length,
                  itemBuilder: (context, index) {
                    final item = _rawTexts[index];
                    final text = item['text'] ?? '';
                    final sender = item['sender'] ?? 'Remote';
                    final date = DateTime.fromMillisecondsSinceEpoch(item['created_at'] ?? 0);

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: SelectableText(text, maxLines: 5),
                        subtitle: Text('$sender • ${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          tooltip: 'Copy to Clipboard',
                          onPressed: () => _copyToClipboard(text, 'Text'),
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
        _buildDeviceSelectorBar(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.upload_file, size: 24),
                label: const Text('Send File to Phone', style: TextStyle(fontSize: 16)),
                onPressed: _pickAndSendFile,
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.folder_special, size: 20),
                label: const Text('Open Downloads Folder'),
                onPressed: _openDownloadsFolder,
              ),
            ],
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
                      Icon(Icons.folder_shared, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No active or recent file transfers', style: TextStyle(color: Colors.grey)),
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
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                item.isOutgoing ? Icons.upload_file : Icons.download_for_offline,
                                color: item.isOutgoing ? Colors.blue : Colors.green,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('$sizeMb MB', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: item.progress,
                            backgroundColor: Colors.grey[200],
                            color: item.isCompleted ? Colors.green : Colors.blue,
                            minHeight: 6,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.isCompleted
                                    ? '✓ Complete'
                                    : item.isFailed
                                        ? '✗ Failed'
                                        : '$pct% (${item.sender})',
                                style: TextStyle(
                                  color: item.isCompleted ? Colors.green : (item.isFailed ? Colors.red : Colors.blue),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (item.isCompleted && item.localPath != null)
                                TextButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 16),
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

  Widget _buildStatusBar() {
    final state = widget.service.state;
    final pin = widget.service.currentPin;
    final scope = widget.service.clientScope;
    final count = widget.service.connectedClientCount;

    Color bgColor;
    String statusText;
    IconData statusIcon;

    switch (state) {
      case ServerState.paired:
        bgColor = Colors.green[700]!;
        statusText = 'Connected & Paired ($count Active Devices - ${scope.name})';
        statusIcon = Icons.link;
        break;
      case ServerState.connected:
        bgColor = Colors.orange[800]!;
        statusText = 'Client Connected ($count Devices) — Waiting for PIN';
        statusIcon = Icons.lock_open;
        break;
      case ServerState.advertising:
        bgColor = Colors.blue[700]!;
        statusText = 'Waiting for Auto-Connect or Client PIN...';
        statusIcon = Icons.wifi;
        break;
      default:
        bgColor = Colors.grey[700]!;
        statusText = 'Server Idle';
        statusIcon = Icons.power_settings_new;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Row(
        children: [
          ScaleTransition(
            scale: _pulseAnimation!,
            child: Icon(statusIcon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          if (pin != null && (state == ServerState.advertising || state == ServerState.connected))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('PIN: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(
                    pin,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
          if (state == ServerState.paired || state == ServerState.connected)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ElevatedButton.icon(
                onPressed: () => widget.service.disconnectClient(),
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Disconnect All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        title: const Text('SMS & Multi-Device Sync Server'),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All Data',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Data?'),
                  content: const Text('This will delete all synced SMS, text logs, and SIM info.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.sms), text: 'SMS & SIM Cards'),
            Tab(icon: Icon(Icons.short_text), text: 'Text Clipboard Exchange'),
            Tab(icon: Icon(Icons.folder_shared), text: 'File Sharing Hub'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusBar(),
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
