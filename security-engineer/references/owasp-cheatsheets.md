# OWASP Security Cheatsheets

Comprehensive security reference based on OWASP guidelines. Covers injection prevention, XSS, CSRF, authentication, authorization, file uploads, SSRF, API security, and HTTP security headers.

---

## Table of Contents

1. [SQL Injection Prevention](#sql-injection-prevention)
2. [XSS Prevention](#xss-prevention)
3. [CSRF Protection](#csrf-protection)
4. [Authentication Cheatsheet](#authentication-cheatsheet)
5. [Authorization Patterns](#authorization-patterns)
6. [File Upload Security](#file-upload-security)
7. [SSRF Prevention](#ssrf-prevention)
8. [API Security Checklist](#api-security-checklist)
9. [HTTP Security Headers](#http-security-headers)

---

## SQL Injection Prevention

SQL injection occurs when untrusted data is sent to an interpreter as part of a command or query. The attacker's hostile data tricks the interpreter into executing unintended commands or accessing unauthorized data.

### Defense 1: Parameterized Queries (Prepared Statements)

The primary defense. Always use parameterized queries. Never concatenate user input into SQL strings.

#### PostgreSQL

```javascript
// Node.js (pg library) -- CORRECT
const result = await pool.query(
  'SELECT id, name, email FROM users WHERE email = $1 AND org_id = $2',
  [userEmail, orgId]
);

// VULNERABLE -- NEVER DO THIS
const result = await pool.query(
  `SELECT id, name, email FROM users WHERE email = '${userEmail}'`
);
```

```python
# Python (psycopg2) -- CORRECT
cursor.execute(
    "SELECT id, name, email FROM users WHERE email = %s AND org_id = %s",
    (user_email, org_id)
)

# Python (asyncpg) -- CORRECT
row = await conn.fetchrow(
    "SELECT id, name, email FROM users WHERE email = $1 AND org_id = $2",
    user_email, org_id
)
```

```java
// Java (JDBC) -- CORRECT
PreparedStatement stmt = connection.prepareStatement(
    "SELECT id, name, email FROM users WHERE email = ? AND org_id = ?"
);
stmt.setString(1, userEmail);
stmt.setInt(2, orgId);
ResultSet rs = stmt.executeQuery();
```

```go
// Go (database/sql) -- CORRECT
row := db.QueryRow(
    "SELECT id, name, email FROM users WHERE email = $1 AND org_id = $2",
    userEmail, orgId,
)
```

```csharp
// C# (ADO.NET) -- CORRECT
using var cmd = new NpgsqlCommand(
    "SELECT id, name, email FROM users WHERE email = @email AND org_id = @orgId",
    connection
);
cmd.Parameters.AddWithValue("email", userEmail);
cmd.Parameters.AddWithValue("orgId", orgId);
```

#### MySQL

```javascript
// Node.js (mysql2) -- CORRECT
const [rows] = await connection.execute(
  'SELECT id, name, email FROM users WHERE email = ? AND org_id = ?',
  [userEmail, orgId]
);
```

```python
# Python (mysql-connector) -- CORRECT
cursor.execute(
    "SELECT id, name, email FROM users WHERE email = %s AND org_id = %s",
    (user_email, org_id)
)
```

```php
// PHP (PDO) -- CORRECT
$stmt = $pdo->prepare('SELECT id, name, email FROM users WHERE email = :email AND org_id = :orgId');
$stmt->execute(['email' => $userEmail, 'orgId' => $orgId]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
```

#### SQLite

```python
# Python (sqlite3) -- CORRECT
cursor.execute(
    "SELECT id, name FROM items WHERE category = ? AND price < ?",
    (category, max_price)
)
```

```javascript
// Node.js (better-sqlite3) -- CORRECT
const stmt = db.prepare('SELECT id, name FROM items WHERE category = ? AND price < ?');
const rows = stmt.all(category, maxPrice);
```

#### MongoDB (NoSQL Injection)

```javascript
// Node.js (MongoDB driver) -- VULNERABLE to NoSQL injection
const user = await db.collection('users').findOne({
  email: req.body.email,      // If req.body.email is { "$ne": "" }, returns first user
  password: req.body.password, // If { "$gt": "" }, bypasses password check
});

// CORRECT: Validate and sanitize input types
const email = String(req.body.email);  // Force to string
const user = await db.collection('users').findOne({
  email: email,
});

// CORRECT: Use schema validation (Mongoose)
const userSchema = new Schema({
  email: { type: String, required: true },
  password: { type: String, required: true },
});
// Mongoose automatically casts to schema types, preventing object injection
```

### Defense 2: ORM Safe Patterns

ORMs generally use parameterized queries, but raw queries and certain patterns bypass this protection.

```typescript
// Prisma -- SAFE (always parameterized)
const users = await prisma.user.findMany({
  where: {
    email: userEmail,
    orgId: orgId,
  },
});

// Prisma raw query -- SAFE with tagged template
const users = await prisma.$queryRaw`
  SELECT id, name FROM users WHERE email = ${userEmail}
`;

// Prisma raw query -- VULNERABLE (using $queryRawUnsafe)
// const users = await prisma.$queryRawUnsafe(
//   `SELECT id, name FROM users WHERE email = '${userEmail}'`
// );
```

```python
# SQLAlchemy -- SAFE
from sqlalchemy import select
stmt = select(User).where(User.email == user_email, User.org_id == org_id)
result = session.execute(stmt)

# SQLAlchemy raw -- SAFE with text() and bound params
from sqlalchemy import text
result = session.execute(
    text("SELECT id, name FROM users WHERE email = :email"),
    {"email": user_email}
)

# Django ORM -- SAFE
users = User.objects.filter(email=user_email, org_id=org_id)

# Django raw -- SAFE with params
User.objects.raw("SELECT * FROM users WHERE email = %s", [user_email])

# Django .extra() -- VULNERABLE if misused (deprecated for this reason)
# User.objects.extra(where=[f"email = '{user_email}'"])  # NEVER
```

### Defense 3: Input Validation (Secondary Defense)

Input validation supplements parameterized queries. It does not replace them.

```typescript
// Validate and constrain input before it reaches the query
import { z } from 'zod';

const SearchSchema = z.object({
  email: z.string().email().max(254),
  orgId: z.string().uuid(),
  sortBy: z.enum(['name', 'email', 'created_at']), // Allowlist for column names
  sortOrder: z.enum(['asc', 'desc']),
  limit: z.number().int().min(1).max(100).default(20),
  offset: z.number().int().min(0).default(0),
});

function buildQuery(input: z.infer<typeof SearchSchema>) {
  // sortBy and sortOrder are validated against allowlists,
  // so they are safe to interpolate (they cannot be parameterized)
  return {
    text: `SELECT id, name, email FROM users
           WHERE email LIKE $1 AND org_id = $2
           ORDER BY ${input.sortBy} ${input.sortOrder}
           LIMIT $3 OFFSET $4`,
    values: [`%${input.email}%`, input.orgId, input.limit, input.offset],
  };
}
```

### Defense 4: Escaping (Last Resort)

Use only when parameterized queries are impossible (e.g., dynamic table/column names). Always prefer allowlists over escaping.

```typescript
// Dynamic column name -- use allowlist, NOT escaping
const ALLOWED_COLUMNS = new Set(['name', 'email', 'created_at', 'updated_at']);

function orderBy(column: string, direction: 'asc' | 'desc'): string {
  if (!ALLOWED_COLUMNS.has(column)) {
    throw new Error(`Invalid sort column: ${column}`);
  }
  // Column is from a known-safe set, so interpolation is acceptable
  return `ORDER BY ${column} ${direction}`;
}
```

---

## XSS Prevention

Cross-Site Scripting (XSS) occurs when untrusted data is included in web output without proper validation or encoding. The key principle is **context-aware output encoding**: encode data differently depending on where it appears in the HTML document.

### Context 1: HTML Body

```html
<!-- VULNERABLE -->
<div>Welcome, ${userName}</div>

<!-- SAFE: HTML entity encoding -->
<div>Welcome, ${htmlEncode(userName)}</div>
```

```typescript
// HTML entity encoding function
function htmlEncode(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

// React/JSX: Auto-escapes by default -- SAFE
function Welcome({ name }: { name: string }) {
  return <div>Welcome, {name}</div>; // React escapes `name` automatically
}

// React: DANGEROUS -- bypasses auto-escaping
// <div dangerouslySetInnerHTML={{ __html: userContent }} />
// Only use with sanitized content (see DOMPurify below)
```

### Context 2: HTML Attributes

```html
<!-- VULNERABLE -->
<input value="${userInput}">
<div class="${userClass}">

<!-- SAFE: Attribute encoding + always quote -->
<input value="${attributeEncode(userInput)}">
<div class="${attributeEncode(userClass)}">

<!-- NEVER put untrusted data in these attributes -->
<!-- <a href="${userUrl}">     Use URL validation instead -->
<!-- <div onclick="${code}">   Never put user data in event handlers -->
<!-- <div style="${styles}">   Never put user data in style attributes -->
```

```typescript
function attributeEncode(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
```

### Context 3: JavaScript Context

```html
<!-- VULNERABLE -->
<script>var data = "${userData}";</script>
<script>var config = ${JSON.stringify(userConfig)};</script>

<!-- SAFE: Use JSON serialization with escaping -->
<script>
  var data = JSON.parse('${jsonStringEscape(JSON.stringify(userData))}');
</script>

<!-- BETTER: Use a data attribute and read it from JS -->
<div id="config" data-config="${htmlEncode(JSON.stringify(config))}"></div>
<script>
  var config = JSON.parse(document.getElementById('config').dataset.config);
</script>
```

```typescript
// Escape for embedding in <script> tags
function jsonStringEscape(str: string): string {
  return str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/"/g, '\\"')
    .replace(/</g, '\\u003C')  // Prevent </script> injection
    .replace(/>/g, '\\u003E')
    .replace(/\u2028/g, '\\u2028') // Line separator
    .replace(/\u2029/g, '\\u2029'); // Paragraph separator
}
```

### Context 4: URL Context

```typescript
// VULNERABLE: User controls the entire URL
// <a href="${userUrl}">Click</a>
// Allows javascript: URLs, data: URLs, etc.

// SAFE: Validate URL scheme
function sanitizeUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (!['http:', 'https:', 'mailto:'].includes(parsed.protocol)) {
      return '#'; // Block javascript:, data:, vbscript:, etc.
    }
    return url;
  } catch {
    return '#'; // Invalid URL
  }
}

// SAFE: URL-encode user data within a URL path or query parameter
function buildSearchUrl(query: string): string {
  return `/search?q=${encodeURIComponent(query)}`;
}
```

### Context 5: CSS Context

```typescript
// NEVER inject user data directly into CSS
// <style> .user-theme { color: ${userColor}; } </style>

// SAFE: Validate against allowlist
const SAFE_COLORS = new Set([
  'red', 'blue', 'green', 'black', 'white',
  '#000000', '#ffffff', '#ff0000', '#00ff00', '#0000ff',
]);

function sanitizeCssColor(color: string): string {
  if (SAFE_COLORS.has(color.toLowerCase())) {
    return color;
  }
  // Validate hex color format
  if (/^#[0-9a-fA-F]{3,6}$/.test(color)) {
    return color;
  }
  return 'inherit'; // Safe default
}
```

### HTML Sanitization (Rich Content)

When you must accept HTML from users (rich text editors, markdown rendering), use a dedicated sanitizer library.

```typescript
// DOMPurify -- browser and Node.js
import DOMPurify from 'dompurify';

// Basic sanitization (strips all dangerous elements/attributes)
const clean = DOMPurify.sanitize(dirtyHtml);

// Configured sanitization for rich text
const clean = DOMPurify.sanitize(dirtyHtml, {
  ALLOWED_TAGS: [
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'p', 'br', 'hr',
    'ul', 'ol', 'li',
    'strong', 'em', 'u', 's', 'code', 'pre',
    'blockquote',
    'a', 'img',
    'table', 'thead', 'tbody', 'tr', 'th', 'td',
  ],
  ALLOWED_ATTR: [
    'href', 'src', 'alt', 'title', 'class',
    'target', 'rel',
    'width', 'height',
  ],
  ALLOW_DATA_ATTR: false,
  ADD_ATTR: ['target'],     // Add target="_blank" to links
  FORBID_TAGS: ['style', 'script', 'iframe', 'form', 'input'],
  FORBID_ATTR: ['onerror', 'onclick', 'onload', 'style'],
});

// Force all links to open in new tab with security attributes
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    node.setAttribute('target', '_blank');
    node.setAttribute('rel', 'noopener noreferrer');
  }
  // Remove remote images if needed
  if (node.tagName === 'IMG') {
    const src = node.getAttribute('src') || '';
    if (!src.startsWith('https://cdn.yourapp.com/')) {
      node.remove();
    }
  }
});
```

```python
# Python: bleach library
import bleach

ALLOWED_TAGS = [
    'h1', 'h2', 'h3', 'p', 'br',
    'ul', 'ol', 'li',
    'strong', 'em', 'code', 'pre',
    'a', 'img', 'blockquote',
]

ALLOWED_ATTRIBUTES = {
    'a': ['href', 'title', 'rel'],
    'img': ['src', 'alt', 'width', 'height'],
}

ALLOWED_PROTOCOLS = ['http', 'https', 'mailto']

clean_html = bleach.clean(
    dirty_html,
    tags=ALLOWED_TAGS,
    attributes=ALLOWED_ATTRIBUTES,
    protocols=ALLOWED_PROTOCOLS,
    strip=True,  # Strip disallowed tags rather than escaping them
)

# Link target attribute handling
clean_html = bleach.linkify(
    clean_html,
    callbacks=[lambda attrs, new: {**attrs, (None, 'rel'): 'noopener noreferrer'}],
)
```

### Content Security Policy (CSP) -- Defense in Depth

CSP is a browser-enforced policy that restricts what resources can be loaded. It mitigates XSS even if encoding is missed.

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-{random}';
  style-src 'self' 'unsafe-inline';
  img-src 'self' https://cdn.example.com data:;
  font-src 'self' https://fonts.gstatic.com;
  connect-src 'self' https://api.example.com;
  frame-src 'none';
  object-src 'none';
  base-uri 'self';
  form-action 'self';
  frame-ancestors 'none';
  upgrade-insecure-requests;
```

See the [HTTP Security Headers](#http-security-headers) section for detailed CSP configuration.

---

## CSRF Protection

Cross-Site Request Forgery forces an authenticated user to submit a request to a web application against which they are currently authenticated. The browser automatically includes cookies, so the server cannot distinguish a legitimate request from a forged one.

### Defense 1: Synchronizer Token Pattern

Generate a unique, unpredictable token per session (or per request) and require it on every state-changing request.

```typescript
// Express.js CSRF middleware
import crypto from 'crypto';

// Generate CSRF token
function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

// Middleware to set CSRF token
app.use((req, res, next) => {
  if (!req.session.csrfToken) {
    req.session.csrfToken = generateCsrfToken();
  }
  // Make token available to templates
  res.locals.csrfToken = req.session.csrfToken;
  next();
});

// Middleware to verify CSRF token on state-changing requests
app.use((req, res, next) => {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    return next(); // Safe methods do not need CSRF protection
  }

  const token = req.body._csrf || req.headers['x-csrf-token'];

  if (!token || token !== req.session.csrfToken) {
    return res.status(403).json({ error: 'Invalid CSRF token' });
  }

  next();
});
```

```html
<!-- Include token in forms -->
<form method="POST" action="/api/transfer">
  <input type="hidden" name="_csrf" value="{{csrfToken}}">
  <input type="text" name="amount" />
  <button type="submit">Transfer</button>
</form>
```

```typescript
// Include token in AJAX/fetch requests
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');

async function apiPost(url: string, data: object) {
  return fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken || '',
    },
    credentials: 'same-origin', // Include cookies
    body: JSON.stringify(data),
  });
}
```

### Defense 2: Double Submit Cookie Pattern

For stateless applications where server-side session storage is not available.

```typescript
// Set CSRF token in both a cookie and expect it in a header
import crypto from 'crypto';

app.use((req, res, next) => {
  if (!req.cookies['csrf-token']) {
    const token = crypto.randomBytes(32).toString('hex');
    res.cookie('csrf-token', token, {
      httpOnly: false,     // JavaScript must read this cookie
      secure: true,
      sameSite: 'strict',
      path: '/',
      maxAge: 3600000,     // 1 hour
    });
  }
  next();
});

// Verify: cookie value must match header value
app.use((req, res, next) => {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    return next();
  }

  const cookieToken = req.cookies['csrf-token'];
  const headerToken = req.headers['x-csrf-token'];

  if (!cookieToken || !headerToken || cookieToken !== headerToken) {
    return res.status(403).json({ error: 'CSRF validation failed' });
  }

  next();
});

// Client-side: read cookie and send as header
function getCsrfToken(): string {
  const match = document.cookie.match(/csrf-token=([^;]+)/);
  return match ? match[1] : '';
}

fetch('/api/action', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': getCsrfToken(),
  },
  credentials: 'same-origin',
  body: JSON.stringify(data),
});
```

### Defense 3: SameSite Cookie Attribute

The SameSite cookie attribute provides browser-level CSRF protection by controlling when cookies are sent with cross-site requests.

```typescript
// Session cookie with SameSite protection
app.use(session({
  name: 'sessionId',
  secret: process.env.SESSION_SECRET,
  cookie: {
    httpOnly: true,
    secure: true,           // HTTPS only
    sameSite: 'lax',        // Blocks cross-site POST, allows top-level GET
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    domain: '.example.com',
    path: '/',
  },
  resave: false,
  saveUninitialized: false,
}));
```

| SameSite Value | Cross-Site GET | Cross-Site POST | Same-Site | Use Case |
|---------------|----------------|-----------------|-----------|----------|
| `Strict`      | Blocked        | Blocked         | Sent      | Banking, admin panels |
| `Lax`         | Sent (top-level nav) | Blocked   | Sent      | General web apps (recommended default) |
| `None`        | Sent           | Sent            | Sent      | Cross-site APIs (requires `Secure`) |

**Recommendation:** Use `SameSite=Lax` as a baseline defense, combined with token-based CSRF protection for defense in depth.

### Defense 4: Custom Request Headers

For API-only endpoints (no form submissions), require a custom header. Browsers enforce that cross-origin requests with custom headers trigger a CORS preflight, which blocks CSRF.

```typescript
// Server: Require a custom header on all state-changing API requests
app.use('/api', (req, res, next) => {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    return next();
  }

  // This header cannot be set cross-origin without CORS approval
  if (req.headers['x-requested-with'] !== 'XMLHttpRequest') {
    return res.status(403).json({ error: 'Missing required header' });
  }

  next();
});

// Client: Always include the custom header
fetch('/api/orders', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
  },
  body: JSON.stringify(orderData),
});
```

---

## Authentication Cheatsheet

### Password Storage

Never store passwords in plaintext or with reversible encryption. Use a purpose-built password hashing function with per-password salts.

```typescript
// Node.js: argon2 (RECOMMENDED)
import argon2 from 'argon2';

