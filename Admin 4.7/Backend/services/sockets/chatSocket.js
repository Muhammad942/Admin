import { randomUUID } from 'node:crypto';
import { Server } from 'socket.io';
import { createClient } from '@supabase/supabase-js';
import { streamLLMResponse } from '../llmService.js';

// This client must use the SERVICE ROLE key, which bypasses Row Level Security.
const serviceKey = process.env.SUPABASE_SERVICE_KEY ?? '';
const supabase = createClient(process.env.SUPABASE_URL, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Sanity check: an anon/publishable key here makes every UPDATE fail silently
// (no error, 0 rows changed) because there is no UPDATE policy for anon.
const keyRole = (() => {
  try {
    return JSON.parse(Buffer.from(serviceKey.split('.')[1], 'base64url').toString()).role;
  } catch {
    return null;
  }
})();
if (keyRole === 'anon' || serviceKey.startsWith('sb_publishable_')) {
  console.warn(
    '⚠️  SUPABASE_SERVICE_KEY is an anon/publishable key, not the service_role key. ' +
      'Updates (chat titles, etc.) will be silently blocked by RLS.'
  );
}

const DEFAULT_TITLE = 'New Academic Chat';
const HISTORY_LIMIT = 10;

// TEMP: set ALLOW_ANON=true in .env to skip token verification and the
// ownership check while testing with anon access. Remove the env var (or set
// it to anything else) and the auth checks are back on. Never ship it enabled.
const ALLOW_ANON = process.env.ALLOW_ANON;
if (ALLOW_ANON) {
  console.warn('⚠️  ALLOW_ANON=true: chat socket auth is DISABLED (testing only)');
}

export function setupChatSocket(server) {
  const io = new Server(server, { cors: { origin: '*' } });

  // 🔐 Authenticate every socket with the student's Supabase access token
  io.use(async (socket, next) => {
    if (ALLOW_ANON) return next();

    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('unauthorized'));

    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data?.user) return next(new Error('unauthorized'));

    socket.data.userId = data.user.id;
    next();
  });

  io.on('connection', (socket) => {
    socket.on('send_message', async (payload) => {
      const {
        conversationId,
        content = '',
        attachments = [],
        isDeepThinking = false,
      } = payload ?? {};

      try {
        if (!conversationId || (!content.trim() && attachments.length === 0)) {
          socket.emit('message_error', { message: 'Empty message.' });
          return;
        }

        // 0. Ownership check: the conversation must belong to this student
        let convoQuery = supabase
          .from('conversations')
          .select('id, title')
          .eq('id', conversationId);
        if (!ALLOW_ANON) convoQuery = convoQuery.eq('user_id', socket.data.userId);
        const { data: convo } = await convoQuery.maybeSingle();

        if (!convo) {
          socket.emit('message_error', { message: 'Conversation not found.' });
          return;
        }

        // 1. Fetch history BEFORE saving the new message.
        //    Newest N rows, then reversed to oldest-first for the LLM.
        const { data: rows } = await supabase
          .from('messages')
          .select('sender_type, content')
          .eq('conversation_id', conversationId)
          .order('created_at', { ascending: false })
          .limit(HISTORY_LIMIT);

        const formattedHistory = (rows ?? [])
          .reverse()
          .filter((m) => m.content)
          .map((m) => ({
            role: m.sender_type === 'user' ? 'user' : 'assistant',
            content: m.content,
          }));

        // 2. Save the user message 💾
        const { error: userErr } = await supabase.from('messages').insert({
          conversation_id: conversationId,
          sender_type: 'user',
          content,
          metadata: attachments.length
            ? { attachments: attachments.map((a) => a.filename) }
            : null,
        });
        if (userErr) throw userErr;

        // 2b. Name the conversation after its first message
        if (convo.title === DEFAULT_TITLE) {
          const title =
            content.trim().slice(0, 50) || attachments[0]?.filename || DEFAULT_TITLE;
          console.log(content.trim().slice(0, 50));
          console.log(attachments[0]);
          const { data: renamed, error: titleErr } = await supabase
            .from('conversations')
            .update({ title })
            .eq('id', conversationId)
            .select('id');

          if (titleErr) {
            console.error('title update failed:', titleErr);
          } else if (!renamed?.length) {
            console.error(
              'title update matched 0 rows: blocked by RLS (backend key is probably not service_role)'
            );
          }
        }

        // 3. Stream the LLM response 🚀
        //    The bot message id is generated here so stream events can carry it,
        //    and the row is inserted ONCE, complete, after streaming finishes.
        const botMsgId = randomUUID();

        const { fullResponse, fullReasoning } = await streamLLMResponse({
          conversationHistory: formattedHistory,
          userQuery: content,
          attachments,
          isDeepThinking,
          onReasoningToken: (token) => {
            socket.emit('stream_thinking', { message_id: botMsgId, token });
          },
          onToken: (token) => {
            socket.emit('stream_token', { message_id: botMsgId, token });
          },
        });

        if (!fullResponse.trim()) throw new Error('LLM returned an empty response');

        // 4. Persist the bot message once 🎯
        const { error: botErr } = await supabase.from('messages').insert({
          id: botMsgId,
          conversation_id: conversationId,
          sender_type: 'bot',
          content: fullResponse,
          metadata: fullReasoning ? { reasoning: fullReasoning } : null,
        });
        if (botErr) throw botErr;

        socket.emit('message_complete', { message_id: botMsgId });
      } catch (err) {
        console.error('send_message failed:', err);
        socket.emit('message_error', { message: 'Something went wrong. Please try again.' });
      }
    });
  });
}