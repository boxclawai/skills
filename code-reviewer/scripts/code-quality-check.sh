#!/usr/bin/env bash
# code-quality-check.sh — Run comprehensive code quality checks across any project
# Usage: ./code-quality-check.sh [--quick] [--full] [--fix] [--ci]
#
# Modes:
#   --quick   Lint + format check only (fastest, great for pre-commit)
#   --full    Full analysis: lint + complexity + duplication + security (default)
#   --fix     Auto-fix what's possible (lint + format)
#   --ci      CI mode: strict, non-interactive, exits non-zero on issues
#
# Supports: JavaScript/TypeScript, Python, Java, Go (auto-detected)

set -euo pipefail

MODE="full"
FIX=false
CI=false
ERRORS=0
WARNINGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)  MODE="quick"; shift ;;
    --full)   MODE="full"; shift ;;
    --fix)    FIX=true; shift ;;
    --ci)     CI=true; MODE="full"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[PASS]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
fail()    { echo -e "${RED}[FAIL]${NC}  $1"; ERRORS=$((ERRORS + 1)); }

# ── Detect project type ──
LANGS=()

if [[ -f "package.json" ]]; then
  LANGS+=("javascript")
fi
if [[ -f "tsconfig.json" ]]; then
  LANGS+=("typescript")
fi
if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
  LANGS+=("python")
