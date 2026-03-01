# Reactive Programming & Observability Reference

## Table of Contents

1. [Spring WebFlux Fundamentals](#spring-webflux-fundamentals)
2. [Project Reactor Patterns](#project-reactor-patterns)
3. [WebClient (Reactive HTTP)](#webclient-reactive-http)
4. [Reactive Data Access (R2DBC)](#reactive-data-access-r2dbc)
5. [Reactive Security](#reactive-security)
6. [Structured Logging](#structured-logging)
7. [Distributed Tracing (OpenTelemetry)](#distributed-tracing-opentelemetry)
8. [Micrometer Metrics Deep Dive](#micrometer-metrics-deep-dive)
9. [Health Checks & Actuator](#health-checks--actuator)
10. [Virtual Threads vs Reactive](#virtual-threads-vs-reactive)

---

## Spring WebFlux Fundamentals

### Annotated Controller (Similar to MVC)

```java
@RestController
@RequestMapping("/api/v1/products")
@RequiredArgsConstructor
public class ProductController {

    private final ProductService productService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<ProductResponse>> getProduct(
            @PathVariable Long id) {
        return productService.findById(id)
                .map(ResponseEntity::ok)
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping
    public Flux<ProductResponse> getAllProducts(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return productService.findAll(page, size);
    }

    @PostMapping
    public Mono<ResponseEntity<ProductResponse>> createProduct(
            @RequestBody @Valid Mono<CreateProductRequest> request) {
        return request
                .flatMap(productService::create)
                .map(p -> ResponseEntity
                        .created(URI.create("/api/v1/products/" + p.id()))
                        .body(p));
    }

    // Server-Sent Events for real-time streaming
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ProductResponse> streamProducts() {
        return productService.streamUpdates()
                .delayElements(Duration.ofMillis(100));
    }
}
```

### Functional Router (Alternative to annotated controllers)

```java
@Configuration
public class ProductRouter {

    @Bean
    public RouterFunction<ServerResponse> productRoutes(ProductHandler handler) {
        return RouterFunctions.route()
                .path("/api/v1/products", builder -> builder
                        .GET("/{id}", handler::getProduct)
                        .GET("", handler::listProducts)
                        .POST("", handler::createProduct)
                        .PUT("/{id}", handler::updateProduct)
                        .DELETE("/{id}", handler::deleteProduct))
                .build();
    }
}

@Component
@RequiredArgsConstructor
public class ProductHandler {

    private final ProductService productService;
    private final Validator validator;

    public Mono<ServerResponse> getProduct(ServerRequest request) {
        Long id = Long.valueOf(request.pathVariable("id"));
        return productService.findById(id)
                .flatMap(p -> ServerResponse.ok()
                        .contentType(MediaType.APPLICATION_JSON)
                        .bodyValue(p))
                .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createProduct(ServerRequest request) {
        return request.bodyToMono(CreateProductRequest.class)
                .doOnNext(this::validate)
                .flatMap(productService::create)
                .flatMap(p -> ServerResponse.created(
                        URI.create("/api/v1/products/" + p.id()))
                        .bodyValue(p));
    }

    private void validate(Object body) {
        var errors = new BeanPropertyBindingResult(body, body.getClass().getName());
        validator.validate(body, errors);
        if (errors.hasErrors()) {
            throw new ServerWebInputException(errors.toString());
        }
    }
}
```

### Reactive Error Handling

```java
@ControllerAdvice
public class ReactiveExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public Mono<ResponseEntity<ProblemDetail>> handleNotFound(
            ResourceNotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.NOT_FOUND, ex.getMessage());
        return Mono.just(ResponseEntity.status(HttpStatus.NOT_FOUND).body(problem));
    }

    @ExceptionHandler(WebExchangeBindException.class)
    public Mono<ResponseEntity<ProblemDetail>> handleValidation(
            WebExchangeBindException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.BAD_REQUEST, "Validation failed");
        Map<String, String> errors = ex.getFieldErrors().stream()
                .collect(Collectors.toMap(
                        FieldError::getField,
                        e -> e.getDefaultMessage() != null ? e.getDefaultMessage() : "invalid"));
        problem.setProperty("errors", errors);
        return Mono.just(ResponseEntity.badRequest().body(problem));
    }
}
```

---

## Project Reactor Patterns

### Core Operators

```java
// Transform & filter
Flux<OrderResponse> orders = orderFlux
        .filter(o -> o.getStatus() == OrderStatus.PENDING)
        .map(orderMapper::toResponse)
        .take(100);                        // Limit to 100

// FlatMap — async per-element transformation (concurrent)
Flux<OrderDetail> details = orderFlux
        .flatMap(order -> enrichOrder(order), 10);  // Concurrency: 10

// ConcatMap — sequential (preserves order, one at a time)
Flux<OrderDetail> sequential = orderFlux
        .concatMap(this::enrichOrder);

// Zip — combine multiple sources
Mono<FullProfile> profile = Mono.zip(
        userService.findById(userId),
        orderService.findByUser(userId).collectList(),
        loyaltyService.getPoints(userId)
).map(tuple -> new FullProfile(tuple.getT1(), tuple.getT2(), tuple.getT3()));

// Retry with backoff
Mono<Response> resilient = externalClient.call()
        .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                .maxBackoff(Duration.ofSeconds(10))
                .filter(e -> e instanceof IOException)
                .doBeforeRetry(signal ->
                        log.warn("Retrying: attempt {}", signal.totalRetries())));

// Timeout with fallback
Mono<Product> withFallback = productService.findById(id)
        .timeout(Duration.ofSeconds(5))
        .onErrorResume(TimeoutException.class,
                e -> cachedProductService.findById(id));
```

### Backpressure Handling

```java
// Buffer — collect elements into batches
Flux<List<Order>> batched = orderFlux
        .buffer(100);                      // Batch of 100 items

// Window — split into sub-flux windows
Flux<Flux<Order>> windowed = orderFlux
        .windowTimeout(50, Duration.ofSeconds(5));  // 50 items or 5s

// Rate limiting
Flux<Order> rateLimited = orderFlux
        .limitRate(10);                    // Request 10 at a time

// onBackpressureDrop — discard if subscriber can't keep up
Flux<SensorData> realtime = sensorFlux
        .onBackpressureDrop(dropped ->
                log.debug("Dropped: {}", dropped.getId()));

// onBackpressureBuffer — buffer with overflow strategy
Flux<SensorData> buffered = sensorFlux
        .onBackpressureBuffer(1000,
                dropped -> log.warn("Buffer overflow"),
                BufferOverflowStrategy.DROP_OLDEST);
```

### Schedulers

```java
// publishOn — switch downstream execution to another scheduler
Flux<byte[]> images = urlFlux
        .publishOn(Schedulers.boundedElastic())    // I/O work downstream
        .map(url -> downloadImage(url));

// subscribeOn — affect the entire chain from source
Mono<String> result = Mono.fromCallable(() -> blockingCall())
        .subscribeOn(Schedulers.boundedElastic()); // Run source on elastic

// Schedulers reference:
// Schedulers.parallel()       — CPU-bound (cores count threads)
// Schedulers.boundedElastic() — I/O-bound (dynamic, bounded pool)
// Schedulers.single()         — Single-thread (sequential tasks)
// Schedulers.immediate()      — Current thread (no scheduling)
```

### Testing Reactive Code

```java
@Test
void findById_returnsProduct() {
    when(repository.findById(1L)).thenReturn(Mono.just(product));

    StepVerifier.create(productService.findById(1L))
            .assertNext(response -> {
                assertThat(response.id()).isEqualTo(1L);
                assertThat(response.name()).isEqualTo("Widget");
            })
            .verifyComplete();
}

@Test
void streamProducts_emitsInOrder() {
    when(repository.findAll()).thenReturn(Flux.just(product1, product2));

    StepVerifier.create(productService.findAll())
            .expectNextCount(2)
            .verifyComplete();
}

@Test
void externalCall_retriesOnFailure() {
    when(client.call())
            .thenReturn(Mono.error(new IOException("timeout")))
            .thenReturn(Mono.error(new IOException("timeout")))
            .thenReturn(Mono.just(response));

    StepVerifier.create(service.callWithRetry())
            .assertNext(r -> assertThat(r.status()).isEqualTo("OK"))
            .verifyComplete();
}

// Virtual time for testing delays
@Test
void delayedProcessing() {
    StepVerifier.withVirtualTime(() ->
                    orderFlux.delayElements(Duration.ofSeconds(10)))
            .thenAwait(Duration.ofSeconds(30))
            .expectNextCount(3)
            .verifyComplete();
}
```

---

## WebClient (Reactive HTTP)

### Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient inventoryClient(
            @Value("${services.inventory.url}") String baseUrl) {
        return WebClient.builder()
                .baseUrl(baseUrl)
                .defaultHeader(HttpHeaders.CONTENT_TYPE,
                        MediaType.APPLICATION_JSON_VALUE)
                .filter(logRequest())
                .filter(logResponse())
                .codecs(config -> config.defaultCodecs()
                        .maxInMemorySize(10 * 1024 * 1024))  // 10MB
                .build();
    }

    // Connection pool tuning
    @Bean
    public WebClient highPerformanceClient(String baseUrl) {
        HttpClient httpClient = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
                .responseTimeout(Duration.ofSeconds(10))
                .doOnConnected(conn -> conn
                        .addHandlerLast(new ReadTimeoutHandler(10))
                        .addHandlerLast(new WriteTimeoutHandler(10)));

        return WebClient.builder()
                .baseUrl(baseUrl)
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
    }

    private ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(request -> {
            log.debug("Request: {} {}", request.method(), request.url());
            return Mono.just(request);
        });
    }

    private ExchangeFilterFunction logResponse() {
        return ExchangeFilterFunction.ofResponseProcessor(response -> {
            log.debug("Response: {}", response.statusCode());
            return Mono.just(response);
        });
    }
}
```

### Usage Patterns

```java
// GET with error handling
public Mono<ProductResponse> getProduct(Long id) {
    return inventoryClient.get()
            .uri("/products/{id}", id)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, response ->
                    response.bodyToMono(ProblemDetail.class)
                            .flatMap(body -> Mono.error(
                                    new ResourceNotFoundException("Product", id))))
            .onStatus(HttpStatusCode::is5xxServerError, response ->
                    Mono.error(new ServiceUnavailableException("Inventory")))
            .bodyToMono(ProductResponse.class);
}

// POST with body
public Mono<ReservationResponse> reserve(ReserveRequest request) {
    return inventoryClient.post()
            .uri("/reservations")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(ReservationResponse.class);
}

// Streaming response
public Flux<ProductUpdate> streamUpdates() {
    return inventoryClient.get()
            .uri("/products/stream")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .retrieve()
            .bodyToFlux(ProductUpdate.class);
}

// Exchange for full response access
public Mono<ProductResponse> getWithHeaders(Long id) {
    return inventoryClient.get()
            .uri("/products/{id}", id)
            .exchangeToMono(response -> {
                if (response.statusCode().is2xxSuccessful()) {
                    String etag = response.headers().asHttpHeaders()
                            .getETag();
                    return response.bodyToMono(ProductResponse.class)
                            .map(p -> p.withEtag(etag));
                }
                return response.createError();
            });
}
```

---

## Reactive Data Access (R2DBC)

### Configuration

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: ${DB_USER:postgres}
    password: ${DB_PASSWORD:postgres}
    pool:
      initial-size: 5
      max-size: 20
      max-idle-time: 30m
```

### Repository

```java
public interface ProductRepository extends ReactiveCrudRepository<Product, Long> {

    Flux<Product> findByCategory(String category);

    @Query("SELECT * FROM products WHERE price BETWEEN :min AND :max ORDER BY price")
    Flux<Product> findByPriceRange(@Param("min") BigDecimal min,
                                    @Param("max") BigDecimal max);

    @Query("SELECT * FROM products WHERE name ILIKE :query OR description ILIKE :query")
    Flux<Product> search(@Param("query") String query);

    @Modifying
    @Query("UPDATE products SET stock = stock - :qty WHERE id = :id AND stock >= :qty")
    Mono<Integer> decrementStock(@Param("id") Long id, @Param("qty") int qty);
}

// R2DBC entity
@Table("products")
@Getter @Setter
public class Product {

    @Id
    private Long id;

    @Column("name")
    private String name;

    @Column("price")
    private BigDecimal price;

    @Column("stock")
    private int stock;

    @CreatedDate
    private Instant createdAt;
}
```

### DatabaseClient for complex queries

```java
@Repository
@RequiredArgsConstructor
public class CustomProductRepository {

    private final DatabaseClient databaseClient;

    public Flux<ProductSummary> searchWithFilters(ProductFilter filter) {
        var sql = new StringBuilder("SELECT p.id, p.name, p.price, c.name as category ");
        sql.append("FROM products p JOIN categories c ON p.category_id = c.id WHERE 1=1 ");

        Map<String, Object> params = new HashMap<>();
        if (filter.category() != null) {
            sql.append("AND c.name = :category ");
            params.put("category", filter.category());
        }
        if (filter.minPrice() != null) {
            sql.append("AND p.price >= :minPrice ");
            params.put("minPrice", filter.minPrice());
        }
        sql.append("ORDER BY p.created_at DESC LIMIT :limit");
        params.put("limit", filter.limit());

        var spec = databaseClient.sql(sql.toString());
        params.forEach(spec::bind);

        return spec.map((row, meta) -> new ProductSummary(
                        row.get("id", Long.class),
                        row.get("name", String.class),
                        row.get("price", BigDecimal.class),
                        row.get("category", String.class)))
                .all();
    }
}
```

---

## Reactive Security

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
public class ReactiveSecurityConfig {

    @Bean
    public SecurityWebFilterChain filterChain(ServerHttpSecurity http) {
        return http
                .csrf(ServerHttpSecurity.CsrfSpec::disable)
                .authorizeExchange(auth -> auth
                        .pathMatchers("/api/v1/auth/**").permitAll()
                        .pathMatchers("/actuator/health/**").permitAll()
                        .pathMatchers(HttpMethod.GET, "/api/v1/products/**").permitAll()
                        .pathMatchers("/api/v1/admin/**").hasRole("ADMIN")
                        .anyExchange().authenticated())
                .addFilterAt(jwtAuthenticationFilter(),
                        SecurityWebFiltersOrder.AUTHENTICATION)
                .build();
    }

    @Bean
    public ReactiveAuthenticationManager authenticationManager(
            ReactiveUserDetailsService userDetailsService) {
        var manager = new UserDetailsRepositoryReactiveAuthenticationManager(
                userDetailsService);
        manager.setPasswordEncoder(new BCryptPasswordEncoder(12));
        return manager;
    }
}
```

---

## Structured Logging

### Logback JSON Configuration

```xml
<!-- logback-spring.xml -->
<configuration>
    <!-- Production: JSON for ELK/Datadog/Splunk -->
    <springProfile name="prod,staging">
        <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <fieldNames>
                    <timestamp>@timestamp</timestamp>
                    <version>[ignore]</version>
                    <levelValue>[ignore]</levelValue>
                </fieldNames>
                <customFields>{"service":"order-service","env":"${ENVIRONMENT:-unknown}"}</customFields>
                <includeMdcKeyName>traceId</includeMdcKeyName>
                <includeMdcKeyName>spanId</includeMdcKeyName>
                <includeMdcKeyName>userId</includeMdcKeyName>
                <includeMdcKeyName>orderId</includeMdcKeyName>
                <throwableConverter class="net.logstash.logback.stacktrace.ShortenedThrowableConverter">
                    <maxDepthPerThrowable>30</maxDepthPerThrowable>
                    <maxLength>4096</maxLength>
                    <rootCauseFirst>true</rootCauseFirst>
                </throwableConverter>
            </encoder>
        </appender>
        <root level="INFO"><appender-ref ref="JSON"/></root>
    </springProfile>

    <!-- Development: human-readable -->
    <springProfile name="dev,local">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} %highlight(%-5level) [%15.15thread] %cyan(%-40.40logger{39}) : %msg%n</pattern>
            </encoder>
        </appender>
        <logger name="org.hibernate.SQL" level="DEBUG"/>
        <logger name="org.hibernate.type.descriptor.sql.BasicBinder" level="TRACE"/>
        <root level="DEBUG"><appender-ref ref="CONSOLE"/></root>
    </springProfile>
</configuration>
```

### MDC Patterns

```java
// MDC filter for web requests
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class MdcFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
            HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            MDC.put("requestId", UUID.randomUUID().toString().substring(0, 8));
            MDC.put("method", request.getMethod());
            MDC.put("path", request.getRequestURI());

            // Extract user from JWT if present
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth != null && auth.isAuthenticated()) {
                MDC.put("userId", auth.getName());
            }

            chain.doFilter(request, response);
        } finally {
            MDC.clear();
        }
    }
}

// Logging best practices
@Slf4j
@Service
public class PaymentService {

    public PaymentResult processPayment(PaymentRequest request) {
        MDC.put("orderId", request.orderId().toString());
        MDC.put("amount", request.amount().toString());

        log.info("Payment processing started");
        Instant start = Instant.now();

        try {
            PaymentResult result = gateway.charge(request);
            long durationMs = Duration.between(start, Instant.now()).toMillis();
            log.info("Payment completed in {}ms, txnId={}",
                    durationMs, result.transactionId());
            return result;

        } catch (PaymentDeclinedException e) {
            log.warn("Payment declined: code={}, reason={}",
                    e.getCode(), e.getReason());
            throw e;

        } catch (Exception e) {
            log.error("Payment failed unexpectedly", e);
            throw new PaymentException("Payment processing failed", e);
        }
    }
}
```

---

## Distributed Tracing (OpenTelemetry)

### Spring Boot 3 + Micrometer Tracing Setup

```xml
<!-- pom.xml dependencies -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

```yaml
# application.yml
management:
  tracing:
    sampling:
      probability: ${TRACE_SAMPLING:0.1}  # 10% in prod
  otlp:
    tracing:
      endpoint: ${OTEL_ENDPOINT:http://localhost:4318/v1/traces}
    metrics:
      export:
        enabled: true
        endpoint: ${OTEL_ENDPOINT:http://localhost:4318/v1/metrics}
```

### Custom Spans

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final ObservationRegistry observationRegistry;

    public OrderResponse processOrder(CreateOrderRequest request) {
        return Observation.createNotStarted("order.process", observationRegistry)
                .lowCardinalityKeyValue("order.type", request.type().name())
                .observe(() -> {
                    // Automatic span creation
                    Order order = createOrder(request);
                    enrichOrder(order);
                    return toResponse(order);
                });
    }

    // Or with @Observed annotation
    @Observed(name = "order.enrich",
              contextualName = "enrich-order",
              lowCardinalityKeyValues = {"source", "internal"})
    private void enrichOrder(Order order) {
        // Automatically traced
    }
}
```

### Propagation Across Services

```java
// WebClient auto-propagates trace context
@Bean
public WebClient tracedWebClient(ObservationRegistry registry) {
    return WebClient.builder()
            .baseUrl("http://inventory-service")
            .observationRegistry(registry)  // Auto-injects traceId headers
            .build();
}