async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, {
    type: argon2.argon2id,   // Hybrid: resistant to side-channel + GPU attacks
    memoryCost: 65536,       // 64 MB
    timeCost: 3,             // 3 iterations
    parallelism: 4,          // 4 threads
    saltLength: 16,          // 16-byte random salt (auto-generated)
  });
  // Returns: $argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, password);
  } catch {
    return false; // Invalid hash format or other error
  }
}
```

```python
# Python: argon2-cffi (RECOMMENDED)
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

ph = PasswordHasher(
    time_cost=3,
    memory_cost=65536,  # 64 MB
    parallelism=4,
    hash_len=32,
    salt_len=16,
)

def hash_password(password: str) -> str:
    return ph.hash(password)

def verify_password(password: str, hash: str) -> bool:
    try:
        return ph.verify(hash, password)
    except VerifyMismatchError:
        return False
```

```typescript
// Fallback: bcrypt (if argon2 is not available)
import bcrypt from 'bcrypt';

const SALT_ROUNDS = 12; // Minimum 10, recommended 12+

async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}
```

**Hashing Algorithm Recommendation Order:**
1. Argon2id (best: memory-hard, resists GPU/ASIC attacks)
2. bcrypt (good: widely supported, proven)
3. scrypt (good: memory-hard)
4. PBKDF2-SHA256 with 600,000+ iterations (acceptable: FIPS compliant)
5. Never use: MD5, SHA-1, SHA-256 alone, unsalted hashes

### Password Policy

```typescript
import { z } from 'zod';

const PasswordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(128, 'Password must be at most 128 characters') // Prevent DoS via hashing
  .refine(
    (password) => {
      // NIST SP 800-63B: Check against breached passwords
      // In production, use the HaveIBeenPwned k-Anonymity API
      const commonPasswords = new Set([
        'password', '12345678', 'qwerty123',
      ]);
      return !commonPasswords.has(password.toLowerCase());
    },
    { message: 'This password is too common. Choose a different one.' }
  );

// Check against HaveIBeenPwned (k-Anonymity model -- safe for production)
async function isPasswordBreached(password: string): Promise<boolean> {
  const hash = crypto.createHash('sha1').update(password).digest('hex').toUpperCase();
  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);

  const response = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`);
  const text = await response.text();

  return text.split('\n').some((line) => {
    const [hashSuffix] = line.split(':');
    return hashSuffix.trim() === suffix;
  });
}
```

### Session Management

```typescript
// Express session configuration
import session from 'express-session';
import RedisStore from 'connect-redis';
import { createClient } from 'redis';

const redisClient = createClient({ url: process.env.REDIS_URL });
await redisClient.connect();

app.use(session({
  store: new RedisStore({ client: redisClient }),
  name: '__Host-session',    // __Host- prefix: HTTPS only, no domain, path=/
  secret: process.env.SESSION_SECRET,   // At least 32 bytes of entropy
  resave: false,
  saveUninitialized: false,
  rolling: true,              // Reset expiry on each request
  cookie: {
    httpOnly: true,           // Not accessible via JavaScript
    secure: true,             // HTTPS only
    sameSite: 'lax',
    maxAge: 24 * 60 * 60 * 1000,  // 24 hours
    path: '/',
  },
}));

// Session regeneration after login (prevents session fixation)
app.post('/auth/login', async (req, res) => {
  const user = await authenticateUser(req.body.email, req.body.password);
  if (!user) {
    // Constant-time response to prevent user enumeration
    await fakeDelay(200);
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // Regenerate session ID to prevent fixation attacks
  req.session.regenerate((err) => {
    if (err) return res.status(500).json({ error: 'Session error' });

    req.session.userId = user.id;
    req.session.role = user.role;
    req.session.loginAt = Date.now();

    req.session.save((err) => {
      if (err) return res.status(500).json({ error: 'Session error' });
      res.json({ success: true });
    });
  });
});

// Session invalidation on logout
app.post('/auth/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) return res.status(500).json({ error: 'Logout failed' });
    res.clearCookie('__Host-session');
    res.json({ success: true });
  });
});
```

