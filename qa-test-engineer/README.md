# :test_tube: QA/Test Engineer

> QA and test engineering expert covering testing strategies (TDD/BDD), unit testing, integration testing, E2E testing, load testing, API testing, test automation frameworks, CI test pipelines, code coverage, and quality metrics.

## What's Included

### SKILL.md
Core expertise covering:
- Core Competencies
  - Testing Pyramid
  - Unit Testing Patterns
  - Integration Testing
  - E2E Testing (Playwright)
  - Test Strategy by Feature Type
  - Dealing with Flaky Tests
  - CI Integration
- Quick Commands
- References

### References
| File | Description | Lines |
|------|-------------|-------|
| [testing-patterns.md](references/testing-patterns.md) | Comprehensive reference for software testing patterns, strategies, and best practices across unit, integration, and end-to-end testing | 1786 |
| [load-testing.md](references/load-testing.md) | Comprehensive guide to load testing with k6, Artillery, and Grafana k6 Cloud covering test types, scripting, thresholds, and CI integration | 1495 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [test-runner.sh](scripts/test-runner.sh) | Comprehensive test runner with coverage and reporting | `./scripts/test-runner.sh [--type unit\|integration\|e2e\|all] [--coverage] [--watch] [--ci]` |

## Tags
`testing` `vitest` `jest` `playwright` `cypress` `k6` `tdd` `bdd` `e2e` `coverage` `load-testing`

## Quick Start

```bash
# Copy this skill to your project
cp -r qa-test-engineer/ /path/to/project/.skills/

# Run all tests with coverage
.skills/qa-test-engineer/scripts/test-runner.sh --type all --coverage

# Run only E2E tests in CI mode
.skills/qa-test-engineer/scripts/test-runner.sh --type e2e --ci
```

## Part of [BoxClaw Skills](../)
