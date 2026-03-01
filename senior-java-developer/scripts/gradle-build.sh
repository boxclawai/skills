#!/usr/bin/env bash
# gradle-build.sh — Smart Gradle build with quality checks
# Usage: ./gradle-build.sh [--quick] [--full] [--docker] [--native]
#
# Modes:
#   --quick    Compile + unit tests only (fastest)
#   --full     Full build with integration tests + coverage (default)
#   --docker   Full build + Docker image build
#   --native   Build GraalVM native image (requires GraalVM)
#
# Requirements:
#   - Java 17+ (JAVA_HOME set)
#   - Gradle wrapper (gradlew) in project root
#   - Docker (for --docker mode)
#   - GraalVM (for --native mode)

set -euo pipefail

MODE="full"
SKIP_TESTS=false
PROFILE="default"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)      MODE="quick"; shift ;;
    --full)       MODE="full"; shift ;;
    --docker)     MODE="docker"; shift ;;
    --native)     MODE="native"; shift ;;
    --skip-tests) SKIP_TESTS=true; shift ;;
    --profile)    PROFILE="$2"; shift 2 ;;
    --tag)        DOCKER_TAG="$2"; shift 2 ;;
    --registry)   DOCKER_REGISTRY="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Detect Gradle wrapper
if [[ -f "./gradlew" ]]; then
  GRADLE="./gradlew"
elif command -v gradle &>/dev/null; then
  GRADLE="gradle"
else
  echo "ERROR: Gradle not found. Add gradlew wrapper or install Gradle."
  exit 1
fi

# Detect project info
PROJECT_NAME=$(${GRADLE} -q properties 2>/dev/null | grep "^name:" | awk '{print $2}' || echo "unknown")
PROJECT_VERSION=$(${GRADLE} -q properties 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "0.0.0")

echo "=== Gradle Build ==="
echo "Project:  ${PROJECT_NAME}"
echo "Version:  ${PROJECT_VERSION}"
echo "Mode:     ${MODE}"
echo "Java:     $(java -version 2>&1 | head -1)"
echo "Gradle:   $(${GRADLE} --version 2>/dev/null | grep "^Gradle" || echo "unknown")"
echo ""

# ── Quick Mode ──
if [[ "$MODE" == "quick" ]]; then
  echo "--- Quick Build: compile + unit tests ---"

  if [[ "$SKIP_TESTS" == "true" ]]; then
    ${GRADLE} classes -q
    echo "Compiled (tests skipped)"
  else
    ${GRADLE} test -q
    echo "Compiled + unit tests passed"
  fi

  # Print test summary
  TEST_REPORT="build/reports/tests/test/index.html"
  if [[ -f "$TEST_REPORT" ]]; then
    echo "  Report: ${TEST_REPORT}"
  fi

  echo ""
  echo "Done (quick mode)"
  exit 0
fi

# ── Full Mode ──
echo "--- Step 1/4: Clean + Compile ---"
${GRADLE} clean classes -q
echo "Compiled successfully"
echo ""

echo "--- Step 2/4: Unit Tests ---"
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "Skipped (--skip-tests)"
else
  ${GRADLE} test -q
  echo "Unit tests passed"

  # Test results summary
  TEST_XML_DIR="build/test-results/test"
  if [[ -d "$TEST_XML_DIR" ]]; then
    TOTAL=$(find "$TEST_XML_DIR" -name "*.xml" | wc -l | tr -d ' ')
    echo "  Test suites: ${TOTAL}"
  fi
fi
echo ""

echo "--- Step 3/4: Integration Tests ---"
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "Skipped (--skip-tests)"
else
  # Try integrationTest task, fall back to check
  if ${GRADLE} tasks --all -q 2>/dev/null | grep -q "integrationTest"; then
    ${GRADLE} integrationTest -q
    echo "Integration tests passed"
  else
    ${GRADLE} check -q
    echo "All checks passed"
  fi
fi
echo ""

echo "--- Step 4/4: Package ---"
if [[ "$SKIP_TESTS" == "true" ]]; then
  ${GRADLE} bootJar -x test -q
