import 'dart:typed_data';
import 'package:drohnen_fronted/models/saved_recording.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VideoDialog extends StatefulWidget {
  final String backendHost;
  final bool isConnected;
  final Future<void> Function(List<Map<String, dynamic>>) onExecuteBuiltIn;
  final Future<void> Function(int) onExecuteSaved;
  final VoidCallback onAddNew;

  const VideoDialog({
    super.key,
    required this.backendHost,
    required this.isConnected,
    required this.onExecuteBuiltIn,
    required this.onExecuteSaved,
    required this.onAddNew,
  });

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  List<SavedRecording> _recordings = [];
  bool _loading = true;
  bool _isRecording = false;
  WebSocketChannel? _channel;
  SavedRecording? _selectedRecording;
  VideoPlayerController? _videoController;
  bool _videoInitializing = false;

  final ValueNotifier<Uint8List?> _frameNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    _checkRecordingStatus(); // Fragt den aktuellen Status beim Öffnen ab
    _connectLiveVideo();
  }

  void _connectLiveVideo() {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://${widget.backendHost}/video'),
    );
    _channel!.stream.listen((message) {
      if (!mounted) return;
      if (message is String) {
        try {
          _frameNotifier.value = base64Decode(message);
        } catch (_) {}
      } else if (message is Uint8List) {
        _frameNotifier.value = message;
      } else if (message is List<int>) {
        _frameNotifier.value = Uint8List.fromList(message);
      }
    });
  }

  Future<void> _checkRecordingStatus() async {
    try {
      final res = await http.get(
        Uri.parse('http://${widget.backendHost}/recordings/status'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && data['isRecording'] != null) {
        setState(() {
          _isRecording = data['isRecording'];
        });
      }
    } catch (_) {
      // Fehler ignorieren, Status wird auf false gelassen
    }
  }

  Future<void> saveRecording() async {
    try {
      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/recordings/save')
      );
      if (jsonDecode(res.body)['success'] == true) {
        _loadRecordings();
      }
    } catch (_) {}
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('http://${widget.backendHost}/recordings'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _recordings = (data['data'] as List)
              .map((e) => SavedRecording.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _deleteRecording(int id) async {
    await http.delete(
      Uri.parse('http://${widget.backendHost}/recordings/$id'),
    );
    if (_selectedRecording?.id == id) {
      await _videoController?.dispose();
      setState(() {
        _videoController = null;
        _selectedRecording = null;
      });
    }
    _loadRecordings();
  }

  Future<void> _toggleRecording() async {
    final action = _isRecording ? 'stop' : 'start';
    try {
      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/recordings/$action'),
      );
      if (jsonDecode(res.body)['success'] == true) {
        setState(() => _isRecording = !_isRecording);
        if (!_isRecording) _loadRecordings();
      }
    } catch (_) {}
  }

  Future<void> _selectRecording(SavedRecording rec) async {
    if (_selectedRecording?.id == rec.id) return;

    await _videoController?.dispose();
    setState(() {
      _selectedRecording = rec;
      _videoController = null;
      _videoInitializing = true;
    });

    final url =
        'http://${widget.backendHost}/recordings/${rec.id}/video';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _videoController = controller;
          _videoInitializing = false;
        });
      } else {
        controller.dispose();
      }
    } catch (_) {
      if (mounted) setState(() => _videoInitializing = false);
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _frameNotifier.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 700,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.videocam, color: Colors.redAccent),
        const SizedBox(width: 8),
        const Text(
          'Video-Aufnahmen',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _toggleRecording,
          icon: Icon(
            _isRecording ? Icons.stop : Icons.fiber_manual_record,
            size: 16,
          ),
          label: Text(_isRecording ? 'Stopp' : 'Aufnehmen'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isRecording ? Colors.redAccent : Colors.green.shade700,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: recording list
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Gespeicherte Aufnahmen',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
                    tooltip: 'Neu laden',
                    onPressed: _loadRecordings,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(child: _buildRecordingList()),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right: video preview
        Expanded(child: _buildVideoPreview()),
      ],
    );
  }

  Widget _buildRecordingList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_recordings.isEmpty) {
      return const Center(
        child: Text(
          'Keine Aufnahmen vorhanden.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      itemCount: _recordings.length,
      itemBuilder: (context, i) {
        final rec = _recordings[i];
        final isSelected = _selectedRecording?.id == rec.id;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blueAccent : Colors.transparent,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.movie, color: Colors.white54, size: 18),
            title: Text(
              rec.filename,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: rec.createdAt != null
                ? Text(
                    rec.createdAt!.length > 19
                        ? rec.createdAt!.substring(0, 19)
                        : rec.createdAt!,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  )
                : null,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              onPressed: () => _deleteRecording(rec.id),
            ),
            onTap: () => _selectRecording(rec),
          ),
        );
      },
    );
  }

  Widget _buildVideoPreview() {
    if (_selectedRecording == null) {
      // Show live stream when nothing selected
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live-Stream',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RepaintBoundary(
              child: ValueListenableBuilder<Uint8List?>(
                valueListenable: _frameNotifier,
                builder: (_, frame, _) => Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: frame != null
                      ? Image.memory(
                          frame,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        )
                      : const Center(
                          child: Icon(
                            Icons.videocam_off,
                            color: Colors.white24,
                            size: 48,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aufnahme anklicken zum Abspielen',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedRecording!.filename,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white38),
              onPressed: () async {
                await _videoController?.dispose();
                setState(() {
                  _selectedRecording = null;
                  _videoController = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Container(
            color: Colors.black,
            width: double.infinity,
            child: _buildPlayerArea(),
          ),
        ),
        if (_videoController != null && _videoController!.value.isInitialized)
          _buildPlayerControls(),
      ],
    );
  }

  Widget _buildPlayerArea() {
    if (_videoInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: Text(
          'Video konnte nicht geladen werden.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: VideoPlayer(ctrl),
    );
  }

  Widget _buildPlayerControls() {
    final ctrl = _videoController!;
    return Row(
      children: [
        IconButton(
          icon: Icon(
            ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
            });
          },
        ),
        Expanded(
          child: VideoProgressIndicator(
            ctrl,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Colors.blueAccent,
              backgroundColor: Colors.white12,
              bufferedColor: Colors.white24,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.replay, color: Colors.white54, size: 18),
          onPressed: () => ctrl.seekTo(Duration.zero),
        ),
      ],
    );
  }
}