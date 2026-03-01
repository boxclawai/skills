#!/usr/bin/env bash
# spring-app-generator.sh — Generate Spring Boot project with best practices
# Usage: ./spring-app-generator.sh <project-name> [--group com.example] [--java 21] [--deps web,jpa,security]
#
# Generates a production-ready Spring Boot project with:
#   - Clean layered architecture (controller/service/repository/model)
#   - Global exception handler with ProblemDetail
#   - Base entity with auditing
#   - Docker + docker-compose setup
#   - Flyway migration templates
#   - application.yml with profiles (dev/prod/test)
#   - GitHub Actions CI pipeline
#   - Dockerfile with multi-stage build
#
# Requirements:
#   - curl (to download from start.spring.io)
#   - unzip

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <project-name> [--group com.example] [--java 21] [--deps web,jpa,security]"
  echo ""
  echo "Options:"
  echo "  --group    Group ID (default: com.example)"
  echo "  --java     Java version: 17 or 21 (default: 21)"
  echo "  --deps     Spring Initializr dependencies (default: web,jpa,validation,actuator,flyway,postgresql,lombok)"
  echo "  --boot     Spring Boot version (default: 3.4.0)"
  exit 1
fi

PROJECT_NAME="$1"
shift

GROUP_ID="com.example"
JAVA_VERSION="21"
BOOT_VERSION="3.4.0"
DEPS="web,data-jpa,validation,actuator,flyway,postgresql,lombok,devtools,testcontainers"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group) GROUP_ID="$2"; shift 2 ;;
    --java)  JAVA_VERSION="$2"; shift 2 ;;
    --deps)  DEPS="$2"; shift 2 ;;
    --boot)  BOOT_VERSION="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ARTIFACT_ID="${PROJECT_NAME}"
BASE_PACKAGE="${GROUP_ID}.${PROJECT_NAME//-/}"

echo "=== Spring Boot Project Generator ==="
echo "Project:    ${PROJECT_NAME}"
echo "Group:      ${GROUP_ID}"
echo "Package:    ${BASE_PACKAGE}"
echo "Java:       ${JAVA_VERSION}"
echo "Boot:       ${BOOT_VERSION}"
echo "Deps:       ${DEPS}"
echo ""

# ── Step 1: Download from Spring Initializr ──
echo "--- Downloading from start.spring.io ---"
curl -sL "https://start.spring.io/starter.zip?\
type=maven-project&\
language=java&\
bootVersion=${BOOT_VERSION}&\
groupId=${GROUP_ID}&\
artifactId=${ARTIFACT_ID}&\
name=${PROJECT_NAME}&\
packageName=${BASE_PACKAGE}&\
javaVersion=${JAVA_VERSION}&\
dependencies=${DEPS}" -o "${PROJECT_NAME}.zip"

unzip -q "${PROJECT_NAME}.zip" -d "${PROJECT_NAME}"
rm "${PROJECT_NAME}.zip"
echo "Downloaded and extracted"
echo ""

cd "${PROJECT_NAME}"
PACKAGE_PATH="src/main/java/${BASE_PACKAGE//./\/}"
TEST_PACKAGE_PATH="src/test/java/${BASE_PACKAGE//./\/}"

# ── Step 2: Create package structure ──
echo "--- Creating package structure ---"
for dir in controller service repository model/entity model/dto model/mapper exception config security util; do
  mkdir -p "${PACKAGE_PATH}/${dir}"
done
mkdir -p "src/main/resources/db/migration"
mkdir -p "src/test/resources"
echo "Created layered architecture packages"
echo ""

# ── Step 3: Generate base classes ──
echo "--- Generating base classes ---"

# Base Entity
cat > "${PACKAGE_PATH}/model/entity/BaseEntity.java" << JAVA
package ${BASE_PACKAGE}.model.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.springframework.data.annotation.CreatedBy;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedBy;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.Instant;

@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter
@Setter
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @Version
    private Long version;
}
JAVA

# Global Exception Handler
cat > "${PACKAGE_PATH}/exception/GlobalExceptionHandler.java" << JAVA
package ${BASE_PACKAGE}.exception;

import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import java.util.Map;
import java.util.stream.Collectors;

@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource Not Found");
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
JAVA

# ResourceNotFoundException
cat > "${PACKAGE_PATH}/exception/ResourceNotFoundException.java" << JAVA
package ${BASE_PACKAGE}.exception;

public class ResourceNotFoundException extends RuntimeException {

    public ResourceNotFoundException(String resource, Object id) {
        super(String.format("%s with id %s not found", resource, id));
    }
}
JAVA

# JPA Auditing Config
cat > "${PACKAGE_PATH}/config/JpaConfig.java" << JAVA
package ${BASE_PACKAGE}.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@Configuration
@EnableJpaAuditing
public class JpaConfig {
}
JAVA

