---
name: code-reviewer
version: "1.0.0"
description: "Code review and quality expert: systematic review frameworks, static analysis (SonarQube/PMD/SpotBugs/ESLint/Pylint), clean code principles, code smell detection, refactoring patterns, security review (OWASP), performance review, CI/CD quality gates, automated review tooling, and PR best practices. Use when: (1) reviewing pull requests, (2) setting up code quality pipelines, (3) configuring SonarQube or static analyzers, (4) identifying code smells and refactoring, (5) enforcing coding standards, (6) improving test quality, (7) conducting security-focused reviews. NOT for: writing new features from scratch or infrastructure setup."
tags: [code-review, sonarqube, static-analysis, clean-code, refactoring, linting, quality-gates, pmd, eslint, security-review]
author: "boxclaw"
references:
  - references/static-analysis-tools.md
  - references/code-smells-refactoring.md
metadata:
  boxclaw:
    emoji: "🔍"
    category: "programming-role"
---

# Code Reviewer

Expert guidance for systematic code review, static analysis tooling, code quality enforcement, and clean code practices.

## Core Competencies

### 1. Code Review Framework

#### Review Priority Checklist (in order)

```
┌─────────────────────────────────────────────────────┐
│                  CODE REVIEW PYRAMID                 │
├─────────────────────────────────────────────────────┤
│  1. CORRECTNESS    Does it work? Edge cases?         │
│  2. SECURITY       Injection? Auth? Data exposure?   │
│  3. ARCHITECTURE   Right abstraction? SOLID?         │
│  4. PERFORMANCE    O(n²)? N+1? Memory leaks?         │
│  5. MAINTAINABILITY  Readable? Testable? DRY?        │
│  6. TESTS          Coverage? Right level? Flaky?     │
│  7. STYLE          Automate this (linter/formatter)  │
└─────────────────────────────────────────────────────┘
```

#### Before Approving — Final Checklist

```markdown
## Review Checklist
- [ ] All tests pass (CI green)
- [ ] No new warnings from static analysis
- [ ] No hardcoded secrets, tokens, or credentials
- [ ] Error handling covers failure modes
- [ ] No unnecessary complexity added
- [ ] Database migrations are reversible
- [ ] API changes are backward compatible
- [ ] Logging is sufficient for debugging
- [ ] No TODO/FIXME without a ticket reference
- [ ] Documentation updated (if public API changed)
```

### 2. Review by Category

#### Correctness Review

```
What to check:
  ✓ Input validation at boundaries (null, empty, negative, overflow)
  ✓ Off-by-one errors in loops and array access
  ✓ Race conditions in concurrent code
  ✓ Resource cleanup (streams, connections, files closed?)
  ✓ Error propagation (exceptions not swallowed silently)
  ✓ Null safety (Optional used correctly, NPE-safe?)
  ✓ Boundary conditions (empty list, max int, unicode, timezone)
  ✓ State mutations (unintended side effects?)

Red flags:
  ✗ catch(Exception e) { } — swallowed exception
  ✗ == instead of .equals() for objects
  ✗ Mutable shared state without synchronization
  ✗ String concatenation with user input (injection risk)
  ✗ Floating-point comparison with == (use BigDecimal for money)
```

#### Security Review

```
OWASP Top 10 Quick Check:
  1. Injection        SQL/NoSQL/OS command injection via user input?
  2. Broken Auth      Weak passwords, missing MFA, session fixation?
  3. Data Exposure    Sensitive data in logs, URLs, or responses?
  4. XXE              XML external entity in XML parsers?
  5. Access Control   Missing authorization checks? IDOR?
  6. Misconfiguration Debug mode on? Default passwords? CORS *?
  7. XSS              User input rendered without escaping?
  8. Deserialization   Untrusted data deserialized?
  9. Vulnerable Deps  Known CVEs in dependencies?
  10. Logging          Insufficient audit trail?

Critical patterns to flag:
  ✗ Raw SQL with string concatenation
  ✗ eval() or dynamic code execution
  ✗ Secrets in source code or config files
  ✗ Missing rate limiting on auth endpoints
  ✗ Sensitive data in GET query parameters
  ✗ CORS with Access-Control-Allow-Origin: *
  ✗ Missing Content-Security-Policy headers
  ✗ Disabled CSRF protection without justification
```

#### Performance Review

