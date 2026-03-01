<p align="center">
  <h1 align="center">BoxClaw Skills</h1>
  <p align="center">Production-grade AI agent skills for every programming role</p>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/boxclaw"><img src="https://img.shields.io/npm/v/boxclaw?style=flat-square&color=red" alt="npm" /></a>
  <img src="https://img.shields.io/badge/Skills-15-blue?style=flat-square" alt="Skills: 15" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT" />
  <img src="https://img.shields.io/badge/Platform-Multi--Agent-purple?style=flat-square" alt="Platform: Multi-Agent" />
  <img src="https://img.shields.io/badge/PRs-Welcome-brightgreen?style=flat-square" alt="PRs Welcome" />
</p>

---

## What is BoxClaw Skills?

BoxClaw Skills is a curated collection of **15 expert-level skill modules** that transform any AI coding agent into a domain specialist.

- **Instant expertise** -- Each skill contains battle-tested patterns, checklists, and workflows distilled from production experience. Your agent goes from generic to specialist in seconds.
- **Deep reference library** -- 34 reference documents with 36,500+ lines of detailed patterns, templates, and real-world examples that agents can load on demand.
- **Automation scripts** -- 21 ready-to-run scripts for scaffolding, auditing, building, and deploying -- agents can execute them directly.
- **Works everywhere** -- Compatible with Claude Code, Cursor, Windsurf, Cline, Antigravity, OpenClaw, and any agent that supports custom instructions.

### Before vs After

```
Without skill:  "Here's a basic Express route handler..."
With skill:     "Here's a production route with Zod validation, cursor pagination,
                 proper error handling, and a matching test file. Let me also
                 generate the scaffolding with the api-scaffold script."
```

---

## Skills Catalog

| | Skill | Role | Key Expertise | Refs | Scripts |
|---|-------|------|---------------|:----:|:-------:|
| :art: | [frontend-developer](frontend-developer/) | Frontend Developer | React/Vue/Angular/Svelte, CSS/Tailwind, a11y, Core Web Vitals | 2 | 2 |
| :wrench: | [backend-developer](backend-developer/) | Backend Developer | REST/GraphQL/gRPC, JWT/OAuth, database, caching, microservices | 2 | 2 |
| :crystal_ball: | [fullstack-developer](fullstack-developer/) | Full-Stack Developer | Next.js/Nuxt/SvelteKit, monorepo, end-to-end deployment | 2 | 1 |
| :rocket: | [devops-engineer](devops-engineer/) | DevOps Engineer | CI/CD, Docker, Kubernetes, Terraform, Prometheus/Grafana | 3 | 2 |
| :iphone: | [mobile-developer](mobile-developer/) | Mobile Developer | React Native, Flutter, Swift, Kotlin, offline-first | 2 | 1 |
| :test_tube: | [qa-test-engineer](qa-test-engineer/) | QA/Test Engineer | TDD/BDD, Playwright, unit/integration/E2E, load testing | 2 | 1 |
| :arrows_counterclockwise: | [data-engineer](data-engineer/) | Data Engineer | ETL/ELT, dbt, Airflow, Spark, data modeling, quality | 2 | 1 |
| :shield: | [security-engineer](security-engineer/) | Security Engineer | OWASP Top 10, secure code review, STRIDE, secrets mgmt | 2 | 1 |
| :building_construction: | [system-architect](system-architect/) | System Architect | System design, DDD, CQRS, scalability, ADR | 2 | 1 |
| :necktie: | [tech-lead](tech-lead/) | Tech Lead | Code review, sprint planning, tech debt, DORA metrics | 2 | 1 |
| :robot: | [ai-ml-engineer](ai-ml-engineer/) | AI/ML Engineer | ML pipelines, LLM/RAG, MLOps, prompt engineering | 2 | 1 |
| :file_cabinet: | [database-administrator](database-administrator/) | Database Administrator | Query optimization, indexing, replication, backup/recovery | 2 | 1 |
| :cloud: | [cloud-architect](cloud-architect/) | Cloud Architect | AWS/GCP/Azure, serverless, IaC, cost optimization, HA/DR | 2 | 1 |
| :coffee: | [senior-java-developer](senior-java-developer/) | Senior Java Developer | Spring Boot, WebFlux, gRPC, JVM tuning, OpenTelemetry, MapStruct | 5 | 3 |
| :mag: | [code-reviewer](code-reviewer/) | Code Reviewer | SonarQube, static analysis, code smells, refactoring, quality gates | 2 | 2 |

