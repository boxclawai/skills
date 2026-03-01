# Testing Patterns Reference

A comprehensive reference for software testing patterns, strategies, and best practices across unit, integration, and end-to-end testing.

---

## Table of Contents

1. [Test Doubles](#test-doubles)
2. [Mocking Strategies](#mocking-strategies)
3. [Snapshot Testing](#snapshot-testing)
4. [Visual Regression Testing](#visual-regression-testing)
5. [Contract Testing](#contract-testing)
6. [Property-Based Testing](#property-based-testing)
7. [Mutation Testing](#mutation-testing)
8. [Component Testing with Testing Library](#component-testing-with-testing-library)
9. [Testing Async Operations](#testing-async-operations)
10. [Database Test Fixtures and Factories](#database-test-fixtures-and-factories)

---

## Test Doubles

Test doubles replace real dependencies in tests. Each type serves a distinct purpose and should be selected based on what the test needs to verify.

### Mock

A mock is a pre-programmed object that records calls made to it and can verify that expected interactions occurred. Use mocks when the test needs to verify **behavior** (that certain methods were called with certain arguments).

```typescript
// Jest mock example
const notificationService = {
  send: jest.fn().mockResolvedValue({ delivered: true }),
};

const orderService = new OrderService(notificationService);
await orderService.placeOrder({ item: 'widget', qty: 3 });

// Verify behavior
expect(notificationService.send).toHaveBeenCalledTimes(1);
expect(notificationService.send).toHaveBeenCalledWith(
  expect.objectContaining({
    type: 'order_confirmation',
    item: 'widget',
  })
);
```

```python
# Python unittest.mock example
from unittest.mock import MagicMock, call

notification_service = MagicMock()
notification_service.send.return_value = {"delivered": True}

order_service = OrderService(notification_service)
order_service.place_order(item="widget", qty=3)

notification_service.send.assert_called_once_with(
    type="order_confirmation",
    item="widget",
    qty=3
)
```

### Stub

A stub provides canned answers to calls made during the test. Use stubs when the test needs to control **indirect inputs** -- the return values from dependencies.

```typescript
// Stub: we only care about the return value, not how it was called
const pricingService = {
  getPrice: jest.fn().mockReturnValue(29.99),
  getDiscount: jest.fn().mockReturnValue(0.1),
};

const cart = new ShoppingCart(pricingService);
cart.addItem('SKU-123');

// We verify state, not interaction
expect(cart.getTotal()).toBe(26.99); // 29.99 * 0.9
```

```python
# Python stub using unittest.mock
pricing_service = MagicMock()
pricing_service.get_price.return_value = Decimal("29.99")
pricing_service.get_discount.return_value = Decimal("0.10")

cart = ShoppingCart(pricing_service)
cart.add_item("SKU-123")

assert cart.get_total() == Decimal("26.99")
```

### Spy

A spy wraps a real object and records interactions while still delegating to the real implementation. Use spies when you want to verify calls but still execute the real logic.

```typescript
// Jest spy on a real method
const analyticsService = new AnalyticsService();
const trackSpy = jest.spyOn(analyticsService, 'track');

const checkout = new Checkout(analyticsService);
await checkout.complete(order);

// Real track() was called, but we can also verify
expect(trackSpy).toHaveBeenCalledWith('checkout_complete', {
  orderId: order.id,
  total: order.total,
});

trackSpy.mockRestore(); // Clean up
```

```python
# Python spy using wraps
from unittest.mock import patch

analytics = AnalyticsService()

with patch.object(analytics, 'track', wraps=analytics.track) as track_spy:
    checkout = Checkout(analytics)
    checkout.complete(order)

    track_spy.assert_called_once_with(
        'checkout_complete',
        order_id=order.id,
        total=order.total
    )
```

### Fake

A fake is a working implementation with shortcuts unsuitable for production (e.g., an in-memory database instead of PostgreSQL). Use fakes when you need realistic behavior without the operational cost of the real dependency.

```typescript
// Fake in-memory repository
class FakeUserRepository implements UserRepository {
  private users: Map<string, User> = new Map();

  async findById(id: string): Promise<User | null> {
    return this.users.get(id) ?? null;
  }

  async save(user: User): Promise<void> {
    this.users.set(user.id, { ...user });
  }

  async delete(id: string): Promise<boolean> {
    return this.users.delete(id);
  }

  async findByEmail(email: string): Promise<User | null> {
    for (const user of this.users.values()) {
      if (user.email === email) return user;
    }
    return null;
  }

  // Test helper -- not part of the interface
  seed(users: User[]): void {
    users.forEach((u) => this.users.set(u.id, u));
  }

  clear(): void {
    this.users.clear();
  }
}

// Usage in tests
const repo = new FakeUserRepository();
repo.seed([
  { id: '1', email: 'alice@example.com', name: 'Alice' },
]);

const service = new UserService(repo);
const user = await service.getByEmail('alice@example.com');
expect(user?.name).toBe('Alice');
```

```python
# Python fake repository
class FakeUserRepository:
    def __init__(self):
        self._users: dict[str, User] = {}

    async def find_by_id(self, user_id: str) -> User | None:
        return self._users.get(user_id)

    async def save(self, user: User) -> None:
        self._users[user.id] = user

    async def find_by_email(self, email: str) -> User | None:
        return next(
            (u for u in self._users.values() if u.email == email),
            None,
        )

    def seed(self, users: list[User]) -> None:
        for u in users:
            self._users[u.id] = u

    def clear(self) -> None:
        self._users.clear()
```

### Choosing the Right Test Double

| Double | Verifies           | Real Logic? | Use Case                                |
|--------|--------------------|-----------|-----------------------------------------|
| Mock   | Behavior (calls)   | No        | Verify interactions with dependencies   |
| Stub   | State (outputs)    | No        | Control return values for SUT           |
| Spy    | Behavior + State   | Yes       | Observe real implementation             |
| Fake   | State              | Partial   | Realistic behavior without infra cost   |

**Rule of thumb:** Prefer stubs over mocks when possible. Over-mocking leads to brittle tests that break on refactoring without catching real bugs.

---

## Mocking Strategies

### MSW (Mock Service Worker) for API Mocking

MSW intercepts network requests at the service worker level, making it ideal for integration tests that hit real fetch/XHR calls without reaching actual servers.

```typescript
// src/mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  // GET with dynamic route param
  http.get('/api/users/:userId', ({ params }) => {
    const { userId } = params;
    return HttpResponse.json({
      id: userId,
      name: 'Test User',
      email: 'test@example.com',
    });
  }),

  // POST with request body inspection
  http.post('/api/orders', async ({ request }) => {
    const body = await request.json();

    if (!body.items || body.items.length === 0) {
      return HttpResponse.json(
        { error: 'Order must contain at least one item' },
        { status: 400 }
      );
    }

    return HttpResponse.json(
      {
        id: 'order-123',
        status: 'created',
        items: body.items,
        total: body.items.reduce(
          (sum: number, i: any) => sum + i.price * i.qty,
          0
        ),
      },
      { status: 201 }
    );
  }),

  // Simulating network errors
  http.get('/api/health', () => {
    return HttpResponse.error();
  }),

  // Simulating slow responses
  http.get('/api/reports/:id', async () => {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    return HttpResponse.json({ status: 'complete', data: [] });
  }),
];
```

```typescript
// src/mocks/server.ts -- for Node.js (Jest/Vitest)
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);

// test setup file (e.g., vitest.setup.ts)
import { server } from './mocks/server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

```typescript
// Per-test handler overrides
import { http, HttpResponse } from 'msw';
import { server } from '../mocks/server';

test('displays error when API returns 500', async () => {
  // Override for this specific test
  server.use(
    http.get('/api/users/:userId', () => {
      return HttpResponse.json(
        { error: 'Internal Server Error' },
        { status: 500 }
      );
    })
  );

  render(<UserProfile userId="123" />);
  expect(await screen.findByText(/something went wrong/i)).toBeInTheDocument();
});
```

```typescript
// src/mocks/browser.ts -- for browser (Storybook, dev)
import { setupWorker } from 'msw/browser';
import { handlers } from './handlers';

export const worker = setupWorker(...handlers);

// In your app entry (dev only):
// if (process.env.NODE_ENV === 'development') {
//   const { worker } = await import('./mocks/browser');
//   await worker.start({ onUnhandledRequest: 'bypass' });
// }
```

### Dependency Injection for Testability

Structure code so dependencies are injected rather than hard-coded. This makes substitution with test doubles trivial.

```typescript
// Bad: Hard-coded dependency -- difficult to test
class OrderService {
  async placeOrder(order: Order) {
    const response = await fetch('/api/inventory/check', {
      method: 'POST',
      body: JSON.stringify({ items: order.items }),
    });
    const inventory = await response.json();
    // ...
  }
}

// Good: Dependency injection -- easy to test
interface InventoryClient {
  checkAvailability(items: OrderItem[]): Promise<InventoryResult>;
}

class OrderService {
  constructor(
    private inventory: InventoryClient,
    private payments: PaymentGateway,
    private notifications: NotificationService
  ) {}

  async placeOrder(order: Order): Promise<OrderResult> {
    const availability = await this.inventory.checkAvailability(order.items);
    if (!availability.allAvailable) {
      return { success: false, reason: 'out_of_stock', unavailable: availability.missing };
    }

    const payment = await this.payments.charge(order.total, order.paymentMethod);
    if (!payment.success) {
      return { success: false, reason: 'payment_failed' };
    }

    await this.notifications.send({
      type: 'order_confirmation',
      orderId: order.id,
      email: order.customerEmail,
    });

    return { success: true, orderId: order.id };
  }
}

// In tests: inject mocks/stubs/fakes
const service = new OrderService(
  fakeInventoryClient,
  stubPaymentGateway,
  mockNotificationService
);
```

```python
# Python: dependency injection with protocols
from typing import Protocol

class InventoryClient(Protocol):
    async def check_availability(self, items: list[OrderItem]) -> InventoryResult:
        ...

class PaymentGateway(Protocol):
    async def charge(self, amount: Decimal, method: PaymentMethod) -> PaymentResult:
        ...

class OrderService:
    def __init__(
        self,
        inventory: InventoryClient,
        payments: PaymentGateway,
        notifications: NotificationService,
    ):
        self._inventory = inventory
        self._payments = payments
        self._notifications = notifications

    async def place_order(self, order: Order) -> OrderResult:
        availability = await self._inventory.check_availability(order.items)
        if not availability.all_available:
            return OrderResult(success=False, reason="out_of_stock")
        # ...
```

### Module Mocking (Jest/Vitest)

When dependency injection is not feasible (legacy code, third-party modules):

```typescript
// Mocking an entire module
import { vi, describe, it, expect } from 'vitest';

// Auto-mock all exports
vi.mock('./analytics', () => ({
  trackEvent: vi.fn(),
  trackPageView: vi.fn(),
  identifyUser: vi.fn(),
}));

// Partial mock: keep real implementation for some exports
vi.mock('./utils', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./utils')>();
  return {
    ...actual,
    // Only mock the network call, keep pure functions real
    fetchConfig: vi.fn().mockResolvedValue({ featureFlags: {} }),
  };
});

// Mocking with factory per test
import { trackEvent } from './analytics';

describe('Checkout', () => {
  it('tracks purchase event', async () => {
    const mocked = vi.mocked(trackEvent);
    await checkout.complete(order);
    expect(mocked).toHaveBeenCalledWith('purchase', expect.any(Object));
  });
});
```

---

## Snapshot Testing

Snapshot testing captures the rendered output and compares it against a stored reference. It is most useful for detecting unintended changes, not for verifying correctness.

### Best Practices

```typescript
// GOOD: Focused, small snapshots
test('renders user avatar with initials when no image', () => {
  const { container } = render(
    <UserAvatar user={{ name: 'Jane Doe', imageUrl: null }} size="md" />
  );
  expect(container.firstChild).toMatchSnapshot();
});

// GOOD: Inline snapshots for small outputs
test('formats currency correctly', () => {
  expect(formatCurrency(1234.5, 'USD')).toMatchInlineSnapshot('"$1,234.50"');
  expect(formatCurrency(1234.5, 'EUR')).toMatchInlineSnapshot('"EUR1,234.50"');
  expect(formatCurrency(0, 'USD')).toMatchInlineSnapshot('"$0.00"');
});

// BAD: Snapshotting entire pages -- too large, too fragile
test('renders entire dashboard', () => {
  const { container } = render(<Dashboard />);
  // This snapshot will be thousands of lines and break constantly
  expect(container).toMatchSnapshot();
});
```

### Snapshot Guidelines

1. **Keep snapshots small.** Snapshot a single component or a meaningful subtree, never an entire page.
2. **Use inline snapshots for scalar values.** `toMatchInlineSnapshot()` keeps the expected value in the test file for easy review.
3. **Review snapshot diffs carefully in PRs.** Treat snapshot updates like code changes -- understand why they changed.
4. **Avoid snapshotting volatile data.** Dates, random IDs, and auto-generated keys will cause constant churn.
5. **Use serializers to stabilize output.**

```typescript
// Custom serializer to strip volatile attributes
expect.addSnapshotSerializer({
  test: (val) => val && val.hasAttribute && val.hasAttribute('data-testid'),
  serialize: (val, config, indentation, depth, refs, printer) => {
    const clone = val.cloneNode(true);
    clone.removeAttribute('data-testid');
    return printer(clone, config, indentation, depth, refs);
  },
});

// Alternatively, use property matchers
test('creates order with generated id', () => {
  const order = createOrder({ item: 'widget', qty: 2 });
  expect(order).toMatchSnapshot({
    id: expect.any(String),
    createdAt: expect.any(Date),
  });
});
```

### When to Use Snapshots vs. Explicit Assertions

| Use Snapshots                              | Use Explicit Assertions              |
|--------------------------------------------|--------------------------------------|
| Serialized UI component output             | Business logic return values         |
| Configuration objects with many fields     | Specific fields that matter          |
| Error message formats                      | Calculated numeric values            |
| GraphQL/REST response shapes               | Boolean conditions                   |

---

## Visual Regression Testing

Visual regression testing captures screenshots of UI components and compares them pixel-by-pixel (or perceptually) against baselines.

### Percy (BrowserStack)

```typescript
// Storybook integration: .storybook/percy.config.js
module.exports = {
  widths: [375, 768, 1280],
  minHeight: 1024,
  enableJavaScript: true,
  percyCSS: `
    /* Hide volatile elements */
    [data-percy-hide] { visibility: hidden !important; }
    /* Freeze animations */
    *, *::before, *::after {
      animation-duration: 0s !important;
      transition-duration: 0s !important;
    }
  `,
};
```

```yaml
# .percy.yml
version: 2
snapshot:
  widths:
    - 375
    - 768
    - 1280
  min-height: 1024
  percy-css: |
    *, *::before, *::after {
      animation-duration: 0s !important;
      transition-duration: 0s !important;
    }
  enable-javascript: true
storybook:
  # Only snapshot stories matching this glob
  include:
    - "Components/**"
    - "Pages/**"
  exclude:
    - "**/*Dev*"
```

```bash
# CI command
npx percy storybook ./storybook-static --partial
```

```typescript
// Cypress + Percy for E2E visual tests
describe('Checkout Flow', () => {
  it('renders payment form correctly', () => {
    cy.visit('/checkout');
    cy.get('[data-testid="payment-form"]').should('be.visible');

    // Freeze time and animations before snapshot
    cy.clock(new Date('2025-01-15T12:00:00Z').getTime());

    cy.percySnapshot('Checkout - Payment Form', {
      widths: [375, 1280],
      minHeight: 800,
    });
  });

  it('shows order summary with items', () => {
    cy.intercept('GET', '/api/cart', { fixture: 'cart-with-items.json' });
    cy.visit('/checkout');
    cy.get('[data-testid="order-summary"]').should('be.visible');
    cy.percySnapshot('Checkout - Order Summary');
  });
});
```

### Chromatic (Storybook-native)

```typescript
// Button.stories.tsx with Chromatic parameters
import type { Meta, StoryObj } from '@storybook/react';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  component: Button,
  parameters: {
    chromatic: {
      // Capture at multiple viewports
      viewports: [375, 768, 1200],
      // Increase diff threshold for anti-aliasing differences
      diffThreshold: 0.063,
      // Delay snapshot for animations to settle
      delay: 300,
    },
  },
};

export default meta;
type Story = StoryObj<typeof Button>;

export const Primary: Story = {
  args: { variant: 'primary', children: 'Click Me' },
};

export const AllVariants: Story = {
  render: () => (
    <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
      {(['primary', 'secondary', 'danger', 'ghost'] as const).map((variant) => (
        <div key={variant} style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
          <Button variant={variant} size="sm">Small</Button>
          <Button variant={variant} size="md">Medium</Button>
          <Button variant={variant} size="lg">Large</Button>
          <Button variant={variant} disabled>Disabled</Button>
        </div>
      ))}
    </div>
  ),
  parameters: {
    chromatic: {
      // Only snapshot at desktop width for this matrix
      viewports: [1200],
    },
  },
};

// Interaction test with Chromatic
export const HoverState: Story = {
  args: { variant: 'primary', children: 'Hover Me' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole('button');
    await userEvent.hover(button);
  },
};

// Disable Chromatic for development-only stories
export const DevPlayground: Story = {
  args: { variant: 'primary', children: 'Dev Only' },
  parameters: {
    chromatic: { disableSnapshot: true },
  },
};
```

```yaml
# CI: Chromatic GitHub Action
- uses: chromaui/action@latest
  with:
    projectToken: ${{ secrets.CHROMATIC_PROJECT_TOKEN }}
    exitOnceUploaded: true  # Don't block CI waiting for review
    onlyChanged: true       # Only test changed stories
    externals: |
      - 'src/styles/**'     # Re-test when global styles change
```

### Visual Testing Tips

1. **Stabilize before capture:** Disable animations, freeze time, wait for fonts/images to load.
2. **Use deterministic data:** Seed random values, use fixed dates, mock API responses.
3. **Set appropriate diff thresholds:** Slight anti-aliasing differences across OS/GPU require a tolerance (typically 0.05-0.1).
4. **Test meaningful states:** Default, hover, focus, error, empty, loading, overflow.
5. **Review baselines as part of PR review:** Approving visual changes should be a conscious team decision.

---

## Contract Testing

Contract testing verifies that the communication between services (consumer and provider) adheres to an agreed-upon contract, without requiring both services to be running simultaneously.

### Pact (Consumer-Driven Contracts)

```typescript
// Consumer side: order-service/tests/contracts/inventory.consumer.pact.ts
import { PactV4, MatchersV3 } from '@pact-foundation/pact';

const { like, eachLike, integer, string, boolean, regex } = MatchersV3;

const provider = new PactV4({
  consumer: 'OrderService',
  provider: 'InventoryService',
  logLevel: 'warn',
});

describe('Inventory Service Contract', () => {
  describe('check stock availability', () => {
    it('returns availability for requested SKUs', async () => {
      await provider
        .addInteraction()
        .given('SKU-001 has 50 units in stock')
        .given('SKU-002 has 0 units in stock')
        .uponReceiving('a request to check stock for multiple SKUs')
        .withRequest('POST', '/api/v1/inventory/check', (builder) => {
          builder
            .headers({ 'Content-Type': 'application/json' })
            .jsonBody({
              skus: ['SKU-001', 'SKU-002'],
              warehouseId: like('WH-EAST-01'),
            });
        })
        .willRespondWith(200, (builder) => {
          builder
            .headers({ 'Content-Type': 'application/json' })
            .jsonBody({
              results: eachLike({
                sku: string('SKU-001'),
                available: boolean(true),
                quantity: integer(50),
                warehouse: string('WH-EAST-01'),
              }),
              checkedAt: regex(
                /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
                '2025-01-15T10:30:00Z'
              ),
            });
        })
        .executeTest(async (mockServer) => {
          const client = new InventoryClient(mockServer.url);
          const result = await client.checkAvailability(
            ['SKU-001', 'SKU-002'],
            'WH-EAST-01'
          );

          expect(result.results).toHaveLength(2);
          expect(result.results[0].available).toBe(true);
        });
    });

    it('returns 404 for unknown warehouse', async () => {
      await provider
        .addInteraction()
        .given('warehouse UNKNOWN does not exist')
        .uponReceiving('a stock check for a non-existent warehouse')
        .withRequest('POST', '/api/v1/inventory/check', (builder) => {
          builder.jsonBody({
            skus: ['SKU-001'],
            warehouseId: 'UNKNOWN',
          });
        })
        .willRespondWith(404, (builder) => {
          builder.jsonBody({
            error: string('warehouse_not_found'),
            message: string('Warehouse UNKNOWN does not exist'),
          });
        })
        .executeTest(async (mockServer) => {
          const client = new InventoryClient(mockServer.url);
          await expect(
            client.checkAvailability(['SKU-001'], 'UNKNOWN')
          ).rejects.toThrow('Warehouse UNKNOWN does not exist');
        });
    });
  });
});
```

```typescript
// Provider side: inventory-service/tests/contracts/pact.provider.ts
import { Verifier } from '@pact-foundation/pact';
import { app } from '../../src/app'; // Express/Fastify app
import { seedDatabase, clearDatabase } from '../helpers/db';

describe('Pact Provider Verification', () => {
  let server: any;

  beforeAll(async () => {
    server = app.listen(0); // Random port
  });

  afterAll(async () => {
    server.close();
  });

  it('validates the expectations of OrderService', async () => {
    const port = server.address().port;

    await new Verifier({
      providerBaseUrl: `http://localhost:${port}`,
      pactBrokerUrl: process.env.PACT_BROKER_URL,
      provider: 'InventoryService',
      providerVersion: process.env.GIT_SHA,
      providerVersionBranch: process.env.GIT_BRANCH,
      publishVerificationResult: process.env.CI === 'true',

      // Set up provider states
      stateHandlers: {
        'SKU-001 has 50 units in stock': async () => {
          await seedDatabase({
            inventory: [{ sku: 'SKU-001', quantity: 50, warehouse: 'WH-EAST-01' }],
          });
        },
        'SKU-002 has 0 units in stock': async () => {
          await seedDatabase({
            inventory: [{ sku: 'SKU-002', quantity: 0, warehouse: 'WH-EAST-01' }],
          });
        },
        'warehouse UNKNOWN does not exist': async () => {
          await clearDatabase('warehouses');
        },
      },

      // Run after each interaction
      afterEach: async () => {
        await clearDatabase('inventory');
      },
    }).verifyProvider();
  });
});
```

### Contract Testing Workflow

1. **Consumer writes contract tests** that define expected interactions.
2. **Pact file is generated** (JSON) and published to a Pact Broker.
3. **Provider runs verification** against the published pact, setting up required state for each interaction.
4. **CI gates deployment** using `can-i-deploy` to ensure compatibility.

```bash
# Check if it's safe to deploy the consumer
pact-broker can-i-deploy \
  --pacticipant OrderService \
  --version $GIT_SHA \
  --to-environment production
```

---

## Property-Based Testing

Property-based testing generates random inputs and verifies that invariants (properties) hold for all of them. It finds edge cases that example-based tests miss.

### fast-check (JavaScript/TypeScript)

```typescript
import fc from 'fast-check';

// Property: sorting is idempotent -- sorting a sorted array yields the same array
test('sort is idempotent', () => {
  fc.assert(
    fc.property(fc.array(fc.integer()), (arr) => {
      const sorted = [...arr].sort((a, b) => a - b);
      const sortedTwice = [...sorted].sort((a, b) => a - b);
      expect(sorted).toEqual(sortedTwice);
    })
  );
});

// Property: encoding then decoding yields the original value
test('JSON roundtrip preserves data', () => {
  fc.assert(
    fc.property(
      fc.record({
        id: fc.uuid(),
        name: fc.string({ minLength: 1, maxLength: 100 }),
        age: fc.integer({ min: 0, max: 150 }),
        email: fc.emailAddress(),
        tags: fc.array(fc.string(), { maxLength: 10 }),
        active: fc.boolean(),
      }),
      (user) => {
        const serialized = JSON.stringify(user);
        const deserialized = JSON.parse(serialized);
        expect(deserialized).toEqual(user);
      }
    )
  );
});

// Property: a valid discount is always between 0 and the original price
test('discount never exceeds original price', () => {
  fc.assert(
    fc.property(
      fc.record({
        price: fc.float({ min: 0.01, max: 10000, noNaN: true }),
        discountPercent: fc.float({ min: 0, max: 100, noNaN: true }),
      }),
      ({ price, discountPercent }) => {
        const discounted = applyDiscount(price, discountPercent);
        expect(discounted).toBeGreaterThanOrEqual(0);
        expect(discounted).toBeLessThanOrEqual(price);
      }
    )
  );
});

// Custom arbitraries for domain objects
const arbMoney = fc
  .record({
    amount: fc.integer({ min: 0, max: 999999 }),
    currency: fc.constantFrom('USD', 'EUR', 'GBP', 'JPY'),
  })
  .map(({ amount, currency }) => Money.fromCents(amount, currency));

const arbLineItem = fc.record({
  product: fc.string({ minLength: 1 }),
  quantity: fc.integer({ min: 1, max: 100 }),
  unitPrice: arbMoney,
});

test('order total equals sum of line items', () => {
  fc.assert(
    fc.property(fc.array(arbLineItem, { minLength: 1, maxLength: 20 }), (items) => {
      const order = Order.create(items);
      const expectedTotal = items.reduce(
        (sum, item) => sum.add(item.unitPrice.multiply(item.quantity)),
        Money.zero(items[0].unitPrice.currency)
      );
      expect(order.total.equals(expectedTotal)).toBe(true);
    }),
    { numRuns: 500 } // Run more iterations for higher confidence
  );
});

// Reproduce a failure from a seed
test('reproduces specific failure', () => {
  fc.assert(
    fc.property(fc.string(), (s) => {
      expect(myParser(s)).not.toThrow();
    }),
    { seed: 1234567890, path: '4:2:1' } // Replay exact shrunk counterexample
  );
});
```

### Property Categories to Test

| Category           | Description                                  | Example                                          |
|--------------------|----------------------------------------------|--------------------------------------------------|
| Roundtrip          | encode/decode returns original                | `decode(encode(x)) === x`                       |
| Idempotence        | Applying twice equals applying once           | `sort(sort(x)) === sort(x)`                     |
| Invariant          | Property always holds                         | `0 <= discount <= originalPrice`                 |
| Commutativity      | Order of operations does not matter           | `merge(a, b) === merge(b, a)`                   |
| Associativity      | Grouping does not matter                      | `concat(a, concat(b, c)) === concat(concat(a, b), c)` |
| Oracle             | Compare against a known-correct implementation| `fastSort(x) === referenceSort(x)`              |

---

## Mutation Testing

Mutation testing measures the quality of your test suite by introducing small changes (mutations) to your source code and checking whether your tests detect them.

### Stryker (JavaScript/TypeScript)

```json
// stryker.config.json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "packageManager": "npm",
  "testRunner": "vitest",
  "reporters": ["html", "clear-text", "progress", "dashboard"],
  "coverageAnalysis": "perTest",
  "thresholds": {
    "high": 80,
    "low": 60,
    "break": 50
  },
  "mutate": [
    "src/**/*.ts",
    "!src/**/*.test.ts",
    "!src/**/*.spec.ts",
    "!src/**/index.ts",
    "!src/**/*.d.ts"
  ],
  "ignorePatterns": ["dist", "node_modules", ".stryker-tmp"],
  "concurrency": 4,
  "timeoutMS": 10000
}
```

```typescript
// Example: Code under mutation
export function calculateShipping(weight: number, distance: number, express: boolean): number {
  const baseRate = 5.0;
  const weightRate = weight * 0.5;        // Mutant: weight * 0.0, weight * 1.5, etc.
  const distanceRate = distance * 0.01;   // Mutant: distance * 0.0
  const expressMultiplier = express ? 2.0 : 1.0; // Mutant: express ? 1.0 : 2.0

  const total = (baseRate + weightRate + distanceRate) * expressMultiplier;
  return Math.max(total, baseRate); // Mutant: Math.min, remove Math.max
}

// Tests that would KILL the mutations above:
describe('calculateShipping', () => {
  it('includes weight in calculation', () => {
    const light = calculateShipping(1, 100, false);
    const heavy = calculateShipping(10, 100, false);
    expect(heavy).toBeGreaterThan(light); // Kills weightRate mutations
  });

  it('includes distance in calculation', () => {
    const close = calculateShipping(5, 10, false);
    const far = calculateShipping(5, 1000, false);
    expect(far).toBeGreaterThan(close); // Kills distanceRate mutations
  });

  it('express doubles the cost', () => {
    const standard = calculateShipping(5, 100, false);
    const express = calculateShipping(5, 100, true);
    expect(express).toBe(standard * 2); // Kills expressMultiplier swap
  });

  it('never goes below base rate', () => {
    const cost = calculateShipping(0, 0, false);
    expect(cost).toBe(5.0); // Kills Math.max removal
  });
});
```

### Interpreting Mutation Scores

- **Killed:** Test suite detected the mutation (test failed). Good.
- **Survived:** Test suite did not detect the mutation (all tests passed). Your tests have a gap.
- **Timeout:** Mutation caused an infinite loop. Counted as killed.
- **No coverage:** No test covers the mutated line. Add tests.

**Target:** 80%+ mutation score for business-critical code. Focus on survived mutants in critical paths rather than chasing 100%.

---

## Component Testing with Testing Library

Testing Library enforces testing from the user's perspective: interact with elements by their accessible roles, labels, and text content rather than implementation details like CSS classes or component state.

### React Components

```typescript
// UserProfile.test.tsx
import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { UserProfile } from './UserProfile';

// Set up userEvent instance (v14+)
const user = userEvent.setup();

describe('UserProfile', () => {
  const defaultProps = {
    userId: 'user-123',
    onSave: jest.fn(),
    onCancel: jest.fn(),
  };

  it('loads and displays user information', async () => {
    render(<UserProfile {...defaultProps} />);

    // Wait for loading to complete
    expect(screen.getByRole('progressbar')).toBeInTheDocument();
    expect(await screen.findByRole('heading', { name: /jane doe/i })).toBeInTheDocument();

    // Verify displayed data
    expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    expect(screen.getByRole('img', { name: /jane doe/i })).toHaveAttribute(
      'src',
      expect.stringContaining('avatar')
    );
  });

  it('allows editing the user name', async () => {
    render(<UserProfile {...defaultProps} />);

    // Wait for data to load
    await screen.findByRole('heading', { name: /jane doe/i });

    // Click edit button
    await user.click(screen.getByRole('button', { name: /edit profile/i }));

    // Find and modify the name input
    const nameInput = screen.getByRole('textbox', { name: /full name/i });
    await user.clear(nameInput);
    await user.type(nameInput, 'Jane Smith');

    // Submit the form
    await user.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(defaultProps.onSave).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'Jane Smith' })
      );
    });
  });

  it('validates required fields', async () => {
    render(<UserProfile {...defaultProps} />);
    await screen.findByRole('heading', { name: /jane doe/i });

    await user.click(screen.getByRole('button', { name: /edit profile/i }));

    // Clear required field
    const nameInput = screen.getByRole('textbox', { name: /full name/i });
    await user.clear(nameInput);
    await user.click(screen.getByRole('button', { name: /save/i }));

    // Check for validation error
    expect(await screen.findByRole('alert')).toHaveTextContent(/name is required/i);
    expect(defaultProps.onSave).not.toHaveBeenCalled();
  });

  it('handles cancel without saving', async () => {
    render(<UserProfile {...defaultProps} />);
    await screen.findByRole('heading', { name: /jane doe/i });

    await user.click(screen.getByRole('button', { name: /edit profile/i }));

    const nameInput = screen.getByRole('textbox', { name: /full name/i });
    await user.clear(nameInput);
    await user.type(nameInput, 'Changed Name');

    await user.click(screen.getByRole('button', { name: /cancel/i }));

    expect(defaultProps.onCancel).toHaveBeenCalled();
    // Original name should be displayed again
    expect(screen.getByRole('heading', { name: /jane doe/i })).toBeInTheDocument();
  });
});

// Testing a component with context providers
function renderWithProviders(
  ui: React.ReactElement,
  {
    theme = 'light',
    locale = 'en-US',
    user: currentUser = mockUser,
    ...renderOptions
  } = {}
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <ThemeProvider theme={theme}>
        <IntlProvider locale={locale}>
          <AuthContext.Provider value={{ user: currentUser }}>
            {children}
          </AuthContext.Provider>
        </IntlProvider>
      </ThemeProvider>
    );
  }

  return render(ui, { wrapper: Wrapper, ...renderOptions });
}

