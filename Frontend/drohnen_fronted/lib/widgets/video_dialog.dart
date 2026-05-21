import 'dart:convert';
import 'dart:typed_data';
import 'package:drohnen_fronted/models/saved_recording.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class VideoDialog extends StatefulWidget {
  final String backendHost;
  final bool isConnected;
  final Future<void> Function(List<Map<String, dynamic>>) onExecuteBuiltIn;
  final Future<void> Function(int) onExecuteSaved;
  final VoidCallback onAddNew;

  const VideoDialog({
    Key? key,
    required this.backendHost,
    required this.isConnected,
    required this.onExecuteBuiltIn,
    required this.onExecuteSaved,
    required this.onAddNew,
  }) : super(key: key);

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  List<SavedRecording> _savedRecordings = [];
  bool _loading = true;
  bool _isRecording = false;
  WebSocketChannel? _channel;
  Uint8List? _latestFrame;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    _connectVideo();
  }

  void _connectVideo() {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://${widget.backendHost}/video'),
    );
    _channel!.stream.listen((message) {
      if (mounted) {
        setState(() {
          _latestFrame = base64Decode(message);
        });
      }
    });
  }

  Future<void> _loadRecordings() async {
    try {
      final res = await http.get(Uri.parse('http://${widget.backendHost}/recordings'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _savedRecordings = (data['data'] as List)
              .map((e) => SavedRecording.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteRecording(int id) async {
    await http.delete(Uri.parse('http://${widget.backendHost}/recordings/$id'));
    _loadRecordings();
  }

  Future<void> _toggleRecording() async {
    final action = _isRecording ? 'stop' : 'start';
    final res = await http.post(Uri.parse('http://${widget.backendHost}/recordings/$action'));
    if (jsonDecode(res.body)['success'] == true) {
      setState(() => _isRecording = !_isRecording);
      if (!_isRecording) _loadRecordings();
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kamera & Aufnahme'),
      content: SizedBox(
        width: 400,
        child: Column(
          children: [
            Container(
              height: 200, color: Colors.black,
              child: _latestFrame != null ? Image.memory(_latestFrame!) : const SizedBox(),
            ),
            ElevatedButton(
              onPressed: _toggleRecording,
              child: Text(_isRecording ? 'Stopp' : 'Start'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _savedRecordings.length,
                itemBuilder: (context, i) => ListTile(
                  // ACHTUNG: Hier muss der Name des Feldes aus deiner saved_recording.dart Klasse stehen!
                  // Falls es nicht .filename heißt, schau in deine Klasse (z.B. .name)
                  title: Text(_savedRecordings[i].toString()), 
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteRecording(_savedRecordings[i].id!),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}