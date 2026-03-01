---
name: senior-java-developer
version: "1.0.0"
description: "Senior Java engineering expert: Spring Boot/Spring Framework, microservices architecture, JVM performance tuning, design patterns (GoF/Enterprise), testing (JUnit 5/Mockito/Testcontainers), build tools (Maven/Gradle), JPA/Hibernate, Spring Security, reactive programming (WebFlux), and modern Java (17–21+). Use when: (1) designing Spring Boot services, (2) writing clean, SOLID Java code, (3) optimizing JVM/GC performance, (4) building microservices with Spring Cloud, (5) writing comprehensive tests, (6) configuring Maven/Gradle builds, (7) implementing security with Spring Security, (8) troubleshooting concurrency or memory issues. NOT for: frontend UI, mobile apps, or non-JVM languages."
tags: [java, spring-boot, microservices, jvm, maven, gradle, junit, hibernate, spring-security, design-patterns]
author: "boxclaw"
references:
  - references/spring-boot-patterns.md
  - references/jvm-performance.md
  - references/testing-patterns.md
metadata:
  boxclaw:
    emoji: "☕"
    category: "programming-role"
---

# Senior Java Developer

Expert guidance for enterprise Java development with Spring Boot, microservices, JVM tuning, and production-grade patterns.

## Core Competencies

### 1. Spring Boot Application Architecture

Follow a clean layered architecture with clear separation of concerns:

```
src/main/java/com/example/app/
├── config/           # Spring configuration classes
├── controller/       # REST controllers (thin — delegate to service)
├── service/          # Business logic (interfaces + implementations)
├── repository/       # Data access layer (Spring Data JPA)
├── model/
│   ├── entity/       # JPA entities
│   ├── dto/          # Data Transfer Objects
│   └── mapper/       # Entity ↔ DTO mappers
├── exception/        # Custom exceptions + global handler
├── security/         # Security config, filters, providers
└── util/             # Shared utilities
```

