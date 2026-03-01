# Software Architecture Pattern Catalog

Detailed implementation guide for advanced architecture patterns used in production distributed systems. Each pattern includes problem context, solution, implementation code, trade-offs, and real-world considerations.

---

## Table of Contents

1. [CQRS (Command Query Responsibility Segregation)](#1-cqrs)
2. [Event Sourcing with Snapshots](#2-event-sourcing-with-snapshots)
3. [Saga Pattern](#3-saga-pattern)
4. [API Gateway Pattern](#4-api-gateway-pattern)
5. [Sidecar / Ambassador Pattern](#5-sidecar--ambassador-pattern)
6. [Strangler Fig (Migration)](#6-strangler-fig)
7. [Backend-for-Frontend (BFF)](#7-backend-for-frontend-bff)
8. [Circuit Breaker with State Machine](#8-circuit-breaker-with-state-machine)
9. [Outbox Pattern for Reliable Messaging](#9-outbox-pattern)
10. [Idempotency Keys for APIs](#10-idempotency-keys-for-apis)

---

## 1. CQRS

### Problem

A single data model serving both writes (commands) and reads (queries) forces compromises. Write-optimized schemas (normalized, with foreign keys and constraints) are poor for complex reads. Read-optimized schemas (denormalized, with pre-computed aggregates) are poor for writes. The result: either reads are slow or writes are complex, and scaling both together is expensive.

### Solution

Separate the system into two sides:
- **Command side:** Handles writes. Validates business rules, applies state changes, emits domain events.
- **Query side:** Handles reads. Maintains denormalized projections optimized for specific query patterns.

The two sides are synchronized through domain events, usually asynchronously.

### Architecture

```
                    Commands                        Queries
                    ────────                        ────────
┌─────────┐    ┌──────────────┐              ┌──────────────┐    ┌──────────┐
│ Client   │───►│ Command API  │              │  Query API   │◄───│  Client  │
└─────────┘    └──────┬───────┘              └──────┬───────┘    └──────────┘
                      │                             │
               ┌──────▼───────┐              ┌──────▼───────┐
               │   Command    │              │   Query      │
               │   Handler    │              │   Handler    │
               └──────┬───────┘              └──────┬───────┘
                      │                             │
               ┌──────▼───────┐              ┌──────▼───────┐
               │  Write DB    │              │  Read DB     │
               │ (normalized  │──── events ──►│ (denormalized│
               │  PostgreSQL) │              │  projections)│
               └──────────────┘              └──────────────┘
                                                    │
                                              Could be Redis,
                                              Elasticsearch,
                                              or another PG
                                              with flat views
```

### Detailed Implementation

```python
# ============================================================
# Command Side: Handles writes with full validation
# ============================================================

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID, uuid4
import json

# --- Commands (intent to change state) ---

@dataclass(frozen=True)
class CreateOrderCommand:
    order_id: UUID
    customer_id: int
    items: list  # [{product_id, quantity, unit_price}]
    shipping_address: dict
    idempotency_key: str

@dataclass(frozen=True)
class CancelOrderCommand:
    order_id: UUID
    reason: str
    cancelled_by: int

# --- Domain Events (facts that happened) ---

@dataclass(frozen=True)
class OrderCreatedEvent:
    order_id: UUID
    customer_id: int
    items: list
    total_amount: int  # cents
    created_at: datetime

@dataclass(frozen=True)
class OrderCancelledEvent:
    order_id: UUID
    reason: str
    cancelled_by: int
    cancelled_at: datetime

# --- Command Handler ---

class OrderCommandHandler:
    """Processes commands, enforces business rules, emits events."""

    def __init__(self, order_repo, event_publisher, idempotency_store):
        self.order_repo = order_repo
        self.event_publisher = event_publisher
        self.idempotency_store = idempotency_store

    async def handle_create_order(self, cmd: CreateOrderCommand) -> dict:
        # Idempotency check
        existing = await self.idempotency_store.get(cmd.idempotency_key)
        if existing:
            return existing

        # Business rule validation
        if not cmd.items:
            raise ValidationError("Order must contain at least one item")

        total_amount = sum(
            item['quantity'] * item['unit_price'] for item in cmd.items
        )
        if total_amount <= 0:
            raise ValidationError("Order total must be positive")

        if total_amount > 1_000_000_00:  # $1M limit in cents
            raise ValidationError("Order exceeds maximum amount")

        # Persist the aggregate
        order = Order(
            order_id=cmd.order_id,
            customer_id=cmd.customer_id,
            items=cmd.items,
            total_amount=total_amount,
            status='created',
            created_at=datetime.now(timezone.utc),
        )
        await self.order_repo.save(order)

        # Emit domain event
        event = OrderCreatedEvent(
            order_id=cmd.order_id,
            customer_id=cmd.customer_id,
            items=cmd.items,
            total_amount=total_amount,
            created_at=order.created_at,
        )
        await self.event_publisher.publish('order.created', event)

        # Store idempotency result
        result = {'order_id': str(cmd.order_id), 'status': 'created'}
        await self.idempotency_store.set(cmd.idempotency_key, result, ttl=86400)

        return result

    async def handle_cancel_order(self, cmd: CancelOrderCommand) -> dict:
        order = await self.order_repo.get(cmd.order_id)
        if not order:
            raise NotFoundError(f"Order {cmd.order_id} not found")

        # Business rule: can only cancel orders in certain states
        if order.status not in ('created', 'confirmed'):
            raise BusinessRuleError(
                f"Cannot cancel order in '{order.status}' status"
            )

        order.status = 'cancelled'
        order.cancelled_at = datetime.now(timezone.utc)
        order.cancel_reason = cmd.reason
        await self.order_repo.save(order)

        event = OrderCancelledEvent(
            order_id=cmd.order_id,
            reason=cmd.reason,
            cancelled_by=cmd.cancelled_by,
            cancelled_at=order.cancelled_at,
        )
        await self.event_publisher.publish('order.cancelled', event)

        return {'order_id': str(cmd.order_id), 'status': 'cancelled'}


# ============================================================
# Query Side: Denormalized read models (projections)
# ============================================================

class OrderProjection:
    """
    Consumes domain events and maintains a denormalized read model.
    Optimized for the specific queries the UI needs.
    """

    def __init__(self, read_db):
        self.read_db = read_db

    async def handle_order_created(self, event: OrderCreatedEvent):
        """Project OrderCreated into the read model."""
        # Denormalized: all data needed for the order list view in one row
        await self.read_db.execute("""
            INSERT INTO order_read_model (
                order_id, customer_id, customer_name, customer_email,
                total_amount, item_count, status, created_at, updated_at
            )
            SELECT
                :order_id, c.id, c.name, c.email,
                :total_amount, :item_count, 'created', :created_at, :created_at
            FROM customers c
            WHERE c.id = :customer_id
        """, {
            'order_id': str(event.order_id),
            'customer_id': event.customer_id,
            'total_amount': event.total_amount,
            'item_count': sum(i['quantity'] for i in event.items),
            'created_at': event.created_at,
        })

        # Also project into the per-item read model for order detail view
        for item in event.items:
            await self.read_db.execute("""
                INSERT INTO order_items_read_model (
                    order_id, product_id, product_name, quantity,
                    unit_price, line_total
                )
                SELECT
                    :order_id, p.id, p.name, :quantity,
                    :unit_price, :line_total
                FROM products p
                WHERE p.id = :product_id
            """, {
                'order_id': str(event.order_id),
                'product_id': item['product_id'],
                'quantity': item['quantity'],
                'unit_price': item['unit_price'],
                'line_total': item['quantity'] * item['unit_price'],
            })

    async def handle_order_cancelled(self, event: OrderCancelledEvent):
        """Update the read model when an order is cancelled."""
        await self.read_db.execute("""
            UPDATE order_read_model
            SET status = 'cancelled',
                cancel_reason = :reason,
                updated_at = :cancelled_at
            WHERE order_id = :order_id
        """, {
            'order_id': str(event.order_id),
            'reason': event.reason,
            'cancelled_at': event.cancelled_at,
        })


# ============================================================
# Query Handler: Serves reads from the denormalized model
# ============================================================

class OrderQueryHandler:
    """Handles read queries against the denormalized read model."""

    def __init__(self, read_db):
        self.read_db = read_db

    async def get_customer_orders(
        self, customer_id: int, page: int = 1, page_size: int = 20
    ) -> dict:
        """Fast query: single table scan, no joins needed."""
        offset = (page - 1) * page_size
        rows = await self.read_db.fetch_all("""
            SELECT
                order_id, total_amount, item_count, status,
                customer_name, created_at, updated_at
            FROM order_read_model
            WHERE customer_id = :customer_id
            ORDER BY created_at DESC
            LIMIT :limit OFFSET :offset
        """, {
            'customer_id': customer_id,
            'limit': page_size,
            'offset': offset,
        })
        return {'orders': rows, 'page': page, 'page_size': page_size}

    async def get_order_detail(self, order_id: str) -> dict:
        """Get full order details including line items."""
        order = await self.read_db.fetch_one("""
            SELECT * FROM order_read_model WHERE order_id = :order_id
        """, {'order_id': order_id})

        items = await self.read_db.fetch_all("""
            SELECT * FROM order_items_read_model WHERE order_id = :order_id
        """, {'order_id': order_id})

        return {'order': order, 'items': items}
```

### Read Model Schema

```sql
-- Denormalized read model: optimized for order list queries
CREATE TABLE order_read_model (
    order_id UUID PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    customer_name TEXT NOT NULL,
    customer_email TEXT,
    total_amount BIGINT NOT NULL,
    item_count INT NOT NULL,
    status VARCHAR(20) NOT NULL,
    cancel_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_orm_customer ON order_read_model (customer_id, created_at DESC);
CREATE INDEX idx_orm_status ON order_read_model (status, created_at DESC);

-- Denormalized read model: optimized for order detail queries
CREATE TABLE order_items_read_model (
    order_id UUID NOT NULL,
    product_id BIGINT NOT NULL,
    product_name TEXT NOT NULL,
    quantity INT NOT NULL,
    unit_price BIGINT NOT NULL,
    line_total BIGINT NOT NULL,
    PRIMARY KEY (order_id, product_id)
);
```

### When to Use / When to Avoid

**Use CQRS when:**
- Read and write workloads have very different performance characteristics.
- You need multiple read models for different query patterns (list view, search, reporting).
- Read and write sides need to scale independently.

**Avoid CQRS when:**
- Simple CRUD where one model serves both sides adequately.
- Eventual consistency between read and write models is unacceptable.
- The added infrastructure complexity is not justified by the benefits.

### Trade-offs

| Advantage | Disadvantage |
|---|---|
| Read and write models optimized independently | Eventual consistency between sides |
| Scales reads and writes separately | Two databases to operate |
| Multiple read models for different views | Event processing lag |
| Simpler query logic (no complex joins) | More code and infrastructure |

---

## 2. Event Sourcing with Snapshots

### Problem

Traditional CRUD systems overwrite state, losing the history of how the current state was reached. For domains that require audit trails, temporal queries, or the ability to reconstruct past states, this is insufficient.

### Solution

Store every state change as an immutable event in an append-only event store. The current state of an entity is derived by replaying all events from the beginning. To avoid replaying thousands of events on every access, periodically save snapshots.

### Architecture

```
  Command ──► Aggregate ──► Event Store (append-only)
                               │
                               ├── Event 1: AccountOpened  {balance: 0}
                               ├── Event 2: FundsDeposited {amount: 500}
                               ├── Event 3: FundsWithdrawn {amount: 200}
                               ├── *** SNAPSHOT ***        {balance: 300}
                               ├── Event 4: FundsDeposited {amount: 100}
                               └── Event 5: FundsWithdrawn {amount: 50}

  To load current state:
    1. Find latest snapshot (balance: 300)
    2. Replay events AFTER the snapshot (Event 4, Event 5)
    3. Current state: 300 + 100 - 50 = 350
```

### Detailed Implementation

```python
# ============================================================
# Domain Events
# ============================================================

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional
from uuid import UUID, uuid4
import json

@dataclass(frozen=True)
class DomainEvent:
    event_id: UUID = field(default_factory=uuid4)
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

@dataclass(frozen=True)
class AccountOpened(DomainEvent):
    account_id: UUID = None
    owner_name: str = ""
    initial_balance: int = 0  # cents

@dataclass(frozen=True)
class FundsDeposited(DomainEvent):
    account_id: UUID = None
    amount: int = 0           # cents
    reference: str = ""

@dataclass(frozen=True)
class FundsWithdrawn(DomainEvent):
    account_id: UUID = None
    amount: int = 0           # cents
    reference: str = ""

@dataclass(frozen=True)
class AccountFrozen(DomainEvent):
    account_id: UUID = None
    reason: str = ""

# ============================================================
# Aggregate: Applies events to build state
# ============================================================

class BankAccount:
    """
    Event-sourced aggregate. State is derived from events.
    Business rules are validated before new events are produced.
    """

    def __init__(self):
        self.account_id: Optional[UUID] = None
        self.owner_name: str = ""
        self.balance: int = 0        # cents
        self.is_frozen: bool = False
        self.version: int = 0        # event sequence number
        self._pending_events: List[DomainEvent] = []

    # --- Command Methods (validate + produce events) ---

    def open(self, account_id: UUID, owner_name: str, initial_balance: int = 0):
        if self.account_id is not None:
            raise BusinessRuleError("Account already exists")
        if initial_balance < 0:
            raise BusinessRuleError("Initial balance cannot be negative")

        self._apply(AccountOpened(
            account_id=account_id,
            owner_name=owner_name,
            initial_balance=initial_balance,
        ))

    def deposit(self, amount: int, reference: str = ""):
        self._assert_exists()
        self._assert_not_frozen()
        if amount <= 0:
            raise BusinessRuleError("Deposit amount must be positive")

        self._apply(FundsDeposited(
            account_id=self.account_id,
            amount=amount,
            reference=reference,
        ))

    def withdraw(self, amount: int, reference: str = ""):
        self._assert_exists()
        self._assert_not_frozen()
        if amount <= 0:
            raise BusinessRuleError("Withdrawal amount must be positive")
        if self.balance < amount:
            raise InsufficientFundsError(
                f"Balance {self.balance} insufficient for withdrawal of {amount}"
            )

        self._apply(FundsWithdrawn(
            account_id=self.account_id,
            amount=amount,
            reference=reference,
        ))

    def freeze(self, reason: str):
        self._assert_exists()
        if self.is_frozen:
            raise BusinessRuleError("Account is already frozen")

        self._apply(AccountFrozen(
            account_id=self.account_id,
            reason=reason,
        ))

    # --- Event Application (state transitions) ---

    def _apply(self, event: DomainEvent):
        """Apply an event: update state and record as pending."""
        self._mutate(event)
        self._pending_events.append(event)

    def _mutate(self, event: DomainEvent):
        """Pure state mutation based on event type."""
        if isinstance(event, AccountOpened):
            self.account_id = event.account_id
            self.owner_name = event.owner_name
            self.balance = event.initial_balance
        elif isinstance(event, FundsDeposited):
            self.balance += event.amount
        elif isinstance(event, FundsWithdrawn):
            self.balance -= event.amount
        elif isinstance(event, AccountFrozen):
            self.is_frozen = True
        self.version += 1

    def load_from_events(self, events: List[DomainEvent]):
        """Replay events to rebuild state."""
        for event in events:
            self._mutate(event)

    def load_from_snapshot(self, snapshot: dict):
        """Load state from a snapshot."""
        self.account_id = UUID(snapshot['account_id'])
        self.owner_name = snapshot['owner_name']
        self.balance = snapshot['balance']
        self.is_frozen = snapshot['is_frozen']
        self.version = snapshot['version']

    def take_snapshot(self) -> dict:
        """Create a snapshot of the current state."""
        return {
            'account_id': str(self.account_id),
            'owner_name': self.owner_name,
            'balance': self.balance,
            'is_frozen': self.is_frozen,
            'version': self.version,
        }

    def get_pending_events(self) -> List[DomainEvent]:
        events = self._pending_events.copy()
        self._pending_events.clear()
        return events

    # --- Guard Methods ---

    def _assert_exists(self):
        if self.account_id is None:
            raise BusinessRuleError("Account does not exist")

    def _assert_not_frozen(self):
        if self.is_frozen:
            raise BusinessRuleError("Account is frozen")


# ============================================================
# Event Store: Persistence layer
# ============================================================

class PostgresEventStore:
    """
    Append-only event store with snapshot support.
    Uses optimistic concurrency control via version numbers.
    """

    def __init__(self, engine):
        self.engine = engine

    async def append_events(
        self,
        aggregate_id: UUID,
        events: List[DomainEvent],
        expected_version: int,
    ):
        """
        Append events with optimistic concurrency check.
        Raises ConcurrencyError if expected_version does not match.
        """
        async with self.engine.begin() as conn:
            # Check current version (optimistic lock)
            result = await conn.execute("""
                SELECT COALESCE(MAX(version), 0) AS current_version
                FROM event_store
                WHERE aggregate_id = :agg_id
            """, {'agg_id': str(aggregate_id)})
            current_version = result.scalar()

            if current_version != expected_version:
                raise ConcurrencyError(
                    f"Expected version {expected_version}, "
                    f"but current is {current_version}"
                )

            # Append events
            for i, event in enumerate(events):
                version = expected_version + i + 1
                await conn.execute("""
                    INSERT INTO event_store (
                        event_id, aggregate_id, aggregate_type,
                        event_type, event_data, version, created_at
                    ) VALUES (
                        :event_id, :agg_id, :agg_type,
                        :event_type, :event_data, :version, :created_at
                    )
                """, {
                    'event_id': str(event.event_id),
                    'agg_id': str(aggregate_id),
                    'agg_type': 'BankAccount',
                    'event_type': type(event).__name__,
                    'event_data': json.dumps(self._serialize_event(event)),
                    'version': version,
                    'created_at': event.timestamp,
                })

    async def load_events(
        self,
        aggregate_id: UUID,
        after_version: int = 0,
    ) -> List[DomainEvent]:
        """Load events for an aggregate, optionally after a given version."""
        result = await self.engine.fetch_all("""
            SELECT event_type, event_data, version
            FROM event_store
            WHERE aggregate_id = :agg_id
              AND version > :after_version
            ORDER BY version ASC
        """, {'agg_id': str(aggregate_id), 'after_version': after_version})

        return [self._deserialize_event(row) for row in result]

    async def save_snapshot(self, aggregate_id: UUID, snapshot: dict, version: int):
        """Save a snapshot for faster aggregate loading."""
        await self.engine.execute("""
            INSERT INTO snapshots (aggregate_id, aggregate_type, snapshot_data, version, created_at)
            VALUES (:agg_id, :agg_type, :data, :version, NOW())
            ON CONFLICT (aggregate_id) DO UPDATE SET
                snapshot_data = EXCLUDED.snapshot_data,
                version = EXCLUDED.version,
                created_at = NOW()
        """, {
            'agg_id': str(aggregate_id),
            'agg_type': 'BankAccount',
            'data': json.dumps(snapshot),
            'version': version,
        })

    async def load_snapshot(self, aggregate_id: UUID) -> Optional[dict]:
        """Load the latest snapshot for an aggregate."""
        result = await self.engine.fetch_one("""
            SELECT snapshot_data, version
            FROM snapshots
            WHERE aggregate_id = :agg_id
        """, {'agg_id': str(aggregate_id)})

        if result:
            return {
                'data': json.loads(result['snapshot_data']),
                'version': result['version'],
            }
        return None

    def _serialize_event(self, event: DomainEvent) -> dict:
        """Convert a domain event to a serializable dict."""
        data = {}
        for key, value in event.__dict__.items():
            if isinstance(value, UUID):
                data[key] = str(value)
            elif isinstance(value, datetime):
                data[key] = value.isoformat()
            else:
                data[key] = value
        return data

    def _deserialize_event(self, row) -> DomainEvent:
        """Reconstruct a domain event from stored data."""
        event_type = row['event_type']
        event_data = json.loads(row['event_data'])
        event_classes = {
            'AccountOpened': AccountOpened,
            'FundsDeposited': FundsDeposited,
            'FundsWithdrawn': FundsWithdrawn,
            'AccountFrozen': AccountFrozen,
        }
        cls = event_classes[event_type]
        # Convert UUID strings back to UUID objects
        if 'account_id' in event_data and event_data['account_id']:
            event_data['account_id'] = UUID(event_data['account_id'])
        if 'event_id' in event_data:
            event_data['event_id'] = UUID(event_data['event_id'])
        if 'timestamp' in event_data:
            event_data['timestamp'] = datetime.fromisoformat(event_data['timestamp'])
        return cls(**event_data)


# ============================================================
# Repository: Combines event store + snapshots
# ============================================================

SNAPSHOT_INTERVAL = 100  # Take a snapshot every 100 events

class BankAccountRepository:
    """
    Loads aggregates from events with snapshot optimization.
    Saves new events and creates snapshots when needed.
    """

    def __init__(self, event_store: PostgresEventStore):
        self.event_store = event_store

    async def load(self, account_id: UUID) -> BankAccount:
        account = BankAccount()

        # 1. Try to load from snapshot
        snapshot = await self.event_store.load_snapshot(account_id)
        after_version = 0

        if snapshot:
            account.load_from_snapshot(snapshot['data'])
            after_version = snapshot['version']

        # 2. Load events after the snapshot
        events = await self.event_store.load_events(account_id, after_version)
        account.load_from_events(events)

        return account

    async def save(self, account: BankAccount):
        pending = account.get_pending_events()
        if not pending:
            return

        expected_version = account.version - len(pending)

        # Append events with optimistic concurrency
        await self.event_store.append_events(
            aggregate_id=account.account_id,
            events=pending,
            expected_version=expected_version,
        )

        # Snapshot if we have crossed the interval threshold
        if account.version % SNAPSHOT_INTERVAL == 0:
            await self.event_store.save_snapshot(
                aggregate_id=account.account_id,
                snapshot=account.take_snapshot(),
                version=account.version,
            )
```

### Database Schema

```sql
-- Event store (append-only)
CREATE TABLE event_store (
    event_id UUID PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    version INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    UNIQUE (aggregate_id, version)  -- optimistic concurrency control
);

CREATE INDEX idx_event_store_aggregate
    ON event_store (aggregate_id, version ASC);

-- Snapshots (upserted)
CREATE TABLE snapshots (
    aggregate_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    snapshot_data JSONB NOT NULL,
    version INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);
```

### Snapshot Strategy

| Strategy | When to Snapshot | Pros | Cons |
|---|---|---|---|
| Every N events | Every 100 events | Predictable, simple | Can be stale for low-activity aggregates |
| Time-based | Every hour/day | Good for background processing | May snapshot unnecessarily |
| On read, if stale | If events_since_snapshot > threshold | Lazy, no wasted snapshots | First read after many events is slow |
| Hybrid | Every N events OR on read if stale | Best of both approaches | Slightly more complex |

### Trade-offs

| Advantage | Disadvantage |
|---|---|
| Complete audit trail | Event schema evolution (upcasting) |
| Temporal queries (state at any point in time) | Eventual consistency if projecting |
| Natural fit for CQRS | Replay can be slow without snapshots |
| Debug by replaying events | Higher storage (events accumulate) |
| Event replay for migrations | Steeper learning curve |

---

## 3. Saga Pattern

### Problem

In a microservice architecture, a business operation may span multiple services. Traditional distributed transactions (2PC) are too slow and tightly coupled. You need a way to maintain data consistency across services without distributed locks.

### Solution

Break the transaction into a sequence of local transactions. Each service performs its own local transaction and publishes an event or calls the next step. If any step fails, compensating transactions undo the completed steps in reverse order.

### Orchestration vs Choreography

```
ORCHESTRATION (Central Coordinator):
┌────────────────────────────────┐
│      Order Saga Orchestrator   │
│                                │
│  Step 1: Reserve Inventory ────┼──► Inventory Service
│    (compensate: Release)       │
│                                │
│  Step 2: Process Payment ──────┼──► Payment Service
│    (compensate: Refund)        │
│                                │
│  Step 3: Arrange Shipping ─────┼──► Shipping Service
│    (compensate: Cancel)        │
│                                │
│  Step 4: Send Confirmation ────┼──► Notification Service
│    (no compensation needed)    │
└────────────────────────────────┘

CHOREOGRAPHY (Event-Driven):
Order Svc       Inventory Svc     Payment Svc      Shipping Svc
    │                │                 │                 │
    │─OrderCreated──►│                 │                 │
    │                │─Inventory       │                 │
    │                │  Reserved──────►│                 │
    │                │                 │─Payment         │
    │                │                 │  Processed─────►│
    │                │                 │                 │─Shipped──►
    │                │                 │                 │
    │◄──────────────────────────── Saga Complete ───────►│
```

### Orchestration Implementation

```python
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Optional, List, Any
from uuid import UUID, uuid4
import asyncio
import json

class SagaStepStatus(Enum):
    PENDING = 'pending'
    RUNNING = 'running'
    COMPLETED = 'completed'
    FAILED = 'failed'
    COMPENSATING = 'compensating'
    COMPENSATED = 'compensated'

@dataclass
class SagaStep:
    name: str
    action: Callable       # async function to execute
    compensation: Optional[Callable]  # async function to undo
    status: SagaStepStatus = SagaStepStatus.PENDING
    result: Any = None
    error: Optional[str] = None
    retries: int = 0
    max_retries: int = 3

@dataclass
class SagaState:
    saga_id: UUID = field(default_factory=uuid4)
    saga_type: str = ""
    status: str = 'running'
    current_step: int = 0
    steps: List[dict] = field(default_factory=list)
    context: dict = field(default_factory=dict)
    started_at: Optional[str] = None
    completed_at: Optional[str] = None

class SagaOrchestrator:
    """
    Orchestrates a multi-step saga with compensating transactions.
    Persists state for recovery from crashes.
    """

    def __init__(self, state_store, event_publisher):
        self.state_store = state_store
        self.event_publisher = event_publisher

    async def execute(
        self,
        saga_type: str,
        steps: List[SagaStep],
        context: dict,
    ) -> dict:
        """Execute a saga: run steps in order, compensate on failure."""
        saga_id = uuid4()
        state = SagaState(
            saga_id=saga_id,
            saga_type=saga_type,
            context=context,
            started_at=datetime.now(timezone.utc).isoformat(),
        )
        await self._save_state(state)

        completed_steps = []

        for i, step in enumerate(steps):
            state.current_step = i
            step.status = SagaStepStatus.RUNNING
            await self._save_state(state)

            try:
                # Execute the step action with retry
                result = await self._execute_with_retry(step, context)
                step.status = SagaStepStatus.COMPLETED
                step.result = result
                context[f'{step.name}_result'] = result
                completed_steps.append(step)
                await self._save_state(state)

            except Exception as e:
                step.status = SagaStepStatus.FAILED
                step.error = str(e)
                await self._save_state(state)

                # Compensate completed steps in reverse order
                await self._compensate(completed_steps, context, state)

                state.status = 'failed'
                state.completed_at = datetime.now(timezone.utc).isoformat()
                await self._save_state(state)

                await self.event_publisher.publish('saga.failed', {
                    'saga_id': str(saga_id),
                    'saga_type': saga_type,
                    'failed_step': step.name,
                    'error': str(e),
                })

                raise SagaFailedError(
                    f"Saga {saga_type} failed at step '{step.name}': {e}"
                )

        state.status = 'completed'
        state.completed_at = datetime.now(timezone.utc).isoformat()
        await self._save_state(state)

        await self.event_publisher.publish('saga.completed', {
            'saga_id': str(saga_id),
            'saga_type': saga_type,
        })

        return context

    async def _execute_with_retry(
        self, step: SagaStep, context: dict
    ) -> Any:
        """Execute a step with exponential backoff retry."""
        last_error = None
        for attempt in range(step.max_retries + 1):
            try:
                return await step.action(context)
            except RetryableError as e:
                last_error = e
                step.retries = attempt + 1
                if attempt < step.max_retries:
                    delay = 2 ** attempt  # exponential backoff
                    await asyncio.sleep(delay)
            except Exception:
                raise  # non-retryable errors fail immediately
        raise last_error

    async def _compensate(
        self, completed_steps: List[SagaStep], context: dict, state: SagaState
    ):
        """Run compensating transactions in reverse order."""
        for step in reversed(completed_steps):
            if step.compensation is None:
                continue

            step.status = SagaStepStatus.COMPENSATING
            await self._save_state(state)

            try:
                await step.compensation(context)
                step.status = SagaStepStatus.COMPENSATED
            except Exception as e:
                # Compensation failure is critical -- needs manual intervention
                step.status = SagaStepStatus.FAILED
                step.error = f"COMPENSATION_FAILED: {e}"
                await self.event_publisher.publish('saga.compensation_failed', {
                    'saga_id': str(state.saga_id),
                    'step': step.name,
                    'error': str(e),
                })
            await self._save_state(state)

    async def _save_state(self, state: SagaState):
        """Persist saga state for crash recovery."""
        await self.state_store.save(state)


# ============================================================
# Usage: Order Processing Saga
# ============================================================

async def create_order_saga(order_data: dict):
    """Define and execute the order processing saga."""
    orchestrator = SagaOrchestrator(state_store, event_publisher)

    steps = [
        SagaStep(
            name='reserve_inventory',
            action=lambda ctx: inventory_service.reserve(
                items=ctx['items'],
                order_id=ctx['order_id'],
            ),
            compensation=lambda ctx: inventory_service.release(
                reservation_id=ctx['reserve_inventory_result']['reservation_id'],
            ),
        ),
        SagaStep(
            name='process_payment',
            action=lambda ctx: payment_service.charge(
                customer_id=ctx['customer_id'],
                amount=ctx['total_amount'],
                idempotency_key=f"order-{ctx['order_id']}",
            ),
            compensation=lambda ctx: payment_service.refund(
                payment_id=ctx['process_payment_result']['payment_id'],
                idempotency_key=f"refund-order-{ctx['order_id']}",
            ),
        ),
        SagaStep(
            name='create_shipment',
            action=lambda ctx: shipping_service.create_shipment(
                order_id=ctx['order_id'],
                address=ctx['shipping_address'],
                items=ctx['items'],
            ),
            compensation=lambda ctx: shipping_service.cancel_shipment(
                shipment_id=ctx['create_shipment_result']['shipment_id'],
            ),
        ),
        SagaStep(
            name='send_confirmation',
            action=lambda ctx: notification_service.send_order_confirmation(
                customer_id=ctx['customer_id'],
                order_id=ctx['order_id'],
            ),
            compensation=None,  # no compensation for notifications
        ),
    ]

    result = await orchestrator.execute(
        saga_type='create_order',
        steps=steps,
        context=order_data,
    )
    return result
```

### Choosing Orchestration vs Choreography

| Factor | Orchestration | Choreography |
|---|---|---|
| **Number of steps** | Good for 4+ steps | Best for 2-3 steps |
| **Visibility** | Full workflow visible in orchestrator | Flow spread across services |
| **Coupling** | Orchestrator knows all participants | Services only know their events |
| **Complexity** | Centralized, easier to debug | Distributed, harder to trace |
| **Single point of failure** | Orchestrator is a dependency | No single point |
| **Testing** | Can test the full saga in isolation | Must test with all services |

---

## 4. API Gateway Pattern

### Problem

Clients must call many microservices directly, each with different protocols, authentication mechanisms, and addresses. Cross-cutting concerns (auth, rate limiting, logging) are duplicated across services.

### Solution

A single entry point that routes requests, handles cross-cutting concerns, and may aggregate responses from multiple backend services.

### Implementation with Request Routing

```python
# API Gateway configuration (Kong/NGINX-like routing)

# gateway_config.yaml
"""
services:
  - name: user-service
    url: http://user-service:8080
    routes:
      - paths: ["/api/v1/users", "/api/v1/users/*"]
        methods: ["GET", "POST", "PUT", "DELETE"]
    plugins:
      - name: jwt-auth
      - name: rate-limiting
        config: { requests_per_second: 100 }

  - name: order-service
    url: http://order-service:8080
    routes:
      - paths: ["/api/v1/orders", "/api/v1/orders/*"]
        methods: ["GET", "POST", "PUT"]
    plugins:
      - name: jwt-auth
      - name: rate-limiting
        config: { requests_per_second: 50 }

  - name: product-service
    url: http://product-service:8080
    routes:
      - paths: ["/api/v1/products", "/api/v1/products/*"]
        methods: ["GET"]
    plugins:
      - name: rate-limiting
        config: { requests_per_second: 200 }
      - name: response-cache
        config: { ttl_seconds: 60 }

global_plugins:
  - name: cors
    config:
      allowed_origins: ["https://app.example.com"]
      allowed_methods: ["GET", "POST", "PUT", "DELETE"]
  - name: request-logging
  - name: request-id
    config: { header: "X-Request-ID" }
  - name: circuit-breaker
    config:
      failure_threshold: 50
      window_seconds: 60
      recovery_timeout: 30
"""
```

### Response Aggregation

```python
import asyncio
from typing import Dict

class APIGatewayAggregator:
    """
    Aggregates responses from multiple backend services into
    a single response for the client.
    """

    def __init__(self, service_registry: dict):
        self.services = service_registry

    async def get_order_detail(self, order_id: str, user_token: str) -> dict:
        """
        Aggregate order details from multiple services in parallel.
        The client makes one call; the gateway makes three.
        """
        headers = {'Authorization': f'Bearer {user_token}'}

        # Fan out requests to three services in parallel
        order_task = self._call_service(
            'order-service', f'/api/v1/orders/{order_id}', headers
        )
        # We'll get the customer_id from the order response,
        # but we can also fetch product data in parallel
        order_items_task = self._call_service(
            'order-service', f'/api/v1/orders/{order_id}/items', headers
        )

        order_data, items_data = await asyncio.gather(
            order_task, order_items_task,
            return_exceptions=True,
        )

        # Handle partial failures gracefully
        result = {}
        if not isinstance(order_data, Exception):
            result['order'] = order_data
            # Now fetch customer data
            customer_data = await self._call_service(
                'user-service',
                f'/api/v1/users/{order_data["customer_id"]}',
                headers,
            )
            if not isinstance(customer_data, Exception):
                result['customer'] = {
                    'name': customer_data.get('name'),
                    'email': customer_data.get('email'),
                }
        else:
            result['order'] = {'error': 'Order service unavailable'}

        if not isinstance(items_data, Exception):
            result['items'] = items_data
        else:
            result['items'] = {'error': 'Could not load order items'}

        return result

    async def _call_service(self, service: str, path: str, headers: dict):
        """Make an HTTP call to a backend service with timeout."""
        base_url = self.services[service]['url']
        timeout = self.services[service].get('timeout_ms', 3000)
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{base_url}{path}",
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=timeout / 1000),
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
                raise ServiceError(f"{service} returned {resp.status}")
```

### Key Considerations

| Concern | Approach |
|---|---|
| Authentication | Validate JWT at gateway; pass user claims downstream |
| Rate limiting | Apply at gateway level (global) and per-service |
| Circuit breaking | Per-route circuit breakers to isolate failures |
| Caching | Cache GET responses at gateway for public data |
| Request routing | Path-based, header-based, or weighted routing |
| Load shedding | Return 503 when backend queue depth exceeds threshold |

---

## 5. Sidecar / Ambassador Pattern

### Problem

Cross-cutting infrastructure concerns (observability, networking, security) are duplicated across every service, written in different languages and frameworks.

### Solution

Deploy a companion process (sidecar) alongside each service instance. The sidecar handles infrastructure concerns, and the service communicates with it over localhost. The Ambassador pattern is a specialization where the sidecar acts as a proxy for outgoing network calls.

### Architecture

```
  Pod / VM / Container Group
  ┌────────────────────────────────────────┐
  │                                        │
  │  ┌──────────────┐  ┌───────────────┐   │
  │  │  Application │  │   Sidecar     │   │
  │  │  (any lang)  │◄─┤   (Envoy)    │◄──┼── Inbound traffic
  │  │              │──►│              │──►─┼── Outbound traffic
  │  └──────────────┘  └───────────────┘   │
  │    localhost:8080    localhost:15001    │
  │                                        │
  └────────────────────────────────────────┘

  What the sidecar handles:
  - mTLS termination / encryption
  - Service discovery
  - Load balancing
  - Circuit breaking
  - Retry / timeout policies
  - Metrics collection (Prometheus)
  - Distributed tracing (inject trace headers)
  - Access logging
```

### Envoy Sidecar Configuration

```yaml
# Envoy sidecar configuration for a service mesh
static_resources:
  listeners:
    # Inbound listener: receives traffic from the mesh
    - name: inbound
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 15006
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: inbound
                route_config:
                  virtual_hosts:
                    - name: local_service
                      domains: ["*"]
                      routes:
                        - match: { prefix: "/" }
                          route:
                            cluster: local_app
                            timeout: 30s
                http_filters:
                  - name: envoy.filters.http.router

    # Outbound listener: proxies outgoing calls
    - name: outbound
      address:
        socket_address:
          address: 127.0.0.1
          port_value: 15001
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: outbound
                route_config:
                  virtual_hosts:
                    - name: external_services
                      domains: ["*"]
                      routes:
                        - match: { prefix: "/" }
                          route:
                            cluster: dynamic_forward_proxy
                http_filters:
                  - name: envoy.filters.http.router

  clusters:
    - name: local_app
      connect_timeout: 1s
      type: STATIC
      load_assignment:
        cluster_name: local_app
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: 8080
      # Circuit breaker for the local app
      circuit_breakers:
        thresholds:
          - max_connections: 1024
            max_pending_requests: 1024
            max_requests: 1024
            max_retries: 3
```

### When to Use Sidecar vs Library

| Factor | Sidecar | Library |
|---|---|---|
| Language diversity | Polyglot services | Single language |
| Upgrade cadence | Independent of app releases | Tied to app releases |
| Resource overhead | Extra process per service | Minimal overhead |
| Latency | Extra network hop (localhost) | In-process, zero hop |
| Debugging | Harder (two processes) | Easier (single process) |
| Best for | Service mesh (Istio, Linkerd) | Monoglot with fast-path needs |

---

## 6. Strangler Fig

### Problem

A legacy monolith needs to be replaced, but a full rewrite is too risky and expensive. The system must continue to operate during the migration.

### Solution

Incrementally build new services alongside the legacy system. Use a routing layer (API gateway or reverse proxy) to direct traffic: migrated endpoints go to new services, everything else goes to the legacy system. Over time, the legacy system shrinks until it can be decommissioned.

### Migration Phases

```
Phase 1: Intercept (add the proxy)
┌──────────────────────────────────────────────┐
│                  Reverse Proxy                │
│  ALL requests ──► Legacy Monolith             │
└──────────────────────────────────────────────┘

Phase 2: Strangle (migrate feature by feature)
┌──────────────────────────────────────────────┐
│                  Reverse Proxy                │
│  /api/users    ──► New User Service           │
│  /api/products ──► New Product Service         │
│  /api/*        ──► Legacy Monolith (shrinking)│
└──────────────────────────────────────────────┘

Phase 3: Complete (legacy is gone)
┌──────────────────────────────────────────────┐
│                  API Gateway                  │
│  /api/users    ──► User Service               │
│  /api/products ──► Product Service            │
│  /api/orders   ──► Order Service              │
│  /api/payments ──► Payment Service            │
└──────────────────────────────────────────────┘
```

### Implementation: Routing Layer

```python
# NGINX configuration for strangler fig routing
"""
upstream legacy_monolith {
    server legacy-app:8080;
}

upstream user_service {
    server user-service:8080;
}

upstream product_service {
    server product-service:8080;
}

server {
    listen 443 ssl;
    server_name api.example.com;

    # Migrated routes go to new services
    location /api/v2/users {
        proxy_pass http://user_service;
        proxy_set_header X-Request-ID $request_id;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /api/v2/products {
        proxy_pass http://product_service;
        proxy_set_header X-Request-ID $request_id;
    }

    # Feature-flagged routes (gradual migration)
    location /api/v2/orders {
        # Route 10% of traffic to new service for validation
        split_clients $request_uri $route_target {
            10%  new_order_service;
            *    legacy_monolith;
        }
        proxy_pass http://$route_target;
    }

    # Everything else goes to the legacy monolith
    location / {
        proxy_pass http://legacy_monolith;
        proxy_set_header X-Request-ID $request_id;
    }
}
"""
```

### Data Migration Strategy

```python
class StranglerDataMigrator:
    """
    Manages the data synchronization between legacy and new service
    during the strangler fig migration.
    """

    async def dual_write_phase(self, entity: dict, service_name: str):
        """
        Phase 1: Write to both old and new systems.
        Legacy is source of truth; new system is a replica.
        """
        # Write to legacy (source of truth)
        await self.legacy_db.write(entity)

        # Async write to new service (best-effort)
        try:
            await self.new_service.sync(entity)
        except Exception as e:
            # Log but do not fail -- legacy write succeeded
            logger.warning(f"Sync to {service_name} failed: {e}")
            await self.reconciliation_queue.enqueue(entity)

    async def verify_and_switch_phase(self, service_name: str):
        """
        Phase 2: Verify data consistency, then switch source of truth.
        """
        # Run reconciliation
        mismatches = await self.reconcile(service_name)
        if mismatches:
            logger.error(f"Found {len(mismatches)} mismatches in {service_name}")
            return False

        # Switch: new service becomes source of truth
        # Legacy becomes the replica (reverse dual-write)
        await self.routing_config.set_primary(service_name, 'new')
        return True

    async def reconcile(self, service_name: str) -> list:
        """Compare data between legacy and new system."""
        legacy_ids = set(await self.legacy_db.get_all_ids(service_name))
        new_ids = set(await self.new_service.get_all_ids())

        missing_in_new = legacy_ids - new_ids
        extra_in_new = new_ids - legacy_ids

        mismatches = []
        for entity_id in legacy_ids & new_ids:
            legacy_data = await self.legacy_db.get(service_name, entity_id)
            new_data = await self.new_service.get(entity_id)
            if self._hash(legacy_data) != self._hash(new_data):
                mismatches.append({
                    'id': entity_id,
                    'type': 'data_mismatch',
                })

        return mismatches + [
            {'id': eid, 'type': 'missing_in_new'} for eid in missing_in_new
        ] + [
            {'id': eid, 'type': 'extra_in_new'} for eid in extra_in_new
        ]
```

### Key Principles

1. **Migrate feature by feature**, never the entire system at once.
2. **Shadow traffic** to the new service before switching (compare responses).
3. **Maintain backward compatibility** during migration; the legacy system must keep working.
4. **Data synchronization** is the hardest part. Plan for dual-write + reconciliation.
5. **Set a deadline** for decommissioning the legacy system to avoid permanent dual maintenance.

---

## 7. Backend-for-Frontend (BFF)

### Problem

Different client types (web, mobile, TV, third-party API) have different data needs, screen sizes, and network constraints. A single generic API either over-fetches for mobile or under-fetches for web.

### Solution

Create a dedicated backend service for each client type. Each BFF aggregates data from backend microservices and shapes it for the specific client's needs.

### Architecture

```
  Web App          Mobile App         Smart TV App
     │                  │                   │
     ▼                  ▼                   ▼
┌──────────┐    ┌──────────────┐    ┌──────────────┐
│  Web BFF │    │  Mobile BFF  │    │   TV BFF     │
│  (Next.js│    │  (Node.js)   │    │  (Go)        │
│   SSR)   │    │              │    │              │
└────┬─────┘    └──────┬───────┘    └──────┬───────┘
     │                 │                    │
     └─────────────────┼────────────────────┘
                       │
              ┌────────▼────────┐
              │ Shared Backend  │
              │ Microservices   │
              │ (User, Order,   │
              │  Product, etc.) │
              └─────────────────┘
```

### Implementation

```python
# Mobile BFF: optimized for bandwidth and latency
class MobileBFF:
    """
    BFF for the mobile app. Returns minimal payloads
    with only the fields the mobile UI needs.
    """

    async def get_home_feed(self, user_id: int) -> dict:
        """
        Mobile home screen: needs lightweight data.
        Aggregate from multiple services but return only essential fields.
        """
        # Fetch in parallel
        user_task = self.user_service.get_user(user_id)
        feed_task = self.feed_service.get_feed(user_id, limit=10)
        notifications_task = self.notification_service.get_unread_count(user_id)

        user, feed, notif_count = await asyncio.gather(
            user_task, feed_task, notifications_task,
            return_exceptions=True,
        )

        # Shape response for mobile (minimal fields, small images)
        return {
            'user': {
                'name': user.get('first_name', ''),
                'avatar_url': self._mobile_image_url(user.get('avatar_url')),
            } if not isinstance(user, Exception) else None,
            'feed': [
                {
                    'id': post['id'],
                    'author_name': post['author']['name'],
                    'author_avatar': self._mobile_image_url(
                        post['author'].get('avatar_url')
                    ),
                    'text': post['content'][:200],  # truncate for mobile
                    'image': self._mobile_image_url(
                        post.get('media_urls', [None])[0]
                    ),
                    'likes': post['like_count'],
                    'time_ago': self._relative_time(post['created_at']),
                }
                for post in (feed if not isinstance(feed, Exception) else [])
            ],
            'unread_notifications': (
                notif_count if not isinstance(notif_count, Exception) else 0
            ),
        }

    def _mobile_image_url(self, url: str) -> str:
        """Convert to mobile-optimized image size."""
        if not url:
            return None
        # Use image CDN to serve 400px width, WebP format
        return f"https://img.example.com/w=400,f=webp/{url}"

    def _relative_time(self, timestamp: str) -> str:
        """Convert timestamp to relative time string for mobile."""
        delta = datetime.now(timezone.utc) - datetime.fromisoformat(timestamp)
        if delta.days > 0:
            return f"{delta.days}d"
        hours = delta.seconds // 3600
        if hours > 0:
            return f"{hours}h"
        minutes = delta.seconds // 60
        return f"{max(1, minutes)}m"


# Web BFF: richer data, server-side rendering support
class WebBFF:
    """
    BFF for the web app. Returns richer data
    including full content, multiple image sizes, and SEO metadata.
    """

    async def get_home_feed(self, user_id: int) -> dict:
        user_task = self.user_service.get_user(user_id)
        feed_task = self.feed_service.get_feed(user_id, limit=20)
        trending_task = self.feed_service.get_trending(limit=5)
        suggestions_task = self.user_service.get_follow_suggestions(user_id)

        user, feed, trending, suggestions = await asyncio.gather(
            user_task, feed_task, trending_task, suggestions_task,
            return_exceptions=True,
        )

        return {
            'user': self._full_user_profile(user),
            'feed': [self._full_post(post) for post in (feed or [])],
            'sidebar': {
                'trending': trending if not isinstance(trending, Exception) else [],
                'suggestions': suggestions if not isinstance(suggestions, Exception) else [],
            },
            'seo': {
                'title': f"{user.get('name', 'Home')} - Feed",
                'description': 'Your personalized feed',
            },
        }
```

### When to Use BFF

| Situation | Use BFF? |
|---|---|
| Web + Mobile with different data needs | Yes |
| Single client type | No, just use the API directly |
| Third-party API consumers | Yes, create a Public API BFF |
| GraphQL already in use | Maybe not; GraphQL lets clients select fields |

---

## 8. Circuit Breaker with State Machine

### Problem

When a downstream service fails, continuing to call it wastes resources, increases latency, and can cause cascading failures upstream. You need to detect failures early and fail fast.

### Solution

A state machine with three states: **Closed** (normal operation), **Open** (fail fast, no calls made), and **Half-Open** (test with limited requests). The breaker transitions between states based on failure rates.

### Full Implementation

```python
import time
import threading
from enum import Enum
from collections import deque
from dataclasses import dataclass, field
from typing import Callable, Any, Optional

class CircuitState(Enum):
    CLOSED = 'closed'       # normal operation
    OPEN = 'open'           # failing fast
    HALF_OPEN = 'half_open' # testing recovery

@dataclass
class CircuitBreakerConfig:
    failure_threshold: float = 0.5     # 50% failure rate to open
    success_threshold: int = 3         # 3 successes in half-open to close
    window_size: int = 100             # sliding window of last N calls
    timeout_seconds: float = 30.0      # time in open state before half-open
    half_open_max_calls: int = 5       # max concurrent calls in half-open
    slow_call_threshold: float = 5.0   # seconds to consider a call "slow"
    slow_call_rate_threshold: float = 0.8  # 80% slow calls triggers open

class CircuitBreaker:
    """
    Thread-safe circuit breaker with sliding window failure tracking.
    """

    def __init__(self, name: str, config: CircuitBreakerConfig = None):
        self.name = name
        self.config = config or CircuitBreakerConfig()
        self._state = CircuitState.CLOSED
        self._lock = threading.Lock()

        # Sliding window tracking
        self._results: deque = deque(maxlen=self.config.window_size)
        self._half_open_successes = 0
        self._half_open_calls = 0
        self._opened_at: Optional[float] = None

        # Metrics
        self.total_calls = 0
        self.total_failures = 0
        self.total_circuit_opens = 0

    @property
    def state(self) -> CircuitState:
        with self._lock:
            if self._state == CircuitState.OPEN:
                # Check if timeout has elapsed -> move to half-open
                elapsed = time.time() - self._opened_at
                if elapsed >= self.config.timeout_seconds:
                    self._transition_to(CircuitState.HALF_OPEN)
            return self._state

    def call(self, func: Callable, *args, **kwargs) -> Any:
        """Execute a function through the circuit breaker."""
        current_state = self.state

        if current_state == CircuitState.OPEN:
            raise CircuitOpenError(
                f"Circuit '{self.name}' is OPEN. "
                f"Will retry in {self._time_until_half_open():.1f}s"
            )

        if current_state == CircuitState.HALF_OPEN:
            with self._lock:
                if self._half_open_calls >= self.config.half_open_max_calls:
                    raise CircuitOpenError(
                        f"Circuit '{self.name}' is HALF_OPEN with max calls reached"
                    )
                self._half_open_calls += 1

        # Execute the call
        start_time = time.time()
        try:
            result = func(*args, **kwargs)
            duration = time.time() - start_time
            self._record_success(duration)
            return result
        except Exception as e:
            duration = time.time() - start_time
            self._record_failure(duration)
            raise

    async def async_call(self, func: Callable, *args, **kwargs) -> Any:
        """Async version of call()."""
        current_state = self.state

        if current_state == CircuitState.OPEN:
            raise CircuitOpenError(
                f"Circuit '{self.name}' is OPEN"
            )

        if current_state == CircuitState.HALF_OPEN:
            with self._lock:
                if self._half_open_calls >= self.config.half_open_max_calls:
                    raise CircuitOpenError(
                        f"Circuit '{self.name}' is HALF_OPEN with max calls reached"
                    )
                self._half_open_calls += 1

        start_time = time.time()
        try:
            result = await func(*args, **kwargs)
            duration = time.time() - start_time
            self._record_success(duration)
            return result
        except Exception as e:
            duration = time.time() - start_time
            self._record_failure(duration)
            raise

    def _record_success(self, duration: float):
        is_slow = duration >= self.config.slow_call_threshold
        with self._lock:
            self._results.append({'success': True, 'slow': is_slow})
            self.total_calls += 1

            if self._state == CircuitState.HALF_OPEN:
                self._half_open_successes += 1
                if self._half_open_successes >= self.config.success_threshold:
                    self._transition_to(CircuitState.CLOSED)

    def _record_failure(self, duration: float):
        with self._lock:
            self._results.append({'success': False, 'slow': True})
            self.total_calls += 1
            self.total_failures += 1

            if self._state == CircuitState.HALF_OPEN:
                # Any failure in half-open immediately opens the circuit
                self._transition_to(CircuitState.OPEN)
            elif self._state == CircuitState.CLOSED:
                self._evaluate_window()

    def _evaluate_window(self):
        """Check if failure rate exceeds threshold."""
        if len(self._results) < 10:  # minimum sample size
            return

        failures = sum(1 for r in self._results if not r['success'])
        failure_rate = failures / len(self._results)

        slow_calls = sum(1 for r in self._results if r['slow'])
        slow_rate = slow_calls / len(self._results)

        if (failure_rate >= self.config.failure_threshold or
                slow_rate >= self.config.slow_call_rate_threshold):
            self._transition_to(CircuitState.OPEN)

    def _transition_to(self, new_state: CircuitState):
        old_state = self._state
        self._state = new_state

        if new_state == CircuitState.OPEN:
            self._opened_at = time.time()
            self.total_circuit_opens += 1

        elif new_state == CircuitState.HALF_OPEN:
            self._half_open_successes = 0
            self._half_open_calls = 0

        elif new_state == CircuitState.CLOSED:
            self._results.clear()

    def _time_until_half_open(self) -> float:
        if self._opened_at is None:
            return 0
        elapsed = time.time() - self._opened_at
        return max(0, self.config.timeout_seconds - elapsed)

    def get_metrics(self) -> dict:
        return {
            'name': self.name,
            'state': self._state.value,
            'total_calls': self.total_calls,
            'total_failures': self.total_failures,
            'total_circuit_opens': self.total_circuit_opens,
            'current_failure_rate': self._current_failure_rate(),
            'window_size': len(self._results),
        }

    def _current_failure_rate(self) -> float:
        if not self._results:
            return 0.0
        failures = sum(1 for r in self._results if not r['success'])
        return failures / len(self._results)
```

### Usage

```python
# Create circuit breakers for each downstream service
payment_breaker = CircuitBreaker('payment-service', CircuitBreakerConfig(
    failure_threshold=0.5,
    timeout_seconds=30,
    window_size=100,
))

inventory_breaker = CircuitBreaker('inventory-service', CircuitBreakerConfig(
    failure_threshold=0.3,     # more sensitive
    timeout_seconds=15,        # recover faster
    window_size=50,
))

# Use the circuit breaker
try:
    result = await payment_breaker.async_call(
        payment_client.charge,
        amount=1000,
        currency='USD',
    )
except CircuitOpenError:
    # Fallback: queue for later processing
    await payment_queue.enqueue(payment_request)
    return {'status': 'pending', 'message': 'Payment queued for processing'}
```

---

## 9. Outbox Pattern

### Problem

A service needs to update its database AND publish an event to a message broker atomically. Without coordination, either the database update or the event publish can fail independently, leading to inconsistency.

### Solution

Write the event to an "outbox" table in the same database transaction as the business data change. A separate process (poller or CDC connector) reads from the outbox table and publishes to the message broker.

### Architecture

```
  ┌──────────────────────────────────────┐
  │           Service                    │
  │                                      │
  │  BEGIN TRANSACTION;                  │
  │    UPDATE orders SET status = 'paid';│
  │    INSERT INTO outbox (event_data);  │
  │  COMMIT;                             │
  │                                      │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │        Outbox Table (DB)             │
  │  ┌────┬───────────┬──────────────┐   │
  │  │ id │ event_type│ published    │   │
  │  ├────┼───────────┼──────────────┤   │
  │  │ 1  │ OrderPaid │ false        │   │
  │  │ 2  │ OrderPaid │ false        │   │
  │  └────┴───────────┴──────────────┘   │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │   Outbox Publisher                   │
  │   (Polling or Debezium CDC)          │
  │                                      │
  │   1. Read unpublished events         │
  │   2. Publish to Kafka                │
  │   3. Mark as published               │
  └──────────────────┬───────────────────┘
                     │
  ┌──────────────────▼───────────────────┐
  │           Kafka                      │
  └──────────────────────────────────────┘
```

### Implementation

```python
# ============================================================
# Outbox Table and Writer
# ============================================================

import json
from uuid import uuid4
from datetime import datetime, timezone

class OutboxWriter:
    """
    Writes events to the outbox table within the same transaction
    as the business data change.
    """

    async def write_event(
        self,
        conn,  # database connection (inside a transaction)
        aggregate_type: str,
        aggregate_id: str,
        event_type: str,
        payload: dict,
    ):
        """
        Must be called within the same transaction as the
        business data change.
        """
        await conn.execute("""
            INSERT INTO outbox (
                event_id, aggregate_type, aggregate_id,
                event_type, payload, created_at
            ) VALUES (
                :event_id, :agg_type, :agg_id,
                :event_type, :payload, :created_at
            )
        """, {
            'event_id': str(uuid4()),
            'agg_type': aggregate_type,
            'agg_id': aggregate_id,
            'event_type': event_type,
            'payload': json.dumps(payload),
            'created_at': datetime.now(timezone.utc),
        })


# ============================================================
# Business Logic: Atomic data change + outbox event
# ============================================================

class OrderService:
    def __init__(self, db, outbox: OutboxWriter):
        self.db = db
        self.outbox = outbox

    async def mark_order_paid(self, order_id: str, payment_id: str):
        """
        Atomic: update order status AND write outbox event
        in a single transaction.
        """
        async with self.db.begin() as conn:
            # Business data change
            await conn.execute("""
                UPDATE orders
                SET status = 'paid', payment_id = :payment_id, updated_at = NOW()
                WHERE order_id = :order_id AND status = 'pending'
            """, {'order_id': order_id, 'payment_id': payment_id})

            # Outbox event (same transaction)
            await self.outbox.write_event(
                conn=conn,
                aggregate_type='Order',
                aggregate_id=order_id,
                event_type='OrderPaid',
                payload={
                    'order_id': order_id,
                    'payment_id': payment_id,
                    'paid_at': datetime.now(timezone.utc).isoformat(),
                },
            )
            # Both succeed or both fail -- atomicity guaranteed


# ============================================================
# Outbox Publisher: Polls the outbox and publishes to Kafka
# ============================================================

class OutboxPublisher:
    """
    Polls the outbox table and publishes events to Kafka.
    Runs as a separate background process.
    """

    def __init__(self, db, kafka_producer, poll_interval: float = 1.0):
        self.db = db
        self.kafka = kafka_producer
        self.poll_interval = poll_interval

    async def run(self):
        """Main polling loop."""
        while True:
            published_count = await self._poll_and_publish()
            if published_count == 0:
                await asyncio.sleep(self.poll_interval)

    async def _poll_and_publish(self, batch_size: int = 100) -> int:
        """Fetch unpublished events and send to Kafka."""
        rows = await self.db.fetch_all("""
            SELECT event_id, aggregate_type, aggregate_id,
                   event_type, payload, created_at
            FROM outbox
            WHERE published_at IS NULL
            ORDER BY created_at ASC
            LIMIT :batch_size
            FOR UPDATE SKIP LOCKED
        """, {'batch_size': batch_size})

        if not rows:
            return 0

        published_ids = []
        for row in rows:
            topic = f"events.{row['aggregate_type'].lower()}"
            try:
                await self.kafka.produce(
                    topic=topic,
                    key=row['aggregate_id'],
                    value=json.dumps({
                        'event_id': row['event_id'],
                        'event_type': row['event_type'],
                        'aggregate_type': row['aggregate_type'],
                        'aggregate_id': row['aggregate_id'],
                        'payload': json.loads(row['payload']),
                        'created_at': row['created_at'].isoformat(),
                    }),
                    headers={
                        'event_type': row['event_type'],
                    },
                )
                published_ids.append(row['event_id'])
            except Exception as e:
                # Stop batch on first error; retry on next poll
                break

        if published_ids:
            await self.db.execute("""
                UPDATE outbox
                SET published_at = NOW()
                WHERE event_id = ANY(:ids)
            """, {'ids': published_ids})

        return len(published_ids)
```

### Outbox Table Schema

```sql
CREATE TABLE outbox (
    event_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE  -- NULL until published
);

-- Index for the polling query
CREATE INDEX idx_outbox_unpublished
    ON outbox (created_at ASC)
    WHERE published_at IS NULL;

-- Cleanup: delete published events older than 7 days
-- (run as a scheduled job)
-- DELETE FROM outbox WHERE published_at < NOW() - INTERVAL '7 days';
```

### Polling vs CDC

| Approach | Latency | Complexity | Reliability |
|---|---|---|---|
| **Polling** (query outbox table) | 1-5 seconds | Simple | Good (but adds DB load) |
| **CDC** (Debezium on outbox table) | < 1 second | Higher (requires Debezium) | Excellent (log-based) |

---

## 10. Idempotency Keys for APIs

### Problem

Network failures, timeouts, and client retries can cause the same request to be processed multiple times. For non-idempotent operations (payments, order creation, email sending), this leads to duplicates.

### Solution

Clients include a unique idempotency key with each request. The server checks if a request with this key has already been processed and returns the cached response instead of re-executing.

### Implementation

```python
import hashlib
import json
from datetime import datetime, timezone, timedelta
from typing import Optional
from uuid import UUID

class IdempotencyStore:
    """
    Stores idempotency keys and their associated responses.
    Uses PostgreSQL with advisory locks for concurrent safety.
    """

    def __init__(self, engine):
        self.engine = engine

    async def check_and_lock(self, key: str) -> Optional[dict]:
        """
        Check if an idempotency key exists.
        If it does, return the cached response.
        If not, acquire an advisory lock and return None.
        """
        # First check if we already have a completed response
        existing = await self.engine.fetch_one("""
            SELECT response_code, response_body, response_headers
            FROM idempotency_keys
            WHERE idempotency_key = :key
              AND status = 'completed'
        """, {'key': key})

        if existing:
            return {
                'status_code': existing['response_code'],
                'body': json.loads(existing['response_body']),
                'headers': json.loads(existing['response_headers']),
            }

        # Try to acquire an advisory lock (prevents concurrent processing)
        lock_key = int(hashlib.md5(key.encode()).hexdigest()[:15], 16)
        locked = await self.engine.fetch_one("""
            SELECT pg_try_advisory_lock(:lock_key) AS acquired
        """, {'lock_key': lock_key})

        if not locked['acquired']:
            # Another request is processing this key right now
            raise ConflictError(
                "A request with this idempotency key is currently being processed"
            )

        # Insert a "processing" record
        try:
            await self.engine.execute("""
                INSERT INTO idempotency_keys (
                    idempotency_key, status, created_at
                ) VALUES (:key, 'processing', :now)
                ON CONFLICT (idempotency_key) DO NOTHING
            """, {'key': key, 'now': datetime.now(timezone.utc)})
        except Exception:
            await self.engine.execute(
                "SELECT pg_advisory_unlock(:lock_key)", {'lock_key': lock_key}
            )
            raise

        return None  # Caller should process the request

    async def save_response(
        self,
        key: str,
        status_code: int,
        body: dict,
        headers: dict = None,
    ):
        """Save the response for a completed idempotent request."""
        lock_key = int(hashlib.md5(key.encode()).hexdigest()[:15], 16)

        await self.engine.execute("""
            UPDATE idempotency_keys
            SET status = 'completed',
                response_code = :code,
                response_body = :body,
                response_headers = :headers,
                completed_at = :now
            WHERE idempotency_key = :key
        """, {
            'key': key,
            'code': status_code,
            'body': json.dumps(body),
            'headers': json.dumps(headers or {}),
            'now': datetime.now(timezone.utc),
        })

        # Release the advisory lock
        await self.engine.execute(
            "SELECT pg_advisory_unlock(:lock_key)", {'lock_key': lock_key}
        )

    async def save_error(self, key: str, error_message: str):
        """Mark a failed idempotent request so it can be retried."""
        lock_key = int(hashlib.md5(key.encode()).hexdigest()[:15], 16)

        # Delete the record so the key can be retried
        await self.engine.execute("""
            DELETE FROM idempotency_keys WHERE idempotency_key = :key
        """, {'key': key})

        await self.engine.execute(
            "SELECT pg_advisory_unlock(:lock_key)", {'lock_key': lock_key}
        )


# ============================================================
# Middleware: Wraps API endpoints with idempotency
# ============================================================

class IdempotencyMiddleware:
    """
    HTTP middleware that handles idempotency key checking and caching.
    """

    def __init__(self, idempotency_store: IdempotencyStore):
        self.store = idempotency_store

    async def process_request(self, request, handler):
        """
        Check for idempotency key in the request header.
        If present, ensure the request is processed at most once.
        """
        idempotency_key = request.headers.get('Idempotency-Key')

        # Only apply to non-GET methods
        if not idempotency_key or request.method in ('GET', 'HEAD', 'OPTIONS'):
            return await handler(request)

        # Validate key format
        if len(idempotency_key) > 255:
            return JSONResponse(
                status_code=400,
                body={'error': 'Idempotency key too long (max 255 chars)'},
            )

        # Check for cached response or acquire lock
        cached = await self.store.check_and_lock(idempotency_key)
        if cached:
            return JSONResponse(
                status_code=cached['status_code'],
                body=cached['body'],
                headers={
                    **cached['headers'],
                    'X-Idempotent-Replayed': 'true',
                },
            )

        # Process the request
        try:
            response = await handler(request)

            # Cache the response
            await self.store.save_response(
                key=idempotency_key,
                status_code=response.status_code,
                body=response.body,
                headers=dict(response.headers),
            )

            return response

        except Exception as e:
            # On error, allow the key to be retried
            await self.store.save_error(idempotency_key, str(e))
            raise
```

### Database Schema

```sql
CREATE TABLE idempotency_keys (
    idempotency_key VARCHAR(255) PRIMARY KEY,
    status VARCHAR(20) NOT NULL DEFAULT 'processing',
    response_code INT,
    response_body JSONB,
    response_headers JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    -- Auto-expire old keys
    CONSTRAINT valid_status CHECK (status IN ('processing', 'completed'))
);

-- Cleanup job: delete keys older than 24 hours
-- CREATE INDEX idx_idempotency_cleanup
--     ON idempotency_keys (created_at)
--     WHERE completed_at IS NOT NULL;
-- DELETE FROM idempotency_keys
--     WHERE completed_at < NOW() - INTERVAL '24 hours';
```

### Client Usage

```python
import requests
from uuid import uuid4

def create_payment_with_retry(amount: int, max_retries: int = 3):
    """
    Client-side: use a stable idempotency key across retries.
    Generate the key once and reuse it for all retry attempts.
    """
    idempotency_key = str(uuid4())  # generated ONCE per logical operation

    for attempt in range(max_retries):
        try:
            response = requests.post(
                'https://api.example.com/v1/payments',
                json={'amount': amount, 'currency': 'USD'},
                headers={
                    'Idempotency-Key': idempotency_key,
                    'Authorization': 'Bearer ...',
                },
                timeout=10,
            )
            if response.status_code in (200, 201):
                return response.json()
            elif response.status_code == 409:
                # Conflict: request is being processed, wait and retry
                time.sleep(2)
                continue
            else:
                response.raise_for_status()
        except requests.Timeout:
            # Timeout: retry with the SAME idempotency key
            continue
        except requests.ConnectionError:
            time.sleep(2 ** attempt)
            continue

    raise Exception("Payment failed after all retries")
```

### Key Design Decisions

| Decision | Recommendation | Rationale |
|---|---|---|
| Key generation | Client-generated UUID | Client controls retry scope |
| Key TTL | 24 hours | Prevents unbounded storage growth |
| Concurrent requests with same key | Return 409 Conflict | Prevents race conditions |
| Error handling | Delete key on server error | Allows retry of failed requests |
| Scope | Per-endpoint, not global | Same key on different endpoints should be independent |
| Storage | Same database as business data | Can participate in the same transaction |
