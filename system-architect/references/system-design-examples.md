# System Design Examples

Production-grade system design examples for common distributed systems. Each example includes requirements, architecture, data model, API design, scale considerations, and key decisions.

---

## Table of Contents

1. [URL Shortener](#1-url-shortener)
2. [Rate Limiter](#2-rate-limiter)
3. [Chat System (WhatsApp-like)](#3-chat-system)
4. [News Feed (Facebook-like)](#4-news-feed)
5. [Notification System](#5-notification-system)
6. [Search Autocomplete](#6-search-autocomplete)
7. [File Storage (S3-like)](#7-file-storage-s3-like)
8. [Payment System](#8-payment-system)

---

## 1. URL Shortener

### Requirements

**Functional:**
- Given a long URL, generate a short unique alias (e.g., `sho.rt/abc123`)
- Redirect short URL to the original URL
- Optional custom aliases
- Expiration support (default: 5 years)
- Analytics: click count, referrer, geo

**Non-Functional:**
- 100M new URLs/month (~40 URLs/sec write)
- 10B redirects/month (~4000 redirects/sec read)
- p99 redirect latency < 50ms
- 99.99% availability
- Short URLs should not be guessable

### High-Level Architecture

```
                         ┌──────────────┐
                         │   CDN/Edge   │ (cache popular redirects)
                         └──────┬───────┘
                                │
┌──────────┐            ┌───────▼───────┐            ┌──────────────┐
│  Client   │───────────│  API Gateway  │───────────│  Analytics   │
│ (Browser) │           │  (nginx/LB)   │           │  Pipeline    │
└──────────┘            └───────┬───────┘            └──────────────┘
                                │                           │
                    ┌───────────┴───────────┐               │
                    │                       │               ▼
             ┌──────▼──────┐        ┌───────▼──────┐  ┌──────────┐
             │  Shortener  │        │   Redirect   │  │ ClickHouse│
             │   Service   │        │   Service    │  │ (analytics)│
             └──────┬──────┘        └───────┬──────┘  └──────────┘
                    │                       │
                    ▼                       ▼
             ┌─────────────┐        ┌─────────────┐
             │  PostgreSQL │        │    Redis     │
             │  (source of │        │   (cache)    │
             │   truth)    │        └─────────────┘
             └─────────────┘
```

### Data Model

```sql
CREATE TABLE urls (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    short_code VARCHAR(10) UNIQUE NOT NULL,
    original_url TEXT NOT NULL,
    user_id BIGINT,
    custom_alias BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    click_count BIGINT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_urls_short_code ON urls (short_code) WHERE is_active = TRUE;
CREATE INDEX idx_urls_expires ON urls (expires_at) WHERE is_active = TRUE;

CREATE TABLE click_events (
    event_id UUID DEFAULT gen_random_uuid(),
    short_code VARCHAR(10) NOT NULL,
    clicked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    referrer TEXT,
    user_agent TEXT,
    ip_address INET,
    country_code CHAR(2),
    device_type VARCHAR(20)
) PARTITION BY RANGE (clicked_at);
```

### API Design

```
POST   /api/v1/urls              -- Create short URL
GET    /api/v1/urls/{short_code} -- Get URL metadata
DELETE /api/v1/urls/{short_code} -- Deactivate URL
GET    /api/v1/urls/{short_code}/stats -- Get analytics
GET    /{short_code}             -- Redirect (301/302)
```

```json
// POST /api/v1/urls
// Request:
{
    "url": "https://example.com/very/long/path?param=value",
    "custom_alias": "my-link",       // optional
    "expires_in_days": 365           // optional
}

// Response: 201 Created
{
    "short_code": "abc123",
    "short_url": "https://sho.rt/abc123",
    "original_url": "https://example.com/very/long/path?param=value",
    "expires_at": "2026-03-15T00:00:00Z",
    "created_at": "2025-03-15T12:00:00Z"
}
```

### Short Code Generation

```python
import hashlib
import base64

# Approach 1: Base62 encoding of a counter (distributed via Snowflake ID)
ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def base62_encode(num: int) -> str:
    if num == 0:
        return ALPHABET[0]
    result = []
    while num > 0:
        result.append(ALPHABET[num % 62])
        num //= 62
    return ''.join(reversed(result))

# Approach 2: Hash-based with collision check
def generate_short_code(url: str, length: int = 7) -> str:
    hash_bytes = hashlib.sha256(url.encode()).digest()
    code = base64.urlsafe_b64encode(hash_bytes)[:length].decode()
    return code.replace('-', 'a').replace('_', 'b')
```

### Scale Considerations

- **Read-heavy (100:1 ratio):** Cache aggressively in Redis. Cache hit rate should exceed 90% since popular URLs follow a power-law distribution.
- **301 vs 302 redirect:** Use 302 (temporary) if you need analytics; 301 (permanent) if browsers can cache indefinitely.
- **Short code space:** 7 chars in base62 = 62^7 = 3.5 trillion combinations. Sufficient for decades.
- **Database sharding:** Shard by short_code hash. Each shard handles its own ID generation.
- **Geographical distribution:** Deploy redirect service at edge locations. Replicate the URL mapping to all regions.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| ID generation | Snowflake IDs + Base62 | Globally unique, sortable, no coordination |
| Cache strategy | Write-through to Redis | Every new URL is cached immediately |
| Redirect code | 302 Temporary | Enables accurate click analytics |
| Expiration | Lazy deletion + scheduled cleanup | Avoids scanning on every request |
| Analytics | Async via Kafka to ClickHouse | Decouples redirect latency from analytics |

---

## 2. Rate Limiter

### Requirements

**Functional:**
- Limit API requests per client/IP/user/endpoint
- Support multiple rate limit rules (per-second, per-minute, per-day)
- Return rate limit headers (remaining, reset time)
- Support burst allowance

**Non-Functional:**
- Sub-millisecond latency (inline with every API request)
- Highly available (limiter failure should not block requests)
- Distributed across multiple API gateway instances
- Accurate counting under concurrent requests

### High-Level Architecture

```
┌──────────┐     ┌──────────────┐     ┌─────────────────┐
│  Client   │────│  API Gateway │────│  Backend Service │
└──────────┘     └──────┬───────┘     └─────────────────┘
                        │
                 ┌──────▼───────┐
                 │ Rate Limiter │
                 │  Middleware   │
                 └──────┬───────┘
                        │
                 ┌──────▼───────┐
                 │    Redis     │  (centralized counter store)
                 │   Cluster    │
                 └──────────────┘

Rate Limit Rules (config):
┌─────────────────────────────────────────────────┐
│  rules:                                         │
│    - key: "user:{user_id}"                      │
│      limits:                                    │
│        - window: 1s,  max: 10                   │
│        - window: 1m,  max: 200                  │
│        - window: 1h,  max: 5000                 │
│    - key: "ip:{client_ip}"                      │
│      limits:                                    │
│        - window: 1s,  max: 50                   │
│        - window: 1m,  max: 1000                 │
└─────────────────────────────────────────────────┘
```

### Algorithm: Sliding Window Counter

```python
import time
import redis

class SlidingWindowRateLimiter:
    """
    Sliding window counter using Redis sorted sets.
    More accurate than fixed windows, less memory than sliding logs.
    """

    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client

    def is_allowed(
        self,
        key: str,
        max_requests: int,
        window_seconds: int
    ) -> dict:
        """Check if a request is allowed and record it."""
        now = time.time()
        window_start = now - window_seconds
        pipeline_key = f"ratelimit:{key}:{window_seconds}"

        # Atomic Redis operation using Lua script
        lua_script = """
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local window_start = tonumber(ARGV[2])
        local max_requests = tonumber(ARGV[3])
        local window_seconds = tonumber(ARGV[4])

        -- Remove expired entries
        redis.call('ZREMRANGEBYSCORE', key, '-inf', window_start)

        -- Count current requests in window
        local current_count = redis.call('ZCARD', key)

        if current_count < max_requests then
            -- Add the new request
            redis.call('ZADD', key, now, now .. ':' .. math.random(1000000))
            redis.call('EXPIRE', key, window_seconds)
            return {1, max_requests - current_count - 1, window_seconds}
        else
            -- Get the oldest entry to calculate reset time
            local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
            local reset_at = oldest[2] + window_seconds
            return {0, 0, reset_at - now}
        end
        """
        result = self.redis.eval(
            lua_script, 1, pipeline_key,
            now, window_start, max_requests, window_seconds
        )

        allowed, remaining, retry_after = result
        return {
            'allowed': bool(allowed),
            'remaining': int(remaining),
            'retry_after_seconds': max(0, float(retry_after)),
            'limit': max_requests,
            'window_seconds': window_seconds,
        }
```

### Algorithm: Token Bucket

```python
class TokenBucketRateLimiter:
    """
    Token bucket algorithm: allows bursts up to bucket capacity,
    refills at a steady rate.
    """

    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client

    def is_allowed(
        self,
        key: str,
        bucket_capacity: int,
        refill_rate: float,  # tokens per second
        tokens_requested: int = 1
    ) -> dict:
        lua_script = """
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local requested = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])

        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now

        -- Calculate tokens to add since last refill
        local elapsed = now - last_refill
        local new_tokens = elapsed * refill_rate
        tokens = math.min(capacity, tokens + new_tokens)

        local allowed = 0
        if tokens >= requested then
            tokens = tokens - requested
            allowed = 1
        end

        redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
        redis.call('EXPIRE', key, math.ceil(capacity / refill_rate) * 2)

        return {allowed, math.floor(tokens)}
        """
        now = time.time()
        result = self.redis.eval(
            lua_script, 1, f"tokenbucket:{key}",
            bucket_capacity, refill_rate, tokens_requested, now
        )

        allowed, remaining = result
        return {
            'allowed': bool(allowed),
            'remaining': int(remaining),
            'bucket_capacity': bucket_capacity,
            'refill_rate': refill_rate,
        }
```

### API Response Headers

```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1710504000
Retry-After: 30
Content-Type: application/json

{
    "error": "rate_limit_exceeded",
    "message": "Too many requests. Please retry after 30 seconds.",
    "retry_after_seconds": 30
}
```

### Scale Considerations

- **Redis single point of failure:** Use Redis Cluster with replicas. On failure, fail-open (allow requests) rather than fail-closed (block all).
- **Clock synchronization:** All API gateway instances must use synchronized clocks (NTP). Token bucket is more forgiving than sliding window.
- **Local + distributed hybrid:** Keep a local token bucket (fast, no network) and sync with Redis periodically. Allows slight over-limit but much lower latency.
- **Per-endpoint vs global:** Stack multiple limiters (global + per-endpoint) using middleware chaining.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Algorithm | Sliding window + token bucket | Sliding window for global, token bucket for burst |
| Storage | Redis with Lua scripts | Atomic operations, sub-ms latency |
| Failure mode | Fail-open | Availability over strict enforcement |
| Key design | `{entity_type}:{entity_id}:{window}` | Flexible multi-tier limiting |
| Response | 429 with headers | Industry standard, client-friendly |

---

## 3. Chat System

### Requirements

**Functional:**
- 1:1 and group messaging (up to 500 members)
- Sent/delivered/read receipts
- Media (images, video, documents) up to 100MB
- Online/offline presence
- Message history with pagination
- Push notifications for offline users

**Non-Functional:**
- 500M daily active users
- Each user sends ~40 messages/day
- p99 message delivery latency < 500ms
- Messages must never be lost
- End-to-end encryption

### High-Level Architecture

```
┌──────────┐     ┌─────────────┐     ┌─────────────────┐
│  Mobile   │◄───│  WebSocket  │◄───│   Message        │
│  Client   │───►│   Gateway   │───►│   Service        │
└──────────┘     └──────┬──────┘     └────────┬────────┘
                        │                      │
                 ┌──────▼──────┐        ┌──────▼──────┐
                 │  Presence   │        │   Kafka     │
                 │  Service    │        │  (message   │
                 │  (Redis)    │        │   queue)    │
                 └─────────────┘        └──────┬──────┘
                                               │
                                    ┌──────────┼──────────┐
                                    │          │          │
                              ┌─────▼───┐ ┌───▼────┐ ┌───▼──────┐
                              │  Chat   │ │ Push   │ │ Media    │
                              │  Store  │ │ Notif  │ │ Service  │
                              │(Cassandra)│ │Service │ │ (S3+CDN)│
                              └─────────┘ └────────┘ └──────────┘

WebSocket Connection Management:
┌──────────────────────────────────────────────────────┐
│  user_id -> [ws_gateway_1:conn_id, ws_gateway_3:..] │
│  Stored in Redis for routing messages to the right   │
│  gateway instance holding the user's connection.     │
└──────────────────────────────────────────────────────┘
```

### Data Model

```sql
-- Conversations (shared metadata)
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY,
    type VARCHAR(10) NOT NULL,  -- 'direct' or 'group'
    name TEXT,                  -- group name (null for direct)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Conversation membership
CREATE TABLE conversation_members (
    conversation_id UUID NOT NULL,
    user_id BIGINT NOT NULL,
    role VARCHAR(20) DEFAULT 'member',  -- 'admin', 'member'
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_read_message_id UUID,
    muted_until TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (conversation_id, user_id)
);
```

```cql
-- Cassandra: Messages (partitioned by conversation, ordered by time)
CREATE TABLE messages (
    conversation_id UUID,
    message_id TIMEUUID,
    sender_id BIGINT,
    content TEXT,
    content_type TEXT,      -- 'text', 'image', 'video', 'document'
    media_url TEXT,
    reply_to_message_id TIMEUUID,
    created_at TIMESTAMP,
    PRIMARY KEY (conversation_id, message_id)
) WITH CLUSTERING ORDER BY (message_id DESC)
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_size': 1,
                    'compaction_window_unit': 'DAYS'};
```

### API Design

```
WebSocket Events:
  Client -> Server:
    send_message     {conversation_id, content, content_type}
    typing_start     {conversation_id}
    typing_stop      {conversation_id}
    mark_read        {conversation_id, message_id}

  Server -> Client:
    new_message      {conversation_id, message}
    message_delivered {message_id, delivered_at}
    message_read     {message_id, reader_id, read_at}
    user_typing      {conversation_id, user_id}
    presence_update  {user_id, status}

REST API (for non-realtime operations):
  GET  /api/v1/conversations                      -- List conversations
  GET  /api/v1/conversations/{id}/messages?before= -- Paginated history
  POST /api/v1/conversations                      -- Create group
  POST /api/v1/media/upload                       -- Upload media
```

### Message Flow

```python
# Simplified message processing flow
async def handle_send_message(sender_id: int, payload: dict):
    conversation_id = payload['conversation_id']
    message_id = generate_timeuuid()

    # 1. Validate sender is a member
    if not await is_member(sender_id, conversation_id):
        raise PermissionError("Not a member of this conversation")

    # 2. Persist the message
    message = {
        'conversation_id': conversation_id,
        'message_id': message_id,
        'sender_id': sender_id,
        'content': payload['content'],
        'content_type': payload.get('content_type', 'text'),
        'created_at': datetime.utcnow(),
    }
    await cassandra.execute(INSERT_MESSAGE, message)

    # 3. Publish to Kafka for fan-out
    await kafka.produce(
        topic='chat.messages',
        key=str(conversation_id),
        value=message,
    )

    # 4. Acknowledge to sender
    await send_to_user(sender_id, {
        'type': 'message_sent',
        'message_id': message_id,
        'conversation_id': conversation_id,
    })

async def fan_out_message(message: dict):
    """Kafka consumer: deliver message to all conversation members."""
    members = await get_conversation_members(message['conversation_id'])

    for member_id in members:
        if member_id == message['sender_id']:
            continue

        # Check if user is online (has active WebSocket)
        ws_connections = await redis.smembers(f"online:{member_id}")
        if ws_connections:
            for conn in ws_connections:
                await send_to_connection(conn, {
                    'type': 'new_message',
                    'message': message,
                })
        else:
            # User is offline: queue push notification
            await push_notification_queue.enqueue({
                'user_id': member_id,
                'title': f"New message from {message['sender_name']}",
                'body': message['content'][:100],
            })
```

### Scale Considerations

- **WebSocket connections:** Each gateway server handles ~500K concurrent connections. Use consistent hashing to route users to specific gateways.
- **Message ordering:** Partition Kafka by conversation_id to guarantee per-conversation ordering.
- **Group messages:** For large groups (100+ members), fan-out is expensive. Use a "mailbox" model where clients pull unread messages instead of server pushing.
- **Media handling:** Upload media to S3 first, then send a message with the media URL. Use pre-signed upload URLs to bypass the application server.
- **Hot conversations:** Very active group chats can overwhelm a single Cassandra partition. Add a time bucket to the partition key for extremely high-volume conversations.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Transport | WebSocket with HTTP fallback | Low latency bidirectional communication |
| Message store | Cassandra | Optimized for time-series writes and range queries |
| Message queue | Kafka | Durable, ordered, replayable |
| Presence | Redis with TTL | Fast reads, automatic expiration |
| Media storage | S3 + CDN | Scalable, cost-effective, edge delivery |
| Fan-out | Write-time (push) | Lower read latency for most conversations |

---

## 4. News Feed

### Requirements

**Functional:**
- Users see posts from friends/followed accounts in reverse chronological order
- Posts contain text, images, videos, links
- Like, comment, share actions
- Feed ranking (relevance vs chronological)
- Infinite scroll pagination

**Non-Functional:**
- 1B daily active users
- Average user has 500 friends/follows
- Average user checks feed 10 times/day
- p99 feed load latency < 500ms
- Feed should include posts from the last 7 days

### High-Level Architecture

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│  Client   │────│  API Gateway │────│  Feed Service │
└──────────┘     └──────────────┘     └──────┬───────┘
                                             │
                              ┌──────────────┼──────────────┐
                              │              │              │
                       ┌──────▼──────┐ ┌─────▼──────┐ ┌────▼─────┐
                       │  Feed Cache │ │  Ranking   │ │ Post     │
                       │   (Redis)   │ │  Service   │ │ Service  │
                       └──────┬──────┘ └────────────┘ └────┬─────┘
                              │                             │
                       ┌──────▼──────┐              ┌──────▼──────┐
                       │  Fan-out    │              │  Post Store │
                       │  Service    │              │ (PostgreSQL)│
                       └──────┬──────┘              └─────────────┘
                              │
                       ┌──────▼──────┐
                       │    Kafka    │
                       └─────────────┘

Feed Generation Strategy:
┌──────────────────────────────────────────────────┐
│  Celebrity users (>10K followers): fan-out on    │
│  READ (pull model - fetch at query time)         │
│                                                  │
│  Regular users (<10K followers): fan-out on      │
│  WRITE (push model - pre-compute feeds)          │
└──────────────────────────────────────────────────┘
```

### Data Model

```sql
-- Posts
CREATE TABLE posts (
    post_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_id BIGINT NOT NULL,
    content TEXT,
    media_urls JSONB DEFAULT '[]',
    post_type VARCHAR(20) DEFAULT 'original', -- 'original', 'share', 'reply'
    shared_post_id BIGINT REFERENCES posts(post_id),
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    share_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_deleted BOOLEAN DEFAULT FALSE
);

-- Social graph
CREATE TABLE follows (
    follower_id BIGINT NOT NULL,
    followed_id BIGINT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id)
);
CREATE INDEX idx_follows_followed ON follows (followed_id);

-- Pre-computed feed (fan-out on write)
CREATE TABLE user_feed (
    user_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    author_id BIGINT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    relevance_score FLOAT DEFAULT 0,
    PRIMARY KEY (user_id, created_at, post_id)
) PARTITION BY RANGE (created_at);
```

### Feed Generation

```python
# Hybrid fan-out strategy
CELEBRITY_THRESHOLD = 10_000

async def on_new_post(post: dict):
    """Handle a new post: fan-out to followers' feeds."""
    author_id = post['author_id']
    follower_count = await get_follower_count(author_id)

    if follower_count > CELEBRITY_THRESHOLD:
        # Celebrity: do NOT fan-out on write (too expensive)
        # Their posts will be pulled at read time
        await redis.zadd(
            f"celebrity_posts:{author_id}",
            {post['post_id']: post['created_at'].timestamp()}
        )
        return

    # Regular user: fan-out on write
    followers = await get_followers(author_id)
    batch = []
    for follower_id in followers:
        batch.append({
            'user_id': follower_id,
            'post_id': post['post_id'],
            'author_id': author_id,
            'created_at': post['created_at'],
        })

    # Batch insert into feed table + Redis cache
    await bulk_insert_feed(batch)
    for follower_id in followers:
        await redis.zadd(
            f"feed:{follower_id}",
            {post['post_id']: post['created_at'].timestamp()}
        )
        # Trim to latest 1000 posts
        await redis.zremrangebyrank(f"feed:{follower_id}", 0, -1001)


async def get_feed(user_id: int, cursor: str = None, limit: int = 20) -> dict:
    """Get a user's feed, combining pre-computed and on-demand posts."""

    # 1. Get pre-computed feed posts (from fan-out on write)
    cached_post_ids = await redis.zrevrange(
        f"feed:{user_id}",
        0, limit * 2,  # fetch extra for ranking
    )

    # 2. Get celebrity posts for users this person follows
    celebrity_followings = await get_celebrity_followings(user_id)
    celebrity_post_ids = []
    for celeb_id in celebrity_followings:
        posts = await redis.zrevrangebyscore(
            f"celebrity_posts:{celeb_id}",
            '+inf', '-inf',
            start=0, num=20,
        )
        celebrity_post_ids.extend(posts)

    # 3. Merge, deduplicate, and rank
    all_post_ids = list(set(cached_post_ids + celebrity_post_ids))
    posts = await fetch_posts(all_post_ids)
    ranked_posts = await ranking_service.rank(user_id, posts)

    # 4. Paginate
    return paginate(ranked_posts, cursor, limit)
```

### Scale Considerations

- **Fan-out on write cost:** A user with 1000 followers means 1000 feed writes per post. Use async Kafka consumers with batch inserts.
- **Celebrity problem:** A user with 10M followers posting means 10M writes. Use fan-out on read for celebrities.
- **Feed cache size:** Keep only the most recent 1000 posts per user in Redis. Older posts fall back to the database.
- **Feed ranking:** Use a lightweight ML model that scores posts by engagement probability. Pre-compute features (author affinity, content type preferences) offline.
- **Cache invalidation:** When a post is deleted, publish a "post_deleted" event. Consumers remove it from affected feeds asynchronously.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fan-out strategy | Hybrid (push for regular, pull for celebrity) | Balances write cost and read latency |
| Feed storage | Redis (cache) + PostgreSQL (persistent) | Fast reads with durability |
| Ranking | Two-phase (candidate retrieval + scoring) | Keeps ranking fast and tunable |
| Pagination | Cursor-based (timestamp + post_id) | Stable under concurrent writes |
| Media | Separate CDN with pre-signed URLs | Offload bandwidth from app servers |

---

## 5. Notification System

### Requirements

**Functional:**
- Multi-channel: push (iOS/Android), email, SMS, in-app
- Template-based messages with variable substitution
- User notification preferences (opt-in/opt-out per channel per type)
- Rate limiting per user per channel
- Scheduled / delayed notifications
- Batch notifications (digest emails)

**Non-Functional:**
- 10M notifications/day across all channels
- Push delivery latency < 5 seconds
- Email delivery within 1 minute
- 99.9% delivery rate
- Audit trail for all notifications

### High-Level Architecture

```
┌──────────────┐     ┌─────────────┐     ┌─────────────────┐
│  Triggering  │────│   Kafka     │────│  Notification    │
│  Services    │     │  (ingest)   │     │  Orchestrator    │
└──────────────┘     └─────────────┘     └────────┬────────┘
                                                   │
                              ┌────────────────────┼───────────────────┐
                              │                    │                   │
                       ┌──────▼──────┐      ┌──────▼──────┐    ┌──────▼──────┐
                       │   Push      │      │   Email     │    │    SMS      │
                       │   Worker    │      │   Worker    │    │   Worker    │
                       │  (APNs/FCM) │      │ (SendGrid)  │    │  (Twilio)   │
                       └─────────────┘      └─────────────┘    └─────────────┘
                                                   │
                                            ┌──────▼──────┐
                                            │  In-App     │
                                            │  Notification│
                                            │  (WebSocket) │
                                            └─────────────┘

Supporting Services:
┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐
│  User Preference │  │  Template    │  │   Rate Limiter   │
│  Service         │  │  Service     │  │   (per user)     │
└─────────────────┘  └──────────────┘  └──────────────────┘
```

### Data Model

```sql
-- Notification events (audit trail)
CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id BIGINT NOT NULL,
    type VARCHAR(50) NOT NULL,           -- 'order_shipped', 'friend_request', etc.
    channel VARCHAR(20) NOT NULL,        -- 'push', 'email', 'sms', 'in_app'
    template_id VARCHAR(100) NOT NULL,
    template_vars JSONB NOT NULL DEFAULT '{}',
    priority VARCHAR(10) DEFAULT 'normal', -- 'critical', 'high', 'normal', 'low'
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'sent', 'delivered', 'failed', 'skipped'
    scheduled_at TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    failed_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- User notification preferences
CREATE TABLE notification_preferences (
    user_id BIGINT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    enabled BOOLEAN DEFAULT TRUE,
    quiet_hours_start TIME,            -- e.g., 22:00
    quiet_hours_end TIME,              -- e.g., 08:00
    frequency VARCHAR(20) DEFAULT 'immediate', -- 'immediate', 'hourly_digest', 'daily_digest'
    PRIMARY KEY (user_id, notification_type, channel)
);
```

### Notification Pipeline

```python
class NotificationOrchestrator:
    """Central orchestrator that routes notifications to the correct channels."""

    async def process_notification_request(self, event: dict):
        user_id = event['user_id']
        notification_type = event['type']

        # 1. Check user preferences
        preferences = await self.get_preferences(user_id, notification_type)
        enabled_channels = [p.channel for p in preferences if p.enabled]

        if not enabled_channels:
            await self.record_skipped(event, reason='user_opted_out')
            return

        # 2. Render template
        template = await self.template_service.get(event['template_id'])
        rendered = template.render(event.get('template_vars', {}))

        # 3. Route to each enabled channel
        for channel in enabled_channels:
            # Check quiet hours
            if await self.is_quiet_hours(user_id, channel):
                if event.get('priority') != 'critical':
                    await self.schedule_for_later(event, channel)
                    continue

            # Check rate limits
            if not await self.rate_limiter.is_allowed(
                key=f"notif:{user_id}:{channel}",
                max_requests=self.get_rate_limit(channel),
                window_seconds=3600,
            ):
                await self.record_skipped(event, reason='rate_limited')
                continue

            # Check digest preference
            pref = next(p for p in preferences if p.channel == channel)
            if pref.frequency != 'immediate':
                await self.add_to_digest(user_id, channel, pref.frequency, event)
                continue

            # Dispatch to channel worker
            await self.dispatch(channel, {
                'notification_id': str(uuid4()),
                'user_id': user_id,
                'channel': channel,
                'subject': rendered.get('subject'),
                'title': rendered.get('title'),
                'body': rendered['body'],
                'data': event.get('data', {}),
                'priority': event.get('priority', 'normal'),
            })

    async def dispatch(self, channel: str, payload: dict):
        """Send to the appropriate Kafka topic for the channel."""
        topic_map = {
            'push': 'notifications.push',
            'email': 'notifications.email',
            'sms': 'notifications.sms',
            'in_app': 'notifications.in_app',
        }
        await kafka.produce(topic_map[channel], payload)
```

### Scale Considerations

- **Push notification throughput:** APNs and FCM have rate limits. Use connection pooling and batch APIs. FCM supports up to 500 devices per multicast.
- **Email sending:** Use dedicated IP pools to maintain sender reputation. Warm up new IPs gradually (100/day -> 1000/day -> 10000/day).
- **Priority queues:** Use separate Kafka topics or consumer groups for critical vs normal notifications. Critical notifications bypass rate limits and quiet hours.
- **Deduplication:** Use a dedup key (user_id + notification_type + time_window) to prevent duplicate notifications from retry storms.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Queue | Kafka with per-channel topics | Independent scaling and backpressure per channel |
| Template engine | Server-side rendering (Jinja2) | Consistent output, easy A/B testing |
| Preference storage | PostgreSQL | Transactional, strongly consistent |
| Rate limiting | Per-user per-channel in Redis | Prevents notification spam |
| Retry strategy | Exponential backoff with max 3 retries | Handles transient failures without flooding |
| Digest | Cron-based aggregation | Batch multiple notifications into one email |

---

## 6. Search Autocomplete

### Requirements

**Functional:**
- Return top 5-10 suggestions as the user types
- Suggestions based on popularity, recency, and personalization
- Support phrase completion (not just prefix matching)
- Handle typos and fuzzy matching
- Region/language-specific suggestions

**Non-Functional:**
- 10B queries/day
- p99 latency < 100ms
- Update suggestions within 1 hour of trending queries
- Handle 100K concurrent users

### High-Level Architecture

```
┌──────────┐     ┌──────────────┐     ┌─────────────────┐
│  Client   │────│  API Gateway │────│  Autocomplete   │
│           │     │  (edge/CDN)  │     │  Service        │
└──────────┘     └──────────────┘     └────────┬────────┘
                                               │
                              ┌────────────────┼────────────────┐
                              │                │                │
                       ┌──────▼──────┐  ┌──────▼──────┐  ┌─────▼──────┐
                       │  Trie Cache │  │ Elasticsearch│  │  Personal  │
                       │   (Redis)   │  │  (fallback)  │  │  Ranker    │
                       └──────┬──────┘  └─────────────┘  └────────────┘
                              │
                       ┌──────▼──────┐
                       │  Suggestion │
                       │  Builder    │ (offline job, updates hourly)
                       └──────┬──────┘
                              │
                       ┌──────▼──────┐
                       │  Query Logs │
                       │  (Kafka ->  │
                       │   ClickHouse)│
                       └─────────────┘
```

### Data Model

```sql
-- Aggregated query suggestions (built offline)
CREATE TABLE suggestions (
    prefix VARCHAR(100) NOT NULL,
    suggestion TEXT NOT NULL,
    score FLOAT NOT NULL,           -- popularity score
    language VARCHAR(5) DEFAULT 'en',
    region VARCHAR(5),              -- optional geo filter
    category VARCHAR(50),           -- 'trending', 'evergreen', 'product', etc.
    updated_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (prefix, suggestion)
);

CREATE INDEX idx_suggestions_prefix ON suggestions (prefix, score DESC);

-- Query logs for computing popularity
CREATE TABLE query_log (
    query_text TEXT NOT NULL,
    user_id BIGINT,
    session_id UUID,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    result_count INT,
    clicked_position INT           -- which result did the user click
);
```

### Trie-Based In-Memory Approach

```python
from collections import defaultdict
from typing import List, Tuple
import heapq

class AutocompleteTrie:
    """
    In-memory trie for fast prefix matching.
    Each node stores top-K suggestions for that prefix.
    """

    def __init__(self, top_k: int = 10):
        self.top_k = top_k
        self.children = defaultdict(AutocompleteTrie)
        self.suggestions: List[Tuple[float, str]] = []  # (score, text)
        self.is_leaf = False

    def insert(self, text: str, score: float):
        """Insert a suggestion into the trie."""
        node = self
        for char in text.lower():
            node = node.children[char]
            # Update top-K suggestions at each prefix node
            node._add_suggestion(text, score)
        node.is_leaf = True

    def _add_suggestion(self, text: str, score: float):
        """Maintain a top-K heap of suggestions."""
        # Remove existing entry for this text if present
        self.suggestions = [
            (s, t) for s, t in self.suggestions if t != text
        ]
        if len(self.suggestions) < self.top_k:
            heapq.heappush(self.suggestions, (score, text))
        elif score > self.suggestions[0][0]:
            heapq.heapreplace(self.suggestions, (score, text))

    def search(self, prefix: str) -> List[Tuple[float, str]]:
        """Return top-K suggestions for a prefix."""
        node = self
        for char in prefix.lower():
            if char not in node.children:
                return []
            node = node.children[char]
        # Return sorted by score descending
        return sorted(node.suggestions, key=lambda x: -x[0])

    @classmethod
    def build_from_queries(cls, query_counts: dict, top_k: int = 10):
        """Build a trie from query -> count mapping."""
        trie = cls(top_k=top_k)
        for query, count in query_counts.items():
            if len(query) >= 2:  # skip single-char queries
                trie.insert(query, count)
        return trie
```

### Redis-Based Approach (Distributed)

```python
class RedisAutocomplete:
    """Distributed autocomplete using Redis sorted sets."""

    def __init__(self, redis_client, prefix_length: int = 2):
        self.redis = redis_client
        self.prefix_length = prefix_length

    async def index_suggestion(self, text: str, score: float, language: str = 'en'):
        """Index a suggestion for all its prefixes."""
        normalized = text.lower().strip()
        key_prefix = f"ac:{language}"

        pipeline = self.redis.pipeline()
        # Index for each prefix length
        for i in range(self.prefix_length, len(normalized) + 1):
            prefix = normalized[:i]
            pipeline.zadd(f"{key_prefix}:{prefix}", {normalized: score})
            # Keep only top 20 per prefix
            pipeline.zremrangebyrank(f"{key_prefix}:{prefix}", 0, -21)
            pipeline.expire(f"{key_prefix}:{prefix}", 86400 * 7)  # 7-day TTL
        await pipeline.execute()

    async def search(
        self, prefix: str, limit: int = 10, language: str = 'en'
    ) -> list:
        """Get top suggestions for a prefix."""
        normalized = prefix.lower().strip()
        if len(normalized) < self.prefix_length:
            return []

        key = f"ac:{language}:{normalized}"
        results = await self.redis.zrevrange(key, 0, limit - 1, withscores=True)
        return [
            {'text': text.decode(), 'score': score}
            for text, score in results
        ]

    async def bulk_rebuild(self, query_counts: dict, language: str = 'en'):
        """Rebuild the entire autocomplete index from aggregated query counts."""
        # Sort by count to process most popular first
        sorted_queries = sorted(query_counts.items(), key=lambda x: -x[1])

        for query, count in sorted_queries[:100_000]:  # top 100K queries
            await self.index_suggestion(query, count, language)
```

### Scale Considerations

- **Edge caching:** Cache the top 1000 prefixes (2-3 character prefixes) at CDN edge locations. These cover the majority of requests.
- **Personalization:** Blend global popular suggestions (70%) with user-specific recent queries (30%). Keep per-user recent queries in Redis with a small sorted set.
- **Trending detection:** Run a sliding window counter on query logs. Compare current-hour frequency to the same-hour-last-week average. Boost suggestions with high ratios.
- **Typo tolerance:** Use phonetic matching (Soundex/Metaphone) or edit-distance algorithms as a fallback when the trie returns no results.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Primary store | Redis sorted sets | Sub-ms lookups, easy score updates |
| Index granularity | Per-character prefix | Good balance of memory and precision |
| Update frequency | Hourly batch rebuild from query logs | Fresh enough for trends, avoids real-time complexity |
| Personalization | 70/30 blend (global + personal) | Useful without being a filter bubble |
| Typo handling | Elasticsearch fuzzy fallback | Only invoked when trie returns empty |

---

## 7. File Storage (S3-like)

### Requirements

**Functional:**
- Upload/download files (1 byte to 5 TB)
- Organize files in buckets and key prefixes
- Versioning support
- Access control (public, private, signed URLs)
- Multipart upload for large files
- Metadata and tagging

**Non-Functional:**
- 99.999999999% (11 nines) durability
- 99.99% availability
- Support 100K requests/sec
- Support petabytes of storage
- Consistent reads after writes

### High-Level Architecture

```
┌──────────┐     ┌──────────────┐     ┌─────────────────┐
│  Client   │────│  API Gateway │────│  Metadata       │
│  (SDK)    │     │  (REST/HTTP) │     │  Service        │
└──────────┘     └──────────────┘     └────────┬────────┘
                        │                       │
                        │              ┌────────▼────────┐
                        │              │  Metadata DB    │
                        │              │  (CockroachDB / │
                        │              │   TiKV)         │
                        │              └─────────────────┘
                        │
                 ┌──────▼──────┐
                 │  Data Plane │
                 │   (direct   │
                 │   upload)   │
                 └──────┬──────┘
                        │
           ┌────────────┼────────────┐
           │            │            │
    ┌──────▼──────┐ ┌───▼────┐ ┌────▼─────┐
    │  Storage    │ │ Storage│ │ Storage  │
    │  Node AZ-1 │ │ Node   │ │ Node     │
    │  (SSD+HDD) │ │ AZ-2   │ │ AZ-3     │
    └─────────────┘ └────────┘ └──────────┘

Data Replication:
┌──────────────────────────────────────────────────┐
│  Each object is split into chunks and replicated │
│  across 3 availability zones using erasure coding│
│  (e.g., Reed-Solomon 6+3 for 11-nines durability)│
└──────────────────────────────────────────────────┘
```

### Data Model

```sql
-- Buckets
CREATE TABLE buckets (
    bucket_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_name VARCHAR(63) UNIQUE NOT NULL,
    owner_id BIGINT NOT NULL,
    region VARCHAR(20) NOT NULL,
    versioning_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    storage_class VARCHAR(20) DEFAULT 'STANDARD'
);

-- Objects (metadata only; data stored on storage nodes)
CREATE TABLE objects (
    bucket_id UUID NOT NULL REFERENCES buckets(bucket_id),
    object_key TEXT NOT NULL,
    version_id UUID DEFAULT gen_random_uuid(),
    is_latest BOOLEAN DEFAULT TRUE,
    size_bytes BIGINT NOT NULL,
    content_type VARCHAR(255),
    etag VARCHAR(32) NOT NULL,           -- MD5 of content
    storage_class VARCHAR(20) DEFAULT 'STANDARD',
    metadata JSONB DEFAULT '{}',
    chunk_map JSONB NOT NULL,            -- maps chunk_id -> storage_node locations
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,  -- soft delete
    PRIMARY KEY (bucket_id, object_key, version_id)
);

CREATE INDEX idx_objects_latest
    ON objects (bucket_id, object_key) WHERE is_latest = TRUE;

-- Multipart uploads (in progress)
CREATE TABLE multipart_uploads (
    upload_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id UUID NOT NULL,
    object_key TEXT NOT NULL,
    initiated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'in_progress' -- 'in_progress', 'completed', 'aborted'
);

CREATE TABLE upload_parts (
    upload_id UUID NOT NULL REFERENCES multipart_uploads(upload_id),
    part_number INT NOT NULL,
    size_bytes BIGINT NOT NULL,
    etag VARCHAR(32) NOT NULL,
    chunk_locations JSONB NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (upload_id, part_number)
);
```

### API Design

```
PUT    /{bucket}/{key}                     -- Upload object
GET    /{bucket}/{key}                     -- Download object
DELETE /{bucket}/{key}                     -- Delete object
HEAD   /{bucket}/{key}                     -- Get object metadata
GET    /{bucket}?prefix=&delimiter=&max-keys= -- List objects

POST   /{bucket}/{key}?uploads             -- Initiate multipart upload
PUT    /{bucket}/{key}?partNumber=&uploadId= -- Upload part
POST   /{bucket}/{key}?uploadId=           -- Complete multipart upload

GET    /{bucket}/{key}?presigned&expires=   -- Generate pre-signed URL
```

### Upload Flow

```python
class ObjectStorageService:
    """Core upload/download logic."""

    CHUNK_SIZE = 64 * 1024 * 1024  # 64 MB chunks

    async def upload_object(
        self, bucket_id: str, key: str, data: bytes, metadata: dict
    ) -> dict:
        """Upload an object, splitting into chunks and replicating."""

        # 1. Split into chunks
        chunks = self._split_into_chunks(data)
        etag = hashlib.md5(data).hexdigest()

        # 2. Allocate storage nodes for each chunk
        chunk_map = {}
        for i, chunk_data in enumerate(chunks):
            # Select 3 storage nodes across different AZs
            nodes = await self.placement_service.select_nodes(
                size=len(chunk_data),
                replication_factor=3,
                placement_policy='cross_az',
            )

            # Write chunk to all replicas
            chunk_id = f"{etag}-{i}"
            write_results = await asyncio.gather(*[
                node.write_chunk(chunk_id, chunk_data)
                for node in nodes
            ])

            # Require at least 2/3 successful writes (quorum)
            successful = [r for r in write_results if r.success]
            if len(successful) < 2:
                await self._cleanup_partial_upload(chunk_map)
                raise StorageError("Failed to achieve write quorum")

            chunk_map[chunk_id] = {
                'size': len(chunk_data),
                'nodes': [n.node_id for n in nodes],
                'checksum': hashlib.sha256(chunk_data).hexdigest(),
            }

        # 3. Write metadata (atomic)
        object_record = {
            'bucket_id': bucket_id,
            'object_key': key,
            'size_bytes': len(data),
            'content_type': metadata.get('content_type', 'application/octet-stream'),
            'etag': etag,
            'chunk_map': chunk_map,
            'metadata': metadata,
        }
        await self.metadata_db.upsert_object(object_record)

        return {'etag': etag, 'version_id': object_record.get('version_id')}

    def _split_into_chunks(self, data: bytes) -> list:
        return [
            data[i:i + self.CHUNK_SIZE]
            for i in range(0, len(data), self.CHUNK_SIZE)
        ]
```

### Scale Considerations

- **Durability:** Use erasure coding (e.g., Reed-Solomon 6+3) instead of full replication for cold storage. 1.5x storage overhead vs 3x for triple replication, with equivalent durability.
- **Metadata bottleneck:** The metadata store must handle millions of objects per bucket. Use a distributed KV store (TiKV, CockroachDB) and shard by bucket_id + key_prefix.
- **List operations:** Listing objects with prefix filtering is expensive. Maintain a secondary index on prefixes or use a dedicated listing service with eventual consistency.
- **Large file uploads:** Multipart upload is mandatory for files > 100MB. Client uploads parts in parallel, server assembles on completion.
- **Consistent hashing:** Map chunks to storage nodes using consistent hashing with virtual nodes. This minimizes data movement when nodes are added/removed.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Replication | 3-way cross-AZ for hot, erasure coding for cold | Durability + cost balance |
| Metadata store | CockroachDB (distributed SQL) | Strong consistency, auto-sharding |
| Chunk size | 64 MB | Good balance of parallelism and overhead |
| Write quorum | 2 of 3 replicas | Availability with strong durability |
| Read path | Read from any replica, verify checksum | Low latency, detect bit rot |
| Large files | Multipart upload with parallel parts | Resilience to network failures |

---

## 8. Payment System

### Requirements

**Functional:**
- Process credit card, debit card, and bank transfer payments
- Support multiple currencies
- Refunds (full and partial)
- Recurring billing / subscriptions
- Payment method management (tokenized, PCI-compliant)
- Webhooks for payment events
- Idempotent payment processing

**Non-Functional:**
- 1000 payments/sec peak
- p99 payment latency < 3 seconds
- 99.999% availability for payment processing
- Zero data loss (financial records)
- PCI DSS Level 1 compliant
- Full audit trail

### High-Level Architecture

```
┌──────────┐     ┌──────────────┐     ┌─────────────────┐
│  Client   │────│  API Gateway │────│  Payment        │
│  (PCI     │     │  (TLS 1.3)   │     │  Service        │
│   iframe) │     └──────────────┘     └────────┬────────┘
└──────────┘                                    │
                                    ┌───────────┼───────────┐
                                    │           │           │
                             ┌──────▼──────┐ ┌──▼──────┐ ┌──▼───────┐
                             │  Payment    │ │ Ledger  │ │ Webhook  │
                             │  Router     │ │ Service │ │ Service  │
                             └──────┬──────┘ └─────────┘ └──────────┘
                                    │
                        ┌───────────┼───────────┐
                        │           │           │
                 ┌──────▼──┐ ┌─────▼──────┐ ┌──▼──────────┐
                 │ Stripe  │ │ Braintree  │ │ Bank Direct │
                 │ Adapter │ │ Adapter    │ │ Adapter     │
                 └─────────┘ └────────────┘ └─────────────┘

Payment State Machine:
┌─────────┐     ┌──────────┐     ┌───────────┐     ┌───────────┐
│ Created │────►│ Pending  │────►│ Authorized│────►│ Captured  │
└─────────┘     └────┬─────┘     └─────┬─────┘     └─────┬─────┘
                     │                  │                   │
                     ▼                  ▼                   ▼
                ┌─────────┐      ┌───────────┐      ┌───────────┐
                │ Failed  │      │  Voided   │      │ Refunded  │
                └─────────┘      └───────────┘      └───────────┘
```

### Data Model

```sql
-- Payments (source of truth)
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key VARCHAR(255) UNIQUE NOT NULL,  -- client-provided dedup key
    merchant_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    amount BIGINT NOT NULL,               -- amount in smallest currency unit (cents)
    currency VARCHAR(3) NOT NULL,         -- ISO 4217 (USD, EUR, GBP)
    status VARCHAR(20) NOT NULL DEFAULT 'created',
    payment_method_id UUID NOT NULL,
    processor VARCHAR(50) NOT NULL,       -- 'stripe', 'braintree', etc.
    processor_transaction_id VARCHAR(255),
    description TEXT,
    metadata JSONB DEFAULT '{}',
    failure_code VARCHAR(50),
    failure_message TEXT,
    authorized_at TIMESTAMP WITH TIME ZONE,
    captured_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INT DEFAULT 1                 -- optimistic locking
);

CREATE INDEX idx_payments_merchant ON payments (merchant_id, created_at DESC);
CREATE INDEX idx_payments_customer ON payments (customer_id, created_at DESC);
CREATE INDEX idx_payments_idempotency ON payments (idempotency_key);

-- Double-entry ledger
CREATE TABLE ledger_entries (
    entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id UUID NOT NULL REFERENCES payments(payment_id),
    account_id VARCHAR(100) NOT NULL,     -- 'merchant:123', 'platform:fees', etc.
    entry_type VARCHAR(10) NOT NULL,      -- 'debit' or 'credit'
    amount BIGINT NOT NULL,               -- always positive
    currency VARCHAR(3) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Every transaction must have balanced debits and credits
-- Enforced by application logic, verified by reconciliation jobs

-- Refunds
CREATE TABLE refunds (
    refund_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES payments(payment_id),
    idempotency_key VARCHAR(255) UNIQUE NOT NULL,
    amount BIGINT NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    processor_refund_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Payment Processing with Idempotency

```python
class PaymentService:
    """Core payment processing with idempotency and double-entry ledger."""

    async def create_payment(self, request: dict) -> dict:
        """Process a payment request idempotently."""
        idempotency_key = request['idempotency_key']

        # 1. Check for existing payment with this idempotency key
        existing = await self.db.fetch_one("""
            SELECT * FROM payments WHERE idempotency_key = :key
        """, {'key': idempotency_key})

        if existing:
            # Return the existing result (idempotent)
            return self._format_response(existing)

        # 2. Create the payment record
        payment_id = str(uuid4())
        await self.db.execute("""
            INSERT INTO payments (
                payment_id, idempotency_key, merchant_id, customer_id,
                amount, currency, status, payment_method_id, processor
            ) VALUES (
                :payment_id, :idempotency_key, :merchant_id, :customer_id,
                :amount, :currency, 'created', :payment_method_id, :processor
            )
        """, {
            'payment_id': payment_id,
            'idempotency_key': idempotency_key,
            'merchant_id': request['merchant_id'],
            'customer_id': request['customer_id'],
            'amount': request['amount'],
            'currency': request['currency'],
            'payment_method_id': request['payment_method_id'],
            'processor': self._select_processor(request),
        })

        # 3. Authorize with payment processor
        try:
            processor = self._get_processor(request)
            auth_result = await processor.authorize(
                amount=request['amount'],
                currency=request['currency'],
                payment_method_token=request['payment_method_id'],
            )

            # 4. Update payment status
            await self.db.execute("""
                UPDATE payments SET
                    status = 'authorized',
                    processor_transaction_id = :processor_tx_id,
                    authorized_at = NOW(),
                    updated_at = NOW()
                WHERE payment_id = :payment_id AND version = 1
            """, {
                'payment_id': payment_id,
                'processor_tx_id': auth_result['transaction_id'],
            })

            # 5. Capture immediately (or defer for two-step auth)
            if request.get('auto_capture', True):
                await self._capture_payment(payment_id, auth_result)

        except ProcessorDeclinedError as e:
            await self._mark_failed(payment_id, e.code, str(e))
            raise PaymentDeclinedError(e.code, str(e))

        except Exception as e:
            await self._mark_failed(payment_id, 'INTERNAL_ERROR', str(e))
            raise

        # 6. Publish event for webhooks and downstream
        await self.event_bus.publish('payment.completed', {
            'payment_id': payment_id,
            'merchant_id': request['merchant_id'],
            'amount': request['amount'],
            'currency': request['currency'],
        })

        return await self._get_payment(payment_id)

    async def _capture_payment(self, payment_id: str, auth_result: dict):
        """Capture an authorized payment and create ledger entries."""
        payment = await self._get_payment(payment_id)

        # Capture with processor
        capture_result = await self._get_processor_for_payment(payment).capture(
            transaction_id=auth_result['transaction_id'],
            amount=payment['amount'],
        )

        # Create double-entry ledger records (atomic transaction)
        await self.db.execute("""
            BEGIN;

            UPDATE payments SET
                status = 'captured',
                captured_at = NOW(),
                updated_at = NOW()
            WHERE payment_id = :payment_id;

            -- Debit: money moves from customer's funding source
            INSERT INTO ledger_entries (
                payment_id, account_id, entry_type, amount, currency, description
            ) VALUES (
                :payment_id, :customer_account, 'debit',
                :amount, :currency, 'Payment capture'
            );

            -- Credit: money goes to merchant
            INSERT INTO ledger_entries (
                payment_id, account_id, entry_type, amount, currency, description
            ) VALUES (
                :payment_id, :merchant_account, 'credit',
                :merchant_amount, :currency, 'Payment to merchant'
            );

            -- Credit: platform fee
            INSERT INTO ledger_entries (
                payment_id, account_id, entry_type, amount, currency, description
            ) VALUES (
                :payment_id, 'platform:fees', 'credit',
                :fee_amount, :currency, 'Platform fee'
            );

            COMMIT;
        """, {
            'payment_id': payment_id,
            'customer_account': f"customer:{payment['customer_id']}",
            'merchant_account': f"merchant:{payment['merchant_id']}",
            'amount': payment['amount'],
            'merchant_amount': payment['amount'] - self._calculate_fee(payment),
            'fee_amount': self._calculate_fee(payment),
            'currency': payment['currency'],
        })
```

### Reconciliation Job

```python
async def daily_reconciliation():
    """
    Daily job to verify ledger consistency.
    Every payment must have balanced debits and credits.
    """
    imbalanced = await db.fetch_all("""
        SELECT
            payment_id,
            SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE 0 END) AS total_debits,
            SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE 0 END) AS total_credits
        FROM ledger_entries
        WHERE created_at >= CURRENT_DATE - INTERVAL '1 day'
          AND created_at <  CURRENT_DATE
        GROUP BY payment_id
        HAVING SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE 0 END)
            <> SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE 0 END)
    """)

    if imbalanced:
        alert_client.send_alert(
            severity='critical',
            title='Ledger imbalance detected',
            message=f'{len(imbalanced)} payments have unbalanced ledger entries',
        )
```

### Scale Considerations

- **Idempotency:** The idempotency_key ensures duplicate API calls (network retries, user double-clicks) produce the same result. Store the full response alongside the key for instant replay.
- **PCI compliance:** Never store raw card numbers. Use payment processor tokenization. Card data only passes through a PCI-compliant iframe, never your backend.
- **Multi-processor failover:** Route payments through primary processor. If it fails with a network error (not a decline), retry with a secondary processor. Track which processor handled each payment.
- **Currency handling:** Always store amounts in the smallest unit (cents/pence) as integers. Never use floating point for money. Use BIGINT, not DECIMAL.
- **Distributed transactions:** Payment creation + ledger entry must be atomic. Use a single database transaction, or use the Saga pattern with compensation if across services.

### Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Money representation | Integers (cents) as BIGINT | Avoids floating-point errors |
| Idempotency | Client-provided idempotency keys | Client controls dedup semantics |
| Ledger | Double-entry with reconciliation | Audit trail, catches inconsistencies |
| Auth vs Capture | Two-step (authorize then capture) | Supports holds, partial captures, voids |
| PCI scope | Tokenization via processor iframe | Minimize PCI compliance surface area |
| Processor routing | Primary with automatic failover | Maximizes success rate |
