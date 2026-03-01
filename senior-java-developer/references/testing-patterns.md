# Java Testing Patterns Reference

## Table of Contents

1. [Testing Pyramid & Strategy](#testing-pyramid--strategy)
2. [JUnit 5 Patterns](#junit-5-patterns)
3. [Mockito Patterns](#mockito-patterns)
4. [Spring Boot Test Slices](#spring-boot-test-slices)
5. [Testcontainers Integration](#testcontainers-integration)
6. [REST API Testing](#rest-api-testing)
7. [JPA Repository Testing](#jpa-repository-testing)
8. [Security Testing](#security-testing)
9. [Architecture Testing with ArchUnit](#architecture-testing-with-archunit)
10. [Test Fixtures & Data Builders](#test-fixtures--data-builders)

---

## Testing Pyramid & Strategy

```
         ╱╲
        ╱  ╲         E2E Tests (few)
       ╱ E2E╲        Selenium, Playwright
      ╱──────╲
     ╱        ╲       Integration Tests (moderate)
    ╱ Integr.  ╲      @SpringBootTest, Testcontainers
   ╱────────────╲
  ╱              ╲     Unit Tests (many)
 ╱   Unit Tests   ╲    JUnit 5, Mockito
╱──────────────────╲
```

### Test Naming Convention

```java
// Pattern: methodName_scenario_expectedBehavior
@Test
void createOrder_withValidRequest_returnsCreatedOrder() { }

@Test
void createOrder_withEmptyItems_throwsValidationException() { }

@Test
void findById_withNonExistentId_throwsResourceNotFoundException() { }
```

### Test Organization

```
src/test/java/com/example/app/
├── unit/
│   ├── service/
│   │   └── OrderServiceTest.java
│   ├── model/
│   │   └── OrderTest.java
│   └── util/
│       └── PriceCalculatorTest.java
├── integration/
│   ├── repository/
│   │   └── OrderRepositoryIT.java
│   ├── controller/
│   │   └── OrderControllerIT.java
│   └── service/
│       └── OrderServiceIT.java
└── e2e/
    └── OrderFlowE2ETest.java

src/test/resources/
├── application-test.yml
├── data/
│   ├── orders.json
│   └── customers.json
└── sql/
    └── test-data.sql
```

---

## JUnit 5 Patterns

### Basic Test Structure

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private OrderMapper orderMapper;

    @Mock
    private EventPublisher eventPublisher;

    @InjectMocks
    private OrderServiceImpl orderService;

    @Test
    void findById_withExistingOrder_returnsOrderResponse() {
        // Arrange
        Long orderId = 1L;
        Order order = OrderFixture.defaultOrder().build();
        OrderResponse expected = OrderFixture.defaultResponse().build();

        when(orderRepository.findById(orderId)).thenReturn(Optional.of(order));
        when(orderMapper.toResponse(order)).thenReturn(expected);

        // Act
        OrderResponse result = orderService.findById(orderId);

        // Assert
        assertThat(result).isEqualTo(expected);
        verify(orderRepository).findById(orderId);
    }

    @Test
    void findById_withNonExistentId_throwsResourceNotFoundException() {
        when(orderRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> orderService.findById(99L))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining("Order")
                .hasMessageContaining("99");
    }
}
```

### Parameterized Tests

```java
class PriceCalculatorTest {

    @ParameterizedTest
    @CsvSource({
        "100.00, 10, 90.00",    // 10% discount
        "100.00, 0, 100.00",    // No discount
        "100.00, 100, 0.00",    // Full discount
        "50.50, 20, 40.40"      // 20% discount
    })
    void calculateDiscountedPrice(BigDecimal price, int discountPercent,
                                   BigDecimal expected) {
        BigDecimal result = calculator.applyDiscount(price, discountPercent);
        assertThat(result).isEqualByComparingTo(expected);
    }

    @ParameterizedTest
    @EnumSource(value = OrderStatus.class,
                names = {"PENDING", "CONFIRMED"})
    void canCancel_withCancelableStatus_returnsTrue(OrderStatus status) {
        Order order = Order.builder().status(status).build();
        assertThat(order.canCancel()).isTrue();
    }

    @ParameterizedTest
    @MethodSource("provideInvalidEmails")
    void validateEmail_withInvalidEmail_throwsException(String email) {
        assertThatThrownBy(() -> validator.validateEmail(email))
                .isInstanceOf(ValidationException.class);
    }

    static Stream<String> provideInvalidEmails() {
        return Stream.of(
                "",
                "   ",
                "no-at-sign",
                "@no-local-part.com",
                "spaces in@email.com",
                "missing@.com"
        );
    }
}
```

### Nested Tests for Grouping

```java
class OrderTest {

    @Nested
    @DisplayName("when creating a new order")
    class WhenCreating {

        @Test
        @DisplayName("sets status to PENDING")
        void setsStatusToPending() {
            Order order = Order.create(customer, items);
            assertThat(order.getStatus()).isEqualTo(OrderStatus.PENDING);
        }

        @Test
        @DisplayName("calculates total from items")
        void calculatesTotalFromItems() {
            List<OrderItem> items = List.of(
                    itemOf("Widget", 10.00, 2),
                    itemOf("Gadget", 25.00, 1));

            Order order = Order.create(customer, items);
            assertThat(order.getTotal())
                    .isEqualByComparingTo(new BigDecimal("45.00"));
        }
    }

    @Nested
    @DisplayName("when cancelling")
    class WhenCancelling {

        @Test
        @DisplayName("succeeds for PENDING orders")
        void succeedsForPendingOrders() {
            Order order = orderWithStatus(PENDING);
            order.cancel("Changed my mind");
            assertThat(order.getStatus()).isEqualTo(CANCELLED);
        }

        @Test
        @DisplayName("throws for SHIPPED orders")
        void throwsForShippedOrders() {
            Order order = orderWithStatus(SHIPPED);
            assertThatThrownBy(() -> order.cancel("Too late"))
                    .isInstanceOf(BusinessRuleException.class)
                    .hasMessageContaining("Cannot cancel");
        }
    }
}
```

### Custom Assertions with AssertJ

```java
// Custom assertion class
public class OrderAssert extends AbstractAssert<OrderAssert, Order> {

    private OrderAssert(Order actual) {
        super(actual, OrderAssert.class);
    }

    public static OrderAssert assertThatOrder(Order actual) {
        return new OrderAssert(actual);
    }

    public OrderAssert hasStatus(OrderStatus expected) {
        isNotNull();
        if (!actual.getStatus().equals(expected)) {
            failWithMessage("Expected status <%s> but was <%s>",
                    expected, actual.getStatus());
        }
        return this;
    }

    public OrderAssert hasTotalGreaterThan(BigDecimal min) {
        isNotNull();
        if (actual.getTotal().compareTo(min) <= 0) {
            failWithMessage("Expected total > <%s> but was <%s>",
                    min, actual.getTotal());
        }
        return this;
    }

    public OrderAssert hasItemCount(int expected) {
        isNotNull();
        assertThat(actual.getItems()).hasSize(expected);
        return this;
    }
}

// Usage
assertThatOrder(order)
    .hasStatus(CONFIRMED)
    .hasTotalGreaterThan(BigDecimal.ZERO)
    .hasItemCount(3);
```

---

## Mockito Patterns

### Argument Matchers & Captors

```java
@Test
void createOrder_publishesEventWithCorrectData() {
    // Arrange
    CreateOrderRequest request = new CreateOrderRequest(
            1L, List.of(new OrderItemRequest(1L, 2)), null);
    Order savedOrder = OrderFixture.defaultOrder()
            .id(42L).total(BigDecimal.valueOf(50)).build();

    when(orderRepository.save(any(Order.class))).thenReturn(savedOrder);
    when(orderMapper.toEntity(request)).thenReturn(new Order());
    when(orderMapper.toResponse(savedOrder)).thenReturn(
            OrderFixture.defaultResponse().build());

    // Act
    orderService.create(request);

    // Assert — capture the published event
    ArgumentCaptor<OrderCreatedEvent> eventCaptor =
            ArgumentCaptor.forClass(OrderCreatedEvent.class);
    verify(eventPublisher).publish(eventCaptor.capture());

    OrderCreatedEvent event = eventCaptor.getValue();
    assertThat(event.orderId()).isEqualTo(42L);
}

// Using argument matchers
verify(orderRepository).save(argThat(order ->
    order.getStatus() == OrderStatus.PENDING &&
    order.getCreatedAt() != null
));
```

### Behavior Verification

```java
@Test
void updateOrder_withNoChanges_doesNotPublishEvent() {
    Order existing = OrderFixture.defaultOrder().build();
    UpdateOrderRequest request = new UpdateOrderRequest(
            existing.getStatus(), existing.getNotes());

    when(orderRepository.findById(1L))
            .thenReturn(Optional.of(existing));

    orderService.update(1L, request);

    // Verify event was NOT published
    verify(eventPublisher, never()).publish(any());
    // Verify save was still called
    verify(orderRepository, times(1)).save(any());
}

// Verify order of interactions
@Test
void processOrder_validatesBeforeSaving() {
    InOrder inOrder = inOrder(validator, orderRepository);
    orderService.process(request);
    inOrder.verify(validator).validate(any());
    inOrder.verify(orderRepository).save(any());
}
```

### Stubbing Exceptions & Answers

```java
// Stub exception
when(paymentClient.charge(any()))
    .thenThrow(new PaymentException("Gateway timeout"));

// Stub with answer (dynamic return)
when(orderRepository.save(any(Order.class)))
    .thenAnswer(invocation -> {
        Order order = invocation.getArgument(0);
        order.setId(1L); // Simulate auto-generated ID
        return order;
    });

// Consecutive stubs
when(retryableClient.call(any()))
    .thenThrow(new IOException("Connection reset"))
    .thenThrow(new IOException("Timeout"))
    .thenReturn(successResponse);
```

---

## Spring Boot Test Slices

### @WebMvcTest — Controller Layer Only

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService orderService;

    @Test
    void getOrder_withExistingId_returns200() throws Exception {
        OrderResponse response = new OrderResponse(
                1L, OrderStatus.PENDING, "John", BigDecimal.TEN,
                List.of(), Instant.now());

        when(orderService.findById(1L)).thenReturn(response);

        mockMvc.perform(get("/api/v1/orders/1")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.customerName").value("John"));
    }

    @Test
    void createOrder_withInvalidRequest_returns400() throws Exception {
        String invalidJson = """
                {
                    "customerId": null,
                    "items": []
                }
                """;

        mockMvc.perform(post("/api/v1/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(invalidJson))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").exists());
    }

    @Test
    void getOrder_withNonExistentId_returns404() throws Exception {
        when(orderService.findById(99L))
                .thenThrow(new ResourceNotFoundException("Order", 99L));

        mockMvc.perform(get("/api/v1/orders/99"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.title").value("Resource Not Found"));
    }
}
```

### @DataJpaTest — Repository Layer Only

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
@Testcontainers
class OrderRepositoryIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void findByIdWithDetails_returnsOrderWithCustomerAndItems() {
        // Arrange
        Customer customer = new Customer("John", "john@example.com");
        entityManager.persistAndFlush(customer);

        Order order = new Order();
        order.setCustomer(customer);
        order.setStatus(OrderStatus.PENDING);
        order.setCreatedAt(Instant.now());
        order.addItem(new OrderItem("Widget", BigDecimal.TEN, 2));
        entityManager.persistAndFlush(order);
        entityManager.clear(); // Force fresh load

        // Act
        Optional<Order> result =
                orderRepository.findByIdWithDetails(order.getId());

        // Assert
        assertThat(result).isPresent();
        assertThat(result.get().getCustomer().getName()).isEqualTo("John");
        assertThat(result.get().getItems()).hasSize(1);
    }

    @Test
    void findSummariesByStatus_returnsPaginatedProjections() {
        // Insert test data
        createOrdersWithStatus(OrderStatus.PENDING, 5);
        createOrdersWithStatus(OrderStatus.SHIPPED, 3);

        Page<OrderSummary> result = orderRepository.findSummariesByStatus(
                OrderStatus.PENDING, PageRequest.of(0, 10));

        assertThat(result.getContent()).hasSize(5);
        assertThat(result.getTotalElements()).isEqualTo(5);
    }

    @Test
    void bulkUpdateStatus_updatesMatchingOrders() {
        createOrdersWithStatus(OrderStatus.PENDING, 5);
        Instant cutoff = Instant.now().plus(1, ChronoUnit.HOURS);

        int updated = orderRepository.bulkUpdateStatus(
                OrderStatus.EXPIRED, OrderStatus.PENDING, cutoff);

        assertThat(updated).isEqualTo(5);
    }
}
```

### @SpringBootTest — Full Integration Test

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
@ActiveProfiles("test")
class OrderFlowIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private OrderRepository orderRepository;

    @Test
    void fullOrderLifecycle() {
        // Create order
        CreateOrderRequest createReq = new CreateOrderRequest(
                1L, List.of(new OrderItemRequest(1L, 2)), "Test order");

        ResponseEntity<OrderResponse> createResp = restTemplate.postForEntity(
                "/api/v1/orders", createReq, OrderResponse.class);

        assertThat(createResp.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(createResp.getHeaders().getLocation()).isNotNull();
        Long orderId = createResp.getBody().id();

        // Verify in database
        Order saved = orderRepository.findById(orderId).orElseThrow();
        assertThat(saved.getStatus()).isEqualTo(OrderStatus.PENDING);

        // Get order
        ResponseEntity<OrderResponse> getResp = restTemplate.getForEntity(
                "/api/v1/orders/" + orderId, OrderResponse.class);

        assertThat(getResp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(getResp.getBody().status()).isEqualTo(OrderStatus.PENDING);
    }
}
```

---

## Testcontainers Integration

### Database Containers

```java
@Testcontainers
@SpringBootTest
class DatabaseIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withDatabaseName("testdb")
                    .withUsername("test")
                    .withPassword("test")
                    .withInitScript("sql/init-test.sql");

    // Spring Boot 3.1+ auto-configures datasource from @ServiceConnection
}
```

### Multiple Containers (Docker Compose)

```java
@Testcontainers
@SpringBootTest
class FullStackIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine");

    @Container
    @ServiceConnection
    static GenericContainer<?> redis =
            new GenericContainer<>("redis:7-alpine")
                    .withExposedPorts(6379);

    @Container
    static KafkaContainer kafka =
            new KafkaContainer(DockerImageName.parse(
                    "confluentinc/cp-kafka:7.5.0"));

    @DynamicPropertySource
    static void kafkaProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.kafka.bootstrap-servers",
                kafka::getBootstrapServers);
    }
}
```

### Reusable Container Base Class

```java
public abstract class AbstractIntegrationTest {

    @Container
    @ServiceConnection
    protected static final PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withReuse(true); // Reuse across test classes

    @Container
    @ServiceConnection
    protected static final GenericContainer<?> redis =
            new GenericContainer<>("redis:7-alpine")
                    .withExposedPorts(6379)
                    .withReuse(true);
}

// Usage
@SpringBootTest
class OrderServiceIT extends AbstractIntegrationTest {
    // postgres and redis are available
}
```

---

## REST API Testing

### RestAssured Integration

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class OrderApiTest {

    @LocalServerPort
    private int port;

    @BeforeEach
    void setUp() {
        RestAssured.port = port;
        RestAssured.basePath = "/api/v1";
    }

    @Test
    void createAndGetOrder() {
        // Create
        Long orderId = given()
                .contentType(ContentType.JSON)
                .body("""
                    {
                        "customerId": 1,
                        "items": [{"productId": 1, "quantity": 2}]
                    }
                    """)
            .when()
                .post("/orders")
            .then()
                .statusCode(201)
                .header("Location", containsString("/orders/"))
                .body("status", equalTo("PENDING"))
                .body("items", hasSize(1))
                .extract()
                .jsonPath().getLong("id");

        // Get
        given()
            .when()
                .get("/orders/{id}", orderId)
            .then()
                .statusCode(200)
                .body("id", equalTo(orderId.intValue()))
                .body("status", equalTo("PENDING"));
    }

    @Test
    void listOrders_withPagination() {
        given()
                .queryParam("page", 0)
                .queryParam("size", 5)
                .queryParam("sort", "createdAt,desc")
            .when()
                .get("/orders")
            .then()
                .statusCode(200)
                .body("content", hasSize(lessThanOrEqualTo(5)))
                .body("totalElements", greaterThanOrEqualTo(0))
                .body("pageable.pageSize", equalTo(5));
    }
}
```

### WebTestClient (Reactive / WebFlux)

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class OrderApiWebFluxTest {

    @Autowired
    private WebTestClient webClient;

    @Test
    void createOrder_returnsCreated() {
        webClient.post().uri("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(new CreateOrderRequest(1L, items, null))
                .exchange()
                .expectStatus().isCreated()
                .expectHeader().exists("Location")
                .expectBody()
                .jsonPath("$.id").isNotEmpty()
                .jsonPath("$.status").isEqualTo("PENDING");
    }
}
```

---

## Security Testing

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService orderService;

    @Test
    void getOrders_withoutAuth_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/orders"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "USER")
    void getOrders_withUserRole_returns200() throws Exception {
        when(orderService.findAll(any())).thenReturn(Page.empty());

        mockMvc.perform(get("/api/v1/orders"))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser(roles = "USER")
    void deleteOrder_withUserRole_returns403() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/orders/1"))
                .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void deleteOrder_withAdminRole_returns204() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/orders/1"))
                .andExpect(status().isNoContent());
    }

    @Test
    @WithMockUser(username = "john@example.com", roles = "USER")
    void getMyOrders_returnsOwnOrdersOnly() throws Exception {
        mockMvc.perform(get("/api/v1/orders/my"))
                .andExpect(status().isOk());

        verify(orderService).findByCustomerEmail("john@example.com", any());
    }
}
```

---

## Architecture Testing with ArchUnit

```java
@AnalyzeClasses(packages = "com.example.app",
                importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest
    static final ArchRule layerDependencies = layeredArchitecture()
            .consideringOnlyDependenciesInLayers()
            .layer("Controller").definedBy("..controller..")
            .layer("Service").definedBy("..service..")
            .layer("Repository").definedBy("..repository..")
            .layer("Model").definedBy("..model..")
            .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
            .whereLayer("Service").mayOnlyBeAccessedByLayers(
                    "Controller", "Service")
            .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service");

    @ArchTest
    static final ArchRule controllersShouldNotDependOnRepositories =
            noClasses().that().resideInAPackage("..controller..")
                    .should().dependOnClassesThat()
                    .resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule servicesShouldBeAnnotated =
            classes().that().resideInAPackage("..service..")
                    .and().areNotInterfaces()
                    .should().beAnnotatedWith(Service.class);

    @ArchTest
    static final ArchRule entitiesShouldNotUseFieldInjection =
            noFields().that().areDeclaredInClassesThat()
                    .areAnnotatedWith(Entity.class)
                    .should().beAnnotatedWith(Autowired.class);

    @ArchTest
    static final ArchRule noSystemOutInProduction =
            noClasses()
                    .should().accessClassesThat()
                    .belongToAnyOf(System.class)
                    .because("Use SLF4J logging instead of System.out");
}
```

---

## Test Fixtures & Data Builders

### Builder Pattern for Test Data

```java
public class OrderFixture {

    public static OrderBuilder defaultOrder() {
        return new OrderBuilder()
                .id(1L)
                .status(OrderStatus.PENDING)
                .customerName("John Doe")
                .total(BigDecimal.valueOf(100))
                .createdAt(Instant.now());
    }

    public static OrderResponseBuilder defaultResponse() {
        return new OrderResponseBuilder()
                .id(1L)
                .status(OrderStatus.PENDING)
                .customerName("John Doe")
                .total(BigDecimal.valueOf(100))
                .items(List.of())
                .createdAt(Instant.now());
    }

    @Getter
    public static class OrderBuilder {
        private Long id;
        private OrderStatus status;
        private String customerName;
        private BigDecimal total;
        private Instant createdAt;
        private List<OrderItem> items = new ArrayList<>();

        public OrderBuilder id(Long id) {
            this.id = id; return this;
        }
        public OrderBuilder status(OrderStatus s) {
            this.status = s; return this;
        }
        public OrderBuilder customerName(String n) {
            this.customerName = n; return this;
        }
        public OrderBuilder total(BigDecimal t) {
            this.total = t; return this;
        }
        public OrderBuilder createdAt(Instant c) {
            this.createdAt = c; return this;
        }
        public OrderBuilder withItem(String name, double price, int qty) {
            items.add(new OrderItem(name, BigDecimal.valueOf(price), qty));
            return this;
        }

        public Order build() {
            Order order = new Order();
            order.setId(id);
            order.setStatus(status);
            order.setTotal(total);
            order.setCreatedAt(createdAt);
            items.forEach(order::addItem);
            // Set customer via reflection or constructor
            return order;
        }
    }
}

// Usage in tests
Order order = OrderFixture.defaultOrder()
        .status(OrderStatus.SHIPPED)
        .withItem("Widget", 25.00, 2)
        .withItem("Gadget", 50.00, 1)
        .build();
```

### SQL Test Data Loading

```java
@DataJpaTest
@Sql(scripts = "/sql/test-data.sql",
     executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
@Sql(scripts = "/sql/cleanup.sql",
     executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD)
class OrderRepositoryIT {

    @Test
    void findByStatus_returnsCorrectOrders() {
        List<Order> pending = orderRepository
                .findByStatus(OrderStatus.PENDING);
        assertThat(pending).hasSize(3); // Matches test-data.sql
    }
}
```

```sql
-- test-data.sql
INSERT INTO customers (id, name, email) VALUES
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com');

INSERT INTO orders (id, customer_id, status, total, created_at) VALUES
    (1, 1, 'PENDING', 100.00, '2025-01-01T10:00:00Z'),
    (2, 1, 'SHIPPED', 200.00, '2025-01-02T10:00:00Z'),
    (3, 2, 'PENDING', 150.00, '2025-01-03T10:00:00Z'),
    (4, 2, 'PENDING', 75.00, '2025-01-04T10:00:00Z');
```

### Test Configuration

```yaml
# application-test.yml
spring:
  jpa:
    show-sql: true
    properties:
      hibernate:
        format_sql: true
  flyway:
    enabled: true
    clean-on-validation-error: true

logging:
  level:
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql.BasicBinder: TRACE
    org.springframework.test: INFO
```