---

## Quick Start

### Install with BoxClaw CLI (Recommended)

```bash
npm install -g boxclaw
boxclaw init
boxclaw install skill frontend-developer
boxclaw install skill devops-engineer
```

That's it. Skills are downloaded to `.skills/` and your agent is auto-configured.

```bash
# See all available skills, MCP servers, and RAG templates
boxclaw list

# Search by keyword
boxclaw search react

# Update installed skills
boxclaw update

# Install MCP servers and RAG templates too
boxclaw install mcp github
boxclaw install rag codebase-rag
```

### Manual Install

<details>
<summary>Click to expand manual install instructions</summary>

#### 1. Clone the repository

```bash
git clone https://github.com/boxclawai/skills.git
cd skills
```

#### 2. Copy skills to your project

```bash
# Copy a single skill
cp -r frontend-developer /path/to/your/project/.skills/

# Copy all skills
cp -r . /path/to/your/project/.skills/boxclaw-skills/

# Or symlink for easier updates
ln -s "$(pwd)/frontend-developer" /path/to/your/project/.skills/frontend-developer
```

#### 3. Configure your agent

See [Agent Setup](#agent-setup) below for quick snippets, or [SETUP.md](SETUP.md) for detailed step-by-step guides.

</details>

---

## Agent Setup

BoxClaw Skills work with any AI coding agent that supports custom instructions. Below are quick-start snippets for popular agents. For detailed walkthroughs, see **[SETUP.md](SETUP.md)**.

### Claude Code

Add to your project's `CLAUDE.md`:

```markdown
# Project Skills

When working on frontend tasks, follow the expert patterns in:
@frontend-developer/SKILL.md

For deep reference material, consult:
@frontend-developer/references/framework-patterns.md
@frontend-developer/references/css-recipes.md

You can run automation scripts from frontend-developer/scripts/ when scaffolding is needed.
```

Or use `.claude/` project commands for skill-specific workflows.

### Cursor

Create `.cursorrules` in your project root:

```
You are a senior frontend developer. Follow these expert patterns and conventions:

[Paste the content of frontend-developer/SKILL.md here]

For deeper reference, consult the files in frontend-developer/references/.
```

Or go to **Settings > Rules for AI** and add the skill content as project rules.

### Windsurf

Create `.windsurfrules` in your project root:

```
You are a senior frontend developer. Follow these expert patterns and conventions:

[Paste the content of frontend-developer/SKILL.md here]
```

### Cline

Create `.clinerules` in your project root, or add to **Cline Settings > Custom Instructions**:

```
You are a senior frontend developer. Follow these expert patterns:

[Paste the content of frontend-developer/SKILL.md here]
```

### Antigravity

BoxClaw Skills work with Google Antigravity's rules system. Create `.antigravityrules` in your project root:

```
You are a senior developer. Follow the expert patterns from BoxClaw Skills.

Installed skills:
- .skills/frontend-developer/SKILL.md

Read the relevant SKILL.md based on the current task and follow its patterns.
Reference documents: .skills/<skill>/references/
Automation scripts: .skills/<skill>/scripts/
```

Or use Antigravity's built-in Skills system by pointing to `.skills/` — each skill's `SKILL.md` is auto-detected.

### OpenClaw

BoxClaw Skills are **natively compatible** with OpenClaw. The skill format (SKILL.md + YAML frontmatter + scripts/ + references/) matches OpenClaw's skill specification.

Add `.skills/` to OpenClaw's skill search path in `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "load": {
      "extraDirs": ["/path/to/your/project/.skills"]
    }
  }
}
```

OpenClaw will auto-detect all installed BoxClaw skills and make them available as agent capabilities.

### Generic / Other Agents

For any agent that accepts a system prompt or custom instructions:

1. Copy the body of the SKILL.md (everything below the YAML frontmatter `---`)
2. Paste into the agent's custom instructions / system prompt field
3. Optionally include reference documents for deeper context

Works with: Aider, Continue, GitHub Copilot Chat, OpenAI Codex CLI, and others.

> **Tip**: See [SETUP.md](SETUP.md) for detailed multi-skill configuration, context budget management, and team setup strategies.

---

## Skill Anatomy

Each skill follows a consistent structure:

```
skill-name/
├── SKILL.md              # Core expertise (YAML frontmatter + markdown)
├── references/           # Deep-dive reference documents (loaded on demand)
│   ├── topic-a.md        #   Detailed patterns, templates, examples
│   └── topic-b.md        #   Real-world production configurations
└── scripts/              # Automation scripts (optional)
    └── tool.sh           #   Scaffolding, auditing, building
