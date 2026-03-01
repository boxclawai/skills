# :building_construction: System Architect

> System architecture expert covering high-level system design, scalability patterns, distributed systems, design patterns (GoF/DDD/CQRS/Event Sourcing), architectural decision records, trade-off analysis, capacity planning, and technology evaluation.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies**
  - Architecture Decision Framework
  - Architecture Styles
  - Scalability Patterns
  - System Design Template
  - Design Patterns (DDD, CQRS + Event Sourcing)
  - Reliability Patterns
  - Capacity Planning
- **Workflow** -- Step-by-step architecture process from requirements to team review

### References
| File | Description | Lines |
|------|-------------|-------|
| [system-design-examples.md](references/system-design-examples.md) | Production-grade system design examples for common distributed systems with requirements, architecture, data model, API design, and scale considerations | 1639 |
| [pattern-catalog.md](references/pattern-catalog.md) | Detailed implementation guide for advanced architecture patterns used in production distributed systems with problem context, solution, code, and trade-offs | 2395 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [adr-generator.sh](scripts/adr-generator.sh) | Architecture Decision Record generator with sequential numbering and standard template | `./scripts/adr-generator.sh <title> [--dir docs/adr]` |

## Tags
`architecture` `system-design` `ddd` `cqrs` `event-sourcing` `microservices` `scalability` `distributed-systems` `adr`

## Quick Start

```bash
# Copy this skill to your project
cp -r system-architect/ /path/to/project/.skills/

# Generate an Architecture Decision Record
.skills/system-architect/scripts/adr-generator.sh "Use PostgreSQL for primary data store" --dir docs/adr
```

## Part of [BoxClaw Skills](../)