// Testing accessible components
it('supports keyboard navigation in dropdown', async () => {
  render(<Dropdown options={['Apple', 'Banana', 'Cherry']} label="Fruit" />);

  const trigger = screen.getByRole('combobox', { name: /fruit/i });
  await user.click(trigger);

  const listbox = screen.getByRole('listbox');
  expect(listbox).toBeVisible();

  await user.keyboard('{ArrowDown}');
  expect(within(listbox).getByRole('option', { name: 'Apple' })).toHaveAttribute(
    'aria-selected',
    'true'
  );

  await user.keyboard('{ArrowDown}');
  expect(within(listbox).getByRole('option', { name: 'Banana' })).toHaveAttribute(
    'aria-selected',
    'true'
  );

  await user.keyboard('{Enter}');
  expect(trigger).toHaveTextContent('Banana');
  expect(listbox).not.toBeVisible();
});
```

### Vue Components

```typescript
// UserProfile.spec.ts (Vue 3 + Testing Library)
import { render, screen, waitFor } from '@testing-library/vue';
import userEvent from '@testing-library/user-event';
import { createTestingPinia } from '@pinia/testing';
import UserProfile from './UserProfile.vue';
import { useUserStore } from '@/stores/user';

const user = userEvent.setup();

describe('UserProfile', () => {
  function renderComponent(options = {}) {
    return render(UserProfile, {
      global: {
        plugins: [
          createTestingPinia({
            initialState: {
              user: {
                currentUser: { id: '123', name: 'Jane Doe', email: 'jane@example.com' },
              },
            },
            stubActions: false,
          }),
        ],
      },
      props: {
        userId: '123',
        ...options,
      },
    });
  }

  it('displays user data from the store', () => {
    renderComponent();
    expect(screen.getByRole('heading', { name: /jane doe/i })).toBeInTheDocument();
    expect(screen.getByText('jane@example.com')).toBeInTheDocument();
  });

  it('calls store action on save', async () => {
    renderComponent();
    const store = useUserStore();

    await user.click(screen.getByRole('button', { name: /edit/i }));
    const input = screen.getByRole('textbox', { name: /name/i });
    await user.clear(input);
    await user.type(input, 'Jane Smith');
    await user.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(store.updateUser).toHaveBeenCalledWith({
        id: '123',
        name: 'Jane Smith',
        email: 'jane@example.com',
      });
    });
  });
});
```

### Query Priority (Testing Library)

Always prefer queries that reflect how users and assistive technology find elements:

1. **`getByRole`** -- Accessible role + name. Covers buttons, headings, inputs, links, etc.
2. **`getByLabelText`** -- Form inputs associated with a label.
3. **`getByPlaceholderText`** -- When no label exists (not ideal, but practical).
4. **`getByText`** -- Static text content.
5. **`getByDisplayValue`** -- Current value of form elements.
6. **`getByAltText`** -- Images.
7. **`getByTitle`** -- Title attribute (less reliable).
8. **`getByTestId`** -- Last resort. Use `data-testid` when no accessible query works.

---

## Testing Async Operations

### Promises, Timers, and Concurrent Operations

```typescript
// Testing promise-based code
test('retries failed requests up to 3 times', async () => {
  const fetchFn = jest.fn()
    .mockRejectedValueOnce(new Error('Network error'))
    .mockRejectedValueOnce(new Error('Network error'))
    .mockResolvedValueOnce({ data: 'success' });

  const result = await fetchWithRetry(fetchFn, { maxRetries: 3, delay: 100 });

  expect(fetchFn).toHaveBeenCalledTimes(3);
  expect(result).toEqual({ data: 'success' });
});

