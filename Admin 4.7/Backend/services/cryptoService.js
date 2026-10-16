import crypto from 'node:crypto';
import 'dotenv/config';

// AES-256-GCM: authenticated encryption. GCM's auth tag means a tampered or
// corrupted blob fails to decrypt loudly instead of returning garbage.
//
// DECRYPTION_KEYS must be a 32-byte key, hex-encoded (64 hex chars), kept
// ONLY in this backend's .env — never sent to Flutter, never committed.
// Generate one once with:
//   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

const KEY_HEX = process.env.DECRYPTION_KEYS;
if (!KEY_HEX || Buffer.from(KEY_HEX, 'hex').length !== 32) {
  throw new Error(
    'DECRYPTION_KEYS is missing or not a 32-byte hex string. Generate one with:\n' +
      '  node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"'
  );
}
const KEY = Buffer.from(KEY_HEX, 'hex');

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12; // recommended IV size for GCM

// /**
//  * Encrypts plaintext for storage. Returns one base64 string: iv + authTag + ciphertext.
//  * A fresh random IV is used every call, so encrypting the same password twice
//  * gives different output on purpose.
//  */

export function encrypt(plainText) {
  if (typeof plainText !== 'string' || plainText.length === 0) {
    throw new Error('encrypt() requires a non-empty string');
  }
  console.log("encrypt");
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);

  const ciphertext = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();

  return Buffer.concat([iv, authTag, ciphertext]).toString('base64');
}

// /**
//  * Reverses encrypt(). Throws if the blob was tampered with, truncated,
//  * or encrypted under a different key.
//  */
export function decrypt(blob) {
  if (typeof blob !== 'string' || blob.length === 0) {
    throw new Error('decrypt() requires a non-empty string');
  }

  const raw = Buffer.from(blob, 'base64');
  const iv = raw.subarray(0, IV_LENGTH);
  const authTag = raw.subarray(IV_LENGTH, IV_LENGTH + 16); // GCM tag is 16 bytes
  const ciphertext = raw.subarray(IV_LENGTH + 16);

  const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);
  decipher.setAuthTag(authTag);

  const plainText = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return plainText.toString('utf8');
}