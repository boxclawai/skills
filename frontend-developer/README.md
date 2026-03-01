# :art: Frontend Developer

> Frontend development expert covering React, Vue, Angular, Svelte, CSS/Tailwind, responsive design, accessibility, performance optimization, state management, and component architecture.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies** -- Component Architecture, State Management Decision Tree, CSS & Layout Strategy, Performance Checklist, Accessibility (a11y) Standards, Build & Tooling
- **Workflow** -- Step-by-step frontend development process from design review to cross-browser testing
- **References** -- Links to included reference documents

### References
| File | Description | Lines |
|------|-------------|-------|
| [framework-patterns.md](references/framework-patterns.md) | Framework patterns reference for React, Vue, and other frontend frameworks | 473 |
| [css-recipes.md](references/css-recipes.md) | CSS recipes reference including design token systems and layout patterns | 491 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [lighthouse-audit.sh](scripts/lighthouse-audit.sh) | Run Lighthouse CI audit and generate report | `./scripts/lighthouse-audit.sh <url> [--budget budget.json] [--output-dir ./reports]` |
| [component-generator.sh](scripts/component-generator.sh) | Generate React/Vue component scaffolding | `./scripts/component-generator.sh <ComponentName> [--framework react\|vue] [--dir src/components]` |

## Tags
`react` `vue` `angular` `svelte` `css` `tailwind` `accessibility` `performance` `components` `responsive`

## Quick Start

```bash
# Copy this skill to your project
cp -r frontend-developer/ /path/to/project/.skills/

# Run a Lighthouse performance audit
.skills/frontend-developer/scripts/lighthouse-audit.sh http://localhost:3000

# Generate a new component
.skills/frontend-developer/scripts/component-generator.sh MyButton --framework react
```

## Part of [BoxClaw Skills](../)