test('throws after exhausting retries', async () => {
  const fetchFn = jest.fn().mockRejectedValue(new Error('Persistent failure'));

  await expect(
    fetchWithRetry(fetchFn, { maxRetries: 3, delay: 100 })
  ).rejects.toThrow('Persistent failure');

  expect(fetchFn).toHaveBeenCalledTimes(4); // 1 initial + 3 retries
});
```

```typescript
// Testing with fake timers
describe('debounce', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('calls the function after the delay', () => {
    const fn = vi.fn();
    const debounced = debounce(fn, 300);

    debounced('first');
    debounced('second');
    debounced('third');

    expect(fn).not.toHaveBeenCalled();

    vi.advanceTimersByTime(300);

    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith('third');
  });

  it('resets the timer on each call', () => {
    const fn = vi.fn();
    const debounced = debounce(fn, 300);

    debounced('a');
    vi.advanceTimersByTime(200);
    debounced('b');
    vi.advanceTimersByTime(200);
    debounced('c');

    expect(fn).not.toHaveBeenCalled();

    vi.advanceTimersByTime(300);
    expect(fn).toHaveBeenCalledWith('c');
  });
});
```

```typescript
// Testing event emitters and streams
test('processes stream items in order', async () => {
  const results: string[] = [];

  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue('chunk-1');
      controller.enqueue('chunk-2');
      controller.enqueue('chunk-3');
      controller.close();
    },
  });

  for await (const chunk of streamToAsyncIterator(stream)) {
    results.push(chunk);
  }

  expect(results).toEqual(['chunk-1', 'chunk-2', 'chunk-3']);
});

