# 🔍 Code Reviewer Skill

Expert code review guidance with static analysis tools, quality gates, and automated review workflows.

## What's Inside

### SKILL.md (Core Expertise)
- **Code Review Pyramid** — Priority framework: correctness → security → architecture → performance → maintainability → tests → style
- **Review Checklists** — Category-specific checklists for correctness, security (OWASP), performance, architecture (SOLID/DRY/KISS)
- **SonarQube Integration** — Quality gates, metrics, Maven/Gradle/npm configuration, GitHub Actions setup
- **Static Analysis Setup** — Multi-language tool chains (Java, JS/TS, Python, Go)
- **PR Review Workflow** — Size guidelines, comment templates, approval criteria
- **Code Coverage Strategy** — Coverage targets, meaningful vs vanity metrics
- **Automated Quality Gates** — CI/CD pipeline integration patterns

### References

| File | Lines | Topics |
|------|:-----:|--------|
| `static-analysis-tools.md` | 900+ | SonarQube deep dive, PMD, SpotBugs, Checkstyle, ESLint, Biome, Ruff, mypy, Bandit, golangci-lint, Semgrep, Trivy, pre-commit hooks, CI/CD templates |
| `code-smells-refactoring.md` | 580+ | Code smell catalog (bloaters, OO abusers, change preventers, dispensables, couplers), refactoring techniques, clean code principles, complexity metrics, anti-patterns, tech debt classification |

### Scripts

| Script | What it does |
|--------|-------------|
| `sonarqube-setup.sh` | Quick SonarQube/SonarCloud setup (Docker local, cloud config, CI pipeline generation) |
| `code-quality-check.sh` | Multi-language quality checks (lint, format, type check, security, dependency audit) |

## Quick Start

```bash
# Install with BoxClaw CLI
boxclaw install skill code-reviewer

# Or copy manually
cp -r code-reviewer /path/to/project/.skills/
```

## Usage

### Run quality checks on any project
```bash
# Quick lint + format check
.skills/code-reviewer/scripts/code-quality-check.sh --quick

# Full analysis (lint + security + deps)
.skills/code-reviewer/scripts/code-quality-check.sh --full

# Auto-fix issues
.skills/code-reviewer/scripts/code-quality-check.sh --fix

# CI mode (strict, exits non-zero on errors)
.skills/code-reviewer/scripts/code-quality-check.sh --ci
```

### Set up SonarQube
```bash
# Start local SonarQube via Docker
.skills/code-reviewer/scripts/sonarqube-setup.sh --local

# Configure SonarCloud
.skills/code-reviewer/scripts/sonarqube-setup.sh --cloud --org myorg --key myproject

# Generate CI pipeline config
.skills/code-reviewer/scripts/sonarqube-setup.sh --ci --github
```

## Supported Languages

| Language | Lint | Format | Type Check | Security | Deps Audit |
|----------|:----:|:------:|:----------:|:--------:|:----------:|
| JavaScript/TypeScript | ESLint | Prettier | tsc | npm audit | npm audit |
| Python | Ruff | Ruff | mypy | Bandit | pip-audit |
| Java | PMD/Checkstyle | - | javac | SpotBugs | OWASP DC |
| Go | go vet | gofmt | - | govulncheck | govulncheck |

## File Structure

```
code-reviewer/
├── SKILL.md                              # Core review expertise
├── README.md                             # This file
├── references/
│   ├── static-analysis-tools.md          # SonarQube, PMD, ESLint, Ruff, etc.
│   └── code-smells-refactoring.md        # Code smells, refactoring, clean code
└── scripts/
    ├── sonarqube-setup.sh                # SonarQube/SonarCloud setup
    └── code-quality-check.sh             # Multi-language quality checks
```

## License

MIT
