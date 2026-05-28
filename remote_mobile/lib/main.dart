import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ui/remote_ui.dart';
import 'ui/tv_remote_ui.dart';

const String kRelayUrl = 'wss://air-mouse-fb25.onrender.com';

void main() => runApp(const MaterialApp(
      home: MobileEntry(),
      debugShowCheckedModeBanner: false,
    ));

enum DeviceType { pc, tv }

// ─────────────────────────────────────────────────────────────────────────────
// MobileEntry
// ─────────────────────────────────────────────────────────────────────────────
class MobileEntry extends StatefulWidget {
  const MobileEntry({super.key});
  @override
  State<MobileEntry> createState() => _MobileEntryState();
}

class _MobileEntryState extends State<MobileEntry> with WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _retryTimer;
  Timer? _pingTimer;

  // The URL we most recently connected to — saved so we can rejoin after lock.
  String? _savedUrl;

  bool _connected = false;      // got status:connected from relay
  bool _reconnecting = false;   // mid-session drop, trying to come back
  bool _userDisconnected = false;
  String? _error;
  DeviceType _deviceType = DeviceType.pc;

  final _codeCtrl = TextEditingController();

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_userDisconnected && _savedUrl != null) {
      // App came back to foreground. If the socket is already alive this is a
      // no-op because _reconnect checks readyState before doing anything.
      _reconnect();
    }
  }

  // ── Socket management ──────────────────────────────────────────────────────

  void _teardown({bool keepUrl = false}) {
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _sub?.cancel();
    try { _ws?.sink.close(); } catch (_) {}
    _ws = null;
    _sub = null;
    if (!keepUrl) _savedUrl = null;
  }

  // Connect fresh (user-initiated).
  void _connectTo(String url) {
    _userDisconnected = false;
    _teardown();
    _savedUrl = url;
    setState(() { _error = null; _reconnecting = false; _connected = false; });
    _openSocket(url);
  }

  // Reconnect to _savedUrl — called on resume or after a drop.
  // Safe to call even if the socket is already open (checks first).
  void _reconnect() {
    if (_ws != null) {
      // Socket object exists — check if it's actually open by trying a ping.
      // If it throws or the stream is closed, _onDone will fire and retry.
      try {
        _ws!.sink.add('ping');
        return; // seems alive, do nothing
      } catch (_) {
        // sink is closed — fall through to reconnect
      }
    }
    _retryTimer?.cancel();
    _openSocket(_savedUrl!);
  }

  void _openSocket(String url) {
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _sub?.cancel();
    try { _ws?.sink.close(); } catch (_) {}

    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _ws = ch;

      _sub = ch.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: (_) => _onDone(),
        cancelOnError: false,
      );

      // Keep-alive ping every 25 s so the relay doesn't time out the socket.
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try { _ws?.sink.add('ping'); } catch (_) {}
      });

    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    final msg = raw.toString();
    if (msg == 'ping' || msg == 'pong') return;

    // If we were showing the reconnecting overlay, clear it now.
    if (_reconnecting && mounted) setState(() => _reconnecting = false);

    if (!mounted) return;

    if (msg.startsWith('status:connected') ||
        msg.startsWith('status:waiting_for_host')) {
      final parts = msg.split(':');
      final type = parts.length > 2 ? parts[2] : 'pc';
      setState(() {
        _connected = true;
        _reconnecting = false;
        _error = null;
        _deviceType = type == 'tv' ? DeviceType.tv : DeviceType.pc;
      });
    } else if (msg == 'error:room_not_found') {
      // Room was deleted on the relay (host closed, TTL expired, etc.).
      // Give up and send user back to the connect screen.
      setState(() {
        _connected = false;
        _reconnecting = false;
        _error = 'Room expired. Please reconnect.';
        _savedUrl = null;
      });
      _teardown();
    } else if (msg.startsWith('status:host_disconnected')) {
      setState(() {
        _connected = false;
        _reconnecting = false;
        _error = 'Host disconnected.';
      });
      // Keep _savedUrl so user can retry, but stop socket.
      _teardown(keepUrl: true);
    }
  }

  void _onDone() {
    if (_userDisconnected || _savedUrl == null) return;

    // Unexpected drop. If we were in a session, show the overlay.
    if (_connected && mounted) {
      setState(() => _reconnecting = true);
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (!_userDisconnected && _savedUrl != null) _openSocket(_savedUrl!);
    });
  }

  void _disconnect() {
    _userDisconnected = true;
    _teardown();
    setState(() {
      _connected = false;
      _reconnecting = false;
      _error = null;
    });
  }

  void _send(String cmd) {
    if (_reconnecting) return;
    try { _ws?.sink.add(cmd); } catch (_) {}
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_connected) return _buildRemote();
    return _buildConnectScreen();
  }

  Widget _buildRemote() {
    final body = _deviceType == DeviceType.tv
        ? TVRemoteUI(sendCommand: _send, onDisconnect: _disconnect)
        : SingleChildScrollView(
            child: RemoteUI(sendCommand: _send, onDisconnect: _disconnect));

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(_deviceType == DeviceType.tv ? Icons.tv : Icons.computer,
              size: 18),
          const SizedBox(width: 8),
          Text(_deviceType == DeviceType.tv ? 'TV Remote' : 'PC Remote'),
          if (_reconnecting) ...[
            const SizedBox(width: 10),
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
        actions: [
          if (_deviceType == DeviceType.tv)
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off, size: 16, color: Colors.redAccent),
              label: const Text('Disconnect',
                  style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: Stack(children: [
        body,
        if (_reconnecting)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                ),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reconnecting…',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  Text('Please wait a moment',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildConnectScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Air Mouse')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 56, color: Colors.blueAccent),
            const SizedBox(height: 12),
            const Text('Air Mouse',
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Control your PC or Android TV',
                style:
                    TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _QrScannerPage(onScanned: (url) {
                  Navigator.of(context).pop();
                  _connectTo(url);
                }),
              )),
              icon: const Icon(Icons.qr_code_scanner, size: 26),
              label: const Text('Scan QR Code'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or enter room code',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 24),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8),
              decoration: const InputDecoration(
                labelText: 'Room Code',
                border: OutlineInputBorder(),
                hintText: 'ABC123',
                hintStyle: TextStyle(letterSpacing: 4),
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              onSubmitted: (_) => _submitCode(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitCode,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Connect', style: TextStyle(fontSize: 16)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                  child: _hint(Icons.computer, 'PC', 'Run AirMouseAgent.exe')),
              const SizedBox(width: 12),
              Expanded(
                  child: _hint(
                      Icons.tv, 'Android TV', 'Open Air Mouse TV app')),
            ]),
          ],
        ),
      ),
    );
  }

  void _submitCode() {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a room code');
      return;
    }
    _connectTo('$kRelayUrl/phone/$code');
  }

  Widget _hint(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 22, color: Colors.blueAccent),
        const SizedBox(height: 6),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── QR Scanner ────────────────────────────────────────────────────────────────
class _QrScannerPage extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrScannerPage({required this.onScanned});
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _scanned = false;
  final _ctrl = MobileScannerController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw != null && raw.startsWith('ws')) {
      _scanned = true;
      widget.onScanned(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: _ctrl.toggleTorch),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        Center(
            child: Container(
          width: 240, height: 240,
          decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(12)),
        )),
        const Align(
          alignment: Alignment(0, 0.75),
          child: Text('Point at the QR on your PC or TV',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 4)])),
        ),
      ]),
    );
  }
}