// Testing WebSocket communication
test('reconnects on connection drop', async () => {
  const mockServer = new MockWebSocketServer('ws://localhost:8080');

  const client = new ReconnectingWebSocket('ws://localhost:8080', {
    maxRetries: 3,
    retryDelay: 100,
  });

  await client.connect();
  expect(client.isConnected).toBe(true);

  // Simulate server-side disconnect
  mockServer.closeAllConnections();

  // Wait for reconnection
  await vi.waitFor(() => {
    expect(client.isConnected).toBe(true);
  }, { timeout: 2000 });

  expect(client.reconnectCount).toBe(1);

  client.disconnect();
  mockServer.close();
});
```

```typescript
// React: testing async component behavior
test('shows loading, then data, then handles refresh', async () => {
  render(<DataTable endpoint="/api/reports" />);

  // Phase 1: Loading
  expect(screen.getByRole('progressbar')).toBeInTheDocument();

  // Phase 2: Data loaded
  const rows = await screen.findAllByRole('row');
  expect(rows).toHaveLength(11); // 1 header + 10 data rows

  // Phase 3: Trigger refresh
  await user.click(screen.getByRole('button', { name: /refresh/i }));

  // Should show inline loading indicator (not full skeleton)
  expect(screen.getByRole('status', { name: /refreshing/i })).toBeInTheDocument();
  // Data should still be visible during refresh
  expect(screen.getAllByRole('row')).toHaveLength(11);

  // Wait for refresh to complete
  await waitFor(() => {
    expect(screen.queryByRole('status', { name: /refreshing/i })).not.toBeInTheDocument();
  });
});
```

### Common Async Testing Pitfalls

1. **Do not use `setTimeout` in tests.** Use `vi.useFakeTimers()` or `waitFor()`.
2. **Always `await` async assertions.** Missing `await` causes tests to pass vacuously.
3. **Use `findBy*` for elements that appear asynchronously.** It polls until the element appears or times out.
4. **Avoid `sleep`/`delay` in tests.** They make tests slow and flaky. Use `waitFor` or fake timers.
5. **Clean up subscriptions.** Unsubscribe from observables, close WebSocket connections, and clear intervals in `afterEach`.

---

## Database Test Fixtures and Factories

### Factory Pattern with Fishery (TypeScript)

```typescript
// factories/index.ts
import { Factory } from 'fishery';
import { faker } from '@faker-js/faker';
import type { User, Organization, Project, Task } from '@/types';

