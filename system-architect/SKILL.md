---
name: system-architect
version: "1.0.0"
description: "System architecture expert: high-level system design, scalability patterns, distributed systems, design patterns (GoF/DDD/CQRS/Event Sourcing), architectural decision records (ADR), trade-off analysis, capacity planning, and technology evaluation. Use when: (1) designing system architecture for new projects, (2) evaluating scalability and trade-offs, (3) writing architectural decision records, (4) choosing between monolith/microservices/serverless, (5) designing for high availability or fault tolerance, (6) reviewing architecture for bottlenecks. NOT for: writing implementation code, UI design, or DevOps tooling."
tags: [architecture, system-design, ddd, cqrs, event-sourcing, microservices, scalability, distributed-systems, adr]
author: "boxclaw"
references:
  - references/system-design-examples.md
  - references/pattern-catalog.md
metadata:
  boxclaw:
    emoji: "🏗️"
    category: "programming-role"
---

# System Architect

Expert guidance for designing scalable, maintainable, and resilient software systems.

## Core Competencies

### 1. Architecture Decision Framework

```
When making architecture decisions, evaluate:

1. Requirements:
   - Functional: What must the system do?
   - Non-functional: Performance, scalability, availability, security
   - Constraints: Budget, team size, timeline, existing tech

2. Trade-off Analysis (pick 2 of 3):
   - Speed of development ←→ System complexity
   - Consistency ←→ Availability (CAP theorem)
   - Cost ←→ Performance

3. Document as ADR:
   Title:    ADR-001: Use PostgreSQL for primary data store
   Status:   Accepted
   Context:  We need ACID transactions for order processing...
   Decision: Use PostgreSQL 17 with read replicas...
   Consequences: + Strong consistency, mature ecosystem
                 - Higher operational cost than DynamoDB
                 - Must manage connection pooling
```

### 2. Architecture Styles

```
Monolith:
  When: Small team (<8), early stage, unclear domain boundaries
  Pro:  Simple deployment, easy debugging, low latency
  Con:  Scaling entire app, deployment coupling

Modular Monolith:
  When: Growing team, clear domains but not ready for distributed
  Pro:  Domain isolation + monolith simplicity
  Con:  Requires discipline to maintain module boundaries

Microservices:
  When: Large org, independent team deployments, domain expertise
  Pro:  Independent scaling/deployment, technology freedom
  Con:  Network complexity, distributed transactions, observability

Serverless:
  When: Event-driven, variable traffic, minimize ops
  Pro:  Zero idle cost, auto-scaling, managed infra
  Con:  Cold starts, vendor lock-in, debugging difficulty

Event-Driven:
  When: Async workflows, loose coupling, audit requirements
  Pro:  Decoupled services, natural audit trail, replay
  Con:  Eventual consistency, complex debugging, ordering
```

### 3. Scalability Patterns

```
Vertical:   Bigger machine (quick win, ceiling)
Horizontal: More machines (stateless services, load balancer)

Read Scaling:
  Cache layer (Redis)  → 100x read reduction to DB
  Read replicas        → Distribute read queries
  CDN                  → Static assets at edge
  Materialized views   → Pre-computed aggregations

Write Scaling:
  Write-behind cache   → Batch writes
  Sharding             → Distribute by key
  CQRS                 → Separate read/write models
  Event sourcing       → Append-only, derive state

Compute Scaling:
  Queue + Workers      → Decouple producer/consumer
  Auto-scaling groups  → Scale on CPU/memory/queue depth
  Edge computing       → Process near users
```

### 4. System Design Template

```
1. REQUIREMENTS (5 min)
   Functional:     Core features, user flows
   Non-functional: QPS, latency p99, data size, availability
   Constraints:    Budget, team, compliance

2. HIGH-LEVEL DESIGN (10 min)
   Draw: Client → LB → API → Service → DB
   Identify: Components, data flow, boundaries

3. DATA MODEL (10 min)
   Entities, relationships, access patterns
   Choose: SQL vs NoSQL based on patterns
   Estimate: Storage growth, query patterns

4. DETAILED DESIGN (15 min)
   Deep dive critical path
   API contracts, caching strategy, async flows
   Handle: Failures, edge cases, hot spots

5. SCALE & RELIABILITY (10 min)
   Bottleneck identification
   Scaling strategy per component
   Failure modes and recovery
```

### 5. Design Patterns

#### Domain-Driven Design (DDD)

```
Strategic:
  Bounded Context: Clear boundary around a domain model
  Ubiquitous Language: Shared vocabulary between dev + business
  Context Map: How bounded contexts relate

Tactical:
  Entity:         Identity-based object (User, Order)
  Value Object:   Immutable, equality by value (Money, Address)
  Aggregate:      Consistency boundary (Order + OrderItems)
  Repository:     Persistence abstraction
  Domain Event:   Something notable that happened
  Domain Service: Logic that doesn't belong to an entity
```

#### CQRS + Event Sourcing

```
Command Side:           Query Side:
  Command → Validate     Event → Projection
  → Execute              → Materialized View
  → Emit Event           → Optimized for reads

Event Store:
  OrderCreated { orderId, items, total, timestamp }
  PaymentReceived { orderId, amount, method, timestamp }
  OrderShipped { orderId, trackingNo, timestamp }

Benefits:
  - Full audit trail
  - Rebuild state from events
  - Separate read/write optimization
  - Temporal queries ("state at time T")
```

### 6. Reliability Patterns

```
Circuit Breaker:
  Closed → failures exceed threshold → Open (fail fast)
  Open → timeout expires → Half-Open (test request)
  Half-Open → success → Closed

Retry with Backoff:
  1st retry: 100ms
  2nd retry: 200ms
  3rd retry: 400ms
  Add jitter: ±50ms (prevent thundering herd)

Bulkhead:
  Isolate resources per tenant/service
  One failure doesn't exhaust all connections

Timeout:
  Always set timeouts on external calls
  client: 3s, service-to-service: 1s, DB: 500ms

Graceful Degradation:
  Feature flags to disable non-critical features
  Fallback: cache → stale data → default → error
```

### 7. Capacity Planning

```
Estimation Framework:
  Users:        DAU → Peak concurrent → QPS
  Storage:      Records/day × record size × retention
  Bandwidth:    QPS × avg response size
  Compute:      QPS / requests-per-instance = instances

Example (Social Media Feed):
  100M DAU, 20% peak = 20M concurrent
  Each user: 10 feed requests/hour = 55K QPS
  Feed response: ~50KB = 2.75 GB/s bandwidth
  Storage: 500M posts/day × 1KB = 500GB/day = 182TB/year
```

## Workflow

```
1. Gather requirements → functional + non-functional
2. Identify bounded contexts → domain decomposition
3. Choose architecture style → monolith/micro/serverless
4. Design data model → entities, access patterns
5. Design APIs → contracts between components
6. Plan for scale → caching, queues, sharding
7. Plan for failure → circuit breakers, retries, fallbacks
8. Document as ADRs → decisions + rationale
9. Review with team → challenge assumptions
```

## References

- **System design examples**: See [references/system-design-examples.md](references/system-design-examples.md)
- **Pattern catalog**: See [references/pattern-catalog.md](references/pattern-catalog.md)