### Multi-Factor Authentication (MFA)

```typescript
// TOTP (Time-based One-Time Password) implementation
import { authenticator } from 'otplib';
import QRCode from 'qrcode';

// Setup: Generate secret and QR code
async function setupMfa(userId: string, userEmail: string) {
  const secret = authenticator.generateSecret();

  // Store secret (encrypted) associated with user -- do NOT activate yet
  await db.user.update({
    where: { id: userId },
    data: {
      mfaSecret: encrypt(secret),   // Encrypt at rest
      mfaEnabled: false,            // Not active until verified
    },
  });

  const otpauthUrl = authenticator.keyuri(userEmail, 'YourApp', secret);
  const qrCodeDataUrl = await QRCode.toDataURL(otpauthUrl);

  return {
    secret,         // Show to user for manual entry
    qrCode: qrCodeDataUrl,
  };
}

// Verify and activate MFA
async function activateMfa(userId: string, token: string): Promise<boolean> {
  const user = await db.user.findUnique({ where: { id: userId } });
  const secret = decrypt(user.mfaSecret);

  const isValid = authenticator.verify({ token, secret });

  if (isValid) {
    // Generate backup codes
    const backupCodes = Array.from({ length: 10 }, () =>
      crypto.randomBytes(4).toString('hex')
    );

    await db.user.update({
      where: { id: userId },
      data: {
        mfaEnabled: true,
        mfaBackupCodes: await Promise.all(
          backupCodes.map((code) => argon2.hash(code))
        ),
      },
    });

    return true; // Return backup codes to user (one time only)
  }

  return false;
}

// Verify TOTP during login
async function verifyMfa(userId: string, token: string): Promise<boolean> {
  const user = await db.user.findUnique({ where: { id: userId } });
  const secret = decrypt(user.mfaSecret);

  // Check TOTP
  const isValid = authenticator.verify({
    token,
    secret,
    window: 1,   // Allow 1 step before/after (30s window)
  });

  if (isValid) return true;

  // Check backup codes
  for (let i = 0; i < user.mfaBackupCodes.length; i++) {
    if (await argon2.verify(user.mfaBackupCodes[i], token)) {
      // Invalidate used backup code
      const codes = [...user.mfaBackupCodes];
      codes.splice(i, 1);
      await db.user.update({
        where: { id: userId },
        data: { mfaBackupCodes: codes },
      });
      return true;
    }
  }

  return false;
}
```

### Brute Force Protection

```typescript
// Rate limiting for authentication endpoints
import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';

// IP-based rate limit
const loginRateLimit = rateLimit({
  store: new RedisStore({ sendCommand: (...args: string[]) => redisClient.sendCommand(args) }),
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 10,                     // 10 attempts per window
  message: { error: 'Too many login attempts. Please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.ip,
  skipSuccessfulRequests: true,
});

// Account-based rate limit (prevents distributed brute force)
const accountRateLimit = rateLimit({
  store: new RedisStore({ sendCommand: (...args: string[]) => redisClient.sendCommand(args) }),
  windowMs: 60 * 60 * 1000,  // 1 hour
  max: 20,                     // 20 attempts per account per hour
  keyGenerator: (req) => `account:${req.body.email?.toLowerCase()}`,
  skipSuccessfulRequests: true,
});

app.post('/auth/login', loginRateLimit, accountRateLimit, loginHandler);

// Progressive delays (account lockout)
async function checkAccountLockout(email: string): Promise<void> {
  const key = `login:failures:${email.toLowerCase()}`;
  const failures = parseInt(await redis.get(key) || '0');

  if (failures >= 10) {
    const lockoutKey = `login:locked:${email.toLowerCase()}`;
    const locked = await redis.get(lockoutKey);
    if (locked) {
      const ttl = await redis.ttl(lockoutKey);
      throw new Error(`Account locked. Try again in ${Math.ceil(ttl / 60)} minutes.`);
    }
    // Lock for 30 minutes after 10 failures
    await redis.setex(lockoutKey, 1800, '1');
    throw new Error('Account locked for 30 minutes due to too many failed attempts.');
  }
}

async function recordFailedLogin(email: string): Promise<void> {
  const key = `login:failures:${email.toLowerCase()}`;
  await redis.incr(key);
  await redis.expire(key, 3600); // Reset after 1 hour of no failures
}

async function clearFailedLogins(email: string): Promise<void> {
  await redis.del(`login:failures:${email.toLowerCase()}`);
  await redis.del(`login:locked:${email.toLowerCase()}`);
}
```

