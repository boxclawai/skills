---
name: qa-test-engineer
version: "1.0.0"
description: "QA and test engineering expert: testing strategies (TDD/BDD), unit testing (Jest/Vitest/pytest), integration testing, E2E testing (Playwright/Cypress), load testing (k6/Artillery), API testing, test automation frameworks, CI test pipelines, code coverage, and quality metrics. Use when: (1) writing or reviewing tests, (2) designing test strategies for features, (3) setting up test automation, (4) debugging flaky tests, (5) implementing TDD/BDD workflows, (6) configuring test coverage and CI integration, (7) performance/load testing. NOT for: writing application business logic or UI design."
tags: [testing, vitest, jest, playwright, cypress, k6, tdd, bdd, e2e, coverage, load-testing]
author: "boxclaw"
references:
  - references/testing-patterns.md
  - references/load-testing.md
metadata:
  boxclaw:
    emoji: "🧪"
    category: "programming-role"
---

# QA/Test Engineer

Expert guidance for testing strategies, automation, and quality assurance.

## Core Competencies

### 1. Testing Pyramid

```
        /  E2E  \         Few, slow, high confidence
       / Integration \    Medium number, medium speed
      /    Unit Tests   \ Many, fast, focused
     ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

Ratio guidance: 70% unit / 20% integration / 10% E2E

Unit:        Test functions/components in isolation
Integration: Test modules working together (API + DB)
E2E:         Test user flows through real browser/app
Contract:    Verify API contracts between services
Performance: Load/stress/soak tests
```

### 2. Unit Testing Patterns

```javascript
// Vitest/Jest - Arrange-Act-Assert pattern
describe('OrderService', () => {
  it('applies discount for orders over $100', () => {
    // Arrange
    const order = createOrder({ items: [{ price: 120, qty: 1 }] });

    // Act
    const result = applyDiscount(order);

    // Assert
    expect(result.total).toBe(108); // 10% off
    expect(result.discountApplied).toBe(true);
  });

  it('throws on empty cart', () => {
    expect(() => applyDiscount(createOrder({ items: [] })))
      .toThrow('Cart is empty');
  });
});

// Test doubles
const mockPayment = vi.fn().mockResolvedValue({ status: 'success' });
const spyLogger = vi.spyOn(logger, 'info');
```

#### What to Test (Unit)

```
Pure functions:     Input → output (always test these)
Edge cases:         null, empty, boundary values, overflow
Error paths:        Invalid input, network failures, timeouts
State transitions:  Before → action → after
Business rules:     Pricing, permissions, validation logic

What NOT to unit test:
  - Framework internals (React rendering, Express routing)
  - Third-party library behavior
  - Trivial getters/setters
  - Implementation details (private methods)
```

### 3. Integration Testing

```javascript
// API integration test (supertest + real DB)
describe('POST /api/users', () => {
  beforeEach(async () => {
    await db.migrate.latest();
    await db.seed.run();
  });

  afterEach(async () => {
    await db.migrate.rollback();
  });

  it('creates user and returns 201', async () => {
    const res = await request(app)
      .post('/api/users')
      .send({ email: 'new@test.com', name: 'Test' })
      .expect(201);

    expect(res.body.data).toMatchObject({
      email: 'new@test.com',
      name: 'Test',
    });

    // Verify side effects
    const dbUser = await db('users').where({ email: 'new@test.com' }).first();
    expect(dbUser).toBeTruthy();
  });

  it('rejects duplicate email with 409', async () => {
    await request(app)
      .post('/api/users')
      .send({ email: 'existing@test.com', name: 'Dupe' })
      .expect(409);
  });
});
```

### 4. E2E Testing (Playwright)

```javascript
import { test, expect } from '@playwright/test';

test.describe('Checkout Flow', () => {
  test('completes purchase as logged-in user', async ({ page }) => {
    // Login
    await page.goto('/login');
    await page.fill('[name=email]', 'user@test.com');
    await page.fill('[name=password]', 'password123');
    await page.click('button[type=submit]');
    await expect(page).toHaveURL('/dashboard');

    // Add to cart
    await page.goto('/products');
    await page.click('[data-testid="product-1"] >> text=Add to Cart');
    await expect(page.locator('.cart-count')).toHaveText('1');

    // Checkout
    await page.click('text=Checkout');
    await page.fill('[name=address]', '123 Test St');
    await page.click('text=Place Order');

    // Verify
    await expect(page).toHaveURL(/\/orders\/\d+/);
    await expect(page.locator('.order-status')).toHaveText('Confirmed');
  });
});
```

### 5. Test Strategy by Feature Type

```
CRUD Feature:
  Unit:  Validate input, test service logic
  Integ: API endpoint + database round-trip
  E2E:   Create → Read → Update → Delete flow

Auth Feature:
  Unit:  Token generation, password hashing
  Integ: Login → token → protected endpoint
  E2E:   Register → login → access → logout

Payment Feature:
  Unit:  Price calculation, discount logic
  Integ: Order creation → mock payment gateway
  E2E:   Add to cart → checkout → confirmation (sandbox)

Real-time Feature:
  Unit:  Message parsing, event handling
  Integ: WebSocket connect → send → receive
  E2E:   Two-user chat scenario
```

### 6. Dealing with Flaky Tests

```
Common Causes:
  - Timing: race conditions, animations, async
  - State: shared DB/files, test order dependency
  - Network: external API calls, DNS
  - Environment: timezone, locale, OS differences

Fixes:
  Timing:    → Use proper waits/assertions, not sleep()
  State:     → Isolate per-test (fresh DB, unique IDs)
  Network:   → Mock external services (MSW, WireMock)
  Env:       → Pin timezone, use Docker for consistency

Detection:
  - Run tests 10x in CI to find intermittent failures
  - Track flaky test rate as a team metric
  - Quarantine flaky tests (don't block CI, fix quickly)
```

### 7. CI Integration

```yaml
# GitHub Actions test pipeline
test:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:17
      env: { POSTGRES_DB: test, POSTGRES_PASSWORD: test }
      ports: ["5432:5432"]
      options: >-
        --health-cmd pg_isready
        --health-interval 5s
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: 22, cache: pnpm }
    - run: pnpm install --frozen-lockfile
    - run: pnpm test:unit -- --coverage
    - run: pnpm test:integration
    - run: pnpm test:e2e
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

## Quick Commands

```bash
# Run tests
pnpm vitest run                    # Unit tests
pnpm vitest run --coverage         # With coverage
pnpm playwright test               # E2E
pnpm playwright test --ui          # E2E with UI

# Debug
pnpm vitest run --reporter=verbose
pnpm playwright test --debug       # Step-by-step
pnpm playwright codegen            # Record test

# Load testing
k6 run loadtest.js
artillery run scenario.yml
```

## References

- **Testing patterns**: See [references/testing-patterns.md](references/testing-patterns.md)
- **Load testing guide**: See [references/load-testing.md](references/load-testing.md)