// ---- User Factory ----
export const userFactory = Factory.define<User>(({ sequence, params, transientParams }) => {
  const firstName = params.name?.split(' ')[0] ?? faker.person.firstName();
  const lastName = params.name?.split(' ')[1] ?? faker.person.lastName();

  return {
    id: `user-${sequence}`,
    name: `${firstName} ${lastName}`,
    email: params.email ?? faker.internet.email({ firstName, lastName }).toLowerCase(),
    role: params.role ?? 'member',
    organizationId: params.organizationId ?? `org-${sequence}`,
    createdAt: new Date('2025-01-01T00:00:00Z'),
    updatedAt: new Date('2025-01-01T00:00:00Z'),
    passwordHash: '$argon2id$v=19$m=65536,t=3,p=4$fakehash',
    emailVerified: true,
    avatarUrl: null,
    preferences: {
      theme: 'system',
      notifications: true,
      locale: 'en-US',
    },
  };
});

// ---- Organization Factory ----
export const organizationFactory = Factory.define<Organization>(({ sequence, afterCreate }) => {
  const org: Organization = {
    id: `org-${sequence}`,
    name: faker.company.name(),
    slug: faker.helpers.slugify(faker.company.name()).toLowerCase(),
    plan: 'free',
    memberCount: 0,
    createdAt: new Date('2025-01-01T00:00:00Z'),
  };

  return org;
});

