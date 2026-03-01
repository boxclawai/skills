# JVM Performance Reference

## Table of Contents

1. [JVM Memory Model](#jvm-memory-model)
2. [Garbage Collection Tuning](#garbage-collection-tuning)
3. [JVM Flags Reference](#jvm-flags-reference)
4. [Profiling & Diagnostics](#profiling--diagnostics)
5. [Spring Boot Performance Tuning](#spring-boot-performance-tuning)
6. [Connection Pool Tuning](#connection-pool-tuning)
7. [Common Performance Anti-Patterns](#common-performance-anti-patterns)
8. [Benchmarking with JMH](#benchmarking-with-jmh)
9. [Container (Docker/K8s) JVM Settings](#container-dockerk8s-jvm-settings)
10. [GraalVM Native Image](#graalvm-native-image)

---

## JVM Memory Model

### Heap Structure

```
┌──────────────────────────────────────────────────┐
│                     JVM Memory                    │
├──────────────────────┬───────────────────────────┤
│       Heap           │       Non-Heap            │
├──────────┬───────────┤                           │
│  Young   │   Old     │  Metaspace               │
│  Gen     │   Gen     │  Code Cache              │
├────┬─────┤           │  Thread Stacks           │
│Eden│ S0  │           │  Direct ByteBuffers      │
│    │ S1  │           │  NIO Buffers             │
└────┴─────┴───────────┴───────────────────────────┘
```

### Key JVM Memory Areas

| Area | Purpose | Flag |
|------|---------|------|
| Heap (Young + Old) | Object allocation | `-Xmx`, `-Xms` |
| Metaspace | Class metadata | `-XX:MaxMetaspaceSize` |
| Code Cache | JIT compiled code | `-XX:ReservedCodeCacheSize` |
| Thread Stacks | Per-thread call stacks | `-Xss` |
| Direct Memory | NIO direct buffers | `-XX:MaxDirectMemorySize` |

---

## Garbage Collection Tuning

### GC Algorithm Selection

| GC | Best For | Flags |
|----|----------|-------|
| G1GC | General purpose, balanced (default JDK 9+) | `-XX:+UseG1GC` |
| ZGC | Ultra-low latency (<1ms pause) | `-XX:+UseZGC` |
| Shenandoah | Low latency, concurrent | `-XX:+UseShenandoahGC` |
| Parallel GC | Maximum throughput, batch jobs | `-XX:+UseParallelGC` |
| Serial GC | Small heaps, single core | `-XX:+UseSerialGC` |

### G1GC Tuning

```bash
# Production G1GC settings
java \
  -Xms4g -Xmx4g \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -XX:G1HeapRegionSize=16m \
  -XX:InitiatingHeapOccupancyPercent=45 \
  -XX:G1ReservePercent=10 \
  -XX:ParallelGCThreads=8 \
  -XX:ConcGCThreads=2 \
  -XX:+UseStringDeduplication \
  -jar app.jar
```

### ZGC Tuning (Java 17+)

```bash
# ZGC for ultra-low latency
java \
  -Xms8g -Xmx8g \
  -XX:+UseZGC \
  -XX:+ZGenerational \
  -XX:SoftMaxHeapSize=6g \
  -XX:ConcGCThreads=4 \
  -jar app.jar
```

### GC Logging

```bash
# JDK 17+ unified GC logging
java \
  -Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m \
  -Xlog:gc+phases=debug:file=gc-phases.log \
  -jar app.jar
```

### Analyzing GC Logs

Key metrics to watch:
- **GC pause time**: Should be < 200ms for interactive apps
- **GC frequency**: More than 1 full GC per minute = problem
- **Heap usage after GC**: If > 80% after full GC = memory pressure
- **Allocation rate**: High allocation rate = excessive object creation
- **Promotion rate**: High promotion = objects surviving too long in young gen

---

## JVM Flags Reference

### Production Baseline

```bash
java \
  # Memory
  -Xms4g -Xmx4g \
  -XX:MaxMetaspaceSize=512m \
  -XX:+AlwaysPreTouch \
  \
  # GC
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  \
  # JIT
  -XX:+TieredCompilation \
  -XX:ReservedCodeCacheSize=256m \
  \
  # Error handling
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/var/log/app/heapdump.hprof \
  -XX:ErrorFile=/var/log/app/hs_err_%p.log \
  -XX:+ExitOnOutOfMemoryError \
  \
  # Diagnostics
  -XX:+UnlockDiagnosticVMOptions \
  -XX:+DebugNonSafepoints \
  -XX:NativeMemoryTracking=summary \
  \
  # Networking
  -Djava.net.preferIPv4Stack=true \
  -Dsun.net.inetaddr.ttl=60 \
  \
  -jar app.jar
```

### Memory Sizing Guidelines

| Application Type | Heap Size | Rationale |
|-----------------|-----------|-----------|
| Microservice (light) | 512m–1g | Small footprint, fast startup |
| Standard web app | 2g–4g | Moderate object retention |
| Data processing | 4g–16g | Large datasets in memory |
| In-memory cache | 8g–64g | Full dataset in heap |

**Rule of thumb**: Set `-Xms` = `-Xmx` (avoid heap resizing overhead)

---

## Profiling & Diagnostics

### JDK Flight Recorder (JFR)

```bash
# Start recording at runtime
jcmd <pid> JFR.start name=profile \
  duration=60s \
  filename=profile.jfr \
  settings=profile

# Continuous recording (dump on demand)
java -XX:StartFlightRecording=name=continuous,\
maxsize=250m,maxage=1h,dumponexit=true,\
filename=recording.jfr \
  -jar app.jar

# Dump running recording
jcmd <pid> JFR.dump name=continuous filename=snapshot.jfr
```

### jcmd Diagnostic Commands

```bash
# List running Java processes
jcmd

# Thread dump
jcmd <pid> Thread.print

# Heap info
jcmd <pid> GC.heap_info

# Force GC
jcmd <pid> GC.run

# Class histogram (find memory-heavy classes)
jcmd <pid> GC.class_histogram | head -30

# VM flags
jcmd <pid> VM.flags

# Native memory tracking
jcmd <pid> VM.native_memory summary

# System properties
jcmd <pid> VM.system_properties
```

### Heap Analysis

```bash
# Create heap dump
jmap -dump:live,format=b,file=heap.hprof <pid>

# Or trigger via flag (on OOM)
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/path/to/dumps/

# Quick histogram without full dump
jmap -histo:live <pid> | head -30

# Analyze with Eclipse MAT or VisualVM
# Look for:
#   - Retained heap by class
#   - Dominator tree
#   - Leak suspects report
```

### Async Profiler (Low-Overhead CPU/Allocation Profiling)

```bash
# CPU profiling
./asprof -d 30 -f cpu-profile.jfr <pid>

# Allocation profiling
./asprof -d 30 -e alloc -f alloc-profile.jfr <pid>

# Lock contention profiling
./asprof -d 30 -e lock -f lock-profile.jfr <pid>

# Wall-clock profiling (includes I/O wait)
./asprof -d 30 -e wall -f wall-profile.jfr <pid>

# Generate flame graph
./asprof -d 30 -f flamegraph.html <pid>
```

---

## Spring Boot Performance Tuning

### Startup Optimization

```yaml
spring:
  jpa:
    defer-datasource-initialization: true
    properties:
      hibernate:
        # Delay schema validation
        temp.use_jdbc_metadata_defaults: false
  main:
    lazy-initialization: true  # Lazy bean init (dev only!)
```

```java
// Use class-path scanning wisely
@SpringBootApplication(scanBasePackages = "com.example.myapp")
// Avoid scanning too broadly

// Exclude unused auto-configurations
@SpringBootApplication(exclude = {
    DataSourceAutoConfiguration.class,
    MongoAutoConfiguration.class
})

// Use AOT processing (Spring Boot 3+)
// mvn spring-boot:process-aot
```

### HTTP Server Tuning

```yaml
server:
  tomcat:
    threads:
      max: 200
      min-spare: 20
    max-connections: 10000
    accept-count: 100
    connection-timeout: 10s
    keep-alive-timeout: 30s
  compression:
    enabled: true
    min-response-size: 1024
    mime-types: application/json,application/xml,text/html,text/plain
```

### Jackson Optimization

```java
@Configuration
public class JacksonConfig {

    @Bean
    public ObjectMapper objectMapper() {
        return JsonMapper.builder()
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                .enable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
                .serializationInclusion(JsonInclude.Include.NON_NULL)
                .addModule(new JavaTimeModule())
                // Performance: use afterburner for faster ser/de
                .addModule(new AfterburnerModule())
                .build();
    }
}
```

---

## Connection Pool Tuning

### HikariCP (Default in Spring Boot)

```yaml
spring:
  datasource:
    hikari:
      # Pool sizing: connections = (core_count * 2) + effective_spindle_count
      # For a 4-core server with SSD: ~10 connections is often optimal
      maximum-pool-size: 10
      minimum-idle: 5

      # Timeouts
      connection-timeout: 30000     # 30s — max wait for connection
      idle-timeout: 600000          # 10min — idle connection lifetime
      max-lifetime: 1800000         # 30min — max connection lifetime
      validation-timeout: 5000     # 5s — connection validation timeout

      # Leak detection
      leak-detection-threshold: 60000  # 60s — warn if connection held too long

      # Connection test
      connection-test-query: SELECT 1
```

### Why Small Pools Are Better

```
Optimal pool size formula:
  connections = (core_count * 2) + effective_spindle_count

Example: 4-core server, SSD (1 spindle)
  connections = (4 * 2) + 1 = 9 ≈ 10

Common mistake: setting pool size to 50+ "for safety"
Reality: more connections = more context switching = slower
```

---

## Common Performance Anti-Patterns

### 1. N+1 Query Problem

```java
// BAD: N+1 queries
List<Order> orders = orderRepository.findAll(); // 1 query
for (Order order : orders) {
    order.getCustomer().getName(); // N queries (lazy load each)
}

// GOOD: Join fetch
@Query("SELECT o FROM Order o JOIN FETCH o.customer")
List<Order> findAllWithCustomers();

// GOOD: Entity graph
@EntityGraph(attributePaths = {"customer", "items"})
List<Order> findByStatus(OrderStatus status);
```

### 2. Loading Entire Table

```java
// BAD: Load all into memory
List<Order> allOrders = orderRepository.findAll();
allOrders.stream().filter(o -> o.getStatus() == PENDING).count();

// GOOD: Database-level filtering with pagination
Page<Order> orders = orderRepository
    .findByStatus(PENDING, PageRequest.of(0, 50));

// GOOD: Count query
long count = orderRepository.countByStatus(PENDING);
```

### 3. String Concatenation in Loops

```java
// BAD: O(n²) string building
String result = "";
for (String item : items) {
    result += item + ", ";
}

// GOOD: StringBuilder
StringBuilder sb = new StringBuilder();
for (String item : items) {
    sb.append(item).append(", ");
}

// BEST: Collectors.joining
String result = items.stream().collect(Collectors.joining(", "));
```

### 4. Autoboxing in Hot Paths

```java
// BAD: Autoboxing creates garbage
long sum = 0L;
for (Integer value : integerList) {
    sum += value; // unboxing Integer → int, then boxing
}

// GOOD: Use primitive streams
long sum = integerList.stream().mapToLong(Integer::longValue).sum();
```

### 5. Blocking I/O in Reactive Pipelines

```java
// BAD: Blocking call in reactive pipeline
Mono<String> result = Mono.fromCallable(() -> {
    return restTemplate.getForObject(url, String.class); // BLOCKS thread
});

// GOOD: Use WebClient for non-blocking I/O
Mono<String> result = webClient.get()
    .uri(url)
    .retrieve()
    .bodyToMono(String.class);
```

---

## Benchmarking with JMH

### Basic Benchmark

```java
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 1)
@Measurement(iterations = 10, time = 1)
@Fork(2)
@State(Scope.Benchmark)
public class SerializationBenchmark {

    private ObjectMapper objectMapper;
    private OrderResponse testOrder;

    @Setup
    public void setup() {
        objectMapper = new ObjectMapper()
                .registerModule(new JavaTimeModule());
        testOrder = new OrderResponse(1L, OrderStatus.PENDING,
                "Test", BigDecimal.TEN, List.of(), Instant.now());
    }

    @Benchmark
    public String serializeJackson() throws Exception {
        return objectMapper.writeValueAsString(testOrder);
    }

    @Benchmark
    public byte[] serializeJacksonBytes() throws Exception {
        return objectMapper.writeValueAsBytes(testOrder);
    }
}
```

```bash
# Run benchmarks
mvn clean package -pl benchmarks
java -jar benchmarks/target/benchmarks.jar

# Common JMH options
java -jar benchmarks.jar \
  -f 2 \             # Forks
  -wi 5 \            # Warmup iterations
  -i 10 \            # Measurement iterations
  -t 4 \             # Threads
  -rf json \         # Result format
  -rff results.json  # Result file
```

---

## Container (Docker/K8s) JVM Settings

### Docker-Optimized Dockerfile

```dockerfile
# Multi-stage build
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY . .
RUN ./mvnw clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Create non-root user
RUN addgroup -S app && adduser -S app -G app
USER app

COPY --from=build /app/target/*.jar app.jar

# JVM container-aware settings
ENV JAVA_OPTS="\
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:InitialRAMPercentage=50.0 \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/tmp/heapdump.hprof \
  -XX:+ExitOnOutOfMemoryError \
  -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

### Kubernetes Resource Limits

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: order-service
          image: myapp:latest
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
          env:
            - name: JAVA_OPTS
              value: >-
                -XX:+UseContainerSupport
                -XX:MaxRAMPercentage=75.0
                -XX:+UseG1GC
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 5
```

**Memory sizing rule**: JVM heap = ~75% of container memory limit. The remaining 25% is for metaspace, thread stacks, code cache, native memory, and OS overhead.

---

## GraalVM Native Image

### Spring Boot Native Build

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
    <configuration>
        <buildArgs>
            <buildArg>--no-fallback</buildArg>
            <buildArg>-H:+ReportExceptionStackTraces</buildArg>
        </buildArgs>
    </configuration>
</plugin>
```

```bash
# Build native image
mvn -Pnative native:compile

# Or with Spring Boot plugin
mvn spring-boot:build-image -Pnative

# Result: ~50ms startup, ~50MB RSS (vs ~2s startup, ~200MB with JVM)
```

### Native Image Trade-Offs

| Aspect | JVM | Native Image |
|--------|-----|-------------|
| Startup time | ~2–5s | ~50–200ms |
| Memory (RSS) | ~200–500MB | ~50–150MB |
| Peak throughput | Higher (JIT) | Lower (AOT) |
| Build time | Fast (~30s) | Slow (~3–10min) |
| Reflection | Full support | Requires config |
| Debugging | Full tooling | Limited |
| Best for | Long-running services | Serverless, CLI |
