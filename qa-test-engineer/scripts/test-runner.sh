#!/usr/bin/env bash
# test-runner.sh - Comprehensive test runner with coverage and reporting
# Usage: ./test-runner.sh [--type unit|integration|e2e|all] [--coverage] [--watch] [--ci]
#
# Features:
#   - Runs different test types
#   - Generates coverage reports
#   - CI-friendly output (JUnit XML, coverage badges)
#   - Flaky test detection (re-run failures)

set -euo pipefail

TEST_TYPE="all"
COVERAGE=false
WATCH=false
CI=false
RETRY_FLAKY=false
FLAKY_RETRIES=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TEST_TYPE="$2"; shift 2 ;;
    --coverage) COVERAGE=true; shift ;;
    --watch) WATCH=true; shift ;;
    --ci) CI=true; COVERAGE=true; RETRY_FLAKY=true; shift ;;
    --retry-flaky) RETRY_FLAKY=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

echo "======================================"
echo "  Test Runner"
echo "======================================"
echo "  Type:     $TEST_TYPE"
echo "  Coverage: $COVERAGE"
echo "  CI Mode:  $CI"
echo "======================================"
echo ""

# Detect test framework
detect_framework() {
  if [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]]; then
    echo "vitest"
  elif grep -q '"jest"' package.json 2>/dev/null; then
    echo "jest"
  elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
    echo "pytest"
  else
    echo "vitest" # default
  fi
}

FRAMEWORK=$(detect_framework)
echo "Test framework: $FRAMEWORK"
echo ""

OVERALL_EXIT=0
RESULTS=()

run_tests() {
  local TYPE="$1"
  local LABEL="$2"
  local EXIT_CODE=0

  echo "--- $LABEL ---"
  local START_TIME=$(date +%s)

  case "$FRAMEWORK" in
    vitest)
      local CMD="npx vitest run"
      case "$TYPE" in
        unit)        CMD="$CMD --config vitest.config.ts" ;;
        integration) CMD="$CMD --config vitest.integration.config.ts 2>/dev/null || $CMD --dir src/__tests__/integration" ;;
        e2e)         CMD="npx playwright test" ;;
      esac

      if [[ "$COVERAGE" == true ]] && [[ "$TYPE" != "e2e" ]]; then
        CMD="$CMD --coverage"
      fi

      if [[ "$CI" == true ]] && [[ "$TYPE" != "e2e" ]]; then
        CMD="$CMD --reporter=junit --outputFile=test-results/${TYPE}-results.xml"
      fi

      if [[ "$WATCH" == true ]] && [[ "$TYPE" != "e2e" ]]; then
        CMD="npx vitest --config vitest.config.ts"
      fi

      eval "$CMD" || EXIT_CODE=$?
      ;;

    jest)
      local CMD="npx jest"
      case "$TYPE" in
        unit)        CMD="$CMD --testPathPattern='.*\\.test\\.(ts|js)x?$' --testPathIgnorePatterns='integration|e2e'" ;;
        integration) CMD="$CMD --testPathPattern='integration'" ;;
        e2e)         CMD="npx playwright test" ;;
      esac

      if [[ "$COVERAGE" == true ]] && [[ "$TYPE" != "e2e" ]]; then
        CMD="$CMD --coverage"
      fi

      if [[ "$CI" == true ]] && [[ "$TYPE" != "e2e" ]]; then
        CMD="$CMD --reporters=default --reporters=jest-junit"
        export JEST_JUNIT_OUTPUT_DIR="test-results"
      fi

      eval "$CMD" || EXIT_CODE=$?
      ;;

    pytest)
      local CMD="python -m pytest"
      case "$TYPE" in
        unit)        CMD="$CMD tests/unit/" ;;
        integration) CMD="$CMD tests/integration/" ;;
        e2e)         CMD="$CMD tests/e2e/" ;;
      esac

      if [[ "$COVERAGE" == true ]]; then
        CMD="$CMD --cov=src --cov-report=html:coverage/${TYPE}"
      fi

      if [[ "$CI" == true ]]; then
        CMD="$CMD --junitxml=test-results/${TYPE}-results.xml"
      fi

      eval "$CMD" || EXIT_CODE=$?
      ;;
  esac

  # Retry flaky tests
  if [[ "$EXIT_CODE" -ne 0 ]] && [[ "$RETRY_FLAKY" == true ]] && [[ "$TYPE" != "e2e" ]]; then
    echo ""
    echo "Tests failed. Retrying $FLAKY_RETRIES time(s) to detect flaky tests..."
    for i in $(seq 1 "$FLAKY_RETRIES"); do
      echo "  Retry $i/$FLAKY_RETRIES..."
      eval "$CMD" && { EXIT_CODE=0; echo "  Passed on retry $i (FLAKY TEST DETECTED)"; break; } || true
    done
  fi

  local DURATION=$(( $(date +%s) - START_TIME ))
  local STATUS="PASS"
  [[ "$EXIT_CODE" -ne 0 ]] && STATUS="FAIL" && OVERALL_EXIT=1

  RESULTS+=("$LABEL|$STATUS|${DURATION}s")
  echo ""
  return "$EXIT_CODE" || true
}

# Create output directories
[[ "$CI" == true ]] && mkdir -p test-results

# Run tests based on type
case "$TEST_TYPE" in
  unit)
    run_tests "unit" "Unit Tests"
    ;;
  integration)
    run_tests "integration" "Integration Tests"
    ;;
  e2e)
    run_tests "e2e" "E2E Tests"
    ;;
  all)
    run_tests "unit" "Unit Tests" || true
    run_tests "integration" "Integration Tests" || true
    run_tests "e2e" "E2E Tests" || true
    ;;
esac

# Summary
echo "======================================"
echo "  Test Summary"
echo "======================================"
for result in "${RESULTS[@]}"; do
  IFS='|' read -r LABEL STATUS DURATION <<< "$result"
  ICON="✅"
  [[ "$STATUS" == "FAIL" ]] && ICON="❌"
  printf "  %s %-25s %s (%s)\n" "$ICON" "$LABEL" "$STATUS" "$DURATION"
done
echo "======================================"

# Coverage summary
if [[ "$COVERAGE" == true ]]; then
  echo ""
  echo "Coverage reports:"
  [[ -d "coverage" ]] && echo "  HTML: coverage/index.html"
  [[ -f "coverage/coverage-summary.json" ]] && {
    node -e "
      const c = require('./coverage/coverage-summary.json').total;
      console.log('  Lines:      ' + c.lines.pct + '%');
      console.log('  Functions:  ' + c.functions.pct + '%');
      console.log('  Branches:   ' + c.branches.pct + '%');
      console.log('  Statements: ' + c.statements.pct + '%');
    " 2>/dev/null || true
  }
fi

exit "$OVERALL_EXIT"
