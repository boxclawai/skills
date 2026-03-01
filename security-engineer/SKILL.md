---
name: security-engineer
version: "1.0.0"
description: "Application security engineering expert: OWASP Top 10, vulnerability assessment, secure code review, authentication/authorization hardening, input validation, cryptography best practices, dependency scanning, secrets management, security headers, CORS, CSP, and penetration testing methodology. Use when: (1) reviewing code for security vulnerabilities, (2) hardening authentication/authorization, (3) implementing input validation or sanitization, (4) configuring security headers, (5) setting up dependency scanning in CI, (6) designing secrets management, (7) threat modeling. NOT for: compliance/legal advice, physical security, or network infrastructure."
tags: [owasp, security, authentication, encryption, xss, sql-injection, secrets, vulnerability, threat-modeling]
author: "boxclaw"
references:
  - references/owasp-cheatsheets.md
  - references/crypto-guidelines.md
metadata:
  boxclaw:
    emoji: "🛡️"
    category: "programming-role"
---

# Security Engineer

Expert guidance for application security, vulnerability prevention, and secure architecture.

## Core Competencies

### 1. OWASP Top 10 (2021) Quick Reference

```
A01 Broken Access Control
  → Enforce server-side, deny by default, RBAC, test authz

A02 Cryptographic Failures
  → TLS everywhere, strong hashing (argon2/bcrypt), no custom crypto

A03 Injection
  → Parameterized queries, input validation, context-aware encoding

A04 Insecure Design
  → Threat modeling, secure design patterns, abuse case testing

A05 Security Misconfiguration
  → Harden defaults, remove unused features, automate config checks

A06 Vulnerable Components
  → SCA scanning (Snyk/Dependabot), update policy, SBOM

A07 Authentication Failures
  → MFA, rate limiting, secure password storage, session management

A08 Data Integrity Failures
  → Verify updates/data integrity, CI/CD security, signed artifacts

A09 Logging & Monitoring Failures
  → Log security events, alerting, tamper-proof audit trail

A10 SSRF
  → Validate URLs, allowlist destinations, segment network
```

### 2. Secure Code Review Checklist

```
Input Handling:
  [ ] All user input validated (type, length, range, format)
  [ ] SQL queries use parameterized statements
  [ ] HTML output encoded to prevent XSS
  [ ] File uploads: validate type, size, scan for malware
  [ ] Redirect URLs validated against allowlist

Authentication:
  [ ] Passwords: argon2id/bcrypt, min 12 chars
  [ ] Sessions: secure, httpOnly, sameSite cookies
  [ ] Tokens: short-lived access + rotating refresh
  [ ] Rate limiting on login (5 attempts / 15 min)
  [ ] Account lockout or progressive delays

Authorization:
  [ ] Server-side enforcement (never trust client)
  [ ] Object-level: user can only access own resources
  [ ] Function-level: role checks on every endpoint
  [ ] No IDOR: verify ownership, not just valid ID

Data Protection:
  [ ] PII encrypted at rest
  [ ] Secrets in vault/env, never in code
  [ ] Logs sanitized: no passwords, tokens, PII
  [ ] Error messages: generic to users, detailed in logs
```

### 3. Input Validation Patterns

```javascript
// Zod schema validation (TypeScript)
import { z } from 'zod';

const CreateUserSchema = z.object({
  email: z.string().email().max(254),
  name: z.string().min(1).max(100).regex(/^[\p{L}\s'-]+$/u),
  age: z.number().int().min(13).max(150),
  role: z.enum(['user', 'admin']),
  bio: z.string().max(500).optional(),
});

// Apply at API boundary
app.post('/users', (req, res) => {
  const result = CreateUserSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ errors: result.error.flatten() });
  }
  // result.data is typed and validated
  createUser(result.data);
});
```

### 4. Security Headers

```javascript
// Express with Helmet
import helmet from 'helmet';
app.use(helmet());

// Manual configuration for fine control
app.use((req, res, next) => {
  // Prevent clickjacking
  res.setHeader('X-Frame-Options', 'DENY');
  // XSS protection
  res.setHeader('Content-Security-Policy',
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'");
  // Prevent MIME sniffing
  res.setHeader('X-Content-Type-Options', 'nosniff');
  // HTTPS only
  res.setHeader('Strict-Transport-Security',
    'max-age=63072000; includeSubDomains; preload');
  // Referrer policy
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  // Permissions policy
  res.setHeader('Permissions-Policy',
    'camera=(), microphone=(), geolocation=()');
  next();
});
```

### 5. Secrets Management

```
Hierarchy (best → worst):
  1. Cloud secret manager (AWS SM, GCP SM, Vault)
  2. CI/CD secrets (GitHub Secrets, GitLab CI vars)
  3. Environment variables (not committed)
  4. .env files (gitignored, local dev only)
  ✗ Hardcoded in source code (NEVER)

Rotation Policy:
  - API keys: every 90 days
  - Database passwords: every 90 days
  - JWT signing keys: every 30 days
  - Automate rotation where possible

Detection:
  - Pre-commit hooks: detect-secrets, git-secrets
  - CI scanning: truffleHog, Gitleaks
  - GitHub secret scanning (built-in)
```

### 6. Dependency Security

```bash
# Scanning tools
npm audit                      # Built-in Node.js
snyk test                      # Comprehensive SCA
trivy fs .                     # File system scan
grype .                        # Container/filesystem scan

# CI integration (GitHub Actions)
- uses: aquasecurity/trivy-action@v0.20.0
  with:
    scan-type: 'fs'
    severity: 'HIGH,CRITICAL'
    exit-code: '1'             # Fail build on findings
```

#### Dependency Policy

```
Critical/High CVE:   Fix within 48 hours
Medium CVE:          Fix within 7 days
Low CVE:             Fix within 30 days
No fix available:    Evaluate alternative, document risk
Unmaintained deps:   Plan migration, add to tech debt
```

### 7. Threat Modeling (STRIDE)

```
For each component/data flow, assess:

S - Spoofing:        Can attacker impersonate a user/service?
T - Tampering:       Can attacker modify data in transit/at rest?
R - Repudiation:     Can attacker deny actions (lacking audit logs)?
I - Info Disclosure: Can attacker access unauthorized data?
D - Denial of Service: Can attacker exhaust resources?
E - Elevation:       Can attacker gain higher privileges?

Process:
  1. Draw data flow diagram (actors, processes, data stores, trust boundaries)
  2. Apply STRIDE to each element
  3. Rate risk: Likelihood x Impact
  4. Define mitigations for high-risk threats
  5. Track as security requirements
```

## Quick Commands

```bash
# Security scanning
npm audit --audit-level=high
snyk test --severity-threshold=high
trivy image myapp:latest
gitleaks detect --source .

# Header testing
curl -I https://myapp.com | grep -iE "x-frame|content-security|strict-transport"

# OWASP ZAP quick scan
docker run -t zaproxy/zap-stable zap-baseline.py -t https://myapp.com
```

## References

- **OWASP cheatsheets**: See [references/owasp-cheatsheets.md](references/owasp-cheatsheets.md)
- **Crypto guidelines**: See [references/crypto-guidelines.md](references/crypto-guidelines.md)
