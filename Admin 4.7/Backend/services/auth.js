// services/auth.js
import { createClient } from '@supabase/supabase-js';

const clientOptions = { auth: { persistSession: false, autoRefreshToken: false } };

export const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  clientOptions
);

export function userClient(token) {
  return createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
    ...clientOptions,
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

export const ALLOW_ANON = process.env.ALLOW_ANON === 'true';

// Same logic as before: returns { userId, db } or null after sending the error response.
export async function authenticate(req, res) {
  if (ALLOW_ANON) {
    const userId = req.body?.userId ?? req.query?.userId;
    if (!userId) {
      res.status(400).json({ error: 'Missing userId' });
      return null;
    }
    return { userId, db: supabaseAdmin };
  }

  const authHeader = req.headers.authorization ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) {
    res.status(401).json({ error: 'Missing Authorization: Bearer <token> header' });
    return null;
  }

  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !data?.user) {
    res.status(401).json({ error: 'Invalid or expired token' });
    return null;
  }
  return { userId: data.user.id, db: userClient(token) };
}