else
  ${GRADLE} bootJar -q
fi
echo "Packaged successfully"

# Show artifact info
JAR_FILE=$(find build/libs -maxdepth 1 -name "*.jar" ! -name "*-plain*" 2>/dev/null | head -1)
if [[ -n "$JAR_FILE" ]]; then
  JAR_SIZE=$(du -h "$JAR_FILE" | cut -f1)
  echo "  Artifact: ${JAR_FILE} (${JAR_SIZE})"
fi
echo ""

# ── Coverage Report ──
if [[ "$SKIP_TESTS" != "true" ]]; then
  echo "--- Coverage Report ---"
  if ${GRADLE} tasks --all -q 2>/dev/null | grep -q "jacocoTestReport"; then
    ${GRADLE} jacocoTestReport -q
    COVERAGE_REPORT="build/reports/jacoco/test/html/index.html"
    if [[ -f "$COVERAGE_REPORT" ]]; then
      echo "  Report: ${COVERAGE_REPORT}"
    fi
  else
    echo "  JaCoCo not configured (add jacoco plugin for coverage)"
  fi
  echo ""
fi

# ── Docker Mode ──
if [[ "$MODE" == "docker" ]]; then
  echo "--- Docker: Build Image ---"

  if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found"
    exit 1
  fi

  IMAGE_NAME="${PROJECT_NAME}"
  if [[ -n "$DOCKER_REGISTRY" ]]; then
    IMAGE_NAME="${DOCKER_REGISTRY}/${PROJECT_NAME}"
  fi

  if [[ -f "Dockerfile" ]]; then
    docker build \
      -t "${IMAGE_NAME}:${DOCKER_TAG}" \
      -t "${IMAGE_NAME}:${PROJECT_VERSION}" \
      .
  else
    # Use Spring Boot buildpacks (no Dockerfile needed)
    ${GRADLE} bootBuildImage \
      --imageName="${IMAGE_NAME}:${DOCKER_TAG}" \
      -q
  fi

  echo "Built image: ${IMAGE_NAME}:${DOCKER_TAG}"

  if [[ -n "$DOCKER_REGISTRY" ]]; then
    echo ""
    echo "--- Docker: Push ---"
    docker push "${IMAGE_NAME}:${DOCKER_TAG}"
    docker push "${IMAGE_NAME}:${PROJECT_VERSION}"
    echo "Pushed to ${DOCKER_REGISTRY}"
  fi
  echo ""
fi

# ── Native Mode (GraalVM) ──
if [[ "$MODE" == "native" ]]; then
  echo "--- GraalVM Native Image ---"

  if ! java -version 2>&1 | grep -qi "graalvm"; then
    echo "WARNING: GraalVM not detected. Native build may fail."
  fi

  ${GRADLE} nativeCompile -q
  NATIVE_BIN=$(find build/native/nativeCompile -maxdepth 1 -type f -executable 2>/dev/null | head -1)

  if [[ -n "$NATIVE_BIN" ]]; then
    NATIVE_SIZE=$(du -h "$NATIVE_BIN" | cut -f1)
    echo "Binary: ${NATIVE_BIN} (${NATIVE_SIZE})"
    echo ""
    echo "Run with: ${NATIVE_BIN}"
  else
    echo "ERROR: Native binary not found"
    exit 1
  fi
  echo ""
fi

# ── Dependency check ──
echo "--- Dependency Summary ---"
OUTDATED=$(${GRADLE} dependencyUpdates -q 2>/dev/null | grep -c "available" || true)
if [[ "$OUTDATED" -gt 0 ]]; then
  echo "  Dependencies with available updates: ${OUTDATED}"
  echo "  Run: ./gradlew dependencyUpdates"
else
  echo "  All dependencies up to date"
fi
echo ""

echo "=== Build Complete ==="
echo "Project:  ${PROJECT_NAME}:${PROJECT_VERSION}"
echo "Artifact: ${JAR_FILE:-N/A}"
echo ""
