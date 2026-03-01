---
name: tech-lead
version: "1.0.0"
description: "Tech lead and engineering management expert: code review best practices, PR management, sprint planning, technical decision-making, team mentoring, coding standards, technical debt management, incident response, engineering metrics, and cross-team coordination. Use when: (1) reviewing pull requests, (2) establishing coding standards or conventions, (3) planning sprints or estimating work, (4) managing technical debt, (5) conducting incident postmortems, (6) mentoring developers, (7) making build-vs-buy decisions. NOT for: writing implementation code, infrastructure setup, or HR/people management."
tags: [code-review, sprint-planning, tech-debt, dora-metrics, incident-response, mentoring, standards]
author: "boxclaw"
references:
  - references/pr-templates.md
  - references/postmortem-template.md
metadata:
  boxclaw:
    emoji: "👔"
    category: "programming-role"
---

# Tech Lead

Expert guidance for technical leadership, code quality, and team engineering practices.

## Core Competencies

### 1. Code Review Framework

#### Review Priorities (in order)

```
1. Correctness:   Does it work? Edge cases handled?
2. Security:      Input validation, auth, injection risks?
3. Design:        Right abstraction level? SOLID principles?
4. Performance:   O(n²) loops? N+1 queries? Memory leaks?
5. Readability:   Clear naming, reasonable complexity?
6. Tests:         Sufficient coverage? Right test level?
7. Style:         Automate this (linter/formatter)
```

#### PR Review Template

```markdown
## Summary
[1-2 sentences on what this PR does and why]

## Review Notes

### Must Fix
- [ ] [Critical issue that blocks merge]

### Should Fix
- [ ] [Important improvement for quality]

### Consider
- [ ] [Suggestion, not blocking]

### Praise
- [Something done well worth highlighting]

## Testing
- [ ] Unit tests cover new logic
- [ ] Tested manually: [scenario]
- [ ] Edge cases considered: [which ones]
```

#### Review Etiquette

```
DO:
  - Review within 24 hours (4 hours for small PRs)
  - Explain WHY, not just what to change
  - Suggest concrete alternatives with code
  - Approve with minor nits (trust author to fix)
  - Praise good work publicly

DON'T:
  - Block on style preferences (use automated tools)
  - Rewrite the author's approach (discuss first)
  - Leave ambiguous feedback ("this could be better")
  - Review while emotional or rushed
  - Pile on (one reviewer per concern is enough)
```

### 2. Coding Standards

#### Establishing Conventions

```
Document decisions, not preferences:
  ✓ "Use named exports for utilities, default for components"
  ✓ "Error responses follow { error: { code, message } } format"
  ✗ "Use semicolons" (just configure the formatter)

Enforce with tools, not reviews:
  Formatting   → Prettier/oxfmt (zero discussion)
  Linting      → ESLint/oxlint (catch patterns)
  Types        → TypeScript strict mode
  Commits      → Conventional Commits + commitlint
  PRs          → PR template + size limits

Write them down:
  CONTRIBUTING.md   → How to contribute
  .editorconfig     → Editor settings
  ADR/              → Architecture decisions
```

### 3. Technical Debt Management

```
Categorize:
  Critical:  Actively causing bugs or security issues
  High:      Slowing development significantly
  Medium:    Increasing complexity, future risk
  Low:       Cosmetic, minor inconsistencies

Track:
  - Maintain tech debt backlog (separate from features)
  - Tag debt items: [security], [performance], [maintainability]
  - Estimate payoff: "Fixing X saves Y hours/week"

Budget:
  - Allocate 15-20% of sprint capacity to debt reduction
  - "Boy Scout Rule": Leave code better than you found it
  - Tackle debt adjacent to feature work (natural refactoring)
  - Schedule "debt sprints" quarterly for larger items

Prevent:
  - ADRs for major decisions (avoid accidental debt)
  - Definition of Done includes "no new debt without ticket"
  - Refactoring PRs welcome anytime
```

### 4. Sprint Planning & Estimation

```
Estimation Approach:
  T-shirt sizing for roadmap (S/M/L/XL)
  Story points for sprints (Fibonacci: 1,2,3,5,8,13)
  Time-box research spikes (max 2 days)

Sizing Guide:
  1 point:  Config change, small bug fix, copy update
  2 points: Simple feature, straightforward logic
  3 points: Feature with some complexity, new API endpoint
  5 points: Feature spanning multiple files/services
  8 points: Large feature, needs design discussion
  13 points: Epic, should be broken down further

Sprint Health Checks:
  Velocity:     Consistent (±20%) over 4 sprints
  Carryover:    < 15% of points carry to next sprint
  Bug ratio:    < 20% of sprint work is bug fixes
  Debt work:    15-20% of capacity on tech debt
```

### 5. Incident Response

```
Severity Levels:
  SEV1: Service down, all users affected → 15min response
  SEV2: Major feature broken, many users → 30min response
  SEV3: Minor feature degraded, some users → 4h response
  SEV4: Cosmetic issue, workaround exists → Next sprint

During Incident:
  1. Acknowledge (who is leading)
  2. Assess severity and blast radius
  3. Communicate to stakeholders
  4. Mitigate (rollback, feature flag, hotfix)
  5. Monitor recovery
  6. Communicate resolution

Post-Incident (Blameless Postmortem):
  Timeline:      What happened and when
  Root Cause:    Why did it happen (5 Whys)
  Impact:        Users affected, duration, revenue
  What Worked:   Detection, response, communication
  Action Items:  Prevent recurrence (with owners + deadlines)
```

### 6. Engineering Metrics (DORA)

```
Deployment Frequency:
  Elite:  Multiple times per day
  High:   Between once per day and once per week
  Medium: Between once per week and once per month
  Low:    Less than once per month

Lead Time for Changes:
  Elite:  Less than one day
  High:   Between one day and one week
  Low:    More than one month

Change Failure Rate:
  Elite:  0-15%
  High:   16-30%
  Low:    > 45%

Mean Time to Recovery:
  Elite:  Less than one hour
  High:   Less than one day
  Low:    More than one week

How to improve:
  - Smaller PRs → faster review → faster deployment
  - Feature flags → decouple deploy from release
  - Automated testing → lower failure rate
  - Runbooks → faster recovery
```

### 7. Build vs Buy Decision

```
Build when:
  - Core differentiator for your product
  - Exact requirements with no market fit
  - Long-term strategic advantage
  - Team has domain expertise
  - Compliance requires full control

Buy when:
  - Commodity feature (auth, payments, email)
  - Time-to-market is critical
  - Vendor is proven and well-supported
  - Cost of building > 3x licensing over 3 years
  - Maintenance burden would distract from core

Evaluate:
  [ ] Total cost (license + integration + maintenance)
  [ ] Vendor lock-in risk
  [ ] Customization needed
  [ ] Team learning curve
  [ ] Exit strategy if vendor dies
```

## Workflow

```
Weekly:
  Mon: Sprint planning, PR queue triage
  Daily: Review PRs (<24h turnaround), unblock team
  Fri: Tech debt review, architecture discussions

Monthly:
  Architecture review, DORA metrics check
  1:1 mentoring sessions, standards review

Quarterly:
  Tech debt sprint, technology radar update
  Team retrospective, process improvements
```

## References

- **PR templates**: See [references/pr-templates.md](references/pr-templates.md)
- **Postmortem template**: See [references/postmortem-template.md](references/postmortem-template.md)
