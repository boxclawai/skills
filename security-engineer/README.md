# :shield: Security Engineer

> Application security engineering expert covering OWASP Top 10, vulnerability assessment, secure code review, authentication/authorization hardening, input validation, cryptography best practices, dependency scanning, secrets management, and threat modeling.

## What's Included

### SKILL.md
Core expertise covering:
- Core Competencies
  - OWASP Top 10 (2021) Quick Reference
  - Secure Code Review Checklist
  - Input Validation Patterns
  - Security Headers
  - Secrets Management
  - Dependency Security
  - Threat Modeling (STRIDE)
- Quick Commands
- References

### References
| File | Description | Lines |
|------|-------------|-------|
| [owasp-cheatsheets.md](references/owasp-cheatsheets.md) | Comprehensive security reference based on OWASP guidelines covering injection prevention, XSS, CSRF, authentication, authorization, file uploads, SSRF, API security, and HTTP security headers | 1955 |
| [crypto-guidelines.md](references/crypto-guidelines.md) | Cryptography best practices for production systems covering password hashing, symmetric/asymmetric encryption, JWT signing, TLS configuration, key management, and secure random generation | 1519 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [security-scan.sh](scripts/security-scan.sh) | Comprehensive security scanning pipeline | `./scripts/security-scan.sh [--type all\|deps\|secrets\|sast\|headers] [--ci] [--fix]` |

## Tags
`owasp` `security` `authentication` `encryption` `xss` `sql-injection` `secrets` `vulnerability` `threat-modeling`

## Quick Start

```bash
# Copy this skill to your project
cp -r security-engineer/ /path/to/project/.skills/

# Run a full security scan
.skills/security-engineer/scripts/security-scan.sh --type all

# Run dependency scanning in CI mode
.skills/security-engineer/scripts/security-scan.sh --type deps --ci
```

## Part of [BoxClaw Skills](../)
