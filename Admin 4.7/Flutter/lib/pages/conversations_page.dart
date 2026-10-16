import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_page.dart';

// TEMP (anon testing): the id of an existing row in public.profiles.
// Only used when nobody is signed in. Delete this and _userId's fallback
// once authenticated users are back.
const _testUserId = '55';

/// Lists the signed-in student's conversations (newest activity first)
/// and creates new ones. Open this instead of ChatPage directly.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _conversations;

  String get _userId => _supabase.auth.currentUser?.id ?? _testUserId;

  @override
  void initState() {
    super.initState();
    print('ConversationsPage built');
    _conversations = _fetch();
  }

  // Filtered by user_id here, so it behaves the same with or without RLS.
  Future<List<Map<String, dynamic>>> _fetch() async {
    print("Here we gooooooo");
    print(_userId);
    return await _supabase
        .from('conversations')
        .select('id, title, updated_at')
        .eq('user_id', _userId)
        .order('updated_at', ascending: false);
  }

  Future<void> _newChat() async {
    try {
      final row = await _supabase
          .from('conversations')
          .insert({'user_id': _userId})
          .select('id')
          .single();
      if (!mounted) return;
      await _open(row['id'] as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a new chat.')),
      );
    }
  }

  Future<void> _open(String conversationId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(conversationId: conversationId),
      ),
    );
    if (!mounted) return;
    // Refresh so the new title / ordering shows up when coming back
    setState(() {
      _conversations = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('💬 My Chats')),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _conversations,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your chats.'));
          }
          final chats = snapshot.data ?? [];
          if (chats.isEmpty) {
            return const Center(
              child: Text('No chats yet. Tap + to start one.'),
            );
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final chat = chats[index];
              return ListTile(
                title: Text(
                  chat['title'] ?? 'New Academic Chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _open(chat['id'] as String),
              );
            },
          );
        },
      ),
    );
  }
}