// ---- Project Factory ----
export const projectFactory = Factory.define<Project>(({ sequence, associations }) => ({
  id: `proj-${sequence}`,
  name: faker.commerce.productName(),
  description: faker.lorem.sentence(),
  organizationId: associations.organization?.id ?? `org-${sequence}`,
  ownerId: associations.owner?.id ?? `user-${sequence}`,
  status: 'active',
  visibility: 'private',
  createdAt: new Date('2025-01-01T00:00:00Z'),
  updatedAt: new Date('2025-01-01T00:00:00Z'),
}));

// ---- Task Factory ----
export const taskFactory = Factory.define<Task>(({ sequence, associations }) => ({
  id: `task-${sequence}`,
  title: faker.hacker.phrase(),
  description: faker.lorem.paragraph(),
  projectId: associations.project?.id ?? `proj-${sequence}`,
  assigneeId: associations.assignee?.id ?? null,
  status: 'todo',
  priority: 'medium',
  dueDate: null,
  labels: [],
  createdAt: new Date('2025-01-01T00:00:00Z'),
  updatedAt: new Date('2025-01-01T00:00:00Z'),
}));
```

```typescript
// Usage in tests
describe('ProjectService', () => {
  it('returns tasks grouped by status', async () => {
    const project = projectFactory.build();
    const tasks = [
      taskFactory.build({ status: 'todo', projectId: project.id }),
      taskFactory.build({ status: 'todo', projectId: project.id }),
      taskFactory.build({ status: 'in_progress', projectId: project.id }),
      taskFactory.build({ status: 'done', projectId: project.id }),
    ];

    const repo = new FakeTaskRepository();
    repo.seed(tasks);

    const service = new ProjectService(repo);
    const grouped = await service.getTasksByStatus(project.id);

    expect(grouped.todo).toHaveLength(2);
    expect(grouped.in_progress).toHaveLength(1);
    expect(grouped.done).toHaveLength(1);
  });

  it('builds related objects with associations', () => {
    const org = organizationFactory.build({ plan: 'enterprise' });
    const admin = userFactory.build({ role: 'admin', organizationId: org.id });
    const project = projectFactory.build({}, { associations: { organization: org, owner: admin } });

    expect(project.organizationId).toBe(org.id);
    expect(project.ownerId).toBe(admin.id);
  });

  it('creates batches with buildList', () => {
    const users = userFactory.buildList(50, { role: 'member', organizationId: 'org-1' });
    expect(users).toHaveLength(50);
    expect(new Set(users.map((u) => u.id)).size).toBe(50); // All unique IDs
  });
});
```

### Database Fixtures with Prisma (Integration Tests)

```typescript
// test-helpers/db.ts
import { PrismaClient } from '@prisma/client';
import { execSync } from 'child_process';