```
Database:
  ✓ N+1 query problem (eager loading or join fetch needed?)
  ✓ Missing indexes on queried columns
  ✓ SELECT * instead of specific columns
  ✓ Unbounded queries without LIMIT/pagination
  ✓ Transactions held too long (API calls inside transactions?)

Memory:
  ✓ Large collections loaded entirely into memory
  ✓ Streams/readers not closed (resource leaks)
  ✓ Accumulating data in static fields or caches without eviction
  ✓ String concatenation in loops (use StringBuilder)

Concurrency:
  ✓ Synchronized blocks too wide
  ✓ Thread pool sizing appropriate
  ✓ Blocking I/O on reactive/async threads
  ✓ Missing timeouts on external calls

Network:
  ✓ Missing HTTP timeouts (connect + read)
  ✓ No retry with backoff for transient failures
  ✓ Large payloads without compression or pagination
  ✓ Sequential calls that could be parallel
```

#### Architecture Review

```
SOLID Principles:
  S — Single Responsibility: Does this class/method do one thing?
  O — Open/Closed: Can we extend without modifying?
  L — Liskov Substitution: Are subtypes substitutable?
  I — Interface Segregation: Are interfaces focused?
  D — Dependency Inversion: Depends on abstractions?

Design Patterns (misuse check):
  ✓ God class / God method (>200 lines?)
  ✓ Feature envy (method uses another class's data more than its own)
  ✓ Shotgun surgery (one change requires modifying many files)
  ✓ Inappropriate intimacy (classes too tightly coupled)
  ✓ Primitive obsession (using strings for structured data)

Layer violations:
  ✗ Controller calling repository directly (skip service layer)
  ✗ Business logic in controller or entity
  ✗ Domain model leaking to API responses
  ✗ Infrastructure concerns in domain layer
```

### 3. SonarQube Integration

#### Quality Gate Configuration

```
Default Quality Gate (recommended):
  ┌────────────────────────────────────────┐
  │  Metric                  │  Threshold  │
  ├──────────────────────────┼─────────────┤
  │  New Code Coverage       │  ≥ 80%      │
  │  New Duplicated Lines    │  ≤ 3%       │
  │  New Maintainability (A) │  Rating A   │
  │  New Reliability (A)     │  Rating A   │
  │  New Security (A)        │  Rating A   │
  │  New Security Hotspots   │  Reviewed   │
  └──────────────────────────┴─────────────┘

Stricter gate (for critical services):
  - New Code Coverage ≥ 90%
  - New Duplicated Lines ≤ 1%
  - Zero new bugs
  - Zero new vulnerabilities
  - Zero new security hotspots unreviewed
```

#### SonarQube with Maven

```xml
<!-- pom.xml -->
<properties>
    <sonar.projectKey>my-project</sonar.projectKey>
    <sonar.organization>my-org</sonar.organization>
    <sonar.host.url>https://sonarcloud.io</sonar.host.url>
    <sonar.coverage.jacoco.xmlReportPaths>
        ${project.basedir}/target/site/jacoco/jacoco.xml
    </sonar.coverage.jacoco.xmlReportPaths>
    <sonar.exclusions>
        **/generated/**,**/config/**,**/*Application.java
    </sonar.exclusions>
    <sonar.cpd.exclusions>**/dto/**,**/entity/**</sonar.cpd.exclusions>
</properties>
```

```bash
# Run SonarQube analysis
mvn clean verify sonar:sonar \
  -Dsonar.token=$SONAR_TOKEN

# With coverage
mvn clean verify jacoco:report sonar:sonar \
  -Dsonar.token=$SONAR_TOKEN
```

#### SonarQube with Gradle

```kotlin
// build.gradle.kts
plugins {
    id("org.sonarqube") version "5.0.0.4638"
    jacoco
}

sonar {
    properties {
        property("sonar.projectKey", "my-project")
        property("sonar.organization", "my-org")
        property("sonar.host.url", "https://sonarcloud.io")
        property("sonar.coverage.jacoco.xmlReportPaths",
            "${layout.buildDirectory}/reports/jacoco/test/jacocoTestReport.xml")
    }
}

tasks.sonar {
    dependsOn(tasks.jacocoTestReport)
}
```

#### GitHub Actions with SonarCloud

```yaml
name: Code Quality
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  sonarcloud:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for accurate blame

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'

      - name: Build + Test + Coverage
        run: mvn clean verify jacoco:report

      - name: SonarCloud Analysis
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: >
          mvn sonar:sonar
          -Dsonar.projectKey=my-project
          -Dsonar.organization=my-org
          -Dsonar.host.url=https://sonarcloud.io
```

### 4. Static Analysis Tools Setup

#### Java: PMD + SpotBugs + Checkstyle

