import { Router } from 'express';
import { createClient } from '@supabase/supabase-js';
import { encrypt, decrypt } from '../services/cryptoService.js';

const clientOptions = { auth: { persistSession: false, autoRefreshToken: false } };

// Admin (service-role) client: bypasses RLS. Used only to verify tokens, and for
// ALLOW_ANON testing where there is no user token. Never expose this key to Flutter.
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  clientOptions
);

// Per-request client that runs as the signed-in user (anon key + the user's JWT),
// so the RLS policies on public.profiles apply.
function userClient(token) {
  return createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
    ...clientOptions,
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

// Same testing switch as chatSocket.js. Remove ALLOW_ANON from .env for production.
const ALLOW_ANON = process.env.ALLOW_ANON === 'true';

/**
 * Resolves the caller and the Supabase client to use for their queries.
 *  - ALLOW_ANON: userId comes from the body (POST) or query string (GET); uses the admin client.
 *  - Otherwise: verifies the Bearer token and returns an RLS-enforced client for that user.
 * Sends the error response itself and returns null on failure.
 */
async function authenticate(req, res) {
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

const router = Router();

/**
 * POST /profile/college-pass
 * Body (ALLOW_ANON): { userId, collegePass }
 * Body (authenticated): { collegePass }   Header: Authorization: Bearer <token>
 *
 * Encrypts collegePass and updates profiles.college_pass for the caller's existing profile row.
 * The plaintext is never stored.
 */
router.post('/profile/college-pass', async (req, res) => {
  try {
    const auth = await authenticate(req, res);
    if (!auth) return; // response already sent
    const { userId, db } = auth;

    const { collegePass } = req.body ?? {};
    if (!collegePass || typeof collegePass !== 'string') {
      return res.status(400).json({ error: 'collegePass is required' });
    }

    const encrypted = encrypt(collegePass);

    // .select('id') returns the updated rows. Without it, an update blocked by RLS
    // (or matching no profile row) succeeds silently with zero rows changed.
    const { data, error } = await db
      .from('profiles')
      .update({ college_pass: encrypted })
      .eq('id', userId)
      .select('id');

    if (error) throw error;
    if (!data?.length) {
      return res.status(404).json({ error: 'Profile not found or update not permitted' });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('POST /profile/college-pass failed:', err);
    res.status(500).json({ error: 'Could not save college password' });
  }
});

/**
 * GET /profile/college-pass
 * ALLOW_ANON: GET /profile/college-pass?userId=...
 * authenticated: Header: Authorization: Bearer <token>
 *
 * Fetches profiles.college_pass and decrypts it.
 * NOTE: this returns the plaintext to the caller. Prefer using decrypt_with_blob
 * server-side only and removing this route.
 */
/*
router.get('/profile/college-pass', async (req, res) => {
  try {
    const auth = await authenticate(req, res);
    if (!auth) return; // response already sent
    const { userId, db } = auth;

    const { data, error } = await db
      .from('profiles')
      .select('college_pass')
      .eq('id', userId)
      .maybeSingle();

    if (error) throw error;
    if (!data?.college_pass) {
      return res.status(404).json({ error: 'No college_pass stored for this profile' });
    }

    res.json({ collegePass: decrypt(data.college_pass) });
  } catch (err) {
    console.error('GET /profile/college-pass failed:', err);
    res.status(500).json({ error: 'Could not retrieve college password' });
  }
});
*/
// Server-side helper for other modules (e.g. before logging into the college portal).
function decrypt_with_blob(blob) {
  return decrypt(blob);
}

export { decrypt_with_blob };
export default router;