```

### SKILL.md Format

Every SKILL.md has a YAML frontmatter header followed by structured markdown:

```yaml
---
name: frontend-developer          # Matches directory name
version: "1.0.0"                  # Semantic version
description: "Frontend expert..." # Trigger description (includes "Use when" / "NOT for")
tags: [react, vue, css, a11y]     # Discovery keywords
author: "boxclaw"                 # Skill author
references:                       # Paths to reference docs
  - references/framework-patterns.md
  - references/css-recipes.md
metadata:
  boxclaw:
    emoji: "🎨"                   # Visual identifier
    category: "programming-role"  # Skill category
---

# Frontend Developer

Expert guidance for building modern web interfaces.

## Core Competencies

### 1. Component Architecture
...

### 2. Performance Optimization
...

## Quick Commands
...

## References
- See [references/framework-patterns.md](references/framework-patterns.md)
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `name` | Unique skill identifier, matches the directory name |
| `description` | Detailed trigger text. Includes "Use when: (1)... (2)..." and "NOT for:" clauses so agents know when to activate the skill |
| `tags` | Keyword array for search and discovery |
| `references` | Relative paths to deep-dive documents; agents load these on demand |
| `metadata.boxclaw.emoji` | Visual icon for the skill |

### References

Reference documents are standalone, comprehensive guides that agents load when deeper knowledge is needed. They contain:

- Production-ready code templates and configurations
- Decision matrices and comparison tables
- Step-by-step procedures with real-world examples
- Best practices distilled from industry experience

Examples: `owasp-cheatsheets.md` (1955 lines), `pattern-catalog.md` (2395 lines), `fullstack-patterns.md` (1703 lines).

### Scripts

Automation scripts that agents can execute directly:

| Script | Skill | What it does |
|--------|-------|-------------|
| `component-generator.sh` | frontend | Scaffolds React/Vue components with tests |
| `lighthouse-audit.sh` | frontend | Runs Lighthouse performance audit with reports |
| `api-scaffold.sh` | backend | Generates REST API resource (route, service, schema, test) |
| `migration-helper.sh` | backend | Database migration workflow (Prisma/Drizzle/Knex) |
| `project-init.sh` | fullstack | Full monorepo project setup (Next.js/Nuxt + API + Docker) |
| `docker-cleanup.sh` | devops | Cleans unused Docker images, containers, volumes |
| `k8s-deploy.sh` | devops | Kubernetes deployment with rollback support |
| `app-build.sh` | mobile | React Native / Flutter build for iOS and Android |
| `test-runner.sh` | qa-test | Multi-framework test runner (vitest/jest/pytest) |
| `dbt-helper.sh` | data | dbt workflow automation (run, test, docs) |
| `security-scan.sh` | security | Runs deps audit, secret detection, SAST, header check |
| `adr-generator.sh` | architect | Creates Architecture Decision Records with templates |
| `pr-stats.sh` | tech-lead | PR metrics, lead time, DORA-like stats |
| `model-eval.py` | ai-ml | ML model evaluation with metrics and reports |
| `pg-health-check.sh` | dba | PostgreSQL health metrics and diagnostics |
| `cost-report.sh` | cloud | AWS cost analysis and waste detection |
| `sonarqube-setup.sh` | code-reviewer | SonarQube/SonarCloud setup (Docker, cloud, CI pipelines) |
| `code-quality-check.sh` | code-reviewer | Multi-language quality checks (lint, format, security) |

All shell scripts are cross-platform compatible (macOS + Linux) and use `set -euo pipefail`.

---

## How Skills Work

```
┌─────────────────────────────────────────────────────────┐
│                     User Request                         │
│        "Help me optimize this PostgreSQL query"          │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Agent reads skill descriptions               │
│    Matches: database-administrator (query optimization)   │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│           SKILL.md loaded into context                    │
│    Core expertise: EXPLAIN ANALYZE, index strategy,       │
│    partitioning, connection pooling, monitoring            │
└──────────┬─────────────────────────────────┬────────────┘
           │                                 │
           ▼                                 ▼
┌──────────────────────┐      ┌──────────────────────────┐
│   references/ (on    │      │    scripts/ (on demand)   │
│   demand)            │      │                          │
│                      │      │  pg-health-check.sh      │
│ postgresql-tuning.md │      │  → Run diagnostics       │
│ migration-patterns.md│      │                          │
└──────────────────────┘      └──────────────────────────┘
```