---

## Authorization Patterns

### RBAC (Role-Based Access Control)

Users are assigned roles. Roles grant permissions. Check permissions, not roles, in application code.

```typescript
// Permission definitions
const PERMISSIONS = {
  'project:read': 'View projects',
  'project:create': 'Create projects',
  'project:update': 'Edit projects',
  'project:delete': 'Delete projects',
  'user:read': 'View users',
  'user:invite': 'Invite users',
  'user:remove': 'Remove users',
  'billing:read': 'View billing',
  'billing:manage': 'Manage billing',
  'settings:manage': 'Manage org settings',
} as const;

type Permission = keyof typeof PERMISSIONS;

// Role definitions
const ROLES: Record<string, Permission[]> = {
  viewer: ['project:read', 'user:read'],
  member: ['project:read', 'project:create', 'project:update', 'user:read'],
  admin: [
    'project:read', 'project:create', 'project:update', 'project:delete',
    'user:read', 'user:invite', 'user:remove',
    'settings:manage',
  ],
  owner: Object.keys(PERMISSIONS) as Permission[],
};

// Check permission, not role
function hasPermission(userRole: string, permission: Permission): boolean {
  const rolePermissions = ROLES[userRole];
  if (!rolePermissions) return false;
  return rolePermissions.includes(permission);
}

// Middleware
function requirePermission(...permissions: Permission[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const user = req.session.user;
    if (!user) return res.status(401).json({ error: 'Not authenticated' });

    const hasAll = permissions.every((p) => hasPermission(user.role, p));
    if (!hasAll) {
      return res.status(403).json({
        error: 'Insufficient permissions',
        required: permissions,
      });
    }

    next();
  };
}

// Usage
app.delete('/api/projects/:id',
  requirePermission('project:delete'),
  deleteProjectHandler
);
```

### ABAC (Attribute-Based Access Control)

Decisions based on attributes of the subject, resource, action, and environment. More flexible than RBAC for complex policies.

```typescript
interface AccessContext {
  subject: {
    id: string;
    role: string;
    department: string;
    clearanceLevel: number;
  };
  resource: {
    type: string;
    ownerId: string;
    classification: string;
    department: string;
  };
  action: string;
  environment: {
    ipAddress: string;
    time: Date;
    isMfaAuthenticated: boolean;
  };
}

interface PolicyRule {
  name: string;
  effect: 'allow' | 'deny';
  condition: (ctx: AccessContext) => boolean;
}

const policies: PolicyRule[] = [
  {
    name: 'owner-full-access',
    effect: 'allow',
    condition: (ctx) =>
      ctx.resource.ownerId === ctx.subject.id,
  },
  {
    name: 'same-department-read',
    effect: 'allow',
    condition: (ctx) =>
      ctx.action === 'read' &&
      ctx.resource.department === ctx.subject.department,
  },
  {
    name: 'confidential-requires-clearance',
    effect: 'deny',
    condition: (ctx) =>
      ctx.resource.classification === 'confidential' &&
      ctx.subject.clearanceLevel < 3,
  },
  {
    name: 'sensitive-actions-require-mfa',
    effect: 'deny',
    condition: (ctx) =>
      ['delete', 'update'].includes(ctx.action) &&
      !ctx.environment.isMfaAuthenticated,
  },
  {
    name: 'business-hours-only-for-external',
    effect: 'deny',
    condition: (ctx) => {
      const hour = ctx.environment.time.getUTCHours();
      const isBusinessHours = hour >= 8 && hour < 18;
      const isExternal = ctx.subject.department === 'external';
      return isExternal && !isBusinessHours;
    },
  },
];

function evaluateAccess(ctx: AccessContext): { allowed: boolean; reason: string } {
  // Deny rules take precedence
  for (const rule of policies.filter((r) => r.effect === 'deny')) {
    if (rule.condition(ctx)) {
      return { allowed: false, reason: `Denied by policy: ${rule.name}` };
    }
  }

  // Check if any allow rule matches
  for (const rule of policies.filter((r) => r.effect === 'allow')) {
    if (rule.condition(ctx)) {
      return { allowed: true, reason: `Allowed by policy: ${rule.name}` };
    }
  }

  // Default deny
  return { allowed: false, reason: 'No matching allow policy' };
}
```

### ReBAC (Relationship-Based Access Control)

Authorization based on relationships between entities. Inspired by Google Zanzibar. Useful for document sharing, social networks, and organizational hierarchies.

```typescript
// Relationship tuples: (object, relation, subject)
// "document:doc-1#viewer@user:alice" means Alice is a viewer of doc-1

interface RelationTuple {
  objectType: string;
  objectId: string;
  relation: string;
  subjectType: string;
  subjectId: string;
  subjectRelation?: string; // For indirect relations (e.g., group#member)
}

// Type definitions with relation inheritance
const typeDefinitions = {
  document: {
    relations: {
      owner: {},      // Direct relation
      editor: {
        union: ['owner'],  // Owners are also editors
      },
      viewer: {
        union: ['editor'], // Editors are also viewers
      },
      parent: {},     // Parent folder
    },
  },
  folder: {
    relations: {
      owner: {},
      editor: {
        union: ['owner'],
      },
      viewer: {
        union: ['editor'],
      },
    },
  },
};

// Relationship store (in production, use SpiceDB, OpenFGA, or Ory Keto)
class RelationshipStore {
  private tuples: RelationTuple[] = [];

  addRelation(tuple: RelationTuple): void {
    this.tuples.push(tuple);
  }

  async check(
    objectType: string,
    objectId: string,
    relation: string,
    subjectType: string,
    subjectId: string
  ): Promise<boolean> {
    // Direct check
    const direct = this.tuples.some(
      (t) =>
        t.objectType === objectType &&
        t.objectId === objectId &&
        t.relation === relation &&
        t.subjectType === subjectType &&
        t.subjectId === subjectId
    );
    if (direct) return true;

    // Check inherited relations (e.g., owner implies editor implies viewer)
    const typeDef = typeDefinitions[objectType as keyof typeof typeDefinitions];
    if (typeDef) {
      const relationDef = typeDef.relations[relation as keyof typeof typeDef.relations] as any;
      if (relationDef?.union) {
        for (const parentRelation of relationDef.union) {
          const inherited = await this.check(
            objectType, objectId, parentRelation, subjectType, subjectId
          );
          if (inherited) return true;
        }
      }
    }

    // Check indirect relations via groups
    const groupMemberships = this.tuples.filter(
      (t) =>
        t.objectType === objectType &&
        t.objectId === objectId &&
        t.relation === relation &&
        t.subjectRelation === 'member'
    );

    for (const membership of groupMemberships) {
      const isMember = await this.check(
        membership.subjectType,
        membership.subjectId,
        'member',
        subjectType,
        subjectId
      );
      if (isMember) return true;
    }

    return false;
  }
}

// Usage
const store = new RelationshipStore();

// Alice owns doc-1
store.addRelation({
  objectType: 'document', objectId: 'doc-1',
  relation: 'owner',
  subjectType: 'user', subjectId: 'alice',
});

// Engineering team can view doc-1
store.addRelation({
  objectType: 'document', objectId: 'doc-1',
  relation: 'viewer',
  subjectType: 'team', subjectId: 'engineering',
  subjectRelation: 'member',
});

// Bob is a member of engineering team
store.addRelation({
  objectType: 'team', objectId: 'engineering',
  relation: 'member',
  subjectType: 'user', subjectId: 'bob',
});

// Checks:
await store.check('document', 'doc-1', 'viewer', 'user', 'alice'); // true (owner -> editor -> viewer)
await store.check('document', 'doc-1', 'viewer', 'user', 'bob');   // true (via engineering team)
await store.check('document', 'doc-1', 'editor', 'user', 'bob');   // false (only viewer via team)
```