echo "Generated: BaseEntity, GlobalExceptionHandler, ResourceNotFoundException, JpaConfig"

# ── Step 4: Application configuration ──
echo "--- Generating application configuration ---"

cat > "src/main/resources/application.yml" << YAML
spring:
  application:
    name: ${PROJECT_NAME}
  datasource:
    url: \${DATABASE_URL:jdbc:postgresql://localhost:5432/${PROJECT_NAME//-/_}}
    username: \${DATABASE_USER:postgres}
    password: \${DATABASE_PASSWORD:postgres}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
  jpa:
    open-in-view: false
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        default_batch_fetch_size: 20
        jdbc.batch_size: 50
  flyway:
    enabled: true
    locations: classpath:db/migration

server:
  port: \${PORT:8080}
  compression:
    enabled: true
    min-response-size: 1024

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized

logging:
  level:
    root: INFO
    ${BASE_PACKAGE}: INFO
YAML

cat > "src/main/resources/application-dev.yml" << YAML
spring:
  datasource:
    url: jdbc:h2:mem:devdb
    driver-class-name: org.h2.Driver
  jpa:
    hibernate:
      ddl-auto: create-drop
    show-sql: true
  h2:
    console:
      enabled: true
  flyway:
    enabled: false

logging:
  level:
    ${BASE_PACKAGE}: DEBUG
    org.hibernate.SQL: DEBUG
YAML

cat > "src/test/resources/application-test.yml" << YAML
spring:
  jpa:
    show-sql: true
  flyway:
    clean-on-validation-error: true

logging:
  level:
    ${BASE_PACKAGE}: DEBUG
YAML

echo "Generated: application.yml, application-dev.yml, application-test.yml"

# ── Step 5: Flyway migration template ──
cat > "src/main/resources/db/migration/V1__initial_schema.sql" << SQL
-- Initial schema for ${PROJECT_NAME}
-- Add your tables here

-- Example:
-- CREATE TABLE users (
--     id         BIGSERIAL PRIMARY KEY,
--     email      VARCHAR(255) NOT NULL UNIQUE,
--     name       VARCHAR(255) NOT NULL,
--     created_at TIMESTAMP NOT NULL DEFAULT NOW(),
--     updated_at TIMESTAMP,
--     version    BIGINT NOT NULL DEFAULT 0
-- );
SQL

echo "Generated: V1__initial_schema.sql migration template"

# ── Step 6: Dockerfile ──
echo "--- Generating Docker configuration ---"

cat > "Dockerfile" << DOCKER
# Multi-stage build
FROM eclipse-temurin:${JAVA_VERSION}-jdk-alpine AS build
WORKDIR /app
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline -q
COPY src/ src/
RUN ./mvnw clean package -DskipTests -q

FROM eclipse-temurin:${JAVA_VERSION}-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
USER app
COPY --from=build /app/target/*.jar app.jar

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \\
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["sh", "-c", "java \$JAVA_OPTS -jar app.jar"]
DOCKER

cat > "docker-compose.yml" << COMPOSE
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - DATABASE_URL=jdbc:postgresql://db:5432/${PROJECT_NAME//-/_}
      - DATABASE_USER=postgres
      - DATABASE_PASSWORD=postgres
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: ${PROJECT_NAME//-/_}
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
COMPOSE

cat > ".dockerignore" << IGNORE
target/
.git/
.idea/
*.iml
.vscode/
*.md
IGNORE

echo "Generated: Dockerfile, docker-compose.yml, .dockerignore"

# ── Step 7: GitHub Actions CI ──
echo "--- Generating CI pipeline ---"
mkdir -p ".github/workflows"

cat > ".github/workflows/ci.yml" << 'WORKFLOW'
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'

      - name: Build & Test
        run: ./mvnw clean verify
        env:
          DATABASE_URL: jdbc:postgresql://localhost:5432/testdb
          DATABASE_USER: test
          DATABASE_PASSWORD: test

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: target/surefire-reports/
WORKFLOW

echo "Generated: .github/workflows/ci.yml"

# ── Step 8: Add useful .gitignore entries ──
cat >> ".gitignore" << GIT

# IDE
.idea/
*.iml
.vscode/
*.swp

# Docker
docker-compose.override.yml

# Env
.env
.env.local
GIT

echo ""
echo "=== Project Generated Successfully ==="
echo ""
echo "  cd ${PROJECT_NAME}"
echo ""
echo "  # Development mode (H2 in-memory DB)"
echo "  ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev"
echo ""
echo "  # With Docker Compose (PostgreSQL)"
echo "  docker compose up -d db"
echo "  ./mvnw spring-boot:run"
echo ""
echo "  # Full Docker stack"
echo "  docker compose up --build"
echo ""
echo "  # Run tests"
echo "  ./mvnw clean verify"
echo ""
