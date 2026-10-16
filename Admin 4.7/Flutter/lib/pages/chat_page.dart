import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;

  const ChatPage({super.key, required this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  late io.Socket _socket;
  final _supabase = Supabase.instance.client;

  // State Variables ⚡
  String _streamingMessage = '';
  String _streamingThinking = '';
  bool _isDeepThinking = false;
  bool _isLoadingHistory = true;
  final List<Map<String, String>> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initWebSocket();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Load this conversation's saved messages (RLS limits it to the signed-in student) 📜
  Future<void> _loadHistory() async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('sender_type, content, metadata')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      final loaded = <Map<String, String>>[];
      for (final row in rows) {
        final isUser = row['sender_type'] == 'user';
        final content = (row['content'] ?? '') as String;
        if (!isUser && content.isEmpty) continue; // unfinished bot placeholder

        final meta = row['metadata'] as Map<String, dynamic>?;
        loaded.add({
          'sender': isUser ? 'user' : 'bot',
          'content': content,
          'thinking': (meta?['reasoning'] as String?) ?? '',
          'attachments': ((meta?['attachments'] as List?) ?? []).join(', '),
        });
      }

      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, loaded);
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
      _showError('Could not load previous messages.');
    }
  }

  void _initWebSocket() {
    // The backend verifies this token and only lets the student
    // write to their own conversations 🔐
    final token = _supabase.auth.currentSession?.accessToken;

    _socket = io.io(dotenv.get('NGROK_URL'), <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'token': token},
    });

    _socket.on(
      'connect_error',
      (_) => _showError('Could not connect to the chat server.'),
    );

    // Backend failed (LLM error, conversation not found, ...) ⚠️
    _socket.on('message_error', (data) {
      if (!mounted) return;
      setState(() {
        _streamingMessage = '';
        _streamingThinking = '';
      });
      final msg =
          (data is Map ? data['message'] : null) ?? 'Something went wrong.';
      _showError(msg.toString());
    });

    // ignore: avoid_print
    _socket.onConnect((_) => print('⚡ WebSocket Connected'));
    // Listen for thinking tokens 🧠
    _socket.on('stream_thinking', (data) {
      final String token = data['token'] ?? '';
      setState(() {
        _streamingThinking += token;
      });
    });

    // Listen for response tokens 💬
    _socket.on('stream_token', (data) {
      final String token = data['token'] ?? '';
      setState(() {
        _streamingMessage += token;
      });
    });

    // Completion listener 🎯
    _socket.on('message_complete', (_) {
      setState(() {
        _messages.add({
          'sender': 'bot',
          'content': _streamingMessage,
          'thinking': _streamingThinking,
        });
        _streamingMessage = '';
        _streamingThinking = '';
      });
    });
  }

  // File Picker Functionality 📎
  Future<void> _pickAttachment() async {
    final List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'md',
        'json',
        'csv',
        'py',
        'js',
        'dart',
        'pdf',
      ],
    );

    // ignore: unnecessary_null_comparison
    if (result != null && result.single.path != null) {
      final file = result.single;
      final fileContent = await File(file.path!).readAsString();

      setState(() {
        _attachedFiles.add({'filename': file.name, 'content': fileContent});
      });
    }
  }

  // end here !!!
  void _sendMessage() {
    final text = _messageController.text.trim();
    print("///////////////");
    print(text);
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    setState(() {
      _messages.add({
        'sender': 'user',
        'content': text,
        'attachments': _attachedFiles.map((e) => e['filename']!).join(', '),
      });
    });

    // Emit payload over Socket 📤
    _socket.emit('send_message', {
      'conversationId': widget.conversationId,
      'content': text,
      'attachments': List.from(_attachedFiles),
      'isDeepThinking': _isDeepThinking,
    });

    _messageController.clear();
    setState(() {
      _attachedFiles.clear();
    });
  }

  @override
  void dispose() {
    _socket.disconnect();
    _socket.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 المعلم'),
        actions: [
          // Deep Thinking Toggle Switch 🧠
          Row(
            children: [
              const Text('🧠 Deep Think', style: TextStyle(fontSize: 12)),
              Switch(
                value: _isDeepThinking,
                activeThumbColor: Colors.purpleAccent,
                onChanged: (val) {
                  setState(() {
                    _isDeepThinking = val;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        _messages.length +
                        (_streamingMessage.isNotEmpty ||
                                _streamingThinking.isNotEmpty
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _buildBubble(
                          _streamingMessage,
                          thinking: _streamingThinking,
                          isUser: false,
                          isStreaming: true,
                        );
                      }
                      final msg = _messages[index];
                      return _buildBubble(
                        msg['content']!,
                        thinking: msg['thinking'],
                        isUser: msg['sender'] == 'user',
                      );
                    },
                  ),
          ),

          // Display Selected Attachment Chips 📎
          if (_attachedFiles.isNotEmpty)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachedFiles.length,
                itemBuilder: (context, index) {
                  return Chip(
                    label: Text(_attachedFiles[index]['filename']!),
                    onDeleted: () {
                      setState(() {
                        _attachedFiles.removeAt(index);
                      });
                    },
                  );
                },
              ),
            ),

          // Bottom Input Bar 📝
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.blueAccent),
                  onPressed: _pickAttachment,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.green),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(
    String text, {
    String? thinking,
    required bool isUser,
    bool isStreaming = false,
  }) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Render Thinking Process Card if present 🧠
          if (thinking != null && thinking.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade900.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.purpleAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '💭 Thinking Process:\n$thinking',
                style: const TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Answer Bubble 💬
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? Colors.green.shade800 : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text + (isStreaming ? ' ▌' : ''),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
