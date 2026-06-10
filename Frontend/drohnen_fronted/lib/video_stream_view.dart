import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VideoStreamView extends StatefulWidget {
  final String backendUrl;

  const VideoStreamView({Key? key, required this.backendUrl}) : super(key: key);

  @override
  _VideoStreamViewState createState() => _VideoStreamViewState();
}

class _VideoStreamViewState extends State<VideoStreamView> {
  late WebSocketChannel _channel;

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(Uri.parse(widget.backendUrl));
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _channel.stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: const Center(
              child: Icon(Icons.videocam_outlined, size: 100, color: Colors.white24),
            ),
          );
        }

        try {
          // Backend sendet binäre JPEG-Frames; base64-Text wird als
          // Fallback weiterhin unterstützt.
          final dynamic data = snapshot.data;
          final Uint8List imageBytes = data is String
              ? base64Decode(data)
              : (data is Uint8List ? data : Uint8List.fromList(data as List<int>));
          return SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.memory(
              imageBytes,
              gaplessPlayback: true,
              fit: BoxFit.cover,
            ),
          );
        } catch (e) {
          return const Center(child: Text("Fehler beim Dekodieren des Videos."));
        }
      },
    );
  }
}