---

## File Upload Security

### Comprehensive File Upload Validation

```typescript
import crypto from 'crypto';
import path from 'path';
import fs from 'fs/promises';
import { fileTypeFromBuffer } from 'file-type';

interface UploadConfig {
  maxFileSize: number;          // bytes
  allowedMimeTypes: Set<string>;
  allowedExtensions: Set<string>;
  uploadDir: string;
}

const config: UploadConfig = {
  maxFileSize: 10 * 1024 * 1024,  // 10 MB
  allowedMimeTypes: new Set([
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'application/pdf',
    'text/plain', 'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ]),
  allowedExtensions: new Set([
    '.jpg', '.jpeg', '.png', '.gif', '.webp',
    '.pdf', '.txt', '.csv', '.xlsx',
  ]),
  uploadDir: '/var/app/uploads',  // Outside web root
};

async function validateAndStoreUpload(
  fileBuffer: Buffer,
  originalName: string,
  declaredMimeType: string
): Promise<{ storagePath: string; publicUrl: string }> {
  // 1. Check file size
  if (fileBuffer.length > config.maxFileSize) {
    throw new Error(`File exceeds maximum size of ${config.maxFileSize / 1024 / 1024}MB`);
  }

  if (fileBuffer.length === 0) {
    throw new Error('Empty file');
  }

  // 2. Validate file extension
  const ext = path.extname(originalName).toLowerCase();
  if (!config.allowedExtensions.has(ext)) {
    throw new Error(`File extension ${ext} is not allowed`);
  }

  // 3. Detect actual MIME type from file content (magic bytes)
  const detectedType = await fileTypeFromBuffer(fileBuffer);
  const actualMime = detectedType?.mime || 'application/octet-stream';

  if (!config.allowedMimeTypes.has(actualMime)) {
    throw new Error(`File type ${actualMime} is not allowed`);
  }

  // 4. Verify declared MIME matches actual MIME
  if (declaredMimeType !== actualMime) {
    console.warn(
      `MIME mismatch: declared=${declaredMimeType}, actual=${actualMime}, file=${originalName}`
    );
  }

  // 5. Check for dangerous content in text files
  if (actualMime.startsWith('text/') || actualMime === 'application/pdf') {
    const content = fileBuffer.toString('utf-8', 0, Math.min(fileBuffer.length, 4096));
    const dangerousPatterns = [
      /<script/i,
      /javascript:/i,
      /on\w+\s*=/i,         // onclick=, onerror=, etc.
      /data:text\/html/i,
    ];
    for (const pattern of dangerousPatterns) {
      if (pattern.test(content)) {
        throw new Error('File contains potentially dangerous content');
      }
    }
  }

  // 6. Generate safe filename (never use original name for storage)
  const safeFilename = `${crypto.randomUUID()}${ext}`;
  const storagePath = path.join(config.uploadDir, safeFilename);

  // 7. Write file with restricted permissions
  await fs.writeFile(storagePath, fileBuffer, { mode: 0o640 });

  // 8. Return safe public URL (no directory traversal possible)
  return {
    storagePath,
    publicUrl: `/files/${safeFilename}`,
  };
}

// Serve uploaded files safely
app.get('/files/:filename', (req, res) => {
  const filename = path.basename(req.params.filename); // Prevent directory traversal
  const filePath = path.join(config.uploadDir, filename);

  // Verify file exists within upload directory
  if (!filePath.startsWith(config.uploadDir)) {
    return res.status(400).json({ error: 'Invalid file path' });
  }

  res.setHeader('Content-Disposition', 'attachment'); // Force download, do not render
  res.setHeader('X-Content-Type-Options', 'nosniff'); // Prevent MIME sniffing
  res.setHeader('Content-Security-Policy', "default-src 'none'"); // No execution
  res.sendFile(filePath);
});
```

### Image-Specific Security

```typescript
import sharp from 'sharp';

async function processUploadedImage(buffer: Buffer): Promise<Buffer> {
  // Re-encode the image to strip all metadata (EXIF, GPS, comments)
  // This also neutralizes any embedded payloads in image metadata
  const processed = await sharp(buffer)
    .rotate()              // Auto-rotate based on EXIF, then strip EXIF
    .resize(2048, 2048, {  // Limit maximum dimensions
      fit: 'inside',
      withoutEnlargement: true,
    })
    .jpeg({ quality: 85 }) // Re-encode (strips all metadata)
    .toBuffer();

  return processed;
}
```

---

## SSRF Prevention

Server-Side Request Forgery (SSRF) occurs when an attacker can make the server send HTTP requests to arbitrary destinations, potentially accessing internal services, metadata endpoints, or private networks.

