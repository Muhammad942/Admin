import { createClient } from '@supabase/supabase-js';
import OpenAI from 'openai'; // there is a problem with importing files
import { authenticate } from './auth.js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
const deepseek = new OpenAI({
  baseURL: 'https://api.deepseek.com',
  apiKey: process.env.DEEPSEEK_API_KEY,
});

// Retrieves course PDF context using vector similarity search[cite: 1]
export async function getCourseContext(courseName, embeddingVector) {

        const auth = await authenticate(req, res);
        console.log(auth);
        if (!auth) return; // response already sent
        const { db } = auth;
  const { data: chunks, error } = await supabase.rpc('match_document_chunks', {
    query_embedding: embeddingVector,
    match_threshold: 0.6,
    match_count: 4,
    filter_course: courseName
  });

  if (error || !chunks) return '';
  return chunks.map(c => `[Source: ${c.metadata.pdf_name}]: ${c.chunk_text}`).join('\n\n');
}

// Stream LLM response via DeepSeek API[cite: 1]
export async function streamRAGResponse(conversationHistory, userQuery, courseContext, onToken) {
  const systemPrompt = `You are an academic AI tutor. Base your answer primarily on the provided course material PDFs below.
  
Course Material Context:
${courseContext || 'No specific PDF materials found for this prompt. Provide general guidance.'}`;

  const stream = await deepseek.chat.completions.create({
    model: 'deepseek-chat', // DeepSeek V4 Flash / R1[cite: 1]
    messages: [
      { role: 'system', content: systemPrompt },
      ...conversationHistory,
      { role: 'user', content: userQuery }
    ],
    stream: true,
  });

  let fullResponse = '';
  for await (const chunk of stream) {
    const token = chunk.choices[0]?.delta?.content || '';
    if (token) {
      fullResponse += token;
      onToken(token);
    }
  }
  return fullResponse;
}