**REST Controller pattern** — keep controllers thin:

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {

    private final OrderService orderService;

    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getOrder(
            @PathVariable @Positive Long id) {
        return ResponseEntity.ok(orderService.findById(id));
    }

    @PostMapping
    public ResponseEntity<OrderResponse> createOrder(
            @RequestBody @Valid CreateOrderRequest request) {
        OrderResponse created = orderService.create(request);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping
    public ResponseEntity<Page<OrderResponse>> listOrders(
            @ParameterObject Pageable pageable) {
        return ResponseEntity.ok(orderService.findAll(pageable));
    }
}
```

**Service layer** — business logic with transactional boundaries:

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderServiceImpl implements OrderService {

    private final OrderRepository orderRepository;
    private final OrderMapper orderMapper;
    private final EventPublisher eventPublisher;

    @Override
    public OrderResponse findById(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Order", id));
        return orderMapper.toResponse(order);
    }

    @Override
    @Transactional
    public OrderResponse create(CreateOrderRequest request) {
        Order order = orderMapper.toEntity(request);
        order.setStatus(OrderStatus.PENDING);
        order.setCreatedAt(Instant.now());

        Order saved = orderRepository.save(order);
        eventPublisher.publish(new OrderCreatedEvent(saved.getId()));

        return orderMapper.toResponse(saved);
    }
}
```

### 2. Exception Handling

Use a global exception handler with problem-detail responses (RFC 9457):

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource Not Found");
        problem.setProperty("resource", ex.getResource());
        problem.setProperty("id", ex.getId());
        return problem;
    }

    @ExceptionHandler(BusinessRuleException.class)
    public ProblemDetail handleBusinessRule(BusinessRuleException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.UNPROCESSABLE_ENTITY, ex.getMessage());
        problem.setTitle("Business Rule Violation");
        problem.setProperty("code", ex.getErrorCode());
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);
        return ProblemDetail.forStatusAndDetail(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "An unexpected error occurred");
    }
}
```

### 3. JPA / Hibernate Best Practices

**Entity design** — use proper equals/hashCode, avoid Lombok @Data on entities:

```java
@Entity
@Table(name = "orders", indexes = {
    @Index(name = "idx_order_customer", columnList = "customer_id"),
    @Index(name = "idx_order_status", columnList = "status")
})
@Getter @Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 50)
    @Enumerated(EnumType.STRING)
    private OrderStatus status;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "customer_id")
    private Customer customer;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL,
               orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();

    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @Column
    private Instant updatedAt;

    // Business method — entity encapsulates behavior
    public void addItem(OrderItem item) {
        items.add(item);
        item.setOrder(this);
    }

    public BigDecimal getTotal() {
        return items.stream()
                .map(OrderItem::getSubtotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    // Natural key equals/hashCode — NOT generated id
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Order other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
```

**Repository** — use projections and custom queries to avoid N+1:

```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    // Join fetch to avoid N+1
    @Query("SELECT o FROM Order o JOIN FETCH o.customer " +
           "JOIN FETCH o.items WHERE o.id = :id")
    Optional<Order> findByIdWithDetails(@Param("id") Long id);

    // Projection for list views — select only needed columns
    @Query("SELECT new com.example.dto.OrderSummary(o.id, o.status, " +
           "o.createdAt, c.name, SIZE(o.items)) " +
           "FROM Order o JOIN o.customer c " +
           "WHERE o.status = :status")
    Page<OrderSummary> findSummariesByStatus(
            @Param("status") OrderStatus status, Pageable pageable);

    // Specification-based dynamic queries
    Page<Order> findAll(Specification<Order> spec, Pageable pageable);

    // Bulk update — much faster than loading + saving
    @Modifying
    @Query("UPDATE Order o SET o.status = :status " +
           "WHERE o.status = :oldStatus AND o.createdAt < :before")
    int bulkUpdateStatus(@Param("status") OrderStatus status,
                         @Param("oldStatus") OrderStatus oldStatus,
                         @Param("before") Instant before);
}
```

### 4. Modern Java Features (17–21+)

Use modern language features for cleaner code:

```java
// Records for DTOs — immutable, concise
public record CreateOrderRequest(
        @NotNull Long customerId,
        @NotEmpty List<OrderItemRequest> items,
        @Size(max = 500) String notes
) {}

public record OrderResponse(
        Long id,
        OrderStatus status,
        String customerName,
        BigDecimal total,
        List<OrderItemResponse> items,
        Instant createdAt
) {}

// Sealed interfaces for type-safe domain modeling
public sealed interface PaymentResult
        permits PaymentResult.Success,
                PaymentResult.Declined,
                PaymentResult.Error {

    record Success(String transactionId, Instant processedAt)
            implements PaymentResult {}
    record Declined(String reason, String code)
            implements PaymentResult {}
    record Error(String message, Exception cause)
            implements PaymentResult {}
}

// Pattern matching + switch expressions
public String describePayment(PaymentResult result) {
    return switch (result) {
        case PaymentResult.Success s ->
                "Payment processed: " + s.transactionId();
        case PaymentResult.Declined d ->
                "Payment declined: " + d.reason();
        case PaymentResult.Error e ->
                "Payment error: " + e.message();
    };
}

// Virtual threads (Java 21+) for high-throughput I/O
@Bean
public TomcatProtocolHandlerCustomizer<?> virtualThreadCustomizer() {
    return handler -> handler.setExecutor(
            Executors.newVirtualThreadPerTaskExecutor());
}
```

### 5. Spring Security

Secure REST APIs with JWT and method-level authorization:

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(sm ->
                        sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/v1/auth/**").permitAll()
                        .requestMatchers("/actuator/health").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/products/**").permitAll()
                        .requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                        .anyRequest().authenticated())
                .addFilterBefore(jwtFilter,
                        UsernamePasswordAuthenticationFilter.class)
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint(new HttpStatusEntryPoint(
                                HttpStatus.UNAUTHORIZED)))
                .build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }
}
```

### 6. Concurrency & Async Processing

```java
// Async configuration with proper thread pool
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean("taskExecutor")
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(16);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.setRejectedExecutionHandler(
                new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}

// Async service methods with CompletableFuture
@Service
@RequiredArgsConstructor
public class ReportService {

    private final OrderRepository orderRepository;
    private final InventoryClient inventoryClient;

    @Async("taskExecutor")
    public CompletableFuture<Report> generateReport(ReportRequest request) {
        // Run independent queries in parallel
        CompletableFuture<List<OrderSummary>> ordersFuture =
                CompletableFuture.supplyAsync(
                        () -> orderRepository.findByDateRange(
                                request.from(), request.to()));

        CompletableFuture<InventorySnapshot> inventoryFuture =
                CompletableFuture.supplyAsync(
                        inventoryClient::getCurrentSnapshot);

        return ordersFuture.thenCombine(inventoryFuture,
                (orders, inventory) -> Report.builder()
                        .orders(orders)
                        .inventory(inventory)
                        .generatedAt(Instant.now())
                        .build());
    }
}
```

### 7. Configuration & Profiles

```yaml
# application.yml — base config
spring:
  application:
    name: order-service
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
  jpa:
    open-in-view: false
    properties:
      hibernate:
        default_batch_fetch_size: 20
        order_inserts: true
        order_updates: true
        jdbc.batch_size: 50

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized

---
# application-dev.yml
spring:
  config:
    activate:
      on-profile: dev
  datasource:
    url: jdbc:h2:mem:devdb
  jpa:
    show-sql: true
    hibernate:
      ddl-auto: create-drop

---
# application-prod.yml
spring:
  config:
    activate:
      on-profile: prod
  datasource:
    url: ${DATABASE_URL}
  jpa:
    hibernate:
      ddl-auto: validate
```

### 8. Observability

```java
// Custom metrics with Micrometer
@Component
@RequiredArgsConstructor
public class OrderMetrics {

    private final MeterRegistry registry;
    private final AtomicInteger activeOrders = new AtomicInteger();

    @PostConstruct
    void init() {
        Gauge.builder("orders.active", activeOrders, AtomicInteger::get)
                .description("Number of active orders")
                .tag("service", "order-service")
                .register(registry);
    }

    public void recordOrderCreated(OrderStatus status) {
        Counter.builder("orders.created")
                .tag("status", status.name())
                .register(registry)
                .increment();
        activeOrders.incrementAndGet();
    }

    public Timer.Sample startTimer() {
        return Timer.start(registry);
    }

    public void recordDuration(Timer.Sample sample, String operation) {
        sample.stop(Timer.builder("orders.operation.duration")
                .tag("operation", operation)
                .register(registry));
    }
}
```

## Quick Commands

```bash
# Maven — build, test, package
mvn clean verify
mvn spring-boot:run -Dspring-boot.run.profiles=dev
mvn clean package -DskipTests -Pprod
mvn dependency:tree | grep "conflict"

# Gradle equivalents
./gradlew clean build
./gradlew bootRun --args='--spring.profiles.active=dev'
./gradlew clean bootJar -x test

# Docker
docker build -t myapp:latest --build-arg PROFILE=prod .
docker run -p 8080:8080 -e SPRING_PROFILES_ACTIVE=prod myapp:latest

# JVM diagnostics
jcmd <pid> GC.heap_info
jcmd <pid> Thread.print
jmap -histo:live <pid> | head -30
jfr start name=profile duration=60s filename=profile.jfr

# Database migrations (Flyway)
mvn flyway:migrate -Dflyway.url=jdbc:postgresql://localhost/mydb
mvn flyway:info
mvn flyway:repair
```

## Design Principles

1. **SOLID everywhere** — single-responsibility services, dependency injection, program to interfaces
2. **Fail fast** — validate input at the boundary, throw specific exceptions early
3. **Immutable DTOs** — use Java records for all request/response objects
4. **Lazy loading by default** — `FetchType.LAZY` on all associations, explicit join fetch when needed
5. **No open-in-view** — `spring.jpa.open-in-view=false` to prevent accidental lazy loading in controllers
6. **Transactional boundaries** — `@Transactional(readOnly=true)` on class, `@Transactional` on write methods
7. **Batch operations** — use bulk updates/inserts for large datasets, never loop single saves
8. **Externalized config** — never hardcode URLs, credentials, or environment-specific values

## References

- **Spring Boot patterns**: See [references/spring-boot-patterns.md](references/spring-boot-patterns.md)
- **JVM performance**: See [references/jvm-performance.md](references/jvm-performance.md)
- **Testing patterns**: See [references/testing-patterns.md](references/testing-patterns.md)
