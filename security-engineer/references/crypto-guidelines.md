# Cryptography Best Practices

Reference for applying cryptographic primitives correctly in production systems. Covers password hashing, symmetric and asymmetric encryption, JWT signing, TLS configuration, key management, HMAC for API signing, data encryption at rest, secure random generation, and common mistakes to avoid.

**Core Principle:** Never implement your own cryptographic algorithms. Use well-audited libraries and follow their documented best practices.

---

## Table of Contents

1. [Password Hashing (Argon2id)](#password-hashing-argon2id)
2. [Symmetric Encryption (AES-256-GCM)](#symmetric-encryption-aes-256-gcm)
3. [JWT Signing (RS256 vs HS256)](#jwt-signing-rs256-vs-hs256)
4. [TLS Configuration](#tls-configuration)
5. [Key Management](#key-management)
6. [HMAC for API Signing](#hmac-for-api-signing)
7. [Data Encryption at Rest](#data-encryption-at-rest)
8. [Secure Random Generation](#secure-random-generation)
9. [Common Crypto Mistakes to Avoid](#common-crypto-mistakes-to-avoid)

---

## Password Hashing (Argon2id)

Argon2id is the recommended password hashing algorithm. It is memory-hard (resistant to GPU/ASIC attacks) and resistant to side-channel attacks. Argon2 won the Password Hashing Competition in 2015 and is recommended by OWASP and NIST.

### Configuration Parameters

| Parameter     | Recommended Value | Description                                        |
|---------------|-------------------|----------------------------------------------------|
| `type`        | Argon2id          | Hybrid: resists both GPU and side-channel attacks  |
| `memoryCost`  | 65536 (64 MB)     | Memory used per hash (in KiB)                      |
| `timeCost`    | 3                 | Number of iterations                               |
| `parallelism` | 4                 | Number of parallel threads                         |
| `hashLength`  | 32                | Output hash length in bytes                        |
| `saltLength`  | 16                | Random salt length in bytes (auto-generated)       |

**Tuning guidance:** Hash time should be 0.5-1.0 seconds on your target hardware. If it is faster, increase `memoryCost` first, then `timeCost`. Measure on production-equivalent hardware, not development laptops.

### Node.js (argon2 package)

```typescript
import argon2 from 'argon2';

// Production configuration
const ARGON2_CONFIG = {
  type: argon2.argon2id,
  memoryCost: 65536,       // 64 MB
  timeCost: 3,             // 3 iterations
  parallelism: 4,          // 4 threads
  saltLength: 16,          // 16-byte random salt
  hashLength: 32,          // 32-byte output
};

async function hashPassword(password: string): Promise<string> {
  // Enforce maximum length to prevent DoS (Argon2 processes entire input)
  if (password.length > 128) {
    throw new Error('Password exceeds maximum length');
  }

  return argon2.hash(password, ARGON2_CONFIG);
  // Output format: $argon2id$v=19$m=65536,t=3,p=4$<base64-salt>$<base64-hash>
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, password);
  } catch {
    // Invalid hash format, corrupted data, etc.
    return false;
  }
}

// Check if a stored hash needs rehashing (e.g., after config changes)
function needsRehash(hash: string): boolean {
  return argon2.needsRehash(hash, ARGON2_CONFIG);
}

// Usage in login flow with transparent rehashing
async function loginUser(email: string, password: string): Promise<User | null> {
  const user = await db.user.findUnique({ where: { email } });
  if (!user) {
    // Hash a dummy password to prevent timing-based user enumeration
    await argon2.hash('dummy-password', ARGON2_CONFIG);
    return null;
  }

  const valid = await verifyPassword(password, user.passwordHash);
  if (!valid) return null;

  // Transparently rehash if config has changed
  if (needsRehash(user.passwordHash)) {
    const newHash = await hashPassword(password);
    await db.user.update({
      where: { id: user.id },
      data: { passwordHash: newHash },
    });
  }

  return user;
}
```

### Python (argon2-cffi package)

```python
from argon2 import PasswordHasher, Type
from argon2.exceptions import VerifyMismatchError, InvalidHashError

ph = PasswordHasher(
    time_cost=3,
    memory_cost=65536,   # 64 MB
    parallelism=4,
    hash_len=32,
    salt_len=16,
    type=Type.ID,        # Argon2id
)

def hash_password(password: str) -> str:
    if len(password) > 128:
        raise ValueError("Password exceeds maximum length")
    return ph.hash(password)

def verify_password(password: str, stored_hash: str) -> bool:
    try:
        return ph.verify(stored_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False

def needs_rehash(stored_hash: str) -> bool:
    return ph.check_needs_rehash(stored_hash)
```

### Go (alexedwards/argon2id package)

```go
package auth

import (
    "github.com/alexedwards/argon2id"
)

var params = &argon2id.Params{
    Memory:      64 * 1024, // 64 MB
    Iterations:  3,
    Parallelism: 4,
    SaltLength:  16,
    KeyLength:   32,
}

func HashPassword(password string) (string, error) {
    return argon2id.CreateHash(password, params)
}

func VerifyPassword(password, hash string) (bool, error) {
    return argon2id.ComparePasswordAndHash(password, hash)
}
```

### Algorithm Preference Order

1. **Argon2id** -- First choice. Memory-hard, GPU-resistant, side-channel resistant.
2. **bcrypt** -- Second choice. Well-tested, widely available. 72-byte input limit.
3. **scrypt** -- Third choice. Memory-hard but harder to tune correctly.
4. **PBKDF2-SHA256** -- Acceptable where FIPS compliance is required. Use 600,000+ iterations (OWASP 2023).
5. **Never use:** MD5, SHA-1, SHA-256/SHA-512 alone, any unsalted hash.

---

## Symmetric Encryption (AES-256-GCM)

AES-256-GCM provides authenticated encryption with associated data (AEAD). It guarantees both confidentiality and integrity in a single operation. Always use an AEAD mode; never use ECB, plain CBC, or other unauthenticated modes.

### Key Parameters

| Parameter        | Value       | Description                                    |
|------------------|-------------|------------------------------------------------|
| Algorithm        | AES-256-GCM | 256-bit key, Galois/Counter Mode               |
| Key length       | 32 bytes    | 256 bits of entropy                            |
| IV/Nonce length  | 12 bytes    | 96 bits -- recommended for GCM                 |
| Auth tag length  | 16 bytes    | 128-bit authentication tag                     |

**Critical rule:** Never reuse a nonce with the same key. A single nonce reuse in GCM completely breaks both confidentiality and authenticity.

### Node.js Implementation

```typescript
import { randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;        // 96 bits -- recommended for GCM
const TAG_LENGTH = 16;       // 128-bit authentication tag
const KEY_LENGTH = 32;       // 256-bit key

interface EncryptedPayload {
  iv: string;         // hex-encoded initialization vector
  ciphertext: string; // hex-encoded encrypted data
  tag: string;        // hex-encoded authentication tag
  version: number;    // schema version for future migrations
}

function encrypt(plaintext: string, key: Buffer): EncryptedPayload {
  if (key.length !== KEY_LENGTH) {
    throw new Error(`Key must be exactly ${KEY_LENGTH} bytes`);
  }

  const iv = randomBytes(IV_LENGTH); // MUST be random for every encryption
  const cipher = createCipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });

  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);

  return {
    iv: iv.toString('hex'),
    ciphertext: encrypted.toString('hex'),
    tag: cipher.getAuthTag().toString('hex'),
    version: 1,
  };
}

function decrypt(payload: EncryptedPayload, key: Buffer): string {
  const iv = Buffer.from(payload.iv, 'hex');
  const ciphertext = Buffer.from(payload.ciphertext, 'hex');
  const tag = Buffer.from(payload.tag, 'hex');

  const decipher = createDecipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });
  decipher.setAuthTag(tag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(), // Throws if authentication tag does not match
  ]);

  return decrypted.toString('utf8');
}

// Generate a cryptographically secure encryption key
function generateEncryptionKey(): Buffer {
  return randomBytes(KEY_LENGTH);
}
```

### Additional Authenticated Data (AAD)

AAD binds ciphertext to a context (user ID, record ID, table name). Decryption fails if AAD does not match, preventing ciphertext from being swapped between records or contexts.

```typescript
function encryptWithAAD(
  plaintext: string,
  key: Buffer,
  aad: string,  // e.g., "user:123:ssn" or "record:456:credit_card"
): EncryptedPayload & { aad: string } {
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });
  cipher.setAAD(Buffer.from(aad, 'utf8'));

  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);

  return {
    iv: iv.toString('hex'),
    ciphertext: encrypted.toString('hex'),
    tag: cipher.getAuthTag().toString('hex'),
    aad,
    version: 1,
  };
}

function decryptWithAAD(payload: EncryptedPayload & { aad: string }, key: Buffer): string {
  const iv = Buffer.from(payload.iv, 'hex');
  const ciphertext = Buffer.from(payload.ciphertext, 'hex');
  const tag = Buffer.from(payload.tag, 'hex');

  const decipher = createDecipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });
  decipher.setAuthTag(tag);
  decipher.setAAD(Buffer.from(payload.aad, 'utf8'));

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(), // Fails if AAD does not match
  ]);

  return decrypted.toString('utf8');
}
```

### Python Implementation

```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

def encrypt_aes_gcm(
    plaintext: bytes,
    key: bytes,
    aad: bytes | None = None,
) -> tuple[bytes, bytes]:
    """
    Encrypt with AES-256-GCM.
    Returns (nonce, ciphertext_with_tag).
    Key must be 32 bytes.
    """
    if len(key) != 32:
        raise ValueError("Key must be 32 bytes for AES-256")

    nonce = os.urandom(12)  # 96-bit nonce
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext, aad)
    # ciphertext includes the 16-byte auth tag appended automatically

    return nonce, ciphertext

def decrypt_aes_gcm(
    nonce: bytes,
    ciphertext: bytes,
    key: bytes,
    aad: bytes | None = None,
) -> bytes:
    """Decrypt AES-256-GCM. Raises InvalidTag on tampered data."""
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ciphertext, aad)

# Generate key
key = AESGCM.generate_key(bit_length=256)
```

### Go Implementation

```go
package crypto

import (
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "errors"
    "io"
)

func EncryptAES256GCM(plaintext, key, aad []byte) (nonce, ciphertext []byte, err error) {
    if len(key) != 32 {
        return nil, nil, errors.New("key must be 32 bytes")
    }

    block, err := aes.NewCipher(key)
    if err != nil {
        return nil, nil, err
    }

    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, nil, err
    }

    nonce = make([]byte, gcm.NonceSize()) // 12 bytes
    if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
        return nil, nil, err
    }

    ciphertext = gcm.Seal(nil, nonce, plaintext, aad)
    return nonce, ciphertext, nil
}

func DecryptAES256GCM(nonce, ciphertext, key, aad []byte) ([]byte, error) {
    block, err := aes.NewCipher(key)
    if err != nil {
        return nil, err
    }

    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, err
    }

    return gcm.Open(nil, nonce, ciphertext, aad)
}
```

---

## JWT Signing (RS256 vs HS256)

### Algorithm Comparison

| Property              | HS256 (HMAC-SHA256)      | RS256 (RSA-SHA256)        | ES256 (ECDSA P-256)    |
|-----------------------|--------------------------|---------------------------|------------------------|
| **Key type**          | Symmetric (shared secret)| Asymmetric (public/private)| Asymmetric (public/private)|
| **Sign + Verify**     | Same key for both        | Private signs, public verifies | Private signs, public verifies |
| **Key distribution**  | Secret must be shared    | Only public key shared    | Only public key shared  |
| **Performance**       | Fastest                  | Slower signing             | Fast signing, fast verify|
| **Token size**        | Smallest (~36B sig)      | Large (~256B sig)          | Small (~64B sig)        |
| **Best for**          | Single-service apps      | Microservices, third-party | Microservices, mobile   |

### When to Use Which

- **HS256:** Only when the same service signs and verifies tokens. The secret must never leave the signing service.
- **RS256:** When multiple services need to verify tokens but only one service signs them. Public keys can be safely distributed via JWKS endpoints.
- **ES256 (recommended):** Same use case as RS256 but with smaller tokens and faster verification. Preferred for new systems.

### RS256 Implementation

```typescript
import jwt from 'jsonwebtoken';
import fs from 'fs';
import { randomUUID } from 'crypto';

// Load keys (typically from environment, secrets manager, or JWKS)
const PRIVATE_KEY = fs.readFileSync('/etc/secrets/jwt-private.pem', 'utf8');
const PUBLIC_KEY = fs.readFileSync('/etc/secrets/jwt-public.pem', 'utf8');

interface TokenPayload {
  sub: string;          // Subject (user ID)
  roles: string[];
  orgId: string;
}

// Signing (auth service only)
function signAccessToken(payload: TokenPayload): string {
  return jwt.sign(payload, PRIVATE_KEY, {
    algorithm: 'RS256',
    expiresIn: '15m',           // Short-lived access tokens
    issuer: 'https://auth.example.com',
    audience: 'https://api.example.com',
    jwtid: randomUUID(),        // Unique token ID for revocation
    notBefore: 0,               // Valid immediately
  });
}

function signRefreshToken(userId: string): string {
  return jwt.sign(
    { sub: userId, type: 'refresh' },
    PRIVATE_KEY,
    {
      algorithm: 'RS256',
      expiresIn: '7d',          // Longer-lived refresh tokens
      issuer: 'https://auth.example.com',
      audience: 'https://auth.example.com', // Only auth service consumes refresh tokens
      jwtid: randomUUID(),
    }
  );
}

// Verification (any service with the public key)
function verifyAccessToken(token: string): TokenPayload & jwt.JwtPayload {
  return jwt.verify(token, PUBLIC_KEY, {
    algorithms: ['RS256'],           // CRITICAL: explicitly allowlist algorithm
    issuer: 'https://auth.example.com',
    audience: 'https://api.example.com',
    clockTolerance: 30,              // 30s clock skew tolerance
    maxAge: '15m',                   // Reject tokens older than 15 minutes
  }) as TokenPayload & jwt.JwtPayload;
}
```

### HS256 Implementation (Single Service)

```typescript
import jwt from 'jsonwebtoken';

// Secret must be at least 256 bits (32 bytes) of entropy
// NEVER use a short or predictable string
const JWT_SECRET = process.env.JWT_SECRET!; // At least 32 random bytes, base64-encoded

function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, JWT_SECRET, {
    algorithm: 'HS256',
    expiresIn: '15m',
    issuer: 'https://app.example.com',
    audience: 'https://app.example.com',
  });
}

function verifyToken(token: string): TokenPayload & jwt.JwtPayload {
  return jwt.verify(token, JWT_SECRET, {
    algorithms: ['HS256'],       // CRITICAL: restrict to HS256 only
    issuer: 'https://app.example.com',
    audience: 'https://app.example.com',
    clockTolerance: 30,
  }) as TokenPayload & jwt.JwtPayload;
}
```

### ES256 Implementation (Recommended for New Projects)

```typescript
import jwt from 'jsonwebtoken';
import { generateKeyPairSync } from 'crypto';

// Generate ECDSA P-256 key pair (one-time, store securely)
// const { publicKey, privateKey } = generateKeyPairSync('ec', {
//   namedCurve: 'P-256',
//   publicKeyEncoding: { type: 'spki', format: 'pem' },
//   privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
// });

const EC_PRIVATE_KEY = process.env.JWT_EC_PRIVATE_KEY!;
const EC_PUBLIC_KEY = process.env.JWT_EC_PUBLIC_KEY!;

function signAccessToken(payload: TokenPayload): string {
  return jwt.sign(payload, EC_PRIVATE_KEY, {
    algorithm: 'ES256',
    expiresIn: '15m',
    issuer: 'https://auth.example.com',
    audience: 'https://api.example.com',
    jwtid: randomUUID(),
  });
}

function verifyAccessToken(token: string): TokenPayload & jwt.JwtPayload {
  return jwt.verify(token, EC_PUBLIC_KEY, {
    algorithms: ['ES256'],      // Only ES256
    issuer: 'https://auth.example.com',
    audience: 'https://api.example.com',
    clockTolerance: 30,
  }) as TokenPayload & jwt.JwtPayload;
}
```

### JWKS (JSON Web Key Set) for Key Distribution

```typescript
// Expose public keys via a JWKS endpoint
// GET https://auth.example.com/.well-known/jwks.json

import { exportJWK, importSPKI } from 'jose';

async function getJwks() {
  const publicKey = await importSPKI(EC_PUBLIC_KEY, 'ES256');
  const jwk = await exportJWK(publicKey);

  return {
    keys: [
      {
        ...jwk,
        kid: 'key-2025-01',        // Key ID for rotation
        use: 'sig',                  // Signature use
        alg: 'ES256',
      },
    ],
  };
}

app.get('/.well-known/jwks.json', async (req, res) => {
  const jwks = await getJwks();
  res.setHeader('Cache-Control', 'public, max-age=3600'); // Cache for 1 hour
  res.json(jwks);
});
```

### JWT Security Rules

1. **Always specify `algorithms`** in verify(). Without this, the `none` algorithm attack or HMAC/RSA confusion attacks are possible.
2. **Validate `iss`, `aud`, and `exp`** on every verification.
3. **Keep access tokens short-lived** (15 minutes or less). Use refresh tokens for session extension.
4. **Use asymmetric algorithms** (ES256, RS256) in microservice architectures. Only use HS256 in single-service contexts.
5. **Include a `jti` (JWT ID) claim** for token revocation capability.
6. **Never store sensitive data in JWT payloads.** JWTs are signed, not encrypted. Anyone can decode the payload.
7. **Rotate signing keys periodically.** Use `kid` headers and JWKS endpoints to support graceful key rotation.

---

## TLS Configuration

### Nginx Configuration (Production)

```nginx
# /etc/nginx/conf.d/tls.conf

# Protocol versions: TLS 1.2 and 1.3 only
ssl_protocols TLSv1.2 TLSv1.3;

# Cipher suites for TLS 1.2
# TLS 1.3 ciphers are configured automatically by the TLS stack
ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';

# Let TLS 1.3 handle cipher negotiation
ssl_prefer_server_ciphers off;

# ECDH curves (ordered by preference)
ssl_ecdh_curve X25519:P-256:P-384;

# OCSP Stapling: server fetches OCSP response instead of client
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;

# Session configuration
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;  # Disable for perfect forward secrecy

# Certificate files
ssl_certificate /etc/ssl/certs/example.com-fullchain.pem;
ssl_certificate_key /etc/ssl/private/example.com-key.pem;
ssl_trusted_certificate /etc/ssl/certs/ca-chain.pem;

# DH parameters (if using DHE ciphers -- not needed for ECDHE-only)
# ssl_dhparam /etc/ssl/dhparam-4096.pem;

# HSTS header
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}
```

### Node.js HTTPS Server

```typescript
import https from 'node:https';
import fs from 'node:fs';

const server = https.createServer({
  cert: fs.readFileSync('/etc/ssl/certs/server-fullchain.pem'),
  key: fs.readFileSync('/etc/ssl/private/server-key.pem'),
  ca: fs.readFileSync('/etc/ssl/certs/ca-chain.pem'),

  minVersion: 'TLSv1.2',
  maxVersion: 'TLSv1.3',

  ciphers: [
    'TLS_AES_256_GCM_SHA384',           // TLS 1.3
    'TLS_CHACHA20_POLY1305_SHA256',     // TLS 1.3
    'TLS_AES_128_GCM_SHA256',           // TLS 1.3
    'ECDHE-ECDSA-AES256-GCM-SHA384',   // TLS 1.2
    'ECDHE-RSA-AES256-GCM-SHA384',     // TLS 1.2
    'ECDHE-ECDSA-CHACHA20-POLY1305',   // TLS 1.2
    'ECDHE-RSA-CHACHA20-POLY1305',     // TLS 1.2
  ].join(':'),

  ecdhCurve: 'X25519:P-256',
  honorCipherOrder: false,   // Let client choose (for TLS 1.3 compatibility)
}, app);
```

### Mutual TLS (mTLS) for Service-to-Service

```typescript
import https from 'node:https';
import fs from 'node:fs';

// Server: require client certificates
const server = https.createServer({
  cert: fs.readFileSync('/etc/ssl/server.crt'),
  key: fs.readFileSync('/etc/ssl/server.key'),
  ca: fs.readFileSync('/etc/ssl/internal-ca.crt'), // CA that signed client certs

  requestCert: true,           // Request client certificate
  rejectUnauthorized: true,    // Reject connections without valid client cert

  minVersion: 'TLSv1.2',
}, app);

// Client: present client certificate
const agent = new https.Agent({
  cert: fs.readFileSync('/etc/ssl/client.crt'),
  key: fs.readFileSync('/etc/ssl/client.key'),
  ca: fs.readFileSync('/etc/ssl/internal-ca.crt'),
  rejectUnauthorized: true,
});

const response = await fetch('https://internal-service.example.com/api/data', {
  agent,
  method: 'GET',
});
```

### TLS Verification

```bash
# Test TLS configuration with OpenSSL
openssl s_client -connect example.com:443 -tls1_2
openssl s_client -connect example.com:443 -tls1_3

# Show supported ciphers
openssl s_client -connect example.com:443 -cipher 'ALL' 2>&1 | grep -i cipher

# Verify certificate chain
openssl s_client -connect example.com:443 -showcerts

# Test with SSL Labs (comprehensive scan)
# https://www.ssllabs.com/ssltest/analyze.html?d=example.com

# Test with testssl.sh (local scanning tool)
# testssl.sh example.com:443
```

---

## Key Management

### Principles

1. **Separation:** Never store encryption keys alongside the data they protect.
2. **Least privilege:** Only the services that need a key should have access to it.
3. **Rotation:** Rotate keys on a schedule (at least annually) and immediately on suspected compromise.
4. **Audit:** Log all key access and operations.
5. **Destruction:** Securely destroy retired keys after the retention period.

### Key Hierarchy

```
Master Key (KEK) -- stored in KMS (AWS KMS, GCP Cloud KMS, HashiCorp Vault)
    |
    +-- Data Encryption Key (DEK) for user data
    |
    +-- Data Encryption Key (DEK) for audit logs
    |
    +-- Signing Key for JWT tokens
    |
    +-- HMAC Key for API signatures
```

### Key Rotation Pattern

```typescript
interface KeyVersion {
  id: string;           // e.g., "key-2025-03"
  key: Buffer;
  createdAt: Date;
  expiresAt: Date;
  status: 'active' | 'decrypt-only' | 'retired';
}

class KeyManager {
  private keys: Map<string, KeyVersion> = new Map();

  // Get the current active key for new encryptions
  getActiveKey(): KeyVersion {
    for (const kv of this.keys.values()) {
      if (kv.status === 'active') return kv;
    }
    throw new Error('No active encryption key available');
  }

  // Get a specific key version for decryption
  getKeyById(id: string): KeyVersion {
    const kv = this.keys.get(id);
    if (!kv) throw new Error(`Key ${id} not found`);
    if (kv.status === 'retired') throw new Error(`Key ${id} has been retired`);
    return kv;
  }

  // Rotate: create new active key, demote current to decrypt-only
  async rotate(): Promise<KeyVersion> {
    const currentActive = this.getActiveKey();
    currentActive.status = 'decrypt-only';

    const newKey: KeyVersion = {
      id: `key-${new Date().toISOString().slice(0, 7)}`,
      key: randomBytes(32),
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000), // 1 year
      status: 'active',
    };

    this.keys.set(newKey.id, newKey);
    return newKey;
  }
}

// Encrypted payloads MUST include the key ID
interface EncryptedRecord {
  keyId: string;        // Which key version was used
  iv: string;
  ciphertext: string;
  tag: string;
}

function encryptRecord(data: string, keyManager: KeyManager): EncryptedRecord {
  const activeKey = keyManager.getActiveKey();
  const payload = encrypt(data, activeKey.key);

  return {
    keyId: activeKey.id,  // Store key ID alongside ciphertext
    ...payload,
  };
}

function decryptRecord(record: EncryptedRecord, keyManager: KeyManager): string {
  const keyVersion = keyManager.getKeyById(record.keyId);
  return decrypt(record, keyVersion.key);
}
```

### Key Derivation with HKDF

Derive purpose-specific keys from a single master key. This allows using one master key to generate isolated keys for different functions.

```typescript
import { hkdf } from 'node:crypto';
import { promisify } from 'node:util';

const hkdfAsync = promisify(hkdf);

async function deriveKey(
  masterKey: Buffer,
  purpose: string,              // e.g., 'field-encryption', 'api-signing', 'session-tokens'
  salt: Buffer = randomBytes(32),
): Promise<{ key: Buffer; salt: Buffer }> {
  const derived = await hkdfAsync(
    'sha256',       // Hash algorithm
    masterKey,      // Input keying material
    salt,           // Salt (store alongside ciphertext)
    purpose,        // Info/context string -- makes each derived key unique
    32,             // Output key length in bytes
  );

  return { key: Buffer.from(derived), salt };
}

// Usage: derive separate keys for different purposes
async function initializeKeys(masterKey: Buffer) {
  const salt = randomBytes(32); // Use the same salt for deterministic derivation

  const { key: encryptionKey } = await deriveKey(masterKey, 'field-encryption', salt);
  const { key: signingKey } = await deriveKey(masterKey, 'api-signing', salt);
  const { key: sessionKey } = await deriveKey(masterKey, 'session-tokens', salt);

  return { encryptionKey, signingKey, sessionKey, salt };
}
```

### Envelope Encryption (KMS Integration)

Encrypt data with a local Data Encryption Key (DEK), then encrypt the DEK with a Key Encryption Key (KEK) managed by a KMS. This combines the speed of local encryption with the security of KMS-managed keys.

```typescript
// AWS KMS envelope encryption
import { KMSClient, GenerateDataKeyCommand, DecryptCommand } from '@aws-sdk/client-kms';

const kms = new KMSClient({ region: 'us-east-1' });
const KEK_ARN = 'arn:aws:kms:us-east-1:123456789:key/your-key-id';

interface EnvelopeEncryptedPayload {
  encryptedDEK: string;    // DEK encrypted by KMS (base64)
  iv: string;              // Nonce for AES-GCM (hex)
  ciphertext: string;      // Data encrypted by plaintext DEK (hex)
  tag: string;             // GCM auth tag (hex)
}

async function envelopeEncrypt(plaintext: string): Promise<EnvelopeEncryptedPayload> {
  // 1. Ask KMS to generate a DEK (returns both plaintext and encrypted versions)
  const { Plaintext: plaintextDEK, CiphertextBlob: encryptedDEK } = await kms.send(
    new GenerateDataKeyCommand({
      KeyId: KEK_ARN,
      KeySpec: 'AES_256',
    })
  );

  if (!plaintextDEK || !encryptedDEK) {
    throw new Error('KMS GenerateDataKey failed');
  }

  // 2. Encrypt data locally with the plaintext DEK
  const key = Buffer.from(plaintextDEK);
  const payload = encrypt(plaintext, key);

  // 3. Securely wipe the plaintext DEK from memory
  key.fill(0);
  Buffer.from(plaintextDEK).fill(0);

  // 4. Return the encrypted DEK + encrypted data
  return {
    encryptedDEK: Buffer.from(encryptedDEK).toString('base64'),
    iv: payload.iv,
    ciphertext: payload.ciphertext,
    tag: payload.tag,
  };
}

async function envelopeDecrypt(payload: EnvelopeEncryptedPayload): Promise<string> {
  // 1. Ask KMS to decrypt the DEK
  const { Plaintext: plaintextDEK } = await kms.send(
    new DecryptCommand({
      CiphertextBlob: Buffer.from(payload.encryptedDEK, 'base64'),
      KeyId: KEK_ARN,
    })
  );

  if (!plaintextDEK) {
    throw new Error('KMS Decrypt failed');
  }

  // 2. Decrypt data locally with the plaintext DEK
  const key = Buffer.from(plaintextDEK);
  const result = decrypt(
    { iv: payload.iv, ciphertext: payload.ciphertext, tag: payload.tag, version: 1 },
    key
  );

  // 3. Wipe DEK from memory
  key.fill(0);

  return result;
}
```

---

## HMAC for API Signing

HMAC (Hash-based Message Authentication Code) verifies both the integrity and authenticity of a message. Use HMAC-SHA256 for API request signing, webhook verification, and data integrity checks.

### API Request Signing

```typescript
import { createHmac, timingSafeEqual } from 'node:crypto';

// Sign a request (client-side)
function signRequest(
  method: string,
  path: string,
  body: string,
  timestamp: string,
  secret: string,
): string {
  // Construct the canonical string to sign
  const canonicalString = [
    method.toUpperCase(),
    path,
    timestamp,
    body ? createHash('sha256').update(body).digest('hex') : '',
  ].join('\n');

  return createHmac('sha256', secret)
    .update(canonicalString)
    .digest('hex');
}

// Verify a request (server-side)
function verifyRequest(
  method: string,
  path: string,
  body: string,
  timestamp: string,
  signature: string,
  secret: string,
): boolean {
  // 1. Check timestamp freshness (prevent replay attacks)
  const requestTime = parseInt(timestamp, 10);
  const now = Math.floor(Date.now() / 1000);
  const MAX_SKEW = 300; // 5 minutes

  if (Math.abs(now - requestTime) > MAX_SKEW) {
    return false; // Request is too old or too far in the future
  }

  // 2. Compute expected signature
  const expectedSignature = signRequest(method, path, body, timestamp, secret);

  // 3. Constant-time comparison to prevent timing attacks
  const sigBuffer = Buffer.from(signature, 'hex');
  const expectedBuffer = Buffer.from(expectedSignature, 'hex');

  if (sigBuffer.length !== expectedBuffer.length) {
    return false;
  }

  return timingSafeEqual(sigBuffer, expectedBuffer);
}

// Express middleware for HMAC verification
function hmacAuthMiddleware(req: Request, res: Response, next: NextFunction) {
  const signature = req.headers['x-signature'] as string;
  const timestamp = req.headers['x-timestamp'] as string;
  const apiKeyId = req.headers['x-api-key-id'] as string;

  if (!signature || !timestamp || !apiKeyId) {
    return res.status(401).json({ error: 'Missing authentication headers' });
  }

  // Look up the secret for this API key
  const apiKey = getApiKeyById(apiKeyId);
  if (!apiKey) {
    return res.status(401).json({ error: 'Invalid API key' });
  }

  const rawBody = (req as any).rawBody || ''; // Requires raw body middleware

  const valid = verifyRequest(
    req.method,
    req.originalUrl,
    rawBody,
    timestamp,
    signature,
    apiKey.secret,
  );

  if (!valid) {
    return res.status(401).json({ error: 'Invalid signature' });
  }

  req.apiKey = apiKey;
  next();
}
```

### Webhook Signature Verification

```typescript
// Verify webhook signatures (e.g., Stripe, GitHub, Slack)
function verifyWebhookSignature(
  payload: string | Buffer,
  signatureHeader: string,
  secret: string,
): boolean {
  const expectedSignature = createHmac('sha256', secret)
    .update(payload)
    .digest('hex');

  const providedSignature = signatureHeader.replace('sha256=', '');

  const expected = Buffer.from(expectedSignature, 'hex');
  const provided = Buffer.from(providedSignature, 'hex');

  if (expected.length !== provided.length) return false;
  return timingSafeEqual(expected, provided);
}

// Express webhook handler
app.post('/webhooks/stripe', express.raw({ type: 'application/json' }), (req, res) => {
  const signature = req.headers['stripe-signature'] as string;

  if (!verifyWebhookSignature(req.body, signature, process.env.STRIPE_WEBHOOK_SECRET!)) {
    return res.status(400).json({ error: 'Invalid webhook signature' });
  }

  // Signature verified, process the event
  const event = JSON.parse(req.body.toString());
  // ...
});
```

### Python HMAC Implementation

```python
import hmac
import hashlib
import time

def sign_request(
    method: str,
    path: str,
    body: str,
    timestamp: str,
    secret: str,
) -> str:
    canonical = f"{method.upper()}\n{path}\n{timestamp}\n"
    if body:
        body_hash = hashlib.sha256(body.encode()).hexdigest()
        canonical += body_hash

    return hmac.new(
        secret.encode(),
        canonical.encode(),
        hashlib.sha256,
    ).hexdigest()

def verify_request(
    method: str,
    path: str,
    body: str,
    timestamp: str,
    signature: str,
    secret: str,
    max_skew: int = 300,
) -> bool:
    # Check timestamp freshness
    request_time = int(timestamp)
    now = int(time.time())
    if abs(now - request_time) > max_skew:
        return False

    expected = sign_request(method, path, body, timestamp, secret)

    # Constant-time comparison
    return hmac.compare_digest(signature, expected)
```

---

## Data Encryption at Rest

### Field-Level Encryption

Encrypt sensitive fields individually within database records. This allows querying non-sensitive fields while protecting PII, financial data, and secrets.

```typescript
// Prisma middleware for transparent field-level encryption
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// Fields to encrypt per model
const ENCRYPTED_FIELDS: Record<string, string[]> = {
  User: ['ssn', 'dateOfBirth', 'taxId'],
  PaymentMethod: ['cardNumber', 'cardholderName'],
  BankAccount: ['accountNumber', 'routingNumber'],
};

// Encryption middleware
prisma.$use(async (params, next) => {
  const modelFields = ENCRYPTED_FIELDS[params.model || ''];
  if (!modelFields) return next(params);

  // Encrypt on write operations
  if (['create', 'update', 'upsert'].includes(params.action)) {
    const data = params.args.data || params.args.create;
    if (data) {
      for (const field of modelFields) {
        if (data[field] !== undefined && data[field] !== null) {
          data[field] = JSON.stringify(
            encryptWithAAD(
              String(data[field]),
              encryptionKey,
              `${params.model}:${field}`,  // AAD prevents field swapping
            )
          );
        }
      }
    }
  }

  const result = await next(params);

  // Decrypt on read operations
  if (result && ['findUnique', 'findFirst', 'findMany'].includes(params.action)) {
    const records = Array.isArray(result) ? result : [result];
    for (const record of records) {
      for (const field of modelFields) {
        if (record[field] && typeof record[field] === 'string') {
          try {
            const payload = JSON.parse(record[field]);
            record[field] = decryptWithAAD(payload, encryptionKey);
          } catch {
            // Field may not be encrypted (migration in progress)
          }
        }
      }
    }
  }

  return result;
});
```

### Full-Disk / Volume Encryption

For database-level encryption at rest, rely on the infrastructure layer:

```yaml
# AWS RDS: encryption at rest is built-in
# Enable during instance creation, cannot be changed after
# Uses AES-256 with keys managed by AWS KMS

# PostgreSQL: enable TDE (Transparent Data Encryption) via pg_tde extension
# Or rely on volume-level encryption (AWS EBS, GCP PD)

# MongoDB: enable encryption at rest
# mongod --enableEncryption --encryptionKeyFile /etc/mongodb/encryption-key
```

### Encryption for Backups

```bash
# Encrypt database backups with age (modern encryption tool)
pg_dump mydb | age -r age1publickey... > backup-$(date +%Y%m%d).sql.age

# Decrypt
age -d -i private-key.txt backup-20250301.sql.age > backup.sql

# Encrypt with GPG (if age is not available)
pg_dump mydb | gpg --symmetric --cipher-algo AES256 -o backup-$(date +%Y%m%d).sql.gpg

# Verify backup integrity
sha256sum backup-20250301.sql.age > backup-20250301.sha256
```

---

## Secure Random Generation

### Cryptographically Secure Random Values

Always use the operating system's CSPRNG (Cryptographically Secure Pseudo-Random Number Generator) for security-sensitive values. Never use `Math.random()`, `random.random()`, or any non-cryptographic PRNG.

### Node.js

```typescript
import { randomBytes, randomUUID, randomInt } from 'node:crypto';

// Generate random bytes (for keys, tokens, salts)
const key = randomBytes(32);              // 256-bit key
const token = randomBytes(32).toString('base64url');  // URL-safe token
const sessionId = randomBytes(24).toString('hex');    // 48-char hex string

// Generate UUID v4 (uses CSPRNG internally)
const id = randomUUID();  // e.g., "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"

// Generate random integer in range [min, max)
const otp = String(randomInt(0, 1000000)).padStart(6, '0');  // 6-digit OTP
const diceRoll = randomInt(1, 7);  // 1-6

// Generate API key with prefix for identification
function generateApiKey(prefix: string = 'sk'): string {
  const randomPart = randomBytes(24).toString('base64url');
  return `${prefix}_${randomPart}`;  // e.g., "sk_dG9rZW4tYmFzZTY0dXJs..."
}

// Generate a URL-safe random string of specific length
function generateRandomString(length: number): string {
  // Each base64url character encodes 6 bits; we need ceil(length * 6 / 8) bytes
  const bytesNeeded = Math.ceil((length * 6) / 8);
  return randomBytes(bytesNeeded).toString('base64url').slice(0, length);
}
```

### Python

```python
import secrets
import os
import uuid

# Generate random bytes
key = os.urandom(32)                     # 256-bit key
token = secrets.token_urlsafe(32)        # URL-safe base64 token (43 chars)
hex_token = secrets.token_hex(32)        # 64-char hex string

# Generate UUID v4
request_id = str(uuid.uuid4())

# Generate random integer
otp = f"{secrets.randbelow(1000000):06d}"  # 6-digit OTP
dice_roll = secrets.randbelow(6) + 1       # 1-6

# Generate API key
def generate_api_key(prefix: str = "sk") -> str:
    random_part = secrets.token_urlsafe(24)
    return f"{prefix}_{random_part}"

# Choose random element from a sequence
winner = secrets.choice(participants)

# Compare strings in constant time
is_valid = secrets.compare_digest(user_token, stored_token)
```

### Go

```go
package main

import (
    "crypto/rand"
    "encoding/base64"
    "encoding/hex"
    "fmt"
    "math/big"
)

func generateToken(length int) (string, error) {
    bytes := make([]byte, length)
    if _, err := rand.Read(bytes); err != nil {
        return "", err
    }
    return base64.URLEncoding.EncodeToString(bytes), nil
}

func generateOTP(digits int) (string, error) {
    max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(digits)), nil)
    n, err := rand.Int(rand.Reader, max)
    if err != nil {
        return "", err
    }
    return fmt.Sprintf("%0*d", digits, n), nil
}
```

### What to Use Where

| Use Case                  | Recommended Approach                          | Minimum Entropy |
|---------------------------|-----------------------------------------------|-----------------|
| Encryption keys           | `randomBytes(32)`                             | 256 bits        |
| Session tokens            | `randomBytes(32).toString('base64url')`       | 256 bits        |
| API keys                  | `randomBytes(24).toString('base64url')`       | 192 bits        |
| CSRF tokens               | `randomBytes(32).toString('hex')`             | 256 bits        |
| Password reset tokens     | `randomBytes(32).toString('base64url')`       | 256 bits        |
| OTP (6-digit)             | `randomInt(0, 1000000)`                       | ~20 bits        |
| Database IDs              | `randomUUID()` (UUID v4)                      | 122 bits        |
| Nonces for encryption     | `randomBytes(12)` for GCM                     | 96 bits         |
| Salts for hashing         | `randomBytes(16)` or `randomBytes(32)`        | 128-256 bits    |

---

## Common Crypto Mistakes to Avoid

### Mistake 1: Using ECB Mode

ECB (Electronic Codebook) encrypts identical plaintext blocks to identical ciphertext blocks, leaking patterns in the data. This is visible in encrypted images where the original shapes remain distinguishable.

```typescript
// WRONG -- ECB mode leaks plaintext patterns
// createCipheriv('aes-256-ecb', key, null)

// CORRECT -- Use GCM (authenticated encryption)
createCipheriv('aes-256-gcm', key, randomBytes(12))
```

### Mistake 2: Reusing Nonces with GCM

Reusing a nonce with the same key in GCM mode completely destroys both confidentiality and authenticity. An attacker can XOR two ciphertexts to recover plaintexts and forge authentication tags.

```typescript
// WRONG -- static or sequential nonce
// const iv = Buffer.alloc(12, 0);         // Always zero
// const iv = Buffer.from('000000000001');  // Sequential counter (risky with multiple writers)

// CORRECT -- fresh random nonce for every encryption operation
const iv = randomBytes(12);
```

### Mistake 3: Using SHA-256 for Passwords

General-purpose hash functions (SHA-256, SHA-512) are designed to be fast. This makes them unsuitable for password hashing because an attacker can compute billions of hashes per second on GPUs.

```typescript
// WRONG -- SHA-256 allows billions of guesses per second on GPU
// const hash = createHash('sha256').update(password + salt).digest('hex');

// CORRECT -- Argon2id is deliberately slow and memory-hard
const hash = await argon2.hash(password, {
  type: argon2.argon2id,
  memoryCost: 65536,
  timeCost: 3,
  parallelism: 4,
});
```

### Mistake 4: Not Validating JWT Algorithm

If you do not restrict the allowed algorithms, an attacker can:
- Switch to `none` algorithm (no signature verification).
- Switch from RS256 to HS256, using the public key as the HMAC secret (since public keys are often publicly available).

```typescript
// WRONG -- accepts any algorithm, including "none"
// jwt.verify(token, publicKey);

// CORRECT -- explicitly allowlist the expected algorithm
jwt.verify(token, publicKey, { algorithms: ['RS256'] });
```

### Mistake 5: Hardcoding Secrets in Source Code

Secrets committed to version control are exposed to anyone with repository access and persist in git history even after deletion.

```typescript
// WRONG -- secret in source code
// const API_KEY = 'sk-live-abc123def456...';
// const DB_PASSWORD = 'production-p@ssw0rd!';

// CORRECT -- load from environment
const API_KEY = process.env.API_KEY;

// BETTER -- load from a secrets manager
const API_KEY = await secretsManager.getSecret('api-key');

// BEST -- use short-lived credentials (IAM roles, service accounts)
// No static secrets needed at all
```

### Mistake 6: Not Using Constant-Time Comparison

Standard string comparison (`===`, `==`) short-circuits on the first mismatched character. An attacker can measure response times to determine how many characters match, brute-forcing one character at a time.

```typescript
import { timingSafeEqual } from 'node:crypto';

// WRONG -- timing side-channel leaks information
// if (userToken === storedToken) { ... }

// CORRECT -- constant-time comparison
function safeCompare(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);

  if (bufA.length !== bufB.length) {
    // Compare against a dummy to maintain constant time
    timingSafeEqual(bufA, bufA);
    return false;
  }

  return timingSafeEqual(bufA, bufB);
}
```

```python
import hmac

# WRONG
# if user_token == stored_token:

# CORRECT -- constant-time comparison
if hmac.compare_digest(user_token, stored_token):
    # Valid token
    pass
```

### Mistake 7: Insufficient Entropy in Random Values

`Math.random()` in JavaScript and `random.random()` in Python use non-cryptographic PRNGs. Their outputs are predictable if an attacker can observe a few values.

```typescript
// WRONG -- Math.random() is predictable
// const token = Math.random().toString(36).substring(2);

// CORRECT -- use CSPRNG
const token = randomBytes(32).toString('base64url');
```

```python
# WRONG -- random module is not cryptographically secure
# import random
# token = ''.join(random.choices(string.ascii_letters, k=32))

# CORRECT -- secrets module uses CSPRNG
import secrets
token = secrets.token_urlsafe(32)
```

### Mistake 8: Using Encryption When You Need Hashing (and Vice Versa)

- **Encryption** is reversible: you can get the plaintext back. Use for data you need to read again (stored PII, backups, inter-service messages).
- **Hashing** is one-way: you cannot recover the input. Use for data you only need to verify (passwords, integrity checks).

```typescript
// WRONG -- encrypting passwords (reversible = attacker can recover all passwords)
// const encryptedPassword = encrypt(password, key);

// CORRECT -- hash passwords (one-way)
const hashedPassword = await argon2.hash(password);

// WRONG -- hashing data you need to read back
// const hashedCreditCard = sha256(creditCardNumber);
// You cannot recover the card number from a hash

// CORRECT -- encrypt data you need to read back
const encryptedCreditCard = encrypt(creditCardNumber, key);
```

### Mistake 9: Rolling Your Own Crypto

Do not implement your own encryption algorithms, hash functions, or random number generators. Even subtle implementation bugs can completely break security.

```typescript
// WRONG -- custom "encryption" (XOR cipher, Caesar cipher, custom algorithm)
// function myEncrypt(data, key) {
//   return data.split('').map((c, i) => String.fromCharCode(c.charCodeAt(0) ^ key.charCodeAt(i % key.length))).join('');
// }

// CORRECT -- use established libraries
import { createCipheriv, randomBytes } from 'node:crypto';

// WRONG -- custom hash function
// function myHash(data) { let h = 0; for (const c of data) h = ((h << 5) - h + c.charCodeAt(0)) | 0; return h; }

// CORRECT -- use standard hash functions
import { createHash } from 'node:crypto';
const hash = createHash('sha256').update(data).digest('hex');
```

### Mistake 10: Not Encrypting Data in Transit Between Internal Services

Even within a private network, encrypt service-to-service communication. Network boundaries can be breached, and internal traffic can be intercepted.

```typescript
// WRONG -- unencrypted gRPC between internal services
// const client = new ServiceClient('service-b:50051', grpc.credentials.createInsecure());

// CORRECT -- use TLS even internally
const creds = grpc.credentials.createSsl(
  fs.readFileSync('ca-cert.pem'),
  fs.readFileSync('client-key.pem'),
  fs.readFileSync('client-cert.pem'),
);
const client = new ServiceClient('service-b:50051', creds);

// BETTER -- use mTLS for mutual authentication
// See the TLS Configuration section above
```

---

## Quick Reference: Algorithm Selection

| Need                     | Use This                    | Key/Output Size    |
|--------------------------|-----------------------------|--------------------|
| Encrypt data at rest     | AES-256-GCM                 | 256-bit key        |
| Hash passwords           | Argon2id                    | 32-byte output     |
| Verify data integrity    | HMAC-SHA-256                | 256-bit key        |
| Sign JWTs (multi-service)| ES256 (ECDSA P-256)         | P-256 key pair     |
| Sign JWTs (single-service)| HS256 (HMAC-SHA-256)       | 256-bit+ secret    |
| Key agreement            | X25519 (ECDH)               | 256-bit            |
| Random tokens/keys       | CSPRNG (`randomBytes`)      | 256+ bits          |
| Key derivation           | HKDF-SHA-256                | Variable output    |
| Digital signatures       | Ed25519 or ECDSA P-256      | 256-bit key pair   |
| TLS                      | TLS 1.3 (prefer) / TLS 1.2 | N/A                |
| File checksums           | SHA-256 or BLAKE2b          | 256-bit output     |