// Kafka: trace context propagation
@Bean
public ProducerFactory<String, OrderEvent> producerFactory(
        ObservationRegistry registry) {
    var factory = new DefaultKafkaProducerFactory<String, OrderEvent>(configs);
    factory.setObservationEnabled(true);  // Propagate trace in Kafka headers
    return factory;
}
```

### Docker Compose for Local Observability Stack

```yaml
services:
  # Jaeger — distributed tracing UI
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"   # Jaeger UI
      - "4318:4318"     # OTLP HTTP

  # Prometheus — metrics
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  # Grafana — dashboards
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

---

## Micrometer Metrics Deep Dive

### Custom Business Metrics

```java
@Component
@RequiredArgsConstructor
public class BusinessMetrics {

    private final MeterRegistry registry;

    // Counter — track events
    public void recordOrderPlaced(String region, String paymentMethod) {
        Counter.builder("business.orders.placed")
                .tag("region", region)
                .tag("payment", paymentMethod)
                .register(registry)
                .increment();
    }

    // Timer — track duration
    public <T> T timeOperation(String name, Supplier<T> operation) {
        return Timer.builder("business.operation.duration")
                .tag("operation", name)
                .register(registry)
                .record(operation);
    }

    // Distribution summary — track value distributions
    public void recordOrderValue(double amount) {
        DistributionSummary.builder("business.order.value")
                .baseUnit("usd")
                .publishPercentiles(0.5, 0.95, 0.99)
                .publishPercentileHistogram()
                .register(registry)
                .record(amount);
    }

    // Gauge — track current state
    @PostConstruct
    void registerGauges() {
        Gauge.builder("business.orders.pending", orderRepository,
                repo -> repo.countByStatus(OrderStatus.PENDING))
                .register(registry);
    }
}
```