```typescript
import { URL } from 'url';
import dns from 'dns/promises';
import net from 'net';

// Blocked IP ranges (RFC 1918, link-local, loopback, cloud metadata)
const BLOCKED_IP_RANGES = [
  { start: '0.0.0.0', end: '0.255.255.255' },         // "This" network
  { start: '10.0.0.0', end: '10.255.255.255' },        // Private Class A
  { start: '100.64.0.0', end: '100.127.255.255' },     // Carrier-grade NAT
  { start: '127.0.0.0', end: '127.255.255.255' },      // Loopback
  { start: '169.254.0.0', end: '169.254.255.255' },    // Link-local / AWS metadata
  { start: '172.16.0.0', end: '172.31.255.255' },      // Private Class B
  { start: '192.0.0.0', end: '192.0.0.255' },          // IETF Protocol Assignments
  { start: '192.168.0.0', end: '192.168.255.255' },    // Private Class C
  { start: '198.18.0.0', end: '198.19.255.255' },      // Benchmark testing
];

function ipToLong(ip: string): number {
  return ip.split('.').reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0) >>> 0;
}

function isBlockedIp(ip: string): boolean {
  if (net.isIPv6(ip)) {
    return ip === '::1' || ip.startsWith('fe80:') || ip.startsWith('fc00:') || ip.startsWith('fd');
  }

  const ipLong = ipToLong(ip);
  return BLOCKED_IP_RANGES.some(
    (range) => ipLong >= ipToLong(range.start) && ipLong <= ipToLong(range.end)
  );
}

async function validateUrl(urlString: string): Promise<URL> {
  let url: URL;

  // 1. Parse URL
  try {
    url = new URL(urlString);
  } catch {
    throw new Error('Invalid URL');
  }

  // 2. Only allow HTTP(S)
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error(`Protocol ${url.protocol} is not allowed`);
  }

  // 3. Block credentials in URL
  if (url.username || url.password) {
    throw new Error('URLs with credentials are not allowed');
  }

  // 4. Block non-standard ports (optional, depending on use case)
  const port = url.port ? parseInt(url.port) : (url.protocol === 'https:' ? 443 : 80);
  if (![80, 443].includes(port)) {
    throw new Error(`Port ${port} is not allowed`);
  }

  // 5. Resolve DNS and check IP
  const hostname = url.hostname;

  if (net.isIP(hostname)) {
    if (isBlockedIp(hostname)) {
      throw new Error('Access to internal network addresses is not allowed');
    }
  } else {
    try {
      const addresses = await dns.resolve4(hostname);
      for (const ip of addresses) {
        if (isBlockedIp(ip)) {
          throw new Error(`Hostname ${hostname} resolves to blocked IP address`);
        }
      }
    } catch (err: any) {
      if (err.code === 'ENOTFOUND') {
        throw new Error(`Hostname ${hostname} could not be resolved`);
      }
      throw err;
    }
  }

  return url;
}

// Safe fetch wrapper
async function safeFetch(urlString: string, options?: RequestInit): Promise<Response> {
  const url = await validateUrl(urlString);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000); // 10s timeout

  try {
    const response = await fetch(url.toString(), {
      ...options,
      signal: controller.signal,
      redirect: 'manual',  // Do not follow redirects automatically
    });

    // If redirect, validate the redirect target too
    if ([301, 302, 307, 308].includes(response.status)) {
      const location = response.headers.get('location');
      if (location) {
        const redirectUrl = new URL(location, url);
        await validateUrl(redirectUrl.toString());
      }
    }

    return response;
  } finally {
    clearTimeout(timeout);
  }
}
```

### Cloud Metadata Endpoint Protection

```typescript
// AWS IMDSv2 protection (if running on AWS)
// Block requests to 169.254.169.254 at the network level
// AND require IMDSv2 (token-based) instead of IMDSv1

// In EC2 instance metadata options:
// aws ec2 modify-instance-metadata-options \
//   --instance-id i-1234567890 \
//   --http-tokens required \           # Require IMDSv2
//   --http-endpoint enabled \
//   --http-put-response-hop-limit 1    # Prevent SSRF via containers

const CLOUD_METADATA_IPS = [
  '169.254.169.254',     // AWS, GCP, Azure
  '169.254.170.2',       // AWS ECS task metadata
  'fd00:ec2::254',       // AWS IPv6 metadata
  '100.100.100.200',     // Alibaba Cloud
];

function isCloudMetadataIp(ip: string): boolean {
  return CLOUD_METADATA_IPS.includes(ip);
}
```

---

## API Security Checklist

### Authentication and Authorization

```typescript
// 1. Use strong authentication (JWT with short expiry + refresh tokens)
// See the Authentication Cheatsheet section for details

// 2. Validate JWT properly
import jwt from 'jsonwebtoken';

function verifyToken(token: string): JwtPayload {
  try {
    const payload = jwt.verify(token, process.env.JWT_PUBLIC_KEY!, {
      algorithms: ['RS256'],           // Explicitly set allowed algorithm
      issuer: 'https://auth.example.com',
      audience: 'https://api.example.com',
      clockTolerance: 30,             // 30 seconds clock skew tolerance
      maxAge: '15m',                  // Reject tokens older than 15 minutes
    }) as JwtPayload;

    return payload;
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      throw new AuthError('Token expired', 401);
    }
    if (err instanceof jwt.JsonWebTokenError) {
      throw new AuthError('Invalid token', 401);
    }
    throw new AuthError('Authentication failed', 401);
  }
}

// 3. Authorization on every endpoint (default deny)
app.use('/api', authenticateMiddleware);
app.use('/api/admin', requireRole('admin'));
```

### Input Validation

```typescript
import { z } from 'zod';

// Validate ALL input: body, params, query, headers
const CreateOrderSchema = z.object({
  body: z.object({
    items: z.array(z.object({
      productId: z.string().uuid(),
      quantity: z.number().int().min(1).max(100),
    })).min(1).max(50),
    shippingAddress: z.object({
      street: z.string().min(1).max(200),
      city: z.string().min(1).max(100),
      state: z.string().length(2),
      zip: z.string().regex(/^\d{5}(-\d{4})?$/),
    }),
    couponCode: z.string().max(20).optional(),
  }),
  params: z.object({
    storeId: z.string().uuid(),
  }),
  query: z.object({
    dryRun: z.enum(['true', 'false']).optional(),
  }),
});

// Validation middleware
function validate(schema: z.ZodType) {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse({
      body: req.body,
      params: req.params,
      query: req.query,
    });

    if (!result.success) {
      return res.status(400).json({
        error: 'Validation failed',
        details: result.error.issues.map((issue) => ({
          path: issue.path.join('.'),
          message: issue.message,
        })),
      });
    }

    req.body = result.data.body;
    req.params = result.data.params;
    next();
  };
}

app.post('/api/stores/:storeId/orders', validate(CreateOrderSchema), createOrderHandler);
```

### Rate Limiting

```typescript
import rateLimit from 'express-rate-limit';

// Tiered rate limiting
const globalRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests', retryAfter: 900 },
});

const apiRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  keyGenerator: (req) => req.user?.id || req.ip,
});

const sensitiveRateLimit = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.user?.id || req.ip,
});

app.use(globalRateLimit);
app.use('/api', apiRateLimit);
app.use('/api/auth', sensitiveRateLimit);
app.use('/api/admin', sensitiveRateLimit);
```

### Response Security

