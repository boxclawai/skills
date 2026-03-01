# BoxClaw Skills -- Setup Guide

Detailed step-by-step instructions for integrating BoxClaw Skills with your AI coding agent.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Claude Code](#claude-code)
4. [Cursor](#cursor)
5. [Windsurf](#windsurf)
6. [Cline](#cline)
7. [Generic / Other Agents](#generic--other-agents)
8. [Combining Multiple Skills](#combining-multiple-skills)
9. [Advanced Configuration](#advanced-configuration)
10. [Troubleshooting](#troubleshooting)
11. [Verification Checklist](#verification-checklist)

---

## Prerequisites

- **Git** -- For cloning and keeping skills updated
- **A supported AI coding agent** -- Claude Code, Cursor, Windsurf, Cline, or any agent with custom instructions
- **Terminal access** -- Required only if you want to use automation scripts

---

## Installation

### Method A: Copy (simplest)

```bash
git clone https://github.com/boxclaw/boxclaw-skills.git

# Copy specific skills to your project
cp -r boxclaw-skills/frontend-developer /path/to/project/.skills/
cp -r boxclaw-skills/backend-developer /path/to/project/.skills/

# Or copy everything
mkdir -p /path/to/project/.skills
cp -r boxclaw-skills/* /path/to/project/.skills/
```

### Method B: Symlink (easy updates)

```bash
git clone https://github.com/boxclaw/boxclaw-skills.git ~/boxclaw-skills

# Symlink individual skills
ln -s ~/boxclaw-skills/frontend-developer /path/to/project/.skills/frontend-developer
ln -s ~/boxclaw-skills/backend-developer /path/to/project/.skills/backend-developer
```

Update with `cd ~/boxclaw-skills && git pull`.

### Method C: Git submodule (version-controlled)

```bash
cd /path/to/project
git submodule add https://github.com/boxclaw/boxclaw-skills.git .skills/boxclaw-skills
git commit -m "chore: add boxclaw-skills as submodule"
```

Team members get skills automatically with:

```bash
git submodule update --init --recursive
```

---

## Claude Code

Claude Code reads project instructions from `CLAUDE.md` and the `.claude/` directory.

### Method A: CLAUDE.md (recommended)

Create or edit `CLAUDE.md` in your project root:

```markdown
# Project Instructions

## Skills

This project uses BoxClaw Skills for expert guidance. Load the appropriate
skill based on the task at hand:

### Frontend Tasks
Read and follow: .skills/frontend-developer/SKILL.md
Deep references available at:
- .skills/frontend-developer/references/framework-patterns.md
- .skills/frontend-developer/references/css-recipes.md
Scripts: .skills/frontend-developer/scripts/component-generator.sh

### Backend Tasks
Read and follow: .skills/backend-developer/SKILL.md
Deep references available at:
- .skills/backend-developer/references/database-patterns.md
- .skills/backend-developer/references/api-security.md
Scripts: .skills/backend-developer/scripts/api-scaffold.sh

### DevOps Tasks
Read and follow: .skills/devops-engineer/SKILL.md
Deep references available at:
- .skills/devops-engineer/references/k8s-patterns.md
- .skills/devops-engineer/references/cicd-templates.md
- .skills/devops-engineer/references/monitoring-templates.md
```

Claude Code will automatically read CLAUDE.md at the start of every conversation and know where to find the skill files.

### Method B: .claude/ directory

Use Claude Code's project commands feature:

```
.claude/
├── settings.json
└── commands/
    ├── frontend.md    # "Load frontend-developer skill from .skills/"
    ├── backend.md     # "Load backend-developer skill from .skills/"
    └── devops.md      # "Load devops-engineer skill from .skills/"
```

Each command file instructs Claude to read the corresponding SKILL.md and apply its patterns.

### Method C: Inline (single skill)

For projects that only need one skill, paste the SKILL.md body directly into CLAUDE.md:

```markdown
# Project Instructions

## Coding Standards

[Paste the markdown body of frontend-developer/SKILL.md here,
everything below the --- frontmatter closing]
```

### Using Scripts with Claude Code

Claude Code can execute scripts directly. Reference them in your CLAUDE.md:

```markdown
## Available Scripts

When scaffolding a new React component, run:
  .skills/frontend-developer/scripts/component-generator.sh <ComponentName>

When generating API resources, run:
  .skills/backend-developer/scripts/api-scaffold.sh <resource-name>
```

### Verification

Test your setup by asking Claude Code:

```
> Read the frontend-developer skill and summarize its core competencies.
> Generate a React component called UserProfile using the component-generator script.
> What security patterns should I follow for this Express API? Check the backend skill.
```

---

## Cursor

Cursor supports custom instructions via `.cursorrules` files and the Settings panel.

### Method A: .cursorrules file (recommended)

Create `.cursorrules` in your project root:

```
You are a senior full-stack developer. Follow these expert patterns and conventions
for all code you write and review.

## Frontend Development

[Paste the body of frontend-developer/SKILL.md here]

## Backend Development

[Paste the body of backend-developer/SKILL.md here]
```

Cursor reads `.cursorrules` automatically for every conversation in the project.

### Method B: Settings > Rules for AI

1. Open Cursor Settings (`Cmd+,` or `Ctrl+,`)
2. Navigate to **Rules for AI**
3. Under **Project Rules**, add the skill content
4. Save

This method is useful for adding rules without committing files to the repo.

### Method C: @docs context

1. Open Cursor Settings > **Features > Docs**
2. Add the skill files as indexed documentation:
   - Path: `.skills/frontend-developer/SKILL.md`
   - Path: `.skills/frontend-developer/references/framework-patterns.md`
3. In chat, reference with `@docs` to pull in skill knowledge

### Combining Skills in Cursor

Keep `.cursorrules` focused. For multi-skill setups, use a role-switching header:

```
When working on frontend code (React, CSS, components):
Follow the frontend-developer patterns.

When working on API routes, services, or database:
Follow the backend-developer patterns.

When working on Docker, CI/CD, or deployment:
Follow the devops-engineer patterns.

[Then include the most critical sections from each skill]
```

### Verification

Test by asking Cursor:

```
> Write a React component with proper typing, CSS modules, and tests.
> Create a REST endpoint for managing products with Zod validation.
> Review this code for security issues based on OWASP guidelines.
```

---

## Windsurf

Windsurf uses `.windsurfrules` for project-level custom instructions.

### Method A: .windsurfrules file

Create `.windsurfrules` in your project root:

```
You are a senior developer. Follow these expert patterns:

## Frontend

[Paste frontend-developer/SKILL.md body]

## Backend

[Paste backend-developer/SKILL.md body]
```

### Method B: Cascade rules

1. Open Windsurf's Cascade panel
2. Navigate to **Rules** or **Instructions**
3. Add skill content as persistent rules
4. These apply to all Cascade conversations in the project

### Verification

```
> Build a Vue component following best practices from the skill instructions.
> Set up a CI/CD pipeline using the devops patterns.
```

---

## Cline

Cline supports custom instructions via `.clinerules` and the settings panel.

### Method A: .clinerules file (recommended)

Create `.clinerules` in your project root:

```
You are a senior developer. Follow these expert patterns for all tasks:

[Paste the body of your chosen SKILL.md here]
```

### Method B: VS Code Extension Settings

1. Open VS Code Settings (`Cmd+,` or `Ctrl+,`)
2. Search for "Cline"
3. Find **Custom Instructions** setting
4. Paste skill content into the instructions field

### Method C: Per-conversation instructions

When starting a Cline conversation, prefix your request:

```
Use the expert patterns from this skill:
[Paste relevant sections of the SKILL.md]

Now help me: [your actual request]
```

### Verification

```
> Generate a database migration following zero-downtime patterns.
> Set up Playwright E2E tests for the login flow.
```

---

## Generic / Other Agents

For any AI agent that accepts custom instructions (Aider, Continue, GitHub Copilot Chat, OpenAI Codex CLI, or custom agents):

### System Prompt Wrapper

Use this template to wrap any skill into a system prompt:

```
You are an expert [role name] AI assistant. Your expertise is defined by
the following skill module. Follow its patterns, conventions, and best
practices in all code you write, review, or suggest.

---

[Paste the full SKILL.md body here - everything below the YAML frontmatter]

---

When you need deeper knowledge on a specific topic, ask the user to provide
the relevant reference document from the skill's references/ directory.

Available references:
- references/[topic-a].md -- [brief description]
- references/[topic-b].md -- [brief description]
```

### Aider

Add to `.aider.conf.yml`:

```yaml
read:
  - .skills/frontend-developer/SKILL.md
  - .skills/backend-developer/SKILL.md
```

### Continue

Add to `.continuerc.json`:

```json
{
  "systemMessage": "[Paste SKILL.md body here]"
}
```

---

## Combining Multiple Skills

### Strategy 1: Role-based loading (recommended)

Load one skill at a time based on the current task. This is the most token-efficient approach.

```markdown
# CLAUDE.md

When the user asks about frontend/UI work:
  Read .skills/frontend-developer/SKILL.md

When the user asks about API/backend work:
  Read .skills/backend-developer/SKILL.md

When the user asks about deployment/infrastructure:
  Read .skills/devops-engineer/SKILL.md
```

### Strategy 2: Composite skill

Extract the most important sections from 2-3 skills into a single document:

```markdown
# .cursorrules (composite)

## Frontend Patterns
[Key sections from frontend-developer/SKILL.md]

## API Patterns
[Key sections from backend-developer/SKILL.md]

## Testing Standards
[Key sections from qa-test-engineer/SKILL.md]
```

Keep it under 500 lines to avoid context bloat.

### Strategy 3: Dispatcher pattern

Create a meta-instruction that routes to the right skill:

```markdown
# CLAUDE.md

You have access to these expert skills in .skills/:
1. frontend-developer -- React/Vue/CSS/a11y
2. backend-developer -- API/auth/database
3. devops-engineer -- CI/CD/Docker/K8s
4. qa-test-engineer -- testing/Playwright/load

For each task, identify the most relevant skill, read its SKILL.md,
and follow its patterns. If a task spans multiple domains, read
the primary skill first, then consult others as needed.
```

### Context Budget Tips

| Content | Approximate Tokens | When to Load |
|---------|-------------------|--------------|
| SKILL.md body | 800-1,500 | Always (per task) |
| One reference doc | 2,000-8,000 | When deep knowledge needed |
| All references for one skill | 5,000-15,000 | Rarely -- pick the relevant one |

Rule of thumb: Load 1 SKILL.md + 1 reference at a time.

---

## Advanced Configuration

### Team Standardization

Share skills across your team using git submodules:

```bash
# In your team's project template
git submodule add https://github.com/boxclaw/boxclaw-skills.git .skills/boxclaw

# Create a CLAUDE.md that references the submodule
echo 'Load skills from .skills/boxclaw/ based on the task.' > CLAUDE.md

# Commit and push -- every team member gets the same skills
git add .gitmodules .skills CLAUDE.md
git commit -m "chore: add shared boxclaw skills"
```

### Custom Skill Registry

For teams with many custom skills, create an index:

```
.skills/
├── boxclaw/              # Third-party skills (git submodule)
│   ├── frontend-developer/
│   ├── backend-developer/
│   └── ...
├── team/                 # Team-specific skills
│   ├── our-api-standards/
│   └── deploy-playbook/
└── SKILLS.md             # Index of all available skills
```

### Override Patterns

Layer team conventions on top of boxclaw skills:

```markdown
# CLAUDE.md

## Base Skills
Read .skills/boxclaw/backend-developer/SKILL.md for general patterns.

## Team Overrides
- We use Drizzle ORM, not Prisma
- All APIs use the /v1/ prefix
- Authentication uses our internal SSO library
- Database migrations go through the DBA team review
```

---

## Troubleshooting

### "Agent doesn't seem to use the skill"

1. **Verify file location** -- Ensure the skill files are in the path referenced by your configuration
2. **Check loading** -- Ask the agent: "What instructions or skills have you loaded?"
3. **Be explicit** -- Some agents need explicit mention: "Follow the frontend-developer skill patterns"
4. **Check file size** -- If the combined instructions exceed the agent's context window, trim to essential sections

### "Too many tokens / context overflow"

- Load only 1 SKILL.md at a time (not all 13)
- Use references on demand, not upfront
- Use the composite strategy: extract key sections only
- Consider the dispatcher pattern for multi-skill projects

### "Scripts don't execute"

```bash
# Check permissions
chmod +x .skills/frontend-developer/scripts/*.sh

# Check shell compatibility (scripts require bash 4+)
bash --version

# Run manually to see errors
bash -x .skills/frontend-developer/scripts/component-generator.sh MyComponent
```

### "Skill doesn't match my stack"

Skills are starting points. Customize them:

1. Edit the SKILL.md to match your stack
2. Add team-specific references
3. Modify the `description` field for better trigger matching
4. Remove irrelevant sections to reduce noise

---

## Verification Checklist

After setup, verify your integration works with these test prompts:

| Agent | Test Prompt | Expected Behavior |
|-------|-------------|-------------------|
| Claude Code | "Read the frontend skill and summarize it" | Agent reads and summarizes SKILL.md |
| Claude Code | "Generate a React component called Card" | Uses component-generator.sh patterns |
| Cursor | "Create a REST API for managing users" | Follows backend skill patterns (Zod, pagination, proper error handling) |
| Windsurf | "Review this code for security issues" | References OWASP patterns from security skill |
| Cline | "Write E2E tests for the login page" | Uses Playwright patterns from qa-test skill |
| Any agent | "What's the best database index strategy for this query?" | References index strategy from dba skill |

If the agent produces generic code without following the skill patterns, double-check that the skill content is properly loaded into the agent's context.