```xml
<!-- pom.xml — all three tools -->
<build>
    <plugins>
        <!-- PMD — code pattern analysis -->
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-pmd-plugin</artifactId>
            <version>3.21.2</version>
            <configuration>
                <rulesets>
                    <ruleset>/rulesets/java/quickstart.xml</ruleset>
                </rulesets>
                <failOnViolation>true</failOnViolation>
                <printFailingErrors>true</printFailingErrors>
                <targetJdk>21</targetJdk>
                <excludeRoots>
                    <excludeRoot>target/generated-sources</excludeRoot>
                </excludeRoots>
            </configuration>
        </plugin>

        <!-- SpotBugs — bug pattern detection -->
        <plugin>
            <groupId>com.github.spotbugs</groupId>
            <artifactId>spotbugs-maven-plugin</artifactId>
            <version>4.8.3.1</version>
            <configuration>
                <effort>Max</effort>
                <threshold>Medium</threshold>
                <failOnError>true</failOnError>
                <plugins>
                    <plugin>
                        <groupId>com.h3xstream.findsecbugs</groupId>
                        <artifactId>findsecbugs-plugin</artifactId>
                        <version>1.13.0</version>
                    </plugin>
                </plugins>
            </configuration>
        </plugin>

        <!-- Checkstyle — code style enforcement -->
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-checkstyle-plugin</artifactId>
            <version>3.3.1</version>
            <configuration>
                <configLocation>google_checks.xml</configLocation>
                <consoleOutput>true</consoleOutput>
                <failOnViolation>true</failOnViolation>
                <violationSeverity>warning</violationSeverity>
            </configuration>
        </plugin>
    </plugins>
</build>
```

```bash
# Run all static analysis
mvn pmd:check spotbugs:check checkstyle:check
```

#### JavaScript/TypeScript: ESLint + Prettier

```json
// .eslintrc.json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:react/recommended",
    "plugin:react-hooks/recommended",
    "plugin:security/recommended-legacy",
    "prettier"
  ],
  "plugins": ["@typescript-eslint", "security", "import"],
  "rules": {
    "no-console": "warn",
    "no-eval": "error",
    "no-implied-eval": "error",
    "security/detect-object-injection": "warn",
    "security/detect-non-literal-regexp": "warn",
    "security/detect-possible-timing-attacks": "warn",
    "import/order": ["error", {
      "groups": ["builtin", "external", "internal", "parent", "sibling"],
      "newlines-between": "always"
    }],
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": "error",
    "react-hooks/exhaustive-deps": "error"
  }
}
```

#### Python: Ruff + mypy + Bandit

```toml
# pyproject.toml
[tool.ruff]
target-version = "py312"
line-length = 100
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # pyflakes
    "I",    # isort
    "N",    # pep8-naming
    "S",    # flake8-bandit (security)
    "B",    # flake8-bugbear
    "A",    # flake8-builtins
    "C4",   # flake8-comprehensions
    "T20",  # flake8-print
    "SIM",  # flake8-simplify
    "UP",   # pyupgrade
    "RUF",  # ruff-specific
]
ignore = ["E501"]  # Line too long (handled by formatter)

[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true

[tool.bandit]
exclude_dirs = ["tests", "venv"]
skips = ["B101"]  # assert in tests is fine
```

```bash
# Run all Python checks
ruff check .
mypy src/
bandit -r src/ -c pyproject.toml
```

### 5. PR Review Workflow

#### PR Size Guidelines

```
Ideal PR sizes:
  🟢 Small:   < 200 lines changed    (review in 15 min)
  🟡 Medium:  200-400 lines changed   (review in 30 min)
  🟠 Large:   400-800 lines changed   (review in 1 hour)
  🔴 XL:      > 800 lines changed     (split into smaller PRs!)

If a PR is too large:
  1. Split by layer: separate DB migration, backend, frontend
  2. Split by feature: core logic first, then edge cases
  3. Split by refactor vs feature: refactor in one PR, feature in next
  4. Use feature flags: merge partial work behind a flag
```

#### PR Description Template

```markdown
## What
[1-2 sentences on what this PR does]

## Why
[Link to ticket/issue. Business context for the change]

## How
[Technical approach. Key design decisions]

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing done (describe steps)

## Screenshots
[If UI changes, before/after screenshots]

## Checklist
- [ ] Self-reviewed the code
- [ ] No sensitive data (secrets, tokens, PII) committed
- [ ] Database migration is backward compatible
- [ ] API changes are documented
```

#### Review Comment Guidelines

```
Prefix system for review comments:
  [nit]       Minor style suggestion, non-blocking
  [suggestion] Alternative approach, non-blocking
  [question]  Seeking to understand, non-blocking
  [concern]   Potential issue, discuss before merging
  [blocker]   Must fix before merge
  [praise]    Something done well (important for team morale!)

Good review comments:
  ✓ "This could cause an N+1 query. Consider using @EntityGraph
     or a join fetch query. See [link to docs]"
  ✓ "[nit] This method name could be more descriptive.
     Maybe `calculateDiscountedPrice` instead of `calc`?"
  ✓ "[praise] Great error handling here with specific exception
     types and meaningful messages"

Bad review comments:
  ✗ "This is wrong" (no explanation)
  ✗ "I would have done it differently" (not actionable)
  ✗ "Fix this" (no context)
```

