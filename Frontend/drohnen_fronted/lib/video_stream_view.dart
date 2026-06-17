import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VideoStreamView extends StatefulWidget {
  final String backendUrl;

  const VideoStreamView({super.key, required this.backendUrl});

  @override
  State<VideoStreamView> createState() => _VideoStreamViewState();
}

class _VideoStreamViewState extends State<VideoStreamView> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Uint8List? _frame;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(widget.backendUrl));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _sub = _channel!.stream.listen(
      (message) {
        if (_disposed) return;
        Uint8List? bytes;
        if (message is Uint8List) {
          bytes = message;
        } else if (message is List<int>) {
          bytes = Uint8List.fromList(message);
        } else if (message is String) {
          // Backend sendet binäre JPEGs. Text ist entweder ein base64-Fallback
          // oder eine JSON-Fehlermeldung ("Kein Videosignal") → dann kein Frame.
          try {
            bytes = base64Decode(message);
          } catch (_) {
            bytes = null;
          }
        }
        if (bytes != null && bytes.isNotEmpty && mounted) {
          setState(() => _frame = bytes);
        }
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _reconnectTimer?.cancel();
    // Immer wieder versuchen, bis der Backend-Stream Frames liefert. So erscheint
    // das Bild von selbst, sobald der H.264-Stream "warm" ist — direkt nach dem
    // Verbinden, OHNE dass man erst auf Start/Takeoff drücken muss.
    _reconnectTimer = Timer(const Duration(milliseconds: 800), _connect);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      // Noch kein Bild → Ladeanzeige (statt schwarz/leer), bis Frames kommen.
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white24),
              SizedBox(height: 12),
              Text(
                'Video wird geladen…',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Image.memory(
        frame,
        gaplessPlayback: true,
        fit: BoxFit.cover,
      ),
    );
  }
}
