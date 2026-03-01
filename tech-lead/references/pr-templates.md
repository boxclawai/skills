# Pull Request Templates & Conventions

A comprehensive collection of PR templates, size guidelines, commit conventions, branching strategies, and merge policies for engineering teams.

---

## Table of Contents

1. [Feature PR Template](#feature-pr-template)
2. [Bug Fix PR Template](#bug-fix-pr-template)
3. [Refactoring PR Template](#refactoring-pr-template)
4. [Dependency Update PR Template](#dependency-update-pr-template)
5. [Hotfix PR Template](#hotfix-pr-template)
6. [PR Size Guidelines](#pr-size-guidelines)
7. [Conventional Commit Format](#conventional-commit-format)
8. [Branch Naming Conventions](#branch-naming-conventions)
9. [Merge Strategies](#merge-strategies)

---

## Feature PR Template

```markdown
## Summary

<!-- Provide a concise description of the feature. Link the tracking issue/ticket. -->

**Ticket:** [PROJ-1234](https://tracker.example.com/PROJ-1234)
**Epic:** <!-- Link to parent epic if applicable -->

### What does this PR do?

<!-- Describe the feature in 2-3 sentences. Focus on the "what" and "why", not the "how". -->

### Why is this change needed?

<!-- Business context, user problem being solved, or technical motivation. -->

---

## Design Decisions

<!-- Document any significant architectural or design decisions made during implementation. -->

- **Decision 1:** Chose X over Y because...
- **Decision 2:** ...

### Alternatives Considered

<!-- Briefly describe alternatives you evaluated and why they were rejected. -->

---

## Changes

<!-- High-level breakdown of changes by area. -->

- [ ] API changes (new endpoints, modified contracts)
- [ ] Database schema changes (migrations included)
- [ ] UI/UX changes
- [ ] Configuration changes
- [ ] New dependencies added

### Files Changed Overview

| Area | Files | Description |
|------|-------|-------------|
| API | `src/api/...` | New endpoint for... |
| Models | `src/models/...` | Added field... |
| Tests | `tests/...` | Unit + integration tests |

---

## Testing

### Automated Tests

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated (if applicable)
- [ ] All existing tests pass

### Manual Testing Checklist

- [ ] Tested happy path for primary use case
- [ ] Tested edge cases: empty input, max length, special characters
- [ ] Tested error handling and error messages
- [ ] Tested with different user roles/permissions
- [ ] Tested on required browsers/devices (if frontend)
- [ ] Tested backward compatibility with existing data
- [ ] Tested feature flag on/off states (if applicable)

### Performance

- [ ] No N+1 queries introduced
- [ ] Checked query execution plans for new queries
- [ ] Load tested (if applicable): results at _____ RPS
- [ ] No memory leaks detected

---

## Screenshots / Recordings

<!-- Include before/after screenshots for UI changes. Use screen recordings for interactive features. -->

### Before

<!-- Screenshot or "N/A" -->

### After

<!-- Screenshot or "N/A" -->

---

## Deployment Notes

- [ ] Feature flag: `flag_name` (default: off)
- [ ] Database migration required (reversible: yes/no)
- [ ] Environment variables added: `VAR_NAME`
- [ ] Cache invalidation needed
- [ ] Runbook updated
- [ ] Documentation updated

### Rollback Plan

<!-- Describe how to roll back this change if issues are detected post-deploy. -->

---

## Reviewer Notes

<!-- Anything specific you want reviewers to focus on or be aware of. -->

**Estimated review time:** ~XX minutes
```

---

## Bug Fix PR Template

```markdown
## Bug Fix

**Ticket:** [BUG-5678](https://tracker.example.com/BUG-5678)
**Severity:** Critical / High / Medium / Low
**Reported by:** <!-- Customer, internal QA, monitoring alert, etc. -->
**Environment:** Production / Staging / Development

---

## Bug Description

<!-- What is the observed behavior? Include error messages, logs, or stack traces. -->

### Steps to Reproduce

1. Go to...
2. Click on...
3. Observe...

### Expected Behavior

<!-- What should happen instead? -->

### Actual Behavior

<!-- What currently happens? Include error messages verbatim. -->

---

## Root Cause Analysis

<!-- Explain WHY the bug occurred. Be specific about the code path that caused the issue. -->

**Root Cause:** <!-- e.g., Race condition in session validation when concurrent requests arrive within the same millisecond window. The session cache TTL was set to 0ms in the connection pool configuration, causing every request to re-authenticate. -->

**Introduced in:** <!-- Commit SHA or PR number where the bug was introduced, if known. -->

---

## Fix Description

<!-- Explain the approach taken to fix the bug and why this approach was chosen. -->

### Changes Made

- `file1.py`: Description of change
- `file2.py`: Description of change

### Why This Fix

<!-- Justify the approach. Why not a different fix? -->

---

## Regression Testing

- [ ] Added regression test that reproduces the original bug
- [ ] Regression test fails without the fix applied
- [ ] Regression test passes with the fix applied
- [ ] Existing test suite passes
- [ ] Tested related functionality for side effects

### Test Case Details

```
Test: test_session_validation_concurrent_requests
Scenario: Two requests arrive within 1ms window
Expected: Both requests use valid sessions
Result: PASS (was FAIL before fix)
```

---

## Impact Assessment

- **Users affected:** <!-- Number or percentage -->
- **Duration of impact:** <!-- How long was this bug live? -->
- **Data impact:** <!-- Was any data corrupted? Is remediation needed? -->
- **Monitoring:** <!-- Are there alerts that would catch recurrence? -->

---

## Screenshots / Evidence

### Before Fix (Bug Present)

<!-- Screenshot showing the bug -->

### After Fix (Bug Resolved)

<!-- Screenshot showing correct behavior -->

---

## Deployment Notes

- [ ] Safe to deploy during business hours
- [ ] Requires coordinated deployment with other services
- [ ] Data migration/fix script needed
- [ ] Customer communication needed
```

---

## Refactoring PR Template

```markdown
## Refactoring

**Ticket:** [TECH-9012](https://tracker.example.com/TECH-9012)
**Type:** Code cleanup / Architecture improvement / Performance optimization / Tech debt reduction

---

## Motivation

<!-- Why is this refactoring needed now? What technical debt does it address? -->

### Current Problems

- Problem 1: e.g., Module has grown to 2000+ lines, making it hard to navigate
- Problem 2: e.g., Circular dependencies between X and Y
- Problem 3: e.g., Duplicated logic across 5 handlers

### Expected Benefits

- Benefit 1: e.g., Reduced cognitive load for developers working in this area
- Benefit 2: e.g., Easier to add new payment providers
- Benefit 3: e.g., 30% reduction in test execution time

---

## Approach

<!-- Describe the refactoring strategy. Reference any design patterns applied. -->

### Before (Structure)

```
src/
  monolith_handler.py  (2000 lines)
```

### After (Structure)

```
src/
  handlers/
    auth.py
    payments.py
    notifications.py
  shared/
    validators.py
```

---

## Behavioral Guarantee

<!-- This is the most critical section for refactoring PRs. -->

- [ ] **No behavioral changes** -- this PR is purely structural
- [ ] All inputs produce identical outputs before and after
- [ ] API contracts unchanged (request/response schemas identical)
- [ ] Database queries produce identical results
- [ ] Error handling behavior preserved
- [ ] Logging output equivalent (or improved with no loss)

### Verification Method

<!-- How did you verify behavior is unchanged? -->

- [ ] Ran full test suite: all tests pass without modification
- [ ] Compared API responses before/after using snapshot testing
- [ ] Ran integration tests against staging environment
- [ ] Verified with production traffic replay (if applicable)

---

## Changes Summary

| Change Type | Count | Description |
|-------------|-------|-------------|
| Files moved | X | Reorganized into modules |
| Files split | X | Large files broken down |
| Files merged | X | Consolidated duplicates |
| Renamed | X | Improved naming |
| Deleted | X | Removed dead code |

---

## Risk Assessment

- **Risk Level:** Low / Medium / High
- **Blast Radius:** <!-- What could break if something goes wrong? -->
- **Rollback Complexity:** Simple revert / Requires migration rollback / Complex

---

## Reviewer Guidance

<!-- Help reviewers focus on the right things for a refactoring PR. -->

Focus areas:
1. Verify no behavioral changes were introduced
2. Review the new structure for clarity and maintainability
3. Check that all references/imports are updated
4. Validate naming conventions are consistent

**Tip:** Use `git diff --stat` to see the full scope, then review file-by-file.
```

---

## Dependency Update PR Template

```markdown
## Dependency Update

**Type:** Security patch / Minor update / Major upgrade / Transitive dependency
**Urgency:** Critical (CVE) / High / Routine

---

## Dependencies Updated

| Package | From | To | Type | Reason |
|---------|------|----|------|--------|
| `lodash` | 4.17.20 | 4.17.21 | patch | CVE-2021-23337 |
| `react` | 18.2.0 | 18.3.0 | minor | New features |
| `webpack` | 5.88.0 | 5.90.0 | minor | Bug fixes |

---

## Security Advisories

<!-- List any CVEs or security advisories addressed by this update. -->

| CVE | Severity | Package | Description |
|-----|----------|---------|-------------|
| CVE-2021-23337 | High | lodash | Command injection via template |

---

## Changelog Review

<!-- Summarize relevant changes from dependency changelogs. -->

### Breaking Changes

- [ ] No breaking changes in any updated packages
- [ ] Breaking changes identified and addressed (see below)

### Notable Changes

- Package X: Added support for...
- Package Y: Deprecated method `foo()`, replaced with `bar()`

---

## Compatibility Verification

- [ ] Application builds successfully
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] E2E tests pass
- [ ] No new deprecation warnings introduced
- [ ] Peer dependency requirements satisfied
- [ ] Lock file (`package-lock.json` / `yarn.lock` / `poetry.lock`) updated
- [ ] No unintended transitive dependency changes

### Dependency Tree Diff

```
# Include output of relevant diff command, e.g.:
# npm ls --depth=1
# pip list --format=columns
```

---

## Rollback Plan

<!-- How to revert if the update causes issues. -->

1. Revert this PR
2. Run `npm install` / `pip install -r requirements.txt`
3. Verify application starts correctly
```

---

## Hotfix PR Template

```markdown
## HOTFIX

**Incident:** [INC-3456](https://tracker.example.com/INC-3456)
**Severity:** SEV-1 / SEV-2
**On-call:** @engineer_name
**Approved by:** @tech_lead_name

---

## Incident Summary

<!-- One-paragraph summary of the production incident this hotfix addresses. -->

**Impact:** <!-- e.g., 15% of users unable to complete checkout for 45 minutes -->
**Started:** YYYY-MM-DD HH:MM UTC
**Detected:** YYYY-MM-DD HH:MM UTC (detection latency: X minutes)

---

## Hotfix Description

<!-- What does this change do? Keep it minimal and focused. -->

### Changes

- `file.py` line XX: Changed VALUE_A to VALUE_B because...

### What This Does NOT Fix

<!-- Explicitly state what is out of scope for this hotfix. -->

- Long-term fix tracked in [PROJ-9999](https://tracker.example.com/PROJ-9999)

---

## Verification

- [ ] Fix verified in staging
- [ ] Fix verified with production-like data
- [ ] Monitoring dashboards checked
- [ ] Rollback tested

### Quick Smoke Test

```bash
# Command(s) to verify the fix works
curl -X GET https://api.example.com/health
# Expected: 200 OK
```

---

## Deployment Plan

1. Merge this PR to `hotfix/incident-3456`
2. Cherry-pick to `main` / `release` branch
3. Deploy to canary (5% traffic)
4. Monitor for 10 minutes
5. Full rollout
6. Confirm metrics normalize

---

## Post-Incident

- [ ] Postmortem scheduled: YYYY-MM-DD
- [ ] Long-term fix ticket created
- [ ] Monitoring/alerting improvements identified
```

---

## PR Size Guidelines

Keeping PRs small improves review quality, reduces risk, and accelerates delivery.

### Size Categories

| Size | Lines Changed | Review Time | Risk |
|------|--------------|-------------|------|
| **XS** | 1-10 | 5 min | Minimal |
| **S** | 11-100 | 15 min | Low |
| **M** | 101-300 | 30 min | Moderate |
| **L** | 301-500 | 60 min | High |
| **XL** | 500+ | 90+ min | Very High |

### Best Practices

1. **Target S-M size PRs** (under 300 lines changed). Research shows reviewer effectiveness drops sharply above 400 lines.

2. **Split large features using stacking:**
   - PR 1: Database schema + migrations
   - PR 2: API models and repository layer
   - PR 3: Business logic and service layer
   - PR 4: API endpoints and integration tests
   - PR 5: Frontend UI components

3. **Exclude from line counts:** Generated files, lock files, snapshots, vendored code, and large test fixtures.

4. **One concern per PR:** Do not mix refactoring with feature work. Do not mix dependency updates with code changes. Do not mix formatting with logic changes.

5. **If a PR is unavoidably large:** Add a PR description with a suggested review order, call out the most critical sections, and consider scheduling a walkthrough with the reviewer.

### Automated Size Labels

```yaml
# .github/labeler.yml (for GitHub Actions)
size/XS:
  - changed-files:
    - any-glob-to-any-file: '**/*'
      all-globs-to-all-files: '!**/*.lock'
    - count: {less-than: 11}

size/S:
  - changed-files:
    - count: {greater-than: 10, less-than: 101}

size/M:
  - changed-files:
    - count: {greater-than: 100, less-than: 301}

size/L:
  - changed-files:
    - count: {greater-than: 300, less-than: 501}

size/XL:
  - changed-files:
    - count: {greater-than: 500}
```

---

## Conventional Commit Format

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | Description | SemVer | Example |
|------|-------------|--------|---------|
| `feat` | New feature | MINOR | `feat(auth): add OAuth2 PKCE flow` |
| `fix` | Bug fix | PATCH | `fix(cart): correct tax calculation for EU` |
| `docs` | Documentation only | - | `docs(api): update rate limit documentation` |
| `style` | Formatting, semicolons, etc. | - | `style: apply prettier formatting` |
| `refactor` | Neither fix nor feature | - | `refactor(db): extract query builder` |
| `perf` | Performance improvement | PATCH | `perf(search): add index on user_email` |
| `test` | Adding/correcting tests | - | `test(auth): add login edge case tests` |
| `build` | Build system changes | - | `build: upgrade webpack to v5` |
| `ci` | CI configuration | - | `ci: add parallel test execution` |
| `chore` | Maintenance tasks | - | `chore: update .gitignore` |
| `revert` | Reverts a commit | varies | `revert: feat(auth): add OAuth2 PKCE flow` |

### Rules

1. **Subject line:** Imperative mood, lowercase, no period, max 72 characters.
2. **Body:** Wrapped at 72 characters. Explain "what" and "why", not "how".
3. **Breaking changes:** Add `!` after type/scope and `BREAKING CHANGE:` in footer.
4. **Issue references:** Use `Closes #123`, `Fixes #456`, `Refs #789` in the footer.

### Examples

```
feat(payments)!: migrate to Stripe Payment Intents API

Replace legacy Charges API with Payment Intents to support SCA
requirements for European customers. The checkout flow now uses
client-side confirmation with 3D Secure support.

BREAKING CHANGE: PaymentService.charge() signature changed.
First argument is now a PaymentIntent object instead of amount.

Closes #1234
```

```
fix(api): prevent duplicate webhook deliveries

Add idempotency key check before processing incoming webhooks.
Previously, retried webhooks could trigger duplicate order
processing when the original response timed out but succeeded.

Fixes #5678
```

---

## Branch Naming Conventions

### Format

```
<type>/<ticket-id>-<short-description>
```

### Types

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feature/` | New features | `feature/PROJ-123-user-avatars` |
| `fix/` | Bug fixes | `fix/BUG-456-login-timeout` |
| `hotfix/` | Production hotfixes | `hotfix/INC-789-payment-crash` |
| `refactor/` | Code refactoring | `refactor/TECH-012-split-user-module` |
| `docs/` | Documentation | `docs/API-345-openapi-spec` |
| `test/` | Test additions | `test/QA-678-e2e-checkout` |
| `chore/` | Maintenance | `chore/DEP-901-upgrade-node-20` |
| `experiment/` | Spikes/POCs | `experiment/eval-graphql` |
| `release/` | Release branches | `release/v2.4.0` |

### Rules

1. Use lowercase with hyphens (kebab-case). No underscores, no camelCase.
2. Include the ticket ID for traceability.
3. Keep descriptions short (2-4 words).
4. Delete branches after merge.
5. Never commit directly to `main` or `develop`.

---

## Merge Strategies

### Strategy Comparison

| Strategy | History | Best For | Avoid When |
|----------|---------|----------|------------|
| **Squash merge** | Linear, clean | Feature branches with messy WIP commits | You need to preserve individual commit context |
| **Merge commit** | Preserves topology | Long-lived branches, release branches | Small PRs where extra merge commits add noise |
| **Rebase + fast-forward** | Linear, detailed | Clean commit history with meaningful commits | Shared branches with multiple contributors |

### Squash Merge

```bash
# GitHub: "Squash and merge" button
# CLI equivalent:
git checkout main
git merge --squash feature/PROJ-123-user-avatars
git commit  # Write a clean, comprehensive commit message
```

**When to use:**
- Feature branches with "WIP", "fixup", "oops" commits
- Small-to-medium PRs (1-5 commits that tell one story)
- When individual commits don't add value to the history

**Commit message:** Use the PR title and description. Reference the PR number.

### Merge Commit (No Fast-Forward)

```bash
git checkout main
git merge --no-ff feature/PROJ-123-user-avatars
```

**When to use:**
- Release branches merging into main
- Long-lived feature branches where commit history tells a valuable story
- When you want to see branch topology in `git log --graph`

### Rebase and Fast-Forward

```bash
git checkout feature/PROJ-123-user-avatars
git rebase main
git checkout main
git merge --ff-only feature/PROJ-123-user-avatars
```

**When to use:**
- Each commit is atomic, tested, and has a clear message
- Developers maintain clean history during development
- Teams that value a perfectly linear history

**Warning:** Never rebase commits that have been pushed to a shared branch.

### Recommended Team Policy

```
main branch protection rules:
  - Require PR with at least 1 approval
  - Require status checks to pass
  - Require linear history (squash or rebase only)
  - Require branches to be up to date before merging
  - Auto-delete branches after merge

Default merge method: Squash merge
Exception: Release branches use merge commits
```

### Decision Flowchart

```
Is this a release branch merge?
  YES --> Merge commit (preserve release history)
  NO  --> Does each commit represent a meaningful, tested change?
            YES --> Rebase + fast-forward
            NO  --> Squash merge
```
