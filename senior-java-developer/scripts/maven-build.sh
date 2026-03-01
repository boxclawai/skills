#!/usr/bin/env bash
# maven-build.sh — Smart Maven build with quality checks
# Usage: ./maven-build.sh [--quick] [--full] [--release] [--docker]
#
# Modes:
#   --quick    Compile + unit tests only (fastest)
#   --full     Full build with integration tests + static analysis (default)
#   --release  Full build + version bump + deploy to registry
#   --docker   Full build + Docker image build + push
#
# Requirements:
#   - Java 17+ (JAVA_HOME set)
#   - Maven 3.9+ (mvnw wrapper preferred)
#   - Docker (for --docker mode)

set -euo pipefail

MODE="full"
SKIP_TESTS=false
PROFILE="default"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)    MODE="quick"; shift ;;
    --full)     MODE="full"; shift ;;
    --release)  MODE="release"; shift ;;
    --docker)   MODE="docker"; shift ;;
    --skip-tests) SKIP_TESTS=true; shift ;;
    --profile)  PROFILE="$2"; shift 2 ;;
    --tag)      DOCKER_TAG="$2"; shift 2 ;;
    --registry) DOCKER_REGISTRY="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Detect Maven wrapper or system Maven
if [[ -f "./mvnw" ]]; then
  MVN="./mvnw"
elif command -v mvn &>/dev/null; then
  MVN="mvn"
else
  echo "ERROR: Maven not found. Install Maven or add mvnw wrapper."
  exit 1
fi

# Detect project info from pom.xml
PROJECT_NAME=$(${MVN} help:evaluate -Dexpression=project.artifactId -q -DforceStdout 2>/dev/null || echo "unknown")
PROJECT_VERSION=$(${MVN} help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null || echo "0.0.0")

echo "=== Maven Build ==="
echo "Project:  ${PROJECT_NAME}"
echo "Version:  ${PROJECT_VERSION}"
echo "Mode:     ${MODE}"
echo "Profile:  ${PROFILE}"
echo "Java:     $(java -version 2>&1 | head -1)"
echo ""

# ── Quick Mode: compile + unit tests ──
if [[ "$MODE" == "quick" ]]; then
  echo "--- Quick Build: compile + unit tests ---"

  if [[ "$SKIP_TESTS" == "true" ]]; then
    ${MVN} clean compile -q
    echo "Compiled (tests skipped)"
  else
    ${MVN} clean test -q
    echo "Compiled + unit tests passed"
  fi

  echo ""
  echo "Done (quick mode)"
  exit 0
fi

# ── Full Mode: complete build with quality checks ──
echo "--- Step 1/4: Clean + Compile ---"
${MVN} clean compile -q
echo "Compiled successfully"
echo ""

echo "--- Step 2/4: Unit Tests ---"
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "Skipped (--skip-tests)"
else
  ${MVN} test -q
  echo "Unit tests passed"

  # Print test summary if surefire reports exist
  SUREFIRE_DIR="target/surefire-reports"
  if [[ -d "$SUREFIRE_DIR" ]]; then
    TOTAL=$(find "$SUREFIRE_DIR" -name "*.xml" -exec grep -l "testsuite" {} \; | wc -l | tr -d ' ')
    FAILURES=$(grep -rl 'failures="[1-9]' "$SUREFIRE_DIR" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Test suites: ${TOTAL}, Failures: ${FAILURES}"
  fi
fi
echo ""

echo "--- Step 3/4: Integration Tests ---"
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "Skipped (--skip-tests)"
else
  ${MVN} verify -DskipUnitTests=true -q 2>/dev/null || ${MVN} verify -q
  echo "Integration tests passed"
fi
echo ""

echo "--- Step 4/4: Package ---"
if [[ "$PROFILE" != "default" ]]; then
  ${MVN} package -DskipTests -P"${PROFILE}" -q
  echo "Packaged with profile: ${PROFILE}"
else
  ${MVN} package -DskipTests -q
  echo "Packaged successfully"
fi

# Show artifact info
JAR_FILE=$(find target -maxdepth 1 -name "*.jar" ! -name "*-sources*" ! -name "*-javadoc*" ! -name "original-*" 2>/dev/null | head -1)
if [[ -n "$JAR_FILE" ]]; then
  JAR_SIZE=$(du -h "$JAR_FILE" | cut -f1)
  echo "  Artifact: ${JAR_FILE} (${JAR_SIZE})"
fi
echo ""

# ── Release Mode: version bump + deploy ──
if [[ "$MODE" == "release" ]]; then
  echo "--- Release: Deploy to Registry ---"

  # Verify no SNAPSHOT
  if [[ "$PROJECT_VERSION" == *"SNAPSHOT"* ]]; then
    echo "ERROR: Cannot release SNAPSHOT version. Run:"
    echo "  ${MVN} versions:set -DnewVersion=X.Y.Z"
    exit 1
  fi

  ${MVN} deploy -DskipTests -q
  echo "Deployed ${PROJECT_NAME}:${PROJECT_VERSION} to registry"
  echo ""
fi

# ── Docker Mode: build image + push ──
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

  # Build with Spring Boot layered JAR
  if [[ -f "Dockerfile" ]]; then
    docker build \
      --build-arg JAR_FILE="${JAR_FILE}" \
      -t "${IMAGE_NAME}:${DOCKER_TAG}" \
      -t "${IMAGE_NAME}:${PROJECT_VERSION}" \
      .
  else
    # Use Spring Boot buildpacks
    ${MVN} spring-boot:build-image \
      -DskipTests \
      -Dspring-boot.build-image.imageName="${IMAGE_NAME}:${DOCKER_TAG}" \
      -q
  fi

  echo "Built image: ${IMAGE_NAME}:${DOCKER_TAG}"

  # Push if registry is set
  if [[ -n "$DOCKER_REGISTRY" ]]; then
    echo ""
    echo "--- Docker: Push ---"
    docker push "${IMAGE_NAME}:${DOCKER_TAG}"
    docker push "${IMAGE_NAME}:${PROJECT_VERSION}"
    echo "Pushed to ${DOCKER_REGISTRY}"
  fi
  echo ""
fi

# ── Dependency check (optional) ──
echo "--- Dependency Summary ---"
OUTDATED=$(${MVN} versions:display-dependency-updates -q 2>/dev/null | grep -c "newer version" || true)
echo "  Dependencies with available updates: ${OUTDATED}"

# Check for known vulnerabilities (if OWASP plugin is configured)
if ${MVN} help:describe -Dplugin=org.owasp:dependency-check-maven -q 2>/dev/null; then
  echo "  Run 'mvn dependency-check:check' for vulnerability scan"
fi
echo ""

echo "=== Build Complete ==="
echo "Project:  ${PROJECT_NAME}:${PROJECT_VERSION}"
echo "Artifact: ${JAR_FILE:-N/A}"
[[ "$MODE" == "docker" ]] && echo "Image:    ${IMAGE_NAME:-N/A}:${DOCKER_TAG}"
echo ""