### Prometheus Endpoint Configuration

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${ENVIRONMENT:dev}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 50ms,100ms,200ms,500ms,1s
```

---

## Health Checks & Actuator

### Custom Health Indicators

```java
@Component
public class ExternalServiceHealthIndicator
        extends AbstractHealthIndicator {

    private final WebClient healthClient;

    @Override
    protected void doHealthCheck(Health.Builder builder) {
        try {
            String status = healthClient.get()
                    .uri("/health")
                    .retrieve()
                    .bodyToMono(String.class)
                    .block(Duration.ofSeconds(3));

            builder.up()
                    .withDetail("service", "external-api")
                    .withDetail("status", status);
        } catch (Exception e) {
            builder.down(e)
                    .withDetail("service", "external-api");
        }
    }
}

// Readiness group — only ready when all dependencies are up
// application.yml
management:
  endpoint:
    health:
      group:
        readiness:
          include: db,redis,externalService
          show-details: always
        liveness:
          include: ping,diskSpace
```

### Kubernetes Probes

```yaml
# Deployment spec
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 5
  failureThreshold: 3

startupProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 30  # 10 + 30*5 = 160s max startup time
```

---

## Virtual Threads vs Reactive

### Decision Matrix

| Factor | Virtual Threads (MVC) | Reactive (WebFlux) |
|--------|----------------------|-------------------|
| Learning curve | Low (familiar MVC) | High (Reactor operators) |
| Debugging | Easy (stack traces) | Hard (async chains) |
| JDBC/JPA support | Full support | Needs R2DBC |
| Throughput | High (I/O bound) | Highest (non-blocking) |
| Backpressure | Manual | Built-in |
| Streaming | Limited | Excellent (SSE, WebSocket) |
| Java version | 21+ required | 17+ |
| Ecosystem | Mature (Spring MVC) | Growing (WebFlux) |

### When to Use What

```
MVC + Virtual Threads:
  ✓ Standard CRUD APIs
  ✓ Existing MVC codebase
  ✓ JDBC/JPA data access
  ✓ Complex business logic
  ✓ Team familiar with blocking code

WebFlux (Reactive):
  ✓ API gateways / aggregators
  ✓ Real-time streaming (SSE, WebSocket)
  ✓ Very high concurrency (10K+ connections)
  ✓ Backpressure-critical pipelines
  ✓ Non-blocking data access (R2DBC, MongoDB Reactive)
```

### Virtual Threads with Spring Boot 3.2+

```yaml
# application.yml — enables virtual threads for Tomcat
spring:
  threads:
    virtual:
      enabled: true  # All @Async and web requests use virtual threads
```

```java
// That's it! All request handling uses virtual threads automatically.
// No code changes needed. JDBC/JPA works normally.
// Virtual threads handle blocking I/O efficiently.
```
