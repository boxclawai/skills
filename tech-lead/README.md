# :necktie: Tech Lead

> Tech lead and engineering management expert covering code review best practices, PR management, sprint planning, technical decision-making, team mentoring, coding standards, technical debt management, incident response, and engineering metrics.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies**
  - Code Review Framework (priorities, PR review template, etiquette)
  - Coding Standards (conventions, enforcement with tools)
  - Technical Debt Management (categorize, track, budget, prevent)
  - Sprint Planning & Estimation (T-shirt sizing, story points, health checks)
  - Incident Response (severity levels, during-incident process, blameless postmortems)
  - Engineering Metrics (DORA: deployment frequency, lead time, change failure rate, MTTR)
  - Build vs Buy Decision framework
- **Workflow** -- Weekly, monthly, and quarterly leadership cadence

### References
| File | Description | Lines |
|------|-------------|-------|
| [pr-templates.md](references/pr-templates.md) | Comprehensive collection of PR templates, size guidelines, commit conventions, branching strategies, and merge policies | 741 |
| [postmortem-template.md](references/postmortem-template.md) | Framework for conducting blameless postmortems, documenting incidents, and driving systematic improvement | 604 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [pr-stats.sh](scripts/pr-stats.sh) | Pull request and team engineering metrics collector | `./scripts/pr-stats.sh [--repo owner/repo] [--days 30] [--team user1,user2]` |

## Tags
`code-review` `sprint-planning` `tech-debt` `dora-metrics` `incident-response` `mentoring` `standards`

## Quick Start

```bash
# Copy this skill to your project
cp -r tech-lead/ /path/to/project/.skills/

# Get PR stats for your repo over the last 30 days
.skills/tech-lead/scripts/pr-stats.sh --repo myorg/myrepo --days 30
```

## Part of [BoxClaw Skills](../)