```typescript
// Never expose internal errors to clients
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  // Log the full error internally
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    userId: req.user?.id,
    requestId: req.headers['x-request-id'],
  });

  // Return generic error to client
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: err.userMessage,
      code: err.code,
      requestId: req.headers['x-request-id'],
    });
  }

  // Never expose stack traces or internal details
  res.status(500).json({
    error: 'An unexpected error occurred',
    requestId: req.headers['x-request-id'],
  });
});

// Remove server identification headers
app.disable('x-powered-by');
```

### API Security Checklist Summary

| Category            | Check                                                    |
|---------------------|----------------------------------------------------------|
| **Authentication**  | JWT with short expiry (15 min), refresh token rotation   |
| **Authorization**   | Check permissions on every endpoint, default deny        |
| **Input**           | Validate type, length, format, range for all inputs      |
| **Rate Limiting**   | Global, per-user, per-endpoint tiers                     |
| **CORS**            | Explicit origin allowlist, no wildcard with credentials  |
| **Logging**         | Log auth events, errors, anomalies; never log secrets    |
| **Errors**          | Generic error messages to clients, detailed internal logs|
| **Transport**       | HTTPS only, HSTS header, TLS 1.2+                       |
| **Versioning**      | Version APIs, deprecate old versions with clear timeline |
| **Dependencies**    | Audit regularly, pin versions, automated vulnerability scanning |

---

## HTTP Security Headers

### Complete Security Headers Configuration

```typescript
// Express middleware for security headers
import helmet from 'helmet';
import crypto from 'crypto';

app.use(helmet({
  // Content Security Policy
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: [
        "'self'",
        // Nonce is set per-request below
      ],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "https://cdn.example.com", "data:"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      connectSrc: ["'self'", "https://api.example.com", "wss://ws.example.com"],
      mediaSrc: ["'self'"],
      objectSrc: ["'none'"],            // Block <object>, <embed>
      frameSrc: ["'none'"],             // Block <iframe> sources
      childSrc: ["'none'"],
      workerSrc: ["'self'", "blob:"],
      frameAncestors: ["'none'"],       // Prevent clickjacking (replaces X-Frame-Options)
      formAction: ["'self'"],           // Restrict form submission targets
      baseUri: ["'self'"],              // Restrict <base> tag
      upgradeInsecureRequests: [],      // Upgrade HTTP to HTTPS
      blockAllMixedContent: [],         // Block mixed content
    },
    reportOnly: false,  // Set to true for testing before enforcement
  },

  // Strict-Transport-Security
  strictTransportSecurity: {
    maxAge: 31536000,         // 1 year
    includeSubDomains: true,
    preload: true,            // Submit to HSTS preload list
  },

  // X-Content-Type-Options
  xContentTypeOptions: true,  // nosniff -- prevent MIME type sniffing

  // Referrer-Policy
  referrerPolicy: {
    policy: 'strict-origin-when-cross-origin',
  },

  // X-Frame-Options (legacy, use CSP frame-ancestors instead)
  xFrameOptions: { action: 'deny' },
}));

// Permissions-Policy (manual header -- helmet does not set this by default)
app.use((req, res, next) => {
  res.setHeader('Permissions-Policy', [
    'camera=()',              // Disable camera
    'microphone=()',          // Disable microphone
    'geolocation=()',         // Disable geolocation
    'payment=(self)',         // Payment API only on same origin
    'usb=()',                 // Disable USB access
    'magnetometer=()',
    'gyroscope=()',
    'accelerometer=()',
    'autoplay=(self)',
    'fullscreen=(self)',
  ].join(', '));
  next();
});

// CSP nonce generation (per request)
app.use((req, res, next) => {
  const nonce = crypto.randomBytes(16).toString('base64');
  res.locals.cspNonce = nonce;

  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      `script-src 'self' 'nonce-${nonce}'`,
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' https://cdn.example.com data:",
      "font-src 'self' https://fonts.gstatic.com",
      "connect-src 'self' https://api.example.com",
      "object-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "upgrade-insecure-requests",
    ].join('; ')
  );

  next();
});
```

```html
<!-- Use nonce in templates -->
<script nonce="{{cspNonce}}">
  // Inline script with matching nonce is allowed by CSP
  const config = { apiUrl: 'https://api.example.com' };
</script>
```

### CORS Configuration

```typescript
import cors from 'cors';

// Production CORS configuration
const ALLOWED_ORIGINS = new Set([
  'https://www.example.com',
  'https://app.example.com',
  'https://admin.example.com',
]);

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (server-to-server, mobile apps)
    if (!origin) return callback(null, true);

    if (ALLOWED_ORIGINS.has(origin)) {
      return callback(null, origin);
    }

    callback(new Error(`Origin ${origin} not allowed by CORS`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-CSRF-Token',
    'X-Requested-With',
    'X-Request-Id',
  ],
  exposedHeaders: [
    'X-Request-Id',
    'X-RateLimit-Limit',
    'X-RateLimit-Remaining',
    'X-RateLimit-Reset',
  ],
  credentials: true,            // Allow cookies
  maxAge: 86400,                // Cache preflight for 24 hours
  preflightContinue: false,
  optionsSuccessStatus: 204,
}));

// IMPORTANT: Never use these in production:
// origin: '*'                   -- Allows any origin
// origin: true                  -- Reflects any origin (equivalent to *)
// credentials: true + origin: * -- Browser blocks this, but still a misconfiguration
```

### Header Security Summary

| Header                       | Value                                      | Purpose                              |
|------------------------------|--------------------------------------------|--------------------------------------|
| `Content-Security-Policy`    | See above (detailed directives)            | Mitigate XSS, injection attacks     |
| `Strict-Transport-Security`  | `max-age=31536000; includeSubDomains; preload` | Force HTTPS                    |
| `X-Content-Type-Options`     | `nosniff`                                  | Prevent MIME type sniffing           |
| `X-Frame-Options`            | `DENY`                                     | Prevent clickjacking                 |
| `Referrer-Policy`            | `strict-origin-when-cross-origin`          | Control referrer information         |
| `Permissions-Policy`         | `camera=(), microphone=(), geolocation=()` | Disable unused browser APIs          |
| `Cross-Origin-Opener-Policy` | `same-origin`                              | Isolate browsing context             |
| `Cross-Origin-Resource-Policy` | `same-origin`                            | Prevent cross-origin resource reads  |
| `Cross-Origin-Embedder-Policy` | `require-corp`                           | Enable cross-origin isolation        |
| `Cache-Control`              | `no-store` (for sensitive data)            | Prevent caching of sensitive pages   |

### Testing Headers

```bash
# Check headers with curl
curl -I https://example.com

# Comprehensive scan with Mozilla Observatory
# https://observatory.mozilla.org

# Check CSP with Google CSP Evaluator
# https://csp-evaluator.withgoogle.com/

# SecurityHeaders.com scan
# https://securityheaders.com/?q=example.com
```
