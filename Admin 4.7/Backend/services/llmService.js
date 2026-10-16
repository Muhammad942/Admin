import OpenAI from 'openai';

const deepseek = new OpenAI({
  baseURL: 'https://api.deepseek.com',
  apiKey: process.env.DEEPSEEK_API_KEY,
});

/**
 * Streams response directly from DeepSeek API 🚀
 * @param {Array} conversationHistory - Past conversation messages
 * @param {String} userQuery - Current user input prompt
 * @param {Array} attachments - Array of attached files [{ filename, content }]
 * @param {Boolean} isDeepThinking - Flag to toggle reasoning model
 * @param {Function} onToken - Callback function for answer tokens
 * @param {Function} onReasoningToken - Callback function for thinking tokens
 */
export async function streamLLMResponse({
  conversationHistory,
  userQuery,
  attachments = [],
  isDeepThinking = false,
  onToken,
  onReasoningToken,
}) {
  console.log(userQuery);
  // Select DeepSeek model based on deep thinking toggle 🧠
  const model = isDeepThinking ? 'deepseek-flash' : 'deepseek-flash';

  // Format file attachments context 📄
  let formattedQuery = userQuery;
  if (attachments && attachments.length > 0) {
    const filesContext = attachments
      .map((file) => `--- FILE ATTACHMENT: ${file.filename} ---\n${file.content}`)
      .join('\n\n');
    formattedQuery = `${filesContext}\n\n--- USER PROMPT ---\n${userQuery}`;
  }

  const systemPrompt = `You are a helpful, accurate, and ethical AI assistant.`;

  const messages = [
    { role: 'system', content: systemPrompt },
    ...conversationHistory,
    { role: 'user', content: formattedQuery },
  ];

  const stream = await deepseek.chat.completions.create({
    model,
    messages,
    stream: true,
  });

  let fullResponse = '';
  let fullReasoning = '';

  for await (const chunk of stream) {
    const delta = chunk.choices[0]?.delta;

    // Stream reasoning/thinking tokens (DeepSeek Reasoner R1) 💡
    if (delta?.reasoning_content) {
      fullReasoning += delta.reasoning_content;
      if (onReasoningToken) onReasoningToken(delta.reasoning_content);
    }

    // Stream regular output response tokens 💬
    if (delta?.content) {
      fullResponse += delta.content;
      if (onToken) onToken(delta.content);
    }
  }

  return { fullResponse, fullReasoning };
}