const prisma = new PrismaClient({
  datasources: {
    db: { url: process.env.TEST_DATABASE_URL },
  },
});

// Reset database between tests using Prisma's transaction-based approach
export async function resetDatabase() {
  const tablenames = await prisma.$queryRaw<Array<{ tablename: string }>>`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  `;

  const tables = tablenames
    .map(({ tablename }) => tablename)
    .filter((name) => name !== '_prisma_migrations')
    .map((name) => `"public"."${name}"`)
    .join(', ');

  if (tables.length > 0) {
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${tables} CASCADE;`);
  }
}

// Seed helpers for common test scenarios
export async function seedOrganizationWithUsers(options: {
  orgName?: string;
  userCount?: number;
  plan?: string;
}) {
  const { orgName = 'Test Org', userCount = 3, plan = 'free' } = options;

  const org = await prisma.organization.create({
    data: {
      name: orgName,
      slug: orgName.toLowerCase().replace(/\s+/g, '-'),
      plan,
    },
  });

  const users = await Promise.all(
    Array.from({ length: userCount }, (_, i) =>
      prisma.user.create({
        data: {
          name: `User ${i + 1}`,
          email: `user${i + 1}@${org.slug}.test`,
          organizationId: org.id,
          role: i === 0 ? 'admin' : 'member',
          passwordHash: '$argon2id$v=19$m=65536,t=3,p=4$testhash',
        },
      })
    )
  );

  return { org, users };
}

// Global test setup
export async function setupTestDatabase() {
  execSync('npx prisma migrate deploy', {
    env: { ...process.env, DATABASE_URL: process.env.TEST_DATABASE_URL },
  });
}
```

```typescript
// Integration test using real database
import { prisma, resetDatabase, seedOrganizationWithUsers } from '../test-helpers/db';

describe('InvitationService (integration)', () => {
  beforeEach(async () => {
    await resetDatabase();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('creates an invitation and sends email', async () => {
    const { org, users } = await seedOrganizationWithUsers({
      orgName: 'Acme Corp',
      plan: 'team',
    });
    const admin = users[0];

    const emailService = new FakeEmailService();
    const service = new InvitationService(prisma, emailService);

    const invitation = await service.invite({
      email: 'newuser@example.com',
      organizationId: org.id,
      invitedById: admin.id,
      role: 'member',
    });

    expect(invitation.status).toBe('pending');
    expect(invitation.token).toMatch(/^[a-f0-9]{64}$/);

    // Verify invitation in database
    const stored = await prisma.invitation.findUnique({
      where: { id: invitation.id },
    });
    expect(stored?.email).toBe('newuser@example.com');

    // Verify email was sent
    expect(emailService.sentEmails).toHaveLength(1);
    expect(emailService.sentEmails[0].to).toBe('newuser@example.com');
  });

  it('rejects duplicate invitations', async () => {
    const { org, users } = await seedOrganizationWithUsers({ orgName: 'Test Org' });
    const admin = users[0];

    const service = new InvitationService(prisma, new FakeEmailService());

    await service.invite({
      email: 'dup@example.com',
      organizationId: org.id,
      invitedById: admin.id,
      role: 'member',
    });

    await expect(
      service.invite({
        email: 'dup@example.com',
        organizationId: org.id,
        invitedById: admin.id,
        role: 'member',
      })
    ).rejects.toThrow('Invitation already exists');
  });
});
```

### Python: Factory Boy for Django/SQLAlchemy

```python
# factories.py
import factory
from factory import fuzzy
from datetime import datetime, timezone
from myapp.models import User, Organization, Project

class OrganizationFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Organization

    name = factory.Faker("company")
    slug = factory.LazyAttribute(lambda o: o.name.lower().replace(" ", "-"))
    plan = "free"
    created_at = factory.LazyFunction(lambda: datetime(2025, 1, 1, tzinfo=timezone.utc))


class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User

    name = factory.Faker("name")
    email = factory.LazyAttribute(
        lambda u: f"{u.name.lower().replace(' ', '.')}@example.com"
    )
    organization = factory.SubFactory(OrganizationFactory)
    role = "member"
    is_active = True
    email_verified = True

    class Params:
        admin = factory.Trait(
            role="admin",
        )


class ProjectFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Project

    name = factory.Faker("catch_phrase")
    description = factory.Faker("paragraph")
    organization = factory.SubFactory(OrganizationFactory)
    owner = factory.SubFactory(
        UserFactory,
        organization=factory.SelfAttribute("..organization"),
    )
    status = "active"


# Usage in tests
class TestProjectPermissions:
    def test_admin_can_delete_project(self, db):
        org = OrganizationFactory(plan="team")
        admin = UserFactory(organization=org, admin=True)
        project = ProjectFactory(organization=org, owner=admin)

        service = ProjectService()
        service.delete_project(project.id, acting_user=admin)

        assert not Project.objects.filter(id=project.id).exists()

    def test_member_cannot_delete_project(self, db):
        org = OrganizationFactory()
        member = UserFactory(organization=org)
        project = ProjectFactory(organization=org)

        service = ProjectService()
        with pytest.raises(PermissionError, match="insufficient permissions"):
            service.delete_project(project.id, acting_user=member)

    def test_batch_creation(self, db):
        org = OrganizationFactory()
        members = UserFactory.create_batch(10, organization=org, role="member")

        assert len(members) == 10
        assert all(m.organization_id == org.id for m in members)
```

### Fixture Strategy Guidelines

| Strategy              | Speed    | Isolation | Realism | Use When                              |
|-----------------------|----------|-----------|---------|---------------------------------------|
| In-memory fakes       | Fastest  | Perfect   | Low     | Unit tests, business logic            |
| Factories (no DB)     | Fast     | Perfect   | Medium  | Service layer tests with fake repos   |
| Factories + real DB   | Slow     | Good*     | High    | Integration tests, query verification |
| Shared fixtures       | Medium   | Poor      | Medium  | Read-only tests, avoid for mutations  |
| DB snapshots          | Medium   | Good      | High    | Complex seed data, CI optimization    |

*With proper cleanup (truncate/rollback) between tests.

**Key principles:**
- Use the lightest fixture strategy that gives you the confidence you need.
- Factories should produce valid objects by default. Override only what the specific test cares about.
- Never share mutable state between tests. Always clean up or use transactions.
- Seed timestamps deterministically to avoid flaky time-dependent assertions.
- Name factories and fixtures clearly so tests read like documentation.