### 6. Automated Quality Gates in CI/CD

```yaml
# .github/workflows/quality-gate.yml
name: Quality Gate

on: [pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Java project
      - name: Build + Test + Coverage
        run: mvn clean verify jacoco:report

      # Enforce coverage threshold
      - name: Check Coverage
        run: |
          COVERAGE=$(grep -oP 'Total.*?(\d+)%' target/site/jacoco/index.html | grep -oP '\d+' | tail -1)
          echo "Coverage: ${COVERAGE}%"
          if [ "$COVERAGE" -lt 80 ]; then
            echo "❌ Coverage ${COVERAGE}% is below 80% threshold"
            exit 1
          fi

      # Static analysis
      - name: PMD
        run: mvn pmd:check

      - name: SpotBugs
        run: mvn spotbugs:check

      # Dependency vulnerabilities
      - name: OWASP Dependency Check
        run: mvn org.owasp:dependency-check-maven:check
        continue-on-error: true  # Report but don't block (initially)

      # SonarCloud
      - name: SonarCloud
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        run: mvn sonar:sonar
```

### 7. Code Coverage Strategy

```
Coverage targets by code type:
  ┌──────────────────────┬───────────┬──────────────────┐
  │  Code Type           │  Target   │  Rationale       │
  ├──────────────────────┼───────────┼──────────────────┤
  │  Business logic      │  ≥ 90%    │  Critical paths  │
  │  Controllers         │  ≥ 80%    │  Integration     │
  │  Utilities           │  ≥ 95%    │  Highly reusable │
  │  DTOs / Records      │  Exclude  │  No logic        │
  │  Configuration       │  Exclude  │  Spring wiring   │
  │  Generated code      │  Exclude  │  Auto-generated  │
  │  Overall project     │  ≥ 80%    │  Balanced target │
  └──────────────────────┴───────────┴──────────────────┘

Coverage anti-patterns:
  ✗ Testing getters/setters for coverage numbers
  ✗ Tests without assertions (execute-only)
  ✗ Ignoring branch coverage (only line coverage)
  ✗ Mocking everything (test doesn't verify behavior)
  ✗ 100% target (leads to brittle, low-value tests)
```

### 8. Dependency Security Scanning

```bash
# OWASP Dependency Check (Java)
mvn org.owasp:dependency-check-maven:check

# npm audit (JavaScript)
npm audit --audit-level=high
npx better-npm-audit audit

# pip-audit (Python)
pip-audit --strict

# Snyk (multi-language)
snyk test
snyk monitor  # Continuous monitoring

# Trivy (containers + code)
trivy fs --security-checks vuln,secret .
trivy image myapp:latest
```

```yaml
# Dependabot config (.github/dependabot.yml)
version: 2
updates:
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels: ["dependencies"]
    reviewers: ["team-leads"]

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "monthly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## Quick Commands

```bash
# SonarQube
mvn clean verify sonar:sonar -Dsonar.token=$SONAR_TOKEN
./gradlew sonar -Dsonar.token=$SONAR_TOKEN

# Java static analysis
mvn pmd:check spotbugs:check checkstyle:check
mvn org.owasp:dependency-check-maven:check

# JavaScript/TypeScript
npx eslint . --ext .ts,.tsx --max-warnings 0
npx prettier --check .

# Python
ruff check . && mypy src/ && bandit -r src/

# Coverage reports
mvn jacoco:report        # Java → target/site/jacoco/
npx vitest --coverage     # JS → coverage/
pytest --cov=src --cov-report=html  # Python → htmlcov/

# Git pre-commit hooks (install)
npx husky init
npx lint-staged
```

## Design Principles

1. **Automate style** — never waste review time on formatting; use linters and formatters
2. **Shift left** — catch bugs in IDE (live linting) before they reach PR review
3. **Review the design, not just the code** — ask "is this the right approach?" first
4. **Small PRs, fast reviews** — review within 24 hours, merge within 48 hours
5. **Quality gates block merges** — CI must pass before review starts
6. **New code standard** — apply stricter rules to new code, grandfather old code
7. **Measure, don't guess** — use SonarQube metrics to track quality trends over time
8. **Security is everyone's job** — every reviewer checks for OWASP top 10 basics

## References

- **Static analysis tools**: See [references/static-analysis-tools.md](references/static-analysis-tools.md)
- **Code smells & refactoring**: See [references/code-smells-refactoring.md](references/code-smells-refactoring.md)
