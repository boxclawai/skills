# Advanced Java Patterns Reference

## Table of Contents

1. [Spring Batch Processing](#spring-batch-processing)
2. [gRPC with Spring Boot](#grpc-with-spring-boot)
3. [MapStruct Advanced Mapping](#mapstruct-advanced-mapping)
4. [Spring Modulith](#spring-modulith)
5. [Contract Testing](#contract-testing)
6. [Feature Flags](#feature-flags)
7. [Gradle Build Patterns](#gradle-build-patterns)
8. [Multi-Module Project Setup](#multi-module-project-setup)
9. [Structured Concurrency (Java 21+)](#structured-concurrency-java-21)
10. [Mutation Testing (PIT)](#mutation-testing-pit)

---

## Spring Batch Processing

### Job Configuration

```java
@Configuration
@RequiredArgsConstructor
public class OrderExportJobConfig {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager transactionManager;
    private final DataSource dataSource;

    @Bean
    public Job orderExportJob(Step exportStep, Step cleanupStep) {
        return new JobBuilder("orderExportJob", jobRepository)
                .incrementer(new RunIdIncrementer())
                .validator(new DefaultJobParametersValidator(
                        new String[]{"outputFile"},  // Required
                        new String[]{"startDate"}))  // Optional
                .start(exportStep)
                .next(cleanupStep)
                .listener(new JobCompletionListener())
                .build();
    }

    @Bean
    public Step exportStep(ItemReader<Order> reader,
                           ItemProcessor<Order, OrderExportDto> processor,
                           ItemWriter<OrderExportDto> writer) {
        return new StepBuilder("exportStep", jobRepository)
                .<Order, OrderExportDto>chunk(500, transactionManager)
                .reader(reader)
                .processor(processor)
                .writer(writer)
                .faultTolerant()
                .retryLimit(3)
                .retry(TransientDataAccessException.class)
                .skipLimit(100)
                .skip(InvalidOrderException.class)
                .listener(new StepExecutionListener() {
                    @Override
                    public ExitStatus afterStep(StepExecution stepExecution) {
                        log.info("Exported {} orders, skipped {}",
                                stepExecution.getWriteCount(),
                                stepExecution.getSkipCount());
                        return stepExecution.getExitStatus();
                    }
                })
                .build();
    }

    @Bean
    @StepScope
    public JdbcPagingItemReader<Order> orderReader(
            @Value("#{jobParameters['startDate']}") String startDate) {
        return new JdbcPagingItemReaderBuilder<Order>()
                .name("orderReader")
                .dataSource(dataSource)
                .selectClause("SELECT id, customer_id, status, total, created_at")
                .fromClause("FROM orders")
                .whereClause("WHERE created_at >= :startDate")
                .sortKeys(Map.of("id", Order.ASCENDING))
                .parameterValues(Map.of("startDate", startDate))
                .pageSize(500)
                .rowMapper(new BeanPropertyRowMapper<>(Order.class))
                .build();
    }

    @Bean
    public ItemProcessor<Order, OrderExportDto> orderProcessor() {
        return order -> {
            if (order.getStatus() == OrderStatus.CANCELLED) return null; // Skip
            return new OrderExportDto(order);
        };
    }

    @Bean
    @StepScope
    public FlatFileItemWriter<OrderExportDto> csvWriter(
            @Value("#{jobParameters['outputFile']}") String outputFile) {
        return new FlatFileItemWriterBuilder<OrderExportDto>()
                .name("csvWriter")
                .resource(new FileSystemResource(outputFile))
                .delimited()
                .delimiter(",")
                .names("id", "customerName", "total", "status", "createdAt")
                .headerCallback(writer -> writer.write("ID,Customer,Total,Status,Date"))
                .build();
    }
}
```

### Scheduling Batch Jobs

```java
@Configuration
@EnableScheduling
public class BatchScheduleConfig {

    private final JobLauncher jobLauncher;
    private final Job orderExportJob;

    @Scheduled(cron = "0 0 2 * * *")  // Daily at 2 AM
    public void runExport() {
        JobParameters params = new JobParametersBuilder()
                .addString("outputFile", "/exports/orders-" +
                        LocalDate.now() + ".csv")
                .addString("startDate",
                        LocalDate.now().minusDays(1).toString())
                .addLong("runId", System.currentTimeMillis())
                .toJobParameters();

        try {
            JobExecution execution = jobLauncher.run(orderExportJob, params);
            log.info("Batch job completed: {}", execution.getStatus());
        } catch (Exception e) {
            log.error("Batch job failed", e);
        }
    }
}
```

---

## gRPC with Spring Boot

### Proto Definition

```protobuf
// src/main/proto/order_service.proto
syntax = "proto3";

package com.example.order;

option java_multiple_files = true;
option java_package = "com.example.order.grpc";

service OrderService {
    rpc GetOrder (GetOrderRequest) returns (OrderResponse);
    rpc CreateOrder (CreateOrderRequest) returns (OrderResponse);
    rpc StreamOrders (StreamOrdersRequest) returns (stream OrderResponse);
}

message GetOrderRequest {
    int64 id = 1;
}

message CreateOrderRequest {
    int64 customer_id = 1;
    repeated OrderItem items = 2;
    string notes = 3;
}

message OrderItem {
    int64 product_id = 1;
    int32 quantity = 2;
}

message OrderResponse {
    int64 id = 1;
    string status = 2;
    string customer_name = 3;
    double total = 4;
    string created_at = 5;
}

message StreamOrdersRequest {
    string status = 1;
}
```

### gRPC Server Implementation

```java
@GrpcService
@RequiredArgsConstructor
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    private final OrderService orderService;
    private final OrderGrpcMapper mapper;

    @Override
    public void getOrder(GetOrderRequest request,
                         StreamObserver<OrderResponse> responseObserver) {
        try {
            var order = orderService.findById(request.getId());
            responseObserver.onNext(mapper.toGrpcResponse(order));
            responseObserver.onCompleted();
        } catch (ResourceNotFoundException e) {
            responseObserver.onError(Status.NOT_FOUND
                    .withDescription(e.getMessage())
                    .asRuntimeException());
        }
    }

    @Override
    public void createOrder(CreateOrderRequest request,
                            StreamObserver<OrderResponse> responseObserver) {
        try {
            var createReq = mapper.fromGrpcRequest(request);
            var order = orderService.create(createReq);
            responseObserver.onNext(mapper.toGrpcResponse(order));
            responseObserver.onCompleted();
        } catch (Exception e) {
            responseObserver.onError(Status.INTERNAL
                    .withDescription(e.getMessage())
                    .asRuntimeException());
        }
    }

    @Override
    public void streamOrders(StreamOrdersRequest request,
                             StreamObserver<OrderResponse> responseObserver) {
        orderService.findByStatus(request.getStatus())
                .forEach(order -> responseObserver.onNext(
                        mapper.toGrpcResponse(order)));
        responseObserver.onCompleted();
    }
}
```

### gRPC Client

```java
@Configuration
public class GrpcClientConfig {

    @Bean
    public ManagedChannel orderChannel(
            @Value("${grpc.order-service.host}") String host,
            @Value("${grpc.order-service.port}") int port) {
        return ManagedChannelBuilder.forAddress(host, port)
                .usePlaintext()
                .build();
    }

    @Bean
    public OrderServiceGrpc.OrderServiceBlockingStub orderStub(
            ManagedChannel orderChannel) {
        return OrderServiceGrpc.newBlockingStub(orderChannel);
    }
}

@Service
@RequiredArgsConstructor
public class OrderGrpcClient {

    private final OrderServiceGrpc.OrderServiceBlockingStub stub;

    public OrderResponse getOrder(long id) {
        return stub.withDeadlineAfter(5, TimeUnit.SECONDS)
                .getOrder(GetOrderRequest.newBuilder().setId(id).build());
    }
}
```

---

## MapStruct Advanced Mapping

### Setup (Maven)

```xml
<dependency>
    <groupId>org.mapstruct</groupId>
    <artifactId>mapstruct</artifactId>
    <version>1.5.5.Final</version>
</dependency>
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <annotationProcessorPaths>
            <path>
                <groupId>org.mapstruct</groupId>
                <artifactId>mapstruct-processor</artifactId>
                <version>1.5.5.Final</version>
            </path>
            <!-- If using Lombok, add lombok-mapstruct-binding -->
            <path>
                <groupId>org.projectlombok</groupId>
                <artifactId>lombok-mapstruct-binding</artifactId>
                <version>0.2.0</version>
            </path>
        </annotationProcessorPaths>
    </configuration>
</plugin>
```

### Advanced Mapper Patterns

```java
@Mapper(componentModel = "spring",
        unmappedTargetPolicy = ReportingPolicy.ERROR,
        nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE,
        uses = {DateMapper.class, MoneyMapper.class})  // Reuse other mappers
public interface OrderMapper {

    // Basic mapping with field name differences
    @Mapping(target = "customerName", source = "customer.name")
    @Mapping(target = "customerEmail", source = "customer.email")
    @Mapping(target = "totalAmount", source = "total")
    @Mapping(target = "itemCount", expression = "java(order.getItems().size())")
    OrderResponse toResponse(Order order);

    // Collection mapping (auto-maps each element)
    List<OrderResponse> toResponseList(List<Order> orders);

    // Ignore generated fields
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    @Mapping(target = "version", ignore = true)
    @Mapping(target = "status", constant = "PENDING")
    Order toEntity(CreateOrderRequest request);

    // Partial update (null values ignored)
    @BeanMapping(nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE)
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    void updateEntity(UpdateOrderRequest request, @MappingTarget Order order);

    // Mapping with context
    @Mapping(target = "displayPrice", source = "price",
             qualifiedByName = "formatPrice")
    ProductResponse toResponse(Product product, @Context Locale locale);

    @Named("formatPrice")
    default String formatPrice(BigDecimal price, @Context Locale locale) {
        return NumberFormat.getCurrencyInstance(locale).format(price);
    }

    // After-mapping hook
    @AfterMapping
    default void enrichResponse(@MappingTarget OrderResponse.Builder builder,
                                 Order order) {
        builder.canCancel(order.getStatus() == OrderStatus.PENDING);
        builder.daysOld(ChronoUnit.DAYS.between(
                order.getCreatedAt(), Instant.now()));
    }
}

// Reusable sub-mapper
@Mapper(componentModel = "spring")
public interface DateMapper {
    default String instantToString(Instant instant) {
        return instant != null ? instant.toString() : null;
    }
    default Instant stringToInstant(String value) {
        return value != null ? Instant.parse(value) : null;
    }
}
```

---

## Spring Modulith

### Module Structure

```
com.example.ecommerce/
├── order/                         # Order module
│   ├── Order.java                 # Public API (aggregate root)
│   ├── OrderService.java          # Public API
│   ├── OrderCreatedEvent.java     # Public event
│   └── internal/                  # Package-private internals
│       ├── OrderRepository.java
│       ├── OrderMapper.java
│       └── OrderValidator.java
├── inventory/                     # Inventory module
│   ├── InventoryService.java      # Public API
│   ├── StockReservedEvent.java    # Public event
│   └── internal/
│       └── InventoryRepository.java
├── notification/                  # Notification module
│   ├── NotificationService.java
│   └── internal/
│       └── EmailSender.java
└── shared/                        # Shared kernel
    ├── Money.java
    └── Address.java
```

### Configuration

```java
@SpringBootApplication
@Modulith   // Enable Spring Modulith
public class EcommerceApplication { }
```

### Event-Based Module Communication

```java
// Order module publishes event
@Service
@RequiredArgsConstructor
public class OrderService {

    private final ApplicationEventPublisher events;

    @Transactional
    public Order createOrder(CreateOrderRequest request) {
        Order order = // ... create and save
        events.publishEvent(new OrderCreatedEvent(
                order.getId(), order.getCustomerEmail(), order.getTotal()));
        return order;
    }
}

// Inventory module listens (async, after commit)
@Component
@RequiredArgsConstructor
public class InventoryEventListener {

    @ApplicationModuleListener  // Spring Modulith annotation
    public void onOrderCreated(OrderCreatedEvent event) {
        // Reserve stock — runs in separate transaction
        inventoryService.reserveStock(event.orderId());
    }
}

// Notification module also listens
@Component
public class NotificationEventListener {

    @ApplicationModuleListener
    public void onOrderCreated(OrderCreatedEvent event) {
        emailService.sendOrderConfirmation(event.customerEmail());
    }
}
```

### Module Verification Tests

```java
class ModularityTests {

    ApplicationModules modules = ApplicationModules.of(EcommerceApplication.class);

    @Test
    void verifyModuleStructure() {
        modules.verify();  // Checks no illegal cross-module dependencies
    }

    @Test
    void documentModules() {
        new Documenter(modules)
                .writeModulesAsPlantUml()      // UML diagram
                .writeIndividualModulesAsPlantUml();
    }
}
```

---

## Contract Testing

### Spring Cloud Contract (Provider Side)

```groovy
// src/test/resources/contracts/shouldReturnOrder.groovy
Contract.make {
    description "should return order by ID"
    request {
        method GET()
        url "/api/v1/orders/1"
        headers {
            accept applicationJson()
        }
    }
    response {
        status 200
        headers {
            contentType applicationJson()
        }
        body([
            id: 1,
            status: "PENDING",
            customerName: $(anyNonBlankString()),
            total: $(anyDouble()),
            createdAt: $(anyNonBlankString())
        ])
    }
}
```

```java
// Base test class for contract verification
@SpringBootTest(webEnvironment = WebEnvironment.MOCK)
@AutoConfigureMockMvc
public abstract class ContractVerifierBase {

    @Autowired MockMvc mockMvc;
    @MockBean OrderService orderService;

    @BeforeEach
    void setup() {
        when(orderService.findById(1L)).thenReturn(
                new OrderResponse(1L, OrderStatus.PENDING, "John",
                        BigDecimal.TEN, List.of(), Instant.now()));
        RestAssuredMockMvc.mockMvc(mockMvc);
    }
}
```

### Pact (Consumer Side)

```java
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "order-service")
class OrderClientPactTest {

    @Pact(consumer = "inventory-service")
    public V4Pact getOrderPact(PactDslWithProvider builder) {
        return builder
                .given("order 1 exists")
                .uponReceiving("get order by id")
                .path("/api/v1/orders/1")
                .method("GET")
                .willRespondWith()
                .status(200)
                .body(new PactDslJsonBody()
                        .integerType("id", 1)
                        .stringType("status", "PENDING")
                        .decimalType("total", 100.0))
                .toPact(V4Pact.class);
    }

    @Test
    @PactTestFor(pactMethod = "getOrderPact")
    void getOrder_returnsExpectedFields(MockServer mockServer) {
        var client = new OrderClient(mockServer.getUrl());
        var order = client.getOrder(1L);

        assertThat(order.id()).isEqualTo(1L);
        assertThat(order.status()).isEqualTo("PENDING");
    }
}
```

---

## Feature Flags

### Custom Feature Flag Implementation

```java
@ConfigurationProperties(prefix = "features")
public record FeatureFlags(
        boolean newCheckoutFlow,
        boolean asyncNotifications,
        boolean experimentalSearch,
        int maxBatchSize
) {}

@Service
@RequiredArgsConstructor
public class OrderService {

    private final FeatureFlags features;

    public OrderResponse create(CreateOrderRequest request) {
        if (features.newCheckoutFlow()) {
            return createWithNewFlow(request);
        }
        return createWithLegacyFlow(request);
    }
}
```

```yaml
features:
  new-checkout-flow: ${FEATURE_NEW_CHECKOUT:false}
  async-notifications: ${FEATURE_ASYNC_NOTIFY:true}
  experimental-search: false
  max-batch-size: ${FEATURE_BATCH_SIZE:100}
```

### FF4j Integration

```java
@Configuration
public class FeatureFlagConfig {

    @Bean
    public FF4j ff4j() {
        FF4j ff4j = new FF4j();
        ff4j.createFeature(new Feature("new-checkout-flow", false,
                "New checkout experience"));
        ff4j.createFeature(new Feature("async-notifications", true,
                "Send notifications asynchronously"));
        return ff4j;
    }
}

@Service
@RequiredArgsConstructor
public class OrderService {

    private final FF4j ff4j;

    public OrderResponse create(CreateOrderRequest request) {
        if (ff4j.check("new-checkout-flow")) {
            return createWithNewFlow(request);
        }
        return createWithLegacyFlow(request);
    }
}
```

---

## Gradle Build Patterns

### Production build.gradle.kts

```kotlin
plugins {
    java
    id("org.springframework.boot") version "3.4.0"
    id("io.spring.dependency-management") version "1.1.4"
    id("com.google.protobuf") version "0.9.4"  // For gRPC
    jacoco
}

group = "com.example"
version = "1.0.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    // Spring Boot
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-security")

    // Database
    implementation("org.flywaydb:flyway-core")
    runtimeOnly("org.postgresql:postgresql")

    // Observability
    implementation("io.micrometer:micrometer-tracing-bridge-otel")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp")
    runtimeOnly("io.micrometer:micrometer-registry-prometheus")

    // Mapping
    implementation("org.mapstruct:mapstruct:1.5.5.Final")
    annotationProcessor("org.mapstruct:mapstruct-processor:1.5.5.Final")

    // Lombok (must be before mapstruct in annotation processor)
    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok-mapstruct-binding:0.2.0")

    // Testing
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.security:spring-security-test")
    testImplementation("org.testcontainers:junit-jupiter")
    testImplementation("org.testcontainers:postgresql")
}

tasks.withType<Test> {
    useJUnitPlatform()
    jvmArgs("-XX:+EnableDynamicAgentLoading")  // Mockito on Java 21
}

// JaCoCo coverage
tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true   // For CI tools
        html.required = true
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.80".toBigDecimal()  // 80% line coverage
            }
        }
    }
}

// Boot jar config
tasks.bootJar {
    archiveFileName = "${project.name}.jar"
    launchScript()  // Makes jar executable: ./app.jar
}
```

### Multi-Module Gradle

```kotlin
// settings.gradle.kts (root)
rootProject.name = "ecommerce"
include("common", "order-service", "inventory-service", "api-gateway")

// build.gradle.kts (root)
subprojects {
    apply(plugin = "java")
    apply(plugin = "org.springframework.boot")
    apply(plugin = "io.spring.dependency-management")

    group = "com.example.ecommerce"
    version = "1.0.0"

    java {
        toolchain {
            languageVersion = JavaLanguageVersion.of(21)
        }
    }

    dependencies {
        implementation("org.springframework.boot:spring-boot-starter")
        testImplementation("org.springframework.boot:spring-boot-starter-test")
    }
}

// build.gradle.kts (order-service)
dependencies {
    implementation(project(":common"))
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
}
```

---

## Multi-Module Project Setup

### Maven Multi-Module

```xml
<!-- pom.xml (parent) -->
<project>
    <groupId>com.example</groupId>
    <artifactId>ecommerce</artifactId>
    <version>1.0.0</version>
    <packaging>pom</packaging>

    <modules>
        <module>common</module>
        <module>order-service</module>
        <module>inventory-service</module>
        <module>api-gateway</module>
    </modules>

    <properties>
        <java.version>21</java.version>
        <spring-boot.version>3.4.0</spring-boot.version>
        <mapstruct.version>1.5.5.Final</mapstruct.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring-boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <!-- Internal modules -->
            <dependency>
                <groupId>com.example</groupId>
                <artifactId>common</artifactId>
                <version>${project.version}</version>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>

<!-- order-service/pom.xml -->
<project>
    <parent>
        <groupId>com.example</groupId>
        <artifactId>ecommerce</artifactId>
        <version>1.0.0</version>
    </parent>
    <artifactId>order-service</artifactId>

    <dependencies>
        <dependency>
            <groupId>com.example</groupId>
            <artifactId>common</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
    </dependencies>
</project>
```

---

## Structured Concurrency (Java 21+)

### StructuredTaskScope (Preview in Java 21)

```java
// ShutdownOnFailure — cancel all on first failure
public OrderDetail getOrderWithDetails(Long orderId)
        throws InterruptedException, ExecutionException {

    try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
        Subtask<Order> orderTask = scope.fork(() ->
                orderRepository.findById(orderId).orElseThrow());
        Subtask<Customer> customerTask = scope.fork(() ->
                customerService.findByOrderId(orderId));
        Subtask<List<Payment>> paymentsTask = scope.fork(() ->
                paymentService.findByOrderId(orderId));

        scope.join();           // Wait for all
        scope.throwIfFailed();  // Propagate first failure

        return new OrderDetail(
                orderTask.get(),
                customerTask.get(),
                paymentsTask.get());
    }
}

// ShutdownOnSuccess — return first successful result
public Product findProductAnywhere(String sku)
        throws InterruptedException, ExecutionException {

    try (var scope = new StructuredTaskScope.ShutdownOnSuccess<Product>()) {
        scope.fork(() -> localCache.findBySku(sku));
        scope.fork(() -> primaryDb.findBySku(sku));
        scope.fork(() -> replicaDb.findBySku(sku));

        scope.join();
        return scope.result();  // First successful result
    }
}
```

### Scoped Values (Java 21+, replaces ThreadLocal)

```java
// ScopedValue — lightweight, thread-safe context
public static final ScopedValue<UserContext> CURRENT_USER =
        ScopedValue.newInstance();

// Set in filter/interceptor
public void handleRequest(HttpServletRequest request) {
    UserContext ctx = extractUser(request);
    ScopedValue.runWhere(CURRENT_USER, ctx, () -> {
        // All code in this scope can read CURRENT_USER
        orderService.processRequest();
    });
}

// Read anywhere in the call chain
public Order processRequest() {
    UserContext user = CURRENT_USER.get();
    log.info("Processing for user: {}", user.name());
    // ...
}
```

---

## Mutation Testing (PIT)

### Maven Configuration

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.15.0</version>
    <configuration>
        <targetClasses>
            <param>com.example.app.service.*</param>
            <param>com.example.app.model.*</param>
        </targetClasses>
        <targetTests>
            <param>com.example.app.*Test</param>
        </targetTests>
        <mutationThreshold>80</mutationThreshold>
        <timestampedReports>false</timestampedReports>
        <outputFormats>
            <format>HTML</format>
            <format>XML</format>
        </outputFormats>
        <excludedMethods>
            <excludedMethod>hashCode</excludedMethod>
            <excludedMethod>equals</excludedMethod>
            <excludedMethod>toString</excludedMethod>
        </excludedMethods>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-junit5-plugin</artifactId>
            <version>1.2.1</version>
        </dependency>
    </dependencies>
</plugin>
```

```bash
# Run mutation testing
mvn org.pitest:pitest-maven:mutationCoverage

# Report at: target/pit-reports/index.html
# Metrics:
#   - Mutation score: % of mutants killed by tests
#   - Line coverage: % of lines covered
#   - Test strength: how well tests detect bugs
```

### Mutation Types PIT Tests

```
Mutation Type              | What It Changes        | Killed By
---------------------------|------------------------|------------------
CONDITIONALS_BOUNDARY      | < → <=, >= → >         | Edge case tests
NEGATE_CONDITIONALS        | == → !=, < → >=        | Boolean logic tests
MATH                       | + → -, * → /           | Arithmetic tests
INCREMENTS                 | i++ → i--              | Counter tests
INVERT_NEGS               | -x → x                 | Sign tests
RETURN_VALS               | return x → return null  | Return value tests
VOID_METHOD_CALLS         | Remove void calls       | Side effect tests
EMPTY_RETURNS             | return list → return [] | Empty collection tests
NULL_RETURNS              | return obj → return null | Null check tests
```