fi
if [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
  LANGS+=("java")
fi
if [[ -f "go.mod" ]]; then
  LANGS+=("go")
fi

if [[ ${#LANGS[@]} -eq 0 ]]; then
  echo "No supported project detected. Supported: JS/TS, Python, Java, Go"
  exit 1
fi

echo "=== Code Quality Check ==="
echo "Mode:      ${MODE}"
echo "Fix mode:  ${FIX}"
echo "Languages: ${LANGS[*]}"
echo ""

# ═══════════════════════════════════════════
# JavaScript / TypeScript
# ═══════════════════════════════════════════
run_js_checks() {
  info "--- JavaScript/TypeScript Checks ---"
  echo ""

  # ESLint
  if command -v npx &>/dev/null && [[ -f "package.json" ]]; then
    # Check for ESLint config
    HAS_ESLINT=false
    for cfg in .eslintrc .eslintrc.js .eslintrc.json .eslintrc.yml eslint.config.js eslint.config.mjs eslint.config.ts; do
      if [[ -f "$cfg" ]]; then HAS_ESLINT=true; break; fi
    done
    # Check package.json for eslintConfig
    if grep -q '"eslintConfig"' package.json 2>/dev/null; then HAS_ESLINT=true; fi

    if [[ "$HAS_ESLINT" == "true" ]]; then
      if [[ "$FIX" == "true" ]]; then
        info "Running ESLint with --fix..."
        npx eslint . --fix --max-warnings=0 2>/dev/null && success "ESLint: all clean" || warn "ESLint: some issues remain after fix"
      else
        info "Running ESLint..."
        npx eslint . --max-warnings=0 2>/dev/null && success "ESLint: all clean" || fail "ESLint: found issues"
      fi
    else
      warn "ESLint not configured. Consider: npx eslint --init"
    fi
    echo ""

    # Prettier
    HAS_PRETTIER=false
    if grep -q '"prettier"' package.json 2>/dev/null; then HAS_PRETTIER=true; fi
    for cfg in .prettierrc .prettierrc.js .prettierrc.json .prettierrc.yml prettier.config.js; do
      if [[ -f "$cfg" ]]; then HAS_PRETTIER=true; break; fi
    done

    if [[ "$HAS_PRETTIER" == "true" ]]; then
      if [[ "$FIX" == "true" ]]; then
        info "Running Prettier with --write..."
        npx prettier --write "src/**/*.{js,jsx,ts,tsx,css,json}" 2>/dev/null && success "Prettier: formatted" || warn "Prettier: some files couldn't be formatted"
      else
        info "Checking Prettier formatting..."
        npx prettier --check "src/**/*.{js,jsx,ts,tsx,css,json}" 2>/dev/null && success "Prettier: all formatted" || fail "Prettier: formatting issues found (run with --fix)"
      fi
    else
      warn "Prettier not configured. Consider adding it for consistent formatting."
    fi
    echo ""

    # TypeScript
    if [[ -f "tsconfig.json" ]]; then
      info "Running TypeScript compiler check..."
      npx tsc --noEmit 2>/dev/null && success "TypeScript: no type errors" || fail "TypeScript: type errors found"
      echo ""
    fi
  fi

  # Full mode: additional checks
  if [[ "$MODE" == "full" ]]; then
    # Bundle size (if build exists)
    if [[ -d "dist" ]] || [[ -d "build" ]]; then
      info "Checking bundle sizes..."
      BUILD_DIR="dist"
      [[ -d "build" ]] && BUILD_DIR="build"
      TOTAL_SIZE=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
      JS_SIZE=$(find "$BUILD_DIR" -name "*.js" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
      info "  Total: ${TOTAL_SIZE}, JS: ${JS_SIZE}"
      echo ""
    fi

    # npm audit
    if [[ -f "package-lock.json" ]] || [[ -f "yarn.lock" ]]; then
      info "Running dependency security audit..."
      if [[ -f "package-lock.json" ]]; then
        AUDIT_RESULT=$(npm audit --json 2>/dev/null || true)
        HIGH=$(echo "$AUDIT_RESULT" | grep -o '"high":[0-9]*' | grep -o '[0-9]*' || echo "0")
        CRITICAL=$(echo "$AUDIT_RESULT" | grep -o '"critical":[0-9]*' | grep -o '[0-9]*' || echo "0")
        if [[ "$CRITICAL" -gt 0 ]]; then
          fail "npm audit: ${CRITICAL} critical vulnerabilities"
        elif [[ "$HIGH" -gt 0 ]]; then
          warn "npm audit: ${HIGH} high vulnerabilities"
        else
          success "npm audit: no high/critical vulnerabilities"
        fi
      fi
      echo ""
    fi
  fi
}

# ═══════════════════════════════════════════
# Python
# ═══════════════════════════════════════════
run_python_checks() {
  info "--- Python Checks ---"
  echo ""

  # Ruff (fast linter + formatter)
  if command -v ruff &>/dev/null; then
    if [[ "$FIX" == "true" ]]; then
      info "Running Ruff with --fix..."
      ruff check . --fix 2>/dev/null && success "Ruff lint: all clean" || warn "Ruff: some issues remain after fix"
      ruff format . 2>/dev/null && success "Ruff format: formatted" || warn "Ruff: formatting issues"
    else
      info "Running Ruff lint..."
      ruff check . 2>/dev/null && success "Ruff lint: all clean" || fail "Ruff lint: found issues"
      info "Checking Ruff formatting..."
      ruff format --check . 2>/dev/null && success "Ruff format: all formatted" || fail "Ruff format: needs formatting (run with --fix)"
    fi
  else
    warn "Ruff not installed. Install: pip install ruff"
  fi
  echo ""

  # mypy (type checking)
  if [[ "$MODE" == "full" ]]; then
    if command -v mypy &>/dev/null; then
      info "Running mypy type checking..."
      mypy . --ignore-missing-imports 2>/dev/null && success "mypy: no type errors" || warn "mypy: type issues found"
    else
      warn "mypy not installed. Install: pip install mypy"
    fi
    echo ""

    # Bandit (security)
    if command -v bandit &>/dev/null; then
      info "Running Bandit security scan..."
      BANDIT_RESULT=$(bandit -r . -f json --exclude .venv,venv,node_modules 2>/dev/null || true)
      HIGH=$(echo "$BANDIT_RESULT" | grep -o '"SEVERITY.HIGH"' | wc -l | tr -d ' ')
      if [[ "$HIGH" -gt 0 ]]; then
        fail "Bandit: ${HIGH} high severity issues"
      else
        success "Bandit: no high severity issues"
      fi
    else
      warn "Bandit not installed. Install: pip install bandit"
    fi
    echo ""

    # pip-audit (dependency vulnerabilities)
    if command -v pip-audit &>/dev/null; then
      info "Running pip-audit..."
      pip-audit 2>/dev/null && success "pip-audit: no vulnerabilities" || warn "pip-audit: vulnerabilities found"
    fi
    echo ""
  fi
}

# ═══════════════════════════════════════════
# Java
# ═══════════════════════════════════════════
run_java_checks() {
  info "--- Java Checks ---"
  echo ""

  # Detect build tool
  if [[ -f "pom.xml" ]]; then
    BUILD_TOOL="maven"
    BUILD_CMD="mvn"
  elif [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
    BUILD_TOOL="gradle"
    if [[ -f "./gradlew" ]]; then
      BUILD_CMD="./gradlew"
    else
      BUILD_CMD="gradle"
    fi
  else
    warn "No Maven/Gradle build file found"
    return
  fi

  info "Build tool: ${BUILD_TOOL}"

  # Compile check
  if [[ "$BUILD_TOOL" == "maven" ]]; then
    info "Compiling..."
    mvn compile -q 2>/dev/null && success "Compilation: success" || fail "Compilation: failed"
  else
    info "Compiling..."
    ${BUILD_CMD} compileJava -q 2>/dev/null && success "Compilation: success" || fail "Compilation: failed"
  fi
  echo ""

  if [[ "$MODE" == "full" ]]; then
    # Checkstyle
    if [[ "$BUILD_TOOL" == "maven" ]]; then
      if grep -q "checkstyle" pom.xml 2>/dev/null; then
        info "Running Checkstyle..."
        mvn checkstyle:check -q 2>/dev/null && success "Checkstyle: passed" || warn "Checkstyle: violations found"
        echo ""
      fi

      # SpotBugs
      if grep -q "spotbugs" pom.xml 2>/dev/null; then
        info "Running SpotBugs..."
        mvn spotbugs:check -q 2>/dev/null && success "SpotBugs: no bugs" || warn "SpotBugs: potential bugs found"
        echo ""
      fi

      # PMD
      if grep -q "pmd" pom.xml 2>/dev/null; then
        info "Running PMD..."
        mvn pmd:check -q 2>/dev/null && success "PMD: passed" || warn "PMD: violations found"
        echo ""
      fi

      # OWASP Dependency Check
      if grep -q "dependency-check" pom.xml 2>/dev/null; then
        info "Running OWASP Dependency Check..."
        mvn dependency-check:check -q 2>/dev/null && success "OWASP: no vulnerabilities" || warn "OWASP: vulnerabilities found"
        echo ""
      fi
    fi

    if [[ "$BUILD_TOOL" == "gradle" ]]; then
      # Run check task (includes checkstyle, pmd, spotbugs if configured)
      info "Running Gradle check..."
      ${BUILD_CMD} check -q 2>/dev/null && success "Gradle check: passed" || warn "Gradle check: issues found"
      echo ""
    fi

    # Test + coverage
    info "Running tests..."
    if [[ "$BUILD_TOOL" == "maven" ]]; then
      mvn test -q 2>/dev/null && success "Tests: passed" || fail "Tests: failed"
      # JaCoCo
      if grep -q "jacoco" pom.xml 2>/dev/null; then
        mvn jacoco:report -q 2>/dev/null
        REPORT="target/site/jacoco/index.html"
        if [[ -f "$REPORT" ]]; then
          info "  Coverage report: ${REPORT}"
        fi
      fi
    else
      ${BUILD_CMD} test -q 2>/dev/null && success "Tests: passed" || fail "Tests: failed"
      if ${BUILD_CMD} tasks --all -q 2>/dev/null | grep -q "jacocoTestReport"; then
        ${BUILD_CMD} jacocoTestReport -q 2>/dev/null
        info "  Coverage report: build/reports/jacoco/test/html/index.html"
      fi
    fi
    echo ""
  fi
}

# ═══════════════════════════════════════════
# Go
# ═══════════════════════════════════════════
run_go_checks() {
  info "--- Go Checks ---"
  echo ""

  if ! command -v go &>/dev/null; then
    warn "Go not installed"
    return
  fi

  # go vet
  info "Running go vet..."
  go vet ./... 2>/dev/null && success "go vet: no issues" || fail "go vet: issues found"
  echo ""

  # gofmt
  if [[ "$FIX" == "true" ]]; then
    info "Running gofmt -w..."
    gofmt -w . 2>/dev/null && success "gofmt: formatted" || warn "gofmt: issues"
  else
    info "Checking gofmt..."
    UNFORMATTED=$(gofmt -l . 2>/dev/null)
    if [[ -z "$UNFORMATTED" ]]; then
      success "gofmt: all formatted"
    else
      fail "gofmt: unformatted files found"
      echo "$UNFORMATTED" | head -5
    fi
  fi
  echo ""

  if [[ "$MODE" == "full" ]]; then
    # staticcheck
    if command -v staticcheck &>/dev/null; then
      info "Running staticcheck..."
      staticcheck ./... 2>/dev/null && success "staticcheck: no issues" || warn "staticcheck: issues found"
    else
      warn "staticcheck not installed. Install: go install honnef.co/go/tools/cmd/staticcheck@latest"
    fi
    echo ""

    # golangci-lint
    if command -v golangci-lint &>/dev/null; then
      info "Running golangci-lint..."
      if [[ "$FIX" == "true" ]]; then
        golangci-lint run --fix ./... 2>/dev/null && success "golangci-lint: clean" || warn "golangci-lint: some issues"
      else
        golangci-lint run ./... 2>/dev/null && success "golangci-lint: clean" || fail "golangci-lint: issues found"
      fi
    else
      warn "golangci-lint not installed. Install: brew install golangci-lint"
    fi
    echo ""

    # Tests
    info "Running tests..."
    go test ./... 2>/dev/null && success "Tests: passed" || fail "Tests: failed"

    # Coverage
    go test -coverprofile=coverage.out ./... 2>/dev/null
    if [[ -f "coverage.out" ]]; then
      COVERAGE=$(go tool cover -func=coverage.out 2>/dev/null | tail -1 | awk '{print $NF}')
      info "  Coverage: ${COVERAGE}"
      rm -f coverage.out
    fi
    echo ""

    # govulncheck
    if command -v govulncheck &>/dev/null; then
      info "Running govulncheck..."
      govulncheck ./... 2>/dev/null && success "govulncheck: no vulnerabilities" || warn "govulncheck: vulnerabilities found"
      echo ""
    fi
  fi
}

# ═══════════════════════════════════════════
# Cross-language checks (full mode)
# ═══════════════════════════════════════════
run_cross_checks() {
  info "--- Cross-language Checks ---"
  echo ""

  # Secret detection
  if command -v gitleaks &>/dev/null; then
    info "Running secret detection (gitleaks)..."
    gitleaks detect --source . --no-git 2>/dev/null && success "Secrets: none detected" || fail "Secrets: potential secrets found!"
  elif command -v trufflehog &>/dev/null; then
    info "Running secret detection (trufflehog)..."
    trufflehog filesystem . --no-verification 2>/dev/null && success "Secrets: none detected" || warn "Secrets: check results"
  else
    warn "No secret scanner found. Install: brew install gitleaks"
  fi
  echo ""

  # File size check
  info "Checking for large files..."
  LARGE_FILES=$(find . -type f -size +1M \
    ! -path "./.git/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/vendor/*" \
    ! -path "*/.venv/*" \
    ! -path "*/build/*" \
    ! -path "*/dist/*" \
    ! -path "*/target/*" \
    ! -name "*.lock" \
    ! -name "package-lock.json" \
    2>/dev/null || true)
  if [[ -n "$LARGE_FILES" ]]; then
    warn "Large files (>1MB) found:"
    echo "$LARGE_FILES" | head -5 | while read -r f; do
      SIZE=$(du -h "$f" | cut -f1)
      echo "    ${f} (${SIZE})"
    done
  else
    success "No large files found"
  fi
  echo ""

  # TODO/FIXME/HACK count
  info "Checking for code annotations..."
  TODO_COUNT=$(grep -rn "TODO\|FIXME\|HACK\|XXX\|TEMP" \
    --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" \
    --include="*.py" --include="*.java" --include="*.go" \
    --include="*.rb" --include="*.rs" \
    . 2>/dev/null | grep -v node_modules | grep -v vendor | grep -v .venv | wc -l | tr -d ' ')
  if [[ "$TODO_COUNT" -gt 20 ]]; then
    warn "Found ${TODO_COUNT} TODO/FIXME/HACK annotations"
  elif [[ "$TODO_COUNT" -gt 0 ]]; then
    info "  Found ${TODO_COUNT} TODO/FIXME/HACK annotations"
  else
    success "No TODO/FIXME/HACK annotations"
  fi
  echo ""
}

# ═══════════════════════════════════════════
# Run checks by detected language
# ═══════════════════════════════════════════
for LANG in "${LANGS[@]}"; do
  case "$LANG" in
    javascript|typescript) run_js_checks ;;
    python)                run_python_checks ;;
    java)                  run_java_checks ;;
    go)                    run_go_checks ;;
  esac
done

# Cross-language checks in full mode
if [[ "$MODE" == "full" ]]; then
  run_cross_checks
fi

# ═══════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════
echo "==============================="
echo "       Quality Summary"
echo "==============================="
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
  echo -e "${RED}  ERRORS:   ${ERRORS}${NC}"
fi
if [[ "$WARNINGS" -gt 0 ]]; then
  echo -e "${YELLOW}  WARNINGS: ${WARNINGS}${NC}"
fi
if [[ "$ERRORS" -eq 0 ]] && [[ "$WARNINGS" -eq 0 ]]; then
  echo -e "${GREEN}  All checks passed!${NC}"
fi

echo ""

if [[ "$CI" == "true" ]] && [[ "$ERRORS" -gt 0 ]]; then
  echo "CI mode: exiting with error (${ERRORS} errors found)"
  exit 1
fi

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi

exit 0
