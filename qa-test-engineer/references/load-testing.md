# Load Testing Reference

A comprehensive guide to load testing with k6, Artillery, and Grafana k6 Cloud. Covers test types, scripting, thresholds, performance budgets, result interpretation, and CI integration.

---

## Table of Contents

1. [Test Types](#test-types)
2. [k6 Scripting](#k6-scripting)
3. [k6 Thresholds and Custom Metrics](#k6-thresholds-and-custom-metrics)
4. [k6 Scenarios](#k6-scenarios)
5. [Artillery Configuration](#artillery-configuration)
6. [Performance Budgets](#performance-budgets)
7. [Interpreting Results](#interpreting-results)
8. [CI Integration](#ci-integration)
9. [Advanced Patterns](#advanced-patterns)

---

## Test Types

Each test type answers a different question about your system's behavior under load.

### Smoke Test

**Purpose:** Verify the system works correctly under minimal load. A sanity check that the test script is valid and the system is functional.

**Configuration:**
- 1-2 virtual users (VUs)
- 1-2 minutes duration
- Run before every other test type

```
Load
  |
2 |████████████████████
  |
  +--------------------→ Time
  0        1m        2m
```

### Load Test

**Purpose:** Assess system performance under expected normal and peak traffic. Identifies whether the system meets its SLOs under realistic conditions.

**Configuration:**
- Ramp up to expected concurrent users
- Sustain for 10-30 minutes
- Ramp down gracefully

```
Load
   |
200|         ████████████████████
   |       ╱                     ╲
   |     ╱                         ╲
   |   ╱                             ╲
   | ╱                                 ╲
   +--------------------------------------→ Time
   0    2m    5m              25m   30m
```

### Stress Test

**Purpose:** Find the system's breaking point. Continuously increase load beyond normal levels to discover where performance degrades and failures begin.

**Configuration:**
- Stepwise ramp to 2-5x normal load
- Hold at each step for 5-10 minutes
- Monitor for error rate spikes and latency degradation

```
Load
    |
800 |                              ████
    |                         ████
600 |                    ████
    |               ████
400 |          ████
    |     ████
200 |████
    +-----------------------------------→ Time
    0   5m  10m  15m  20m  25m  30m  35m
```

### Soak Test (Endurance Test)

**Purpose:** Detect memory leaks, resource exhaustion, database connection pool depletion, and other degradation that only appears over extended periods.

**Configuration:**
- Normal expected load
- Extended duration: 2-8 hours (or longer)
- Monitor memory, CPU, connections, disk over time

```
Load
   |
200|    ██████████████████████████████████████
   |  ╱                                       ╲
   +-------------------------------------------→ Time
   0  5m                               4h   4h5m
```

### Spike Test

**Purpose:** Determine how the system handles sudden, extreme load spikes and whether it recovers afterward. Simulates flash sales, viral events, or traffic bursts.

**Configuration:**
- Instant ramp to 5-10x normal load
- Hold for 1-5 minutes
- Instant drop back to normal
- Monitor recovery time and error handling

```
Load
     |
1000 |         █
     |         █
     |         █
     |         █
 200 |████████ █ ████████
     +-------------------→ Time
     0    3m  4m  5m   8m
```

### Breakpoint Test

**Purpose:** Continuously increase load with no ceiling until the system fails. Identifies the absolute maximum capacity.

**Configuration:**
- Linear or stepwise ramp with no plateau
- Run until errors exceed acceptable threshold or system becomes unresponsive

```
Load
     |                          ╱ ← system breaks
     |                        ╱
     |                      ╱
     |                    ╱
     |                  ╱
     |                ╱
     |              ╱
     |            ╱
     |          ╱
     |        ╱
     |      ╱
     |    ╱
     |  ╱
     |╱
     +---------------------------→ Time
```

---

## k6 Scripting

### Basic Script Structure

```javascript
// load-test.js
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const orderLatency = new Trend('order_latency', true);
const ordersCreated = new Counter('orders_created');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 VUs
    { duration: '10m', target: 50 },   // Stay at 50 VUs
    { duration: '2m', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1500'],
    http_req_failed: ['rate<0.01'],
    errors: ['rate<0.05'],
    order_latency: ['p(95)<2000'],
  },
};

// Setup: runs once before the test
export function setup() {
  const loginRes = http.post(
    'https://api.example.com/auth/login',
    JSON.stringify({ email: 'loadtest@example.com', password: 'testpassword' }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  const token = loginRes.json('accessToken');
  if (!token) {
    throw new Error('Failed to authenticate for load test');
  }

  return { token };
}

// Default function: runs once per VU iteration
export default function (data) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${data.token}`,
  };

  group('Browse Products', () => {
    // List products
    const listRes = http.get('https://api.example.com/api/products?page=1&limit=20', {
      headers,
      tags: { name: 'GET /api/products' },
    });

    check(listRes, {
      'products: status 200': (r) => r.status === 200,
      'products: has items': (r) => r.json('data.length') > 0,
    }) || errorRate.add(1);

    sleep(1); // Simulate user think time

    // View a specific product
    const products = listRes.json('data');
    if (products && products.length > 0) {
      const productId = products[Math.floor(Math.random() * products.length)].id;
      const detailRes = http.get(`https://api.example.com/api/products/${productId}`, {
        headers,
        tags: { name: 'GET /api/products/:id' },
      });

      check(detailRes, {
        'product detail: status 200': (r) => r.status === 200,
        'product detail: has price': (r) => r.json('price') !== undefined,
      }) || errorRate.add(1);
    }

    sleep(2);
  });

  group('Place Order', () => {
    const orderPayload = JSON.stringify({
      items: [
        { productId: 'prod-001', quantity: 2 },
        { productId: 'prod-002', quantity: 1 },
      ],
      shippingAddress: {
        street: '123 Load Test St',
        city: 'Testville',
        zip: '12345',
      },
    });

    const startTime = Date.now();
    const orderRes = http.post('https://api.example.com/api/orders', orderPayload, {
      headers,
      tags: { name: 'POST /api/orders' },
    });
    const duration = Date.now() - startTime;

    orderLatency.add(duration);

    const orderSuccess = check(orderRes, {
      'order: status 201': (r) => r.status === 201,
      'order: has order id': (r) => r.json('id') !== undefined,
      'order: status is created': (r) => r.json('status') === 'created',
    });

    if (orderSuccess) {
      ordersCreated.add(1);
    } else {
      errorRate.add(1);
      console.error(`Order failed: ${orderRes.status} - ${orderRes.body}`);
    }

    sleep(3);
  });
}

// Teardown: runs once after the test
export function teardown(data) {
  // Clean up test data if needed
  http.del('https://api.example.com/api/loadtest/cleanup', null, {
    headers: { Authorization: `Bearer ${data.token}` },
  });
}
```

### Handling Authentication Patterns

```javascript
// Per-VU authentication (each VU gets a unique token)
import http from 'k6/http';
import { SharedArray } from 'k6/data';
import { check } from 'k6';

// Load test users from a file (shared across VUs, read-only)
const users = new SharedArray('users', function () {
  return JSON.parse(open('./test-users.json'));
});

export const options = {
  vus: 100,
  duration: '15m',
};

export function setup() {
  // Optionally warm up caches or create test data
  return {};
}

export default function () {
  // Each VU gets a deterministic user based on VU ID
  const user = users[__VU % users.length];

  // Login (or use a pre-generated token)
  const loginRes = http.post(
    'https://api.example.com/auth/login',
    JSON.stringify({ email: user.email, password: user.password }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(loginRes, { 'login succeeded': (r) => r.status === 200 });

  if (loginRes.status !== 200) {
    console.error(`Login failed for ${user.email}: ${loginRes.status}`);
    return;
  }

  const token = loginRes.json('accessToken');

  // Use the token for subsequent requests
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  const res = http.get('https://api.example.com/api/me', { headers });
  check(res, { 'profile loaded': (r) => r.status === 200 });
}
```

### File Upload Testing

```javascript
import http from 'k6/http';
import { check } from 'k6';

const testFile = open('./fixtures/sample-report.pdf', 'b'); // binary mode

export default function () {
  const payload = {
    file: http.file(testFile, 'report.pdf', 'application/pdf'),
    description: 'Load test upload',
  };

  const res = http.post('https://api.example.com/api/uploads', payload, {
    headers: {
      Authorization: `Bearer ${__ENV.API_TOKEN}`,
    },
  });

  check(res, {
    'upload: status 201': (r) => r.status === 201,
    'upload: has file URL': (r) => r.json('url') !== undefined,
  });
}
```

---

## k6 Thresholds and Custom Metrics

### Threshold Configuration

```javascript
export const options = {
  thresholds: {
    // Built-in HTTP metrics
    http_req_duration: [
      'p(50)<200',     // 50th percentile under 200ms
      'p(95)<500',     // 95th percentile under 500ms
      'p(99)<1500',    // 99th percentile under 1500ms
      'max<5000',      // No request over 5s
    ],
    http_req_failed: [
      'rate<0.01',     // Less than 1% error rate
    ],
    http_req_waiting: [
      'p(95)<400',     // Server processing time (TTFB)
    ],

    // Thresholds scoped to specific requests using tags
    'http_req_duration{name:GET /api/products}': ['p(95)<300'],
    'http_req_duration{name:POST /api/orders}': ['p(95)<2000'],
    'http_req_duration{name:GET /api/products/:id}': ['p(95)<200'],

    // Custom metrics
    'order_latency': ['p(95)<2000', 'avg<1000'],
    'errors': ['rate<0.05'],
    'orders_created': ['count>100'],   // At least 100 orders created

    // Group duration
    'group_duration{group:::Browse Products}': ['p(95)<3000'],
    'group_duration{group:::Place Order}': ['p(95)<5000'],

    // Iteration duration
    iteration_duration: ['p(95)<15000'], // Full iteration under 15s

    // VU metrics
    vus: ['value>0'],
    vus_max: ['value<=200'],
  },
};
```

### Custom Metrics

```javascript
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Rate: percentage of non-zero values
const cacheHitRate = new Rate('cache_hit_rate');
const authFailureRate = new Rate('auth_failure_rate');

// Trend: statistical distribution (min, max, avg, median, percentiles)
const dbQueryTime = new Trend('db_query_time', true); // true = time values
const responseSize = new Trend('response_size_bytes');

// Counter: cumulative count
const totalOrders = new Counter('total_orders');
const totalRevenue = new Counter('total_revenue_cents');

// Gauge: latest value (min and max tracked automatically)
const activeConnections = new Gauge('active_connections');
const queueDepth = new Gauge('queue_depth');

export default function () {
  const res = http.get('https://api.example.com/api/data');

  // Track cache hits
  cacheHitRate.add(res.headers['X-Cache'] === 'HIT');

  // Track response size
  responseSize.add(res.body.length);

  // Track DB query time from server header
  const queryTime = parseFloat(res.headers['X-Query-Time-Ms'] || '0');
  dbQueryTime.add(queryTime);

  // Track business metrics
  if (res.status === 201) {
    const order = res.json();
    totalOrders.add(1);
    totalRevenue.add(order.totalCents);
  }

  // Track gauge from API response
  const healthRes = http.get('https://api.example.com/api/health');
  if (healthRes.status === 200) {
    activeConnections.add(healthRes.json('activeConnections'));
    queueDepth.add(healthRes.json('queueDepth'));
  }
}

export const options = {
  thresholds: {
    cache_hit_rate: ['rate>0.8'],           // 80%+ cache hit rate
    db_query_time: ['p(95)<50'],            // DB queries under 50ms at p95
    response_size_bytes: ['p(95)<102400'],  // Responses under 100KB
    total_orders: ['count>500'],            // At least 500 orders in test
    active_connections: ['value<500'],      // Connection pool not exhausted
  },
};
```

---

## k6 Scenarios

Scenarios allow you to define multiple workload patterns that run in parallel, each with its own executor, VU count, and thresholds.

### Multiple Scenarios Example

```javascript
export const options = {
  scenarios: {
    // Scenario 1: Constant browsing traffic
    browse: {
      executor: 'constant-vus',
      vus: 50,
      duration: '20m',
      exec: 'browseProducts',
      tags: { scenario: 'browse' },
      env: { SCENARIO: 'browse' },
    },

    // Scenario 2: Ramping API calls
    api_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 100 },
        { duration: '10m', target: 100 },
        { duration: '5m', target: 0 },
      ],
      exec: 'apiWorkload',
      tags: { scenario: 'api' },
    },

    // Scenario 3: Fixed request rate (RPS-based)
    order_rate: {
      executor: 'constant-arrival-rate',
      rate: 10,             // 10 iterations per timeUnit
      timeUnit: '1s',       // = 10 RPS
      duration: '20m',
      preAllocatedVUs: 50,  // Pre-allocate VUs
      maxVUs: 200,          // Scale up if needed
      exec: 'placeOrder',
      tags: { scenario: 'orders' },
    },

    // Scenario 4: Spike test with ramping arrival rate
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      stages: [
        { duration: '2m', target: 5 },     // Warm up at 5 RPS
        { duration: '30s', target: 200 },   // Spike to 200 RPS
        { duration: '2m', target: 200 },    // Hold spike
        { duration: '30s', target: 5 },     // Return to normal
        { duration: '5m', target: 5 },      // Recovery observation
      ],
      preAllocatedVUs: 100,
      maxVUs: 500,
      exec: 'apiWorkload',
      startTime: '25m',  // Start after other scenarios finish
      tags: { scenario: 'spike' },
    },

    // Scenario 5: Per-VU iterations (each VU runs exactly N iterations)
    data_migration: {
      executor: 'per-vu-iterations',
      vus: 10,
      iterations: 100,     // Each VU runs 100 iterations = 1000 total
      maxDuration: '30m',
      exec: 'migrateData',
      tags: { scenario: 'migration' },
    },

    // Scenario 6: Shared iterations (total iterations split across VUs)
    onboarding: {
      executor: 'shared-iterations',
      vus: 10,
      iterations: 200,    // 200 total iterations shared across 10 VUs
      maxDuration: '15m',
      exec: 'onboardUser',
      tags: { scenario: 'onboarding' },
    },
  },

  thresholds: {
    // Global thresholds
    http_req_duration: ['p(95)<1000'],

    // Per-scenario thresholds
    'http_req_duration{scenario:browse}': ['p(95)<300'],
    'http_req_duration{scenario:api}': ['p(95)<500'],
    'http_req_duration{scenario:orders}': ['p(95)<2000'],
    'http_req_duration{scenario:spike}': ['p(99)<5000'],
  },
};

// Scenario-specific functions
export function browseProducts() {
  const res = http.get('https://api.example.com/products', {
    tags: { name: 'GET /products' },
  });
  check(res, { 'browse: status 200': (r) => r.status === 200 });
  sleep(randomIntBetween(1, 5));
}

export function apiWorkload() {
  http.batch([
    ['GET', 'https://api.example.com/api/products', null, { tags: { name: 'GET /api/products' } }],
    ['GET', 'https://api.example.com/api/categories', null, { tags: { name: 'GET /api/categories' } }],
    ['GET', 'https://api.example.com/api/featured', null, { tags: { name: 'GET /api/featured' } }],
  ]);
  sleep(1);
}

export function placeOrder() {
  const payload = JSON.stringify({
    items: [{ productId: `prod-${randomIntBetween(1, 100)}`, quantity: 1 }],
  });
  const res = http.post('https://api.example.com/api/orders', payload, {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'POST /api/orders' },
  });
  check(res, { 'order: status 201': (r) => r.status === 201 });
}

export function migrateData() {
  // Each VU processes a batch
  const batchId = `batch-${__VU}-${__ITER}`;
  const res = http.post(
    'https://api.example.com/api/migrate',
    JSON.stringify({ batchId, size: 100 }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /api/migrate' } }
  );
  check(res, { 'migrate: status 200': (r) => r.status === 200 });
}

export function onboardUser() {
  const userId = `user-${__ITER}`;
  const steps = [
    () => http.post('https://api.example.com/api/users', JSON.stringify({ id: userId, name: `User ${__ITER}` })),
    () => http.post(`https://api.example.com/api/users/${userId}/profile`, JSON.stringify({ bio: 'Test' })),
    () => http.post(`https://api.example.com/api/users/${userId}/preferences`, JSON.stringify({ theme: 'dark' })),
  ];

  for (const step of steps) {
    const res = step();
    check(res, { 'onboard step: success': (r) => r.status < 300 });
    sleep(0.5);
  }
}

function randomIntBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
```

### Executor Reference

| Executor                    | Controls         | Use Case                                   |
|-----------------------------|------------------|--------------------------------------------|
| `constant-vus`              | VU count         | Steady-state load testing                  |
| `ramping-vus`               | VU count (ramp)  | Standard load test with ramp up/down       |
| `constant-arrival-rate`     | Request rate     | Fixed RPS regardless of response time      |
| `ramping-arrival-rate`      | Request rate     | Variable RPS (spike, ramp)                 |
| `per-vu-iterations`         | Iterations/VU    | Each VU runs a fixed number of iterations  |
| `shared-iterations`         | Total iterations | Fixed total work distributed across VUs    |
| `externally-controlled`     | External API     | Adjust VUs in real-time via REST API       |

---

## Artillery Configuration

### Basic YAML Configuration

```yaml
# artillery-config.yml
config:
  target: "https://api.example.com"
  phases:
    - name: "Warm up"
      duration: 60        # seconds
      arrivalRate: 5       # new virtual users per second
    - name: "Ramp to peak"
      duration: 120
      arrivalRate: 5
      rampTo: 50
    - name: "Sustained peak"
      duration: 300
      arrivalRate: 50
    - name: "Cool down"
      duration: 60
      arrivalRate: 50
      rampTo: 0

  defaults:
    headers:
      Content-Type: "application/json"
      Accept: "application/json"

  http:
    timeout: 10           # seconds
    maxSockets: 256

  plugins:
    expect: {}
    metrics-by-endpoint: {}

  ensure:
    thresholds:
      - http.response_time.p95: 500
      - http.response_time.p99: 1500
    conditions:
      - expression: "http.codes.200/http.responses < 0.99"
        strict: false     # Warn but don't fail

  environments:
    staging:
      target: "https://staging-api.example.com"
      phases:
        - duration: 60
          arrivalRate: 10
    production:
      target: "https://api.example.com"
      phases:
        - duration: 300
          arrivalRate: 50

  variables:
    productIds:
      - "prod-001"
      - "prod-002"
      - "prod-003"
      - "prod-004"
      - "prod-005"

  payload:
    - path: "./test-users.csv"
      fields:
        - "email"
        - "password"
      order: "sequence"    # or "random"

scenarios:
  - name: "Browse and purchase flow"
    weight: 70             # 70% of traffic
    flow:
      # Step 1: Login
      - post:
          url: "/auth/login"
          json:
            email: "{{ email }}"
            password: "{{ password }}"
          capture:
            - json: "$.accessToken"
              as: "token"
          expect:
            - statusCode: 200
            - hasProperty: "accessToken"

      # Step 2: Browse products
      - get:
          url: "/api/products?page=1&limit=20"
          headers:
            Authorization: "Bearer {{ token }}"
          capture:
            - json: "$.data[0].id"
              as: "firstProductId"
          expect:
            - statusCode: 200

      - think: 2           # 2-second pause

      # Step 3: View product detail
      - get:
          url: "/api/products/{{ firstProductId }}"
          headers:
            Authorization: "Bearer {{ token }}"
          expect:
            - statusCode: 200
            - hasProperty: "price"

      - think: 3

      # Step 4: Add to cart
      - post:
          url: "/api/cart/items"
          headers:
            Authorization: "Bearer {{ token }}"
          json:
            productId: "{{ firstProductId }}"
            quantity: 1
          expect:
            - statusCode: 201

      # Step 5: Place order
      - post:
          url: "/api/orders"
          headers:
            Authorization: "Bearer {{ token }}"
          json:
            items:
              - productId: "{{ firstProductId }}"
                quantity: 1
            shippingAddress:
              street: "123 Test St"
              city: "Loadville"
              zip: "12345"
          capture:
            - json: "$.id"
              as: "orderId"
          expect:
            - statusCode: 201
            - hasProperty: "id"

  - name: "API health monitoring"
    weight: 10             # 10% of traffic
    flow:
      - get:
          url: "/api/health"
          expect:
            - statusCode: 200
            - contentType: "application/json"
            - hasProperty: "status"

  - name: "Search workload"
    weight: 20             # 20% of traffic
    flow:
      - get:
          url: "/api/search?q=laptop&category=electronics&page=1"
          expect:
            - statusCode: 200
      - think: 1
      - get:
          url: "/api/search?q=laptop&category=electronics&page=2"
          expect:
            - statusCode: 200
```

### Artillery with Custom JavaScript

```yaml
# artillery-advanced.yml
config:
  target: "https://api.example.com"
  processor: "./artillery-helpers.js"
  phases:
    - duration: 300
      arrivalRate: 20

scenarios:
  - name: "Dynamic flow with custom logic"
    flow:
      - function: "generateUser"
      - post:
          url: "/api/users"
          json:
            name: "{{ name }}"
            email: "{{ email }}"
          capture:
            - json: "$.id"
              as: "userId"
          afterResponse: "validateResponse"
      - function: "selectRandomProducts"
      - loop:
          - post:
              url: "/api/cart/items"
              json:
                productId: "{{ $loopElement }}"
                quantity: 1
          - think: 0.5
        over: "selectedProducts"
```

```javascript
// artillery-helpers.js
const { faker } = require('@faker-js/faker');

module.exports = {
  generateUser(userContext, events, done) {
    userContext.vars.name = faker.person.fullName();
    userContext.vars.email = faker.internet.email().toLowerCase();
    return done();
  },

  selectRandomProducts(userContext, events, done) {
    const allProducts = ['prod-001', 'prod-002', 'prod-003', 'prod-004', 'prod-005'];
    const count = Math.floor(Math.random() * 3) + 1;
    const shuffled = allProducts.sort(() => 0.5 - Math.random());
    userContext.vars.selectedProducts = shuffled.slice(0, count);
    return done();
  },

  validateResponse(req, res, userContext, events, done) {
    if (res.statusCode >= 400) {
      events.emit('counter', 'errors.client_error', 1);
      console.error(`Error ${res.statusCode}: ${res.body}`);
    }

    const responseTime = res.timings?.phases?.firstByte || 0;
    if (responseTime > 1000) {
      events.emit('counter', 'warnings.slow_response', 1);
    }

    return done();
  },
};
```

### Running Artillery

```bash
# Basic run
artillery run artillery-config.yml

# Run specific environment
artillery run --environment staging artillery-config.yml

# Generate HTML report
artillery run --output results.json artillery-config.yml
artillery report results.json --output report.html

# Quick endpoint test (no config needed)
artillery quick --count 100 --num 10 https://api.example.com/api/health
```

---

## Performance Budgets

Performance budgets define measurable limits that gate deployments. They translate business requirements into technical constraints.

### Budget Definition

```yaml
# performance-budget.yml
budgets:
  api:
    latency:
      p50: 100ms
      p95: 500ms
      p99: 1500ms
    throughput:
      min_rps: 200          # Minimum requests per second
    availability:
      error_rate: 0.1%      # Less than 0.1% error rate
      uptime: 99.9%
    saturation:
      cpu: 70%              # Max CPU during peak load
      memory: 80%           # Max memory during peak load
      connections: 80%      # Max DB connection pool utilization

  frontend:
    core_web_vitals:
      lcp: 2.5s             # Largest Contentful Paint
      fid: 100ms            # First Input Delay
      cls: 0.1              # Cumulative Layout Shift
      inp: 200ms            # Interaction to Next Paint
    bundle:
      js_initial: 200KB     # Initial JS bundle (compressed)
      js_total: 500KB       # Total JS (compressed)
      css_total: 100KB      # Total CSS (compressed)
    loading:
      ttfb: 600ms           # Time to First Byte
      tti: 3.5s             # Time to Interactive
      fcp: 1.8s             # First Contentful Paint

  database:
    queries:
      p95: 50ms             # 95th percentile query time
      p99: 200ms
      slow_query_rate: 0.1% # Queries exceeding 1s
    connections:
      max_pool: 100
      avg_utilization: 60%
```

### k6 Budget Implementation

```javascript
// performance-budget-test.js
import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// API latency budgets as thresholds
export const options = {
  scenarios: {
    steady_state: {
      executor: 'constant-arrival-rate',
      rate: 200,         // 200 RPS (minimum throughput budget)
      timeUnit: '1s',
      duration: '10m',
      preAllocatedVUs: 100,
      maxVUs: 500,
    },
  },
  thresholds: {
    // Latency budgets
    http_req_duration: [
      { threshold: 'p(50)<100', abortOnFail: false },
      { threshold: 'p(95)<500', abortOnFail: true, delayAbortEval: '30s' },
      { threshold: 'p(99)<1500', abortOnFail: true, delayAbortEval: '30s' },
    ],

    // Availability budget
    http_req_failed: [
      { threshold: 'rate<0.001', abortOnFail: true, delayAbortEval: '60s' },
    ],

    // Throughput budget (tracked via custom metric)
    'http_reqs{expected_response:true}': ['rate>=200'],

    // Per-endpoint budgets
    'http_req_duration{name:GET /api/products}': ['p(95)<300'],
    'http_req_duration{name:POST /api/orders}': ['p(95)<2000'],
    'http_req_duration{name:GET /api/search}': ['p(95)<500'],
  },
};

export default function () {
  const endpoints = [
    { method: 'GET', url: '/api/products', name: 'GET /api/products', weight: 50 },
    { method: 'GET', url: '/api/search?q=test', name: 'GET /api/search', weight: 30 },
    { method: 'POST', url: '/api/orders', name: 'POST /api/orders', weight: 20 },
  ];

  // Weighted random selection
  const rand = Math.random() * 100;
  let cumulative = 0;
  let selected = endpoints[0];

  for (const ep of endpoints) {
    cumulative += ep.weight;
    if (rand <= cumulative) {
      selected = ep;
      break;
    }
  }

  const params = { tags: { name: selected.name } };

  if (selected.method === 'GET') {
    http.get(`https://api.example.com${selected.url}`, params);
  } else {
    http.post(
      `https://api.example.com${selected.url}`,
      JSON.stringify({ items: [{ productId: 'prod-001', quantity: 1 }] }),
      { ...params, headers: { 'Content-Type': 'application/json' } }
    );
  }
}
```

---

## Interpreting Results

### Key Metrics to Monitor

| Metric                     | What It Tells You                                         | Warning Sign                      |
|----------------------------|-----------------------------------------------------------|-----------------------------------|
| **p50 latency**            | Typical user experience                                   | > 200ms for API calls             |
| **p95 latency**            | Worst case for most users                                 | > 3x the p50                      |
| **p99 latency**            | Tail latency (often reveals GC pauses, lock contention)   | > 5x the p50                      |
| **Error rate**             | Percentage of failed requests                             | Any increase from baseline        |
| **Throughput (RPS)**       | Requests processed per second                             | Flattens or drops under load      |
| **VU active**              | Number of active virtual users                            | Growing while throughput flat     |
| **Iteration duration**     | Total time for one complete user journey                  | Growing over time                 |
| **http_req_waiting (TTFB)**| Server processing time (excludes network)                 | Growing faster than duration      |

### Common Patterns and Diagnosis

**Latency increases linearly with load:**
- Likely single-threaded bottleneck (single DB connection, mutex, global lock)
- Check: Does adding more application instances help?

**Latency is stable then spikes suddenly:**
- Resource saturation (connection pool exhausted, memory pressure triggers GC, swap thrashing)
- Check: Monitor connection pool utilization, memory, and GC pauses

**High p99 but acceptable p50/p95:**
- Tail latency from garbage collection, cold caches, or background jobs
- Check: Correlate spikes with GC logs or cron schedules

**Error rate increases under load:**
- Timeouts, connection refused, rate limiting
- Check: Server error logs, check for 429/503/504 status codes

**Throughput plateaus while VUs increase:**
- System is saturated. Adding more concurrent users only increases queuing time.
- This is your system's capacity ceiling under current configuration.

### Reading k6 Output

```
          /\      |------| /\
     /\  /  \     |  k6  |/  \
    /  \/    \    |      /    |
   /          \   |     /     |
  /   ________\  |    /______|
 /___/          \ |           |

     execution: local
        script: load-test.js
        output: -

     scenarios: (100.00%) 1 scenario, 200 max VUs, 14m30s max duration
                * default: Up to 200 VUs for 14m0s (gracefulRampDown: 30s)

     ✓ products: status 200
     ✓ products: has items
     ✓ order: status 201
     ✗ order: status is created
      ↳  98% — ✓ 4901 / ✗ 99

     █ Browse Products

     █ Place Order

     checks.........................: 99.50%  ✓ 19703    ✗ 99
     data_received..................: 156 MB  186 kB/s
     data_sent......................: 12 MB   14 kB/s
     errors.........................: 1.98%   ✓ 99       ✗ 4901
   ✓ http_req_blocked...............: avg=1.2ms  min=0s   med=0s    max=320ms  p(90)=0s    p(95)=0s
   ✓ http_req_connecting............: avg=0.8ms  min=0s   med=0s    max=280ms  p(90)=0s    p(95)=0s
   ✓ http_req_duration..............: avg=89ms   min=12ms med=45ms  max=4.2s   p(90)=180ms p(95)=320ms
       { expected_response:true }...: avg=82ms   min=12ms med=42ms  max=3.8s   p(90)=170ms p(95)=290ms
   ✓ http_req_failed................: 1.98%   ✓ 99       ✗ 4901
   ✓ http_req_receiving.............: avg=2ms    min=0s   med=1ms   max=120ms  p(90)=4ms   p(95)=8ms
     http_req_sending...............: avg=0.1ms  min=0s   med=0s    max=12ms   p(90)=0s    p(95)=0s
   ✓ http_req_tls_handshaking.......: avg=0.5ms  min=0s   med=0s    max=210ms  p(90)=0s    p(95)=0s
   ✓ http_req_waiting...............: avg=86ms   min=11ms med=43ms  max=4.1s   p(90)=175ms p(95)=310ms
     http_reqs......................: 10000   595.23/s
     iteration_duration.............: avg=8.2s   min=6s   med=7.8s  max=18s    p(90)=10s   p(95)=12s
     iterations.....................: 5000    297.61/s
   ✓ order_latency..................: avg=180ms  min=45ms med=120ms max=4.2s   p(90)=350ms p(95)=520ms
     orders_created.................: 4901    291.72/s
     vus............................: 1       min=1      max=200
     vus_max........................: 200     min=200    max=200
```

**How to read this:**
- The `✓` marks indicate thresholds that passed; `✗` marks indicate failures.
- `http_req_duration` p(95) of 320ms means 95% of all requests completed in under 320ms.
- `http_req_failed` at 1.98% means roughly 2% of requests returned non-2xx status codes.
- `http_reqs` rate of 595.23/s is the overall throughput.
- The difference between `http_req_duration` and `http_req_waiting` reveals network overhead.

---

## CI Integration

### GitHub Actions with k6

```yaml
# .github/workflows/load-test.yml
name: Load Test

on:
  pull_request:
    types: [labeled]
  schedule:
    - cron: '0 2 * * 1'   # Weekly Monday 2 AM
  workflow_dispatch:
    inputs:
      test_type:
        description: 'Test type to run'
        required: true
        default: 'smoke'
        type: choice
        options:
          - smoke
          - load
          - stress

jobs:
  load-test:
    if: >
      github.event_name == 'workflow_dispatch' ||
      github.event_name == 'schedule' ||
      contains(github.event.pull_request.labels.*.name, 'run-load-test')
    runs-on: ubuntu-latest
    services:
      app:
        image: ${{ github.event.repository.full_name }}:${{ github.sha }}
        ports:
          - 3000:3000
        env:
          DATABASE_URL: postgresql://postgres:postgres@postgres:5432/testdb
          NODE_ENV: production
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: testdb
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          curl -fsSL https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz -o k6.tar.gz
          tar xzf k6.tar.gz
          sudo mv k6-v0.50.0-linux-amd64/k6 /usr/local/bin/

      - name: Wait for app to be ready
        run: |
          for i in $(seq 1 30); do
            curl -sf http://localhost:3000/api/health && break
            echo "Waiting for app... (attempt $i)"
            sleep 2
          done

      - name: Seed test data
        run: |
          curl -X POST http://localhost:3000/api/test/seed \
            -H "Content-Type: application/json" \
            -d '{"users": 100, "products": 500}'

      - name: Run smoke test
        if: inputs.test_type == 'smoke' || github.event_name == 'pull_request'
        run: |
          k6 run \
            --env BASE_URL=http://localhost:3000 \
            --out json=results-smoke.json \
            tests/load/smoke.js

      - name: Run load test
        if: inputs.test_type == 'load' || github.event_name == 'schedule'
        run: |
          k6 run \
            --env BASE_URL=http://localhost:3000 \
            --out json=results-load.json \
            tests/load/load.js

      - name: Run stress test
        if: inputs.test_type == 'stress'
        run: |
          k6 run \
            --env BASE_URL=http://localhost:3000 \
            --out json=results-stress.json \
            tests/load/stress.js

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: k6-results-${{ inputs.test_type || 'smoke' }}
          path: results-*.json

      - name: Comment PR with results
        if: github.event_name == 'pull_request' && always()
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const results = fs.readFileSync('results-smoke.json', 'utf-8')
              .split('\n')
              .filter(line => line.trim())
              .map(JSON.parse)
              .filter(d => d.type === 'Point' && d.metric === 'http_req_duration');

            const durations = results.map(r => r.data.value);
            const p95 = durations.sort((a, b) => a - b)[Math.floor(durations.length * 0.95)];
            const avg = durations.reduce((a, b) => a + b, 0) / durations.length;

            const body = `## Load Test Results (Smoke)
            | Metric | Value |
            |--------|-------|
            | Requests | ${durations.length} |
            | Avg Latency | ${avg.toFixed(1)}ms |
            | p95 Latency | ${p95.toFixed(1)}ms |
            | Status | ${p95 < 500 ? '✅ PASS' : '❌ FAIL'} |`;

            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: body
            });
```

### GitLab CI with Artillery

```yaml
# .gitlab-ci.yml
load-test:
  stage: performance
  image: artilleryio/artillery:latest
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_MERGE_REQUEST_LABELS =~ /load-test/
    - when: manual
  variables:
    TARGET_URL: "https://staging-api.example.com"
  script:
    - artillery run
        --environment staging
        --output results.json
        tests/load/artillery-config.yml
    - artillery report results.json --output report.html
  artifacts:
    paths:
      - results.json
      - report.html
    expire_in: 30 days
    reports:
      performance: results.json
  allow_failure: false
```

### Grafana k6 Cloud Integration

```javascript
// k6 script with cloud output
export const options = {
  // Cloud execution settings
  ext: {
    loadimpact: {
      projectID: 12345,
      name: 'API Load Test - Staging',
      distribution: {
        'amazon:us:ashburn': { loadZone: 'amazon:us:ashburn', percent: 50 },
        'amazon:eu:dublin': { loadZone: 'amazon:eu:dublin', percent: 50 },
      },
    },
  },

  scenarios: {
    main: {
      executor: 'ramping-vus',
      stages: [
        { duration: '2m', target: 100 },
        { duration: '10m', target: 100 },
        { duration: '2m', target: 0 },
      ],
    },
  },

  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};
```

```bash
# Run on k6 Cloud
K6_CLOUD_TOKEN=your-token k6 cloud load-test.js

# Run locally but stream results to k6 Cloud
K6_CLOUD_TOKEN=your-token k6 run --out cloud load-test.js
```

---

## Advanced Patterns

### Parameterized Tests from CSV

```javascript
import { SharedArray } from 'k6/data';
import papaparse from 'https://jslib.k6.io/papaparse/5.1.1/index.js';

const csvData = new SharedArray('test data', function () {
  return papaparse.parse(open('./test-data.csv'), { header: true }).data;
});

export default function () {
  const record = csvData[Math.floor(Math.random() * csvData.length)];
  const res = http.get(`https://api.example.com/api/users/${record.userId}`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
```

### Browser-Based Load Testing (k6 Browser)

```javascript
import { browser } from 'k6/browser';
import { check } from 'k6';

export const options = {
  scenarios: {
    browser_test: {
      executor: 'constant-vus',
      vus: 5,
      duration: '5m',
      options: {
        browser: {
          type: 'chromium',
        },
      },
    },
  },
  thresholds: {
    browser_web_vital_lcp: ['p(95)<2500'],
    browser_web_vital_fid: ['p(95)<100'],
    browser_web_vital_cls: ['p(95)<0.1'],
  },
};

export default async function () {
  const page = await browser.newPage();

  try {
    await page.goto('https://example.com/dashboard', {
      waitUntil: 'networkidle',
    });

    // Interact with the page
    const searchInput = await page.locator('[data-testid="search"]');
    await searchInput.type('performance test');
    await page.keyboard.press('Enter');

    // Wait for results
    await page.locator('[data-testid="results"]').waitFor({ state: 'visible' });

    // Collect Web Vitals
    const lcp = await page.evaluate(() => {
      return new Promise((resolve) => {
        new PerformanceObserver((list) => {
          const entries = list.getEntries();
          resolve(entries[entries.length - 1]?.startTime || 0);
        }).observe({ type: 'largest-contentful-paint', buffered: true });

        setTimeout(() => resolve(0), 5000);
      });
    });

    check(lcp, {
      'LCP under 2.5s': (val) => val < 2500,
    });
  } finally {
    await page.close();
  }
}
```

### Distributed Load Testing with Docker Compose

```yaml
# docker-compose.load-test.yml
version: '3.8'

services:
  k6-master:
    image: grafana/k6:latest
    volumes:
      - ./tests/load:/scripts
      - ./results:/results
    environment:
      - K6_OUT=influxdb=http://influxdb:8086/k6
    command: run /scripts/load-test.js
    depends_on:
      - influxdb

  influxdb:
    image: influxdb:1.8
    environment:
      - INFLUXDB_DB=k6
    ports:
      - "8086:8086"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - influxdb
```

### Test Data Management

```javascript
// Generating unique test data per VU and iteration
import { SharedArray } from 'k6/data';
import { vu } from 'k6/execution';

// Shared read-only data (loaded once, shared across all VUs)
const products = new SharedArray('products', function () {
  return JSON.parse(open('./fixtures/products.json'));
});

// Per-VU unique data using VU ID and iteration count
export default function () {
  const uniqueEmail = `loadtest-vu${vu.idInTest}-iter${vu.iterationInScenario}@example.com`;

  // Deterministic but distributed product selection
  const productIndex = (vu.idInTest * 31 + vu.iterationInScenario) % products.length;
  const product = products[productIndex];

  const res = http.post(
    'https://api.example.com/api/orders',
    JSON.stringify({
      email: uniqueEmail,
      productId: product.id,
      quantity: 1,
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(res, { 'order created': (r) => r.status === 201 });
}
```
