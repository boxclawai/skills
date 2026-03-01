# :coffee: Senior Java Developer

> Expert guidance for enterprise Java development — Spring Boot, microservices, JVM performance tuning, design patterns, testing, and production-grade architecture.

## What's Included

### SKILL.md (530 lines)

Core competencies covering:

- Spring Boot layered architecture (controller/service/repository)
- Exception handling with ProblemDetail (RFC 9457)
- JPA/Hibernate best practices (entities, repositories, N+1 prevention)
- Modern Java features (records, sealed interfaces, pattern matching, virtual threads)
- Spring Security (JWT, method-level authorization)
- Concurrency & async processing (CompletableFuture, thread pools)
- Configuration & profiles (type-safe properties, YAML profiles)
- Observability (Micrometer metrics, Prometheus)

### References

| File | Lines | Description |
|------|-------|-------------|
| `spring-boot-patterns.md` | 864 | REST API design, caching (Caffeine/Redis), event-driven patterns, Kafka, Spring Cloud microservices, Resilience4j circuit breaker, Feign clients |
| `jvm-performance.md` | 620 | JVM memory model, GC tuning (G1/ZGC), JVM flags reference, JFR profiling, HikariCP tuning, performance anti-patterns, JMH benchmarking, Docker/K8s JVM settings, GraalVM native image |
| `testing-patterns.md` | 945 | JUnit 5 patterns, Mockito, Spring test slices (@WebMvcTest/@DataJpaTest), Testcontainers, REST API testing (RestAssured/WebTestClient), security testing, ArchUnit, test fixtures/builders |

### Scripts

| File | Lines | Description |
|------|-------|-------------|
| `maven-build.sh` | 199 | Smart Maven build with modes: `--quick` (compile+test), `--full` (integration tests+analysis), `--release` (deploy), `--docker` (image build+push) |
| `spring-app-generator.sh` | 464 | Generate production-ready Spring Boot project from Spring Initializr with layered architecture, exception handler, Docker, Flyway migrations, GitHub Actions CI |

## Tags

`java` `spring-boot` `microservices` `jvm` `maven` `gradle` `junit` `hibernate` `spring-security` `design-patterns`

## Quick Start

```bash
# Install with BoxClaw CLI
npx boxclaw install skill senior-java-developer

# Or manual install
git clone https://github.com/boxclawai/skills.git
cp -r skills/senior-java-developer .skills/
```

## Part of [BoxClaw Skills](https://github.com/boxclawai/skills)
