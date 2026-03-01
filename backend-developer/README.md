# :wrench: Backend Developer

> Backend development expert covering API design (REST/GraphQL/gRPC), database integration, authentication/authorization, server architecture, caching, message queues, and microservices patterns.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies** -- API Design, Authentication & Authorization, Database Strategy, Caching Strategy, Error Handling, Security Checklist
- **Architecture Patterns** -- Monolith, Modular Monolith, Microservices, Serverless, and communication strategies (sync, async, event-driven)
- **References** -- Links to included reference documents

### References
| File | Description | Lines |
|------|-------------|-------|
| [database-patterns.md](references/database-patterns.md) | Database patterns reference covering repository pattern and more | 577 |
| [api-security.md](references/api-security.md) | API security reference covering authentication implementation and best practices | 798 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [migration-helper.sh](scripts/migration-helper.sh) | Safe database migration workflow with multiple actions | `./scripts/migration-helper.sh <action> [args]` |
| [api-scaffold.sh](scripts/api-scaffold.sh) | Generate REST API resource scaffolding (route, service, validation, tests) | `./scripts/api-scaffold.sh <resource-name> [--dir src] [--orm prisma\|drizzle]` |

## Tags
`api` `rest` `graphql` `grpc` `nodejs` `python` `go` `authentication` `database` `redis` `microservices`

## Quick Start

```bash
# Copy this skill to your project
cp -r backend-developer/ /path/to/project/.skills/

# Scaffold a new API resource
.skills/backend-developer/scripts/api-scaffold.sh users --orm prisma

# Run a safe database migration
.skills/backend-developer/scripts/migration-helper.sh migrate
```

## Part of [BoxClaw Skills](../)
