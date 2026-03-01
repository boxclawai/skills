# Spring Boot Patterns Reference

## Table of Contents

1. [Project Structure & Layered Architecture](#project-structure--layered-architecture)
2. [REST API Design Patterns](#rest-api-design-patterns)
3. [Configuration Patterns](#configuration-patterns)
4. [Database & JPA Patterns](#database--jpa-patterns)
5. [Caching Patterns](#caching-patterns)
6. [Event-Driven Patterns](#event-driven-patterns)
7. [Microservices Patterns with Spring Cloud](#microservices-patterns-with-spring-cloud)
8. [Security Patterns](#security-patterns)
9. [Error Handling Patterns](#error-handling-patterns)
10. [Resilience Patterns](#resilience-patterns)

---

## Project Structure & Layered Architecture

### Package-by-Feature (Recommended for large projects)

```
com.example.ecommerce/
├── order/
│   ├── OrderController.java
│   ├── OrderService.java
│   ├── OrderServiceImpl.java
│   ├── OrderRepository.java
│   ├── Order.java
│   ├── OrderDto.java
│   └── OrderMapper.java
├── product/
│   ├── ProductController.java
│   ├── ProductService.java
│   └── ...
├── user/
│   └── ...
└── shared/
    ├── config/
    ├── exception/
    ├── security/
    └── util/
```

### Package-by-Layer (Suitable for smaller projects)

```
com.example.app/
├── controller/
├── service/
├── repository/
├── model/
│   ├── entity/
│   └── dto/
├── config/
├── exception/
└── util/
```

### Hexagonal Architecture (Ports & Adapters)

```
com.example.app/
├── domain/
│   ├── model/          # Entities, value objects
│   ├── port/
│   │   ├── in/         # Use case interfaces (driving ports)
│   │   └── out/        # Repository/external interfaces (driven ports)
│   └── service/        # Domain service implementations
├── application/
│   ├── usecase/        # Use case implementations
│   └── dto/            # Application DTOs
├── adapter/
│   ├── in/
│   │   ├── web/        # REST controllers
│   │   └── messaging/  # Kafka/RabbitMQ consumers
│   └── out/
│       ├── persistence/ # JPA repositories, entities
│       └── client/     # HTTP clients, external APIs
└── config/             # Spring configuration
```

---

## REST API Design Patterns

### Resource Naming Conventions

```
GET    /api/v1/orders              → List orders (paginated)
GET    /api/v1/orders/{id}         → Get order by ID
POST   /api/v1/orders              → Create order
PUT    /api/v1/orders/{id}         → Full update
PATCH  /api/v1/orders/{id}         → Partial update
DELETE /api/v1/orders/{id}         → Delete order
GET    /api/v1/orders/{id}/items   → List items for order (sub-resource)
POST   /api/v1/orders/{id}/cancel  → Action endpoint (verb as sub-resource)
```

### Pagination & Sorting

```java
@GetMapping
public ResponseEntity<Page<OrderResponse>> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(defaultValue = "createdAt,desc") String[] sort) {

    Pageable pageable = PageRequest.of(page, size, Sort.by(
            Arrays.stream(sort)
                    .map(s -> {
                        String[] parts = s.split(",");
                        return parts.length > 1 && parts[1].equalsIgnoreCase("desc")
                                ? Sort.Order.desc(parts[0])
                                : Sort.Order.asc(parts[0]);
                    })
                    .toList()));

    return ResponseEntity.ok(orderService.findAll(pageable));
}
```

### HATEOAS Response

```java
@GetMapping("/{id}")
public EntityModel<OrderResponse> getOrder(@PathVariable Long id) {
    OrderResponse order = orderService.findById(id);
    return EntityModel.of(order,
            linkTo(methodOn(OrderController.class).getOrder(id)).withSelfRel(),
            linkTo(methodOn(OrderController.class).list(Pageable.unpaged()))
                    .withRel("orders"),
            linkTo(methodOn(OrderItemController.class).listItems(id))
                    .withRel("items"));
}
```

### API Versioning Strategies

```java
// URI versioning (most common)
@RequestMapping("/api/v1/orders")
public class OrderControllerV1 { }

@RequestMapping("/api/v2/orders")
public class OrderControllerV2 { }

// Header versioning
@GetMapping(value = "/api/orders", headers = "X-API-Version=1")
public ResponseEntity<OrderV1Response> getOrderV1() { }

// Content negotiation
@GetMapping(value = "/api/orders/{id}",
            produces = "application/vnd.myapp.v1+json")
public ResponseEntity<OrderV1Response> getOrderV1() { }
```

---

## Configuration Patterns

### Type-Safe Configuration Properties

```java
@ConfigurationProperties(prefix = "app.orders")
@Validated
public record OrderProperties(
        @NotNull @Positive Integer maxItemsPerOrder,
        @NotNull Duration processingTimeout,
        @NotBlank String defaultCurrency,
        @Valid NotificationConfig notification
) {
    public record NotificationConfig(
            boolean enabled,
            @Email String fromAddress,
            @NotBlank String templatePath
    ) {}
}

// Register in main class or config
@Configuration
@EnableConfigurationProperties(OrderProperties.class)
public class AppConfig { }
```

```yaml
app:
  orders:
    max-items-per-order: 50
    processing-timeout: PT30M
    default-currency: USD
    notification:
      enabled: true
      from-address: orders@example.com
      template-path: classpath:templates/order-email.html
```

### Profile-Based Configuration

```yaml
# application.yml — shared base
spring:
  application:
    name: order-service

---
# application-dev.yml
spring:
  config:
    activate:
      on-profile: dev
  datasource:
    url: jdbc:h2:mem:devdb
    driver-class-name: org.h2.Driver
  h2:
    console:
      enabled: true
  jpa:
    show-sql: true
    hibernate:
      ddl-auto: create-drop
logging:
  level:
    com.example: DEBUG
    org.hibernate.SQL: DEBUG

---
# application-prod.yml
spring:
  config:
    activate:
      on-profile: prod
  datasource:
    url: ${DATABASE_URL}
    hikari:
      maximum-pool-size: 30
      minimum-idle: 10
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
logging:
  level:
    root: WARN
    com.example: INFO
```

### Custom Auto-Configuration

```java
@AutoConfiguration
@ConditionalOnClass(AuditService.class)
@ConditionalOnProperty(prefix = "app.audit", name = "enabled",
                       havingValue = "true", matchIfMissing = true)
@EnableConfigurationProperties(AuditProperties.class)
public class AuditAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public AuditService auditService(AuditProperties props) {
        return new DefaultAuditService(props);
    }

    @Bean
    @ConditionalOnBean(AuditService.class)
    public AuditAspect auditAspect(AuditService auditService) {
        return new AuditAspect(auditService);
    }
}
```

---

## Database & JPA Patterns

### Entity Lifecycle Callbacks

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter @Setter
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @CreatedBy
    @Column(updatable = false)
    private String createdBy;

    @LastModifiedBy
    private String updatedBy;

    @Version
    private Long version; // Optimistic locking
}
```

### Specification Pattern for Dynamic Queries

```java
public class OrderSpecifications {

    public static Specification<Order> hasStatus(OrderStatus status) {
        return (root, query, cb) ->
                status == null ? null : cb.equal(root.get("status"), status);
    }

    public static Specification<Order> createdAfter(Instant after) {
        return (root, query, cb) ->
                after == null ? null : cb.greaterThan(root.get("createdAt"), after);
    }

    public static Specification<Order> customerNameContains(String name) {
        return (root, query, cb) -> {
            if (name == null || name.isBlank()) return null;
            Join<Order, Customer> customer = root.join("customer");
            return cb.like(cb.lower(customer.get("name")),
                    "%" + name.toLowerCase() + "%");
        };
    }

    public static Specification<Order> totalGreaterThan(BigDecimal min) {
        return (root, query, cb) ->
                min == null ? null : cb.greaterThan(root.get("total"), min);
    }
}

// Usage in service
public Page<Order> search(OrderSearchCriteria criteria, Pageable pageable) {
    Specification<Order> spec = Specification.where(null)
            .and(OrderSpecifications.hasStatus(criteria.status()))
            .and(OrderSpecifications.createdAfter(criteria.from()))
            .and(OrderSpecifications.customerNameContains(criteria.customerName()))
            .and(OrderSpecifications.totalGreaterThan(criteria.minTotal()));
    return orderRepository.findAll(spec, pageable);
}
```

### Flyway Database Migrations

```
src/main/resources/db/migration/
├── V1__create_users_table.sql
├── V2__create_orders_table.sql
├── V3__add_order_status_index.sql
├── V4__add_customer_email_column.sql
└── R__refresh_order_summary_view.sql  (repeatable)
```

```sql
-- V2__create_orders_table.sql
CREATE TABLE orders (
    id         BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES users(id),
    status     VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    total      DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes      TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    version    BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created ON orders(created_at);
```

### Read-Replica Configuration

```java
@Configuration
public class DataSourceConfig {

    @Bean
    @ConfigurationProperties("spring.datasource.primary")
    public DataSource primaryDataSource() {
        return DataSourceBuilder.create().build();
    }

    @Bean
    @ConfigurationProperties("spring.datasource.replica")
    public DataSource replicaDataSource() {
        return DataSourceBuilder.create().build();
    }

    @Bean
    public DataSource routingDataSource(
            DataSource primaryDataSource,
            DataSource replicaDataSource) {
        var routing = new ReadReplicaRoutingDataSource();
        routing.setDefaultTargetDataSource(primaryDataSource);
        routing.setTargetDataSources(Map.of(
                "primary", primaryDataSource,
                "replica", replicaDataSource));
        return routing;
    }
}

public class ReadReplicaRoutingDataSource
        extends AbstractRoutingDataSource {
    @Override
    protected Object determineCurrentLookupKey() {
        return TransactionSynchronizationManager
                .isCurrentTransactionReadOnly() ? "replica" : "primary";
    }
}
```

---

## Caching Patterns

### Spring Cache Abstraction

```java
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        CaffeineCacheManager manager = new CaffeineCacheManager();
        manager.setCaffeine(Caffeine.newBuilder()
                .maximumSize(1000)
                .expireAfterWrite(Duration.ofMinutes(10))
                .recordStats());
        return manager;
    }
}

@Service
@RequiredArgsConstructor
public class ProductService {

    @Cacheable(value = "products", key = "#id")
    public ProductResponse findById(Long id) {
        return productRepository.findById(id)
                .map(productMapper::toResponse)
                .orElseThrow(() -> new ResourceNotFoundException("Product", id));
    }

    @CachePut(value = "products", key = "#result.id()")
    @Transactional
    public ProductResponse update(Long id, UpdateProductRequest request) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product", id));
        productMapper.updateEntity(request, product);
        return productMapper.toResponse(productRepository.save(product));
    }

    @CacheEvict(value = "products", key = "#id")
    @Transactional
    public void delete(Long id) {
        productRepository.deleteById(id);
    }

    @CacheEvict(value = "products", allEntries = true)
    @Scheduled(fixedRate = 3600000) // Every hour
    public void evictAllProducts() {
        // Periodic full cache refresh
    }
}
```

### Redis Caching

```java
@Configuration
@EnableCaching
public class RedisCacheConfig {

    @Bean
    public RedisCacheManager cacheManager(
            RedisConnectionFactory connectionFactory) {
        RedisCacheConfiguration defaults = RedisCacheConfiguration
                .defaultCacheConfig()
                .entryTtl(Duration.ofMinutes(30))
                .serializeValuesWith(SerializationPair.fromSerializer(
                        new GenericJackson2JsonRedisSerializer()));

        return RedisCacheManager.builder(connectionFactory)
                .cacheDefaults(defaults)
                .withCacheConfiguration("products",
                        defaults.entryTtl(Duration.ofHours(1)))
                .withCacheConfiguration("user-sessions",
                        defaults.entryTtl(Duration.ofMinutes(5)))
                .build();
    }
}
```

---

## Event-Driven Patterns

### Application Events (In-Process)

```java
// Event definition
public record OrderCreatedEvent(Long orderId, String customerEmail,
                                 BigDecimal total) {}

// Publishing
@Service
@RequiredArgsConstructor
public class OrderService {

    private final ApplicationEventPublisher publisher;

    @Transactional
    public OrderResponse create(CreateOrderRequest request) {
        Order order = // ... save order
        publisher.publishEvent(new OrderCreatedEvent(
                order.getId(), order.getCustomer().getEmail(),
                order.getTotal()));
        return orderMapper.toResponse(order);
    }
}

// Async listener
@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventListener {

    private final NotificationService notificationService;
    private final AnalyticsService analyticsService;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Async
    public void onOrderCreated(OrderCreatedEvent event) {
        log.info("Processing order created event: {}", event.orderId());
        notificationService.sendOrderConfirmation(
                event.customerEmail(), event.orderId());
        analyticsService.trackOrder(event);
    }
}
```

### Kafka Integration

```java
@Configuration
public class KafkaConfig {

    @Bean
    public NewTopic orderEventsTopic() {
        return TopicBuilder.name("order-events")
                .partitions(6)
                .replicas(3)
                .config(TopicConfig.RETENTION_MS_CONFIG, "604800000") // 7 days
                .build();
    }
}

@Service
@RequiredArgsConstructor
public class OrderEventProducer {

    private final KafkaTemplate<String, OrderEvent> kafkaTemplate;

    public CompletableFuture<SendResult<String, OrderEvent>> publish(
            OrderEvent event) {
        return kafkaTemplate.send("order-events",
                event.orderId().toString(), event);
    }
}

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventConsumer {

    private final OrderProcessingService processingService;

    @KafkaListener(topics = "order-events",
                   groupId = "order-processing",
                   concurrency = "3")
    @RetryableTopic(attempts = "3",
                    backoff = @Backoff(delay = 1000, multiplier = 2))
    public void consume(OrderEvent event,
                        @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
                        @Header(KafkaHeaders.OFFSET) long offset) {
        log.info("Received event [partition={}, offset={}]: {}",
                partition, offset, event.orderId());
        processingService.process(event);
    }

    @DltHandler
    public void handleDlt(OrderEvent event) {
        log.error("Dead letter: failed to process order event: {}",
                event.orderId());
        // Send to dead letter queue or alert
    }
}
```

---

## Microservices Patterns with Spring Cloud

### Service Discovery (Eureka)

```yaml
# Discovery server
spring:
  application:
    name: discovery-server
eureka:
  client:
    register-with-eureka: false
    fetch-registry: false

# Client service
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
  instance:
    prefer-ip-address: true
```

### API Gateway

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: order-service
          uri: lb://order-service
          predicates:
            - Path=/api/v1/orders/**
          filters:
            - StripPrefix=0
            - name: CircuitBreaker
              args:
                name: orderServiceCB
                fallbackUri: forward:/fallback/orders
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 100
                redis-rate-limiter.burstCapacity: 200
```

### OpenFeign Client

```java
@FeignClient(name = "inventory-service",
             fallbackFactory = InventoryClientFallbackFactory.class)
public interface InventoryClient {

    @GetMapping("/api/v1/inventory/{sku}")
    InventoryResponse checkStock(@PathVariable String sku);

    @PostMapping("/api/v1/inventory/reserve")
    ReservationResponse reserve(@RequestBody ReserveRequest request);
}

@Component
@Slf4j
public class InventoryClientFallbackFactory
        implements FallbackFactory<InventoryClient> {

    @Override
    public InventoryClient create(Throwable cause) {
        log.warn("Inventory service fallback triggered", cause);
        return new InventoryClient() {
            @Override
            public InventoryResponse checkStock(String sku) {
                return new InventoryResponse(sku, 0, false);
            }

            @Override
            public ReservationResponse reserve(ReserveRequest request) {
                throw new ServiceUnavailableException(
                        "Inventory service unavailable");
            }
        };
    }
}
```

---

## Security Patterns

### JWT Token Service

```java
@Service
@RequiredArgsConstructor
public class JwtTokenService {

    private final JwtProperties jwtProperties;

    public String generateToken(UserDetails userDetails) {
        Map<String, Object> claims = Map.of(
                "roles", userDetails.getAuthorities().stream()
                        .map(GrantedAuthority::getAuthority)
                        .toList());

        return Jwts.builder()
                .setClaims(claims)
                .setSubject(userDetails.getUsername())
                .setIssuedAt(Date.from(Instant.now()))
                .setExpiration(Date.from(
                        Instant.now().plus(jwtProperties.expiration())))
                .signWith(getSigningKey(), SignatureAlgorithm.HS256)
                .compact();
    }

    public String extractUsername(String token) {
        return extractClaims(token).getSubject();
    }

    public boolean isTokenValid(String token, UserDetails userDetails) {
        String username = extractUsername(token);
        return username.equals(userDetails.getUsername())
                && !isTokenExpired(token);
    }

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(
                Decoders.BASE64.decode(jwtProperties.secret()));
    }
}
```

### Method-Level Security

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    @PreAuthorize("hasRole('ADMIN') or #customerId == authentication.principal.id")
    public Page<OrderResponse> findByCustomer(Long customerId,
                                               Pageable pageable) {
        return orderRepository.findByCustomerId(customerId, pageable)
                .map(orderMapper::toResponse);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostAuthorize("returnObject.customerEmail() == authentication.name "
            + "or hasRole('ADMIN')")
    public OrderDetailResponse findById(Long id) {
        return orderRepository.findByIdWithDetails(id)
                .map(orderMapper::toDetailResponse)
                .orElseThrow(() -> new ResourceNotFoundException("Order", id));
    }
}
```

---

## Error Handling Patterns

### Custom Exception Hierarchy

```java
// Base exception
public abstract class ApplicationException extends RuntimeException {
    private final String errorCode;

    protected ApplicationException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public String getErrorCode() { return errorCode; }
}

// Specific exceptions
public class ResourceNotFoundException extends ApplicationException {
    private final String resource;
    private final Object id;

    public ResourceNotFoundException(String resource, Object id) {
        super("NOT_FOUND",
              String.format("%s with id %s not found", resource, id));
        this.resource = resource;
        this.id = id;
    }
}

public class BusinessRuleException extends ApplicationException {
    public BusinessRuleException(String code, String message) {
        super(code, message);
    }
}

public class ConflictException extends ApplicationException {
    public ConflictException(String message) {
        super("CONFLICT", message);
    }
}
```

---

## Resilience Patterns

### Circuit Breaker with Resilience4j

```java
@Service
@RequiredArgsConstructor
public class PaymentService {

    private final PaymentGatewayClient gatewayClient;

    @CircuitBreaker(name = "payment-gateway",
                    fallbackMethod = "paymentFallback")
    @Retry(name = "payment-gateway")
    @RateLimiter(name = "payment-gateway")
    public PaymentResult processPayment(PaymentRequest request) {
        return gatewayClient.charge(request);
    }

    private PaymentResult paymentFallback(PaymentRequest request,
                                          Throwable t) {
        log.warn("Payment gateway unavailable, queuing for retry", t);
        paymentRetryQueue.add(request);
        return new PaymentResult.Queued(request.orderId(),
                "Payment queued for processing");
    }
}
```

```yaml
resilience4j:
  circuitbreaker:
    instances:
      payment-gateway:
        sliding-window-size: 10
        failure-rate-threshold: 50
        wait-duration-in-open-state: 30s
        permitted-number-of-calls-in-half-open-state: 3
  retry:
    instances:
      payment-gateway:
        max-attempts: 3
        wait-duration: 2s
        exponential-backoff-multiplier: 2
        retry-exceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
  ratelimiter:
    instances:
      payment-gateway:
        limit-for-period: 100
        limit-refresh-period: 1s
        timeout-duration: 5s
```
