import 'dart:convert';
import 'package:drohnen_fronted/models/saved_recording.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


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
  late List<SavedRecording> _savedRecordings;
  late bool _loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _savedRecordings = [];
    _loading = true;
    _error = null;
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    try {
      final res = await http.get(
        Uri.parse('http://${widget.backendHost}/recordings'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = (data['data'] as List)
            .map((e) => SavedRecording.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _savedRecordings = list;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = data['error'] as String?;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Verbindungsfehler';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
  Future<void> _deleteRecording(int id) async {
    try {
      await http.delete(Uri.parse('http://${widget.backendHost}/recordings/$id'));
      await _loadRecordings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Löschen des Videos'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}