1. **Trigger** -- The agent reads the `description` field and determines which skill best matches the user's request.
2. **Load** -- The SKILL.md body provides the agent with expert-level instructions, patterns, and decision frameworks.
3. **Reference** -- When deeper knowledge is needed, the agent loads specific reference documents listed in the `references` array.
4. **Execute** -- The agent can run scripts from `scripts/` for scaffolding, auditing, or automation tasks.

---

## Customization

### Add company-specific references

```bash
# Add your team's API standards to the backend skill
cp our-api-standards.md backend-developer/references/
```

Then update `references` in `backend-developer/SKILL.md`:

```yaml
references:
  - references/database-patterns.md
  - references/api-security.md
  - references/our-api-standards.md    # Added
```

### Modify skill instructions

Edit the SKILL.md body to match your team's stack:

```markdown
### State Management
- Use Zustand for global state (not Redux)
- Use TanStack Query for server state
- Use URL state for filters and pagination
```

### Add custom scripts

```bash
# Add a deploy script to devops
cp deploy-staging.sh devops-engineer/scripts/
chmod +x devops-engineer/scripts/deploy-staging.sh
```

### Tune trigger descriptions

Adjust the `description` field to match your team's vocabulary:

```yaml
description: "Frontend expert specializing in our React + Zustand + Tailwind stack.
  Use when working on the dashboard app or component library."
```

### Create a new skill

Use this skeleton:

````yaml
---
name: your-skill-name
version: "1.0.0"
description: "Expert in [domain]. Use when: (1) [scenario], (2) [scenario]. NOT for: [out of scope]."
tags: [tag1, tag2, tag3]
author: "your-team"
references:
  - references/your-reference.md
metadata:
  boxclaw:
    emoji: "your-emoji"
    category: "programming-role"
---

# Your Skill Title

Expert guidance for [domain].

## Core Competencies

### 1. [First Area]

...

### 2. [Second Area]

...

## Quick Commands

```bash
# Common commands for this domain
```

## References

- See [references/your-reference.md](references/your-reference.md)
````

---

## Contributing

Contributions are welcome! Here's how you can help:

- **Report issues** -- Found a bug in a script or outdated pattern? [Open an issue](../../issues).
- **Improve skills** -- Submit a PR to add patterns, fix examples, or update references.
- **Add new skills** -- Follow the [skeleton template](#create-a-new-skill) and submit a PR.
- **Share feedback** -- What skills are missing? What patterns would you like to see?

### Pull Request Guidelines

1. One skill change per PR (unless they're related)
2. Test scripts on both macOS and Linux if possible
3. Keep reference documents focused and well-structured with a Table of Contents
4. Follow existing YAML frontmatter format exactly

---

## FAQ

**Do I need all 15 skills?**
No. Copy only the skills relevant to your project. A React app might only need `frontend-developer` and `qa-test-engineer`.

**Can I use multiple skills at once?**
Yes. You can load multiple skills into your agent's context. For large projects, consider a dispatcher approach -- see [SETUP.md](SETUP.md#combining-multiple-skills) for strategies.

**How large are the skills? Will they overflow my context?**
SKILL.md files are 179-279 lines (compact). Reference documents are larger (500-2400 lines) but are designed to be loaded **on demand**, not all at once. Only load what you need.

**Can I use this with my own custom agent?**
Yes. The SKILL.md is standard markdown with YAML frontmatter. Copy the body into any system prompt, custom instructions field, or agent configuration.

**Are the scripts required?**
No. Scripts are optional automation helpers. The skills work perfectly without them -- the scripts just speed up common tasks.

**Can I use the references standalone?**
Absolutely. Each reference document is self-contained. You can use `postgresql-tuning.md` or `owasp-cheatsheets.md` independently as reference material.

**What makes these different from a prompt template?**
BoxClaw Skills are structured expertise modules, not simple prompts. Each skill includes: decision frameworks (when to use what), production patterns (not toy examples), reference documents (deep knowledge), and automation scripts (executable tools).

**How do I keep skills updated?**
With BoxClaw CLI: `boxclaw update` updates all installed skills. Manual install: `git pull` if you cloned, or re-copy from the latest release.

---

## License

[MIT](LICENSE) -- Use freely in personal and commercial projects.
