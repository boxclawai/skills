#!/usr/bin/env bash
# security-scan.sh - Comprehensive security scanning pipeline
# Usage: ./security-scan.sh [--type all|deps|secrets|sast|headers] [--ci] [--fix]
#
# Scans:
#   deps:    Dependency vulnerability scanning (npm audit, Trivy)
#   secrets: Secret/credential detection (Gitleaks)
#   sast:    Static Application Security Testing (Semgrep)
#   headers: HTTP security headers check
#   all:     Run all scans

set -euo pipefail

SCAN_TYPE="all"
CI=false
FIX=false
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) SCAN_TYPE="$2"; shift 2 ;;
    --ci) CI=true; shift ;;
    --fix) FIX=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

mkdir -p .security-reports

echo "======================================"
echo "  Security Scanner"
echo "======================================"
echo "  Scan: $SCAN_TYPE"
echo "  CI:   $CI"
echo "======================================"
echo ""

# --- Dependency Scanning ---
scan_deps() {
  echo "=== Dependency Vulnerability Scan ==="
  echo ""

  # npm audit
  if [[ -f "package.json" ]]; then
    echo "--- npm audit ---"
    if [[ "$FIX" == true ]]; then
      npm audit fix --audit-level=high 2>&1 | tee .security-reports/npm-audit.txt || true
    else
      npm audit --audit-level=high 2>&1 | tee .security-reports/npm-audit.txt || EXIT_CODE=1
    fi
    echo ""
  fi

  # Trivy filesystem scan
  if command -v trivy &>/dev/null; then
    echo "--- Trivy Scan ---"
    trivy fs . \
      --severity HIGH,CRITICAL \
      --format table \
      --output .security-reports/trivy-report.txt \
      2>&1 | tail -20
    if [[ "$CI" == true ]]; then
      trivy fs . --severity CRITICAL --exit-code 1 || EXIT_CODE=1
    fi
    echo ""
  else
    echo "Trivy not installed. Install: brew install trivy"
    echo ""
  fi

  # Python safety check
  if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
    echo "--- Python dependency check ---"
    if command -v pip-audit &>/dev/null; then
      pip-audit 2>&1 | tee .security-reports/pip-audit.txt || EXIT_CODE=1
    else
      echo "pip-audit not installed. Install: pip install pip-audit"
    fi
    echo ""
  fi
}

# --- Secret Detection ---
scan_secrets() {
  echo "=== Secret Detection ==="
  echo ""

  if command -v gitleaks &>/dev/null; then
    echo "--- Gitleaks ---"
    gitleaks detect --source . \
      --report-path .security-reports/gitleaks-report.json \
      --report-format json \
      --verbose 2>&1 | tail -20 || EXIT_CODE=1
    echo ""
  else
    echo "Gitleaks not installed. Install: brew install gitleaks"
    echo ""
  fi

  # Quick pattern check for common secrets
  echo "--- Quick Secret Patterns Check ---"
  PATTERNS=(
    'AKIA[0-9A-Z]{16}'                    # AWS Access Key
    'sk-[a-zA-Z0-9]{48}'                  # OpenAI API Key
    'ghp_[a-zA-Z0-9]{36}'                 # GitHub PAT
    'password\s*=\s*["\x27][^"\x27]+'     # Hardcoded passwords
    'secret\s*=\s*["\x27][^"\x27]+'       # Hardcoded secrets
    'BEGIN (RSA|DSA|EC) PRIVATE KEY'       # Private keys
  )

  FOUND_SECRETS=0
  for pattern in "${PATTERNS[@]}"; do
    MATCHES=$(grep -rn --include="*.ts" --include="*.js" --include="*.py" --include="*.env" \
      -E "$pattern" . --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null || true)
    if [[ -n "$MATCHES" ]]; then
      echo "ALERT: Potential secret found matching: $pattern"
      echo "$MATCHES" | head -5
      FOUND_SECRETS=$((FOUND_SECRETS + 1))
      echo ""
    fi
  done

  if [[ "$FOUND_SECRETS" -eq 0 ]]; then
    echo "No secret patterns detected."
  else
    echo ""
    echo "Found $FOUND_SECRETS potential secret pattern(s)!"
    EXIT_CODE=1
  fi
  echo ""
}

# --- SAST ---
scan_sast() {
  echo "=== Static Application Security Testing ==="
  echo ""

  if command -v semgrep &>/dev/null; then
    echo "--- Semgrep ---"
    semgrep scan --config auto \
      --severity ERROR \
      --output .security-reports/semgrep-report.json \
      --json 2>/dev/null

    # Human-readable output
    semgrep scan --config auto --severity ERROR 2>&1 | tail -30 || EXIT_CODE=1
    echo ""
  else
    echo "Semgrep not installed. Install: pip install semgrep"
    echo ""
  fi
}

# --- HTTP Headers ---
scan_headers() {
  URL="${1:-}"
  if [[ -z "$URL" ]]; then
    echo "=== HTTP Security Headers ==="
    echo "Usage: $0 --type headers <url>"
    echo ""
    echo "Provide a URL to check security headers."
    return
  fi

  echo "=== HTTP Security Headers: $URL ==="
  echo ""

  HEADERS=$(curl -sI "$URL" 2>/dev/null)

  check_header() {
    local NAME="$1"
    local REQUIRED="${2:-true}"
    if echo "$HEADERS" | grep -qi "^$NAME:"; then
      VALUE=$(echo "$HEADERS" | grep -i "^$NAME:" | head -1 | cut -d: -f2- | xargs)
      echo "  ✅ $NAME: $VALUE"
    elif [[ "$REQUIRED" == true ]]; then
      echo "  ❌ $NAME: MISSING"
      EXIT_CODE=1
    else
      echo "  ⚠️  $NAME: not set (recommended)"
    fi
  }

  echo "Required headers:"
  check_header "Strict-Transport-Security" true
  check_header "X-Content-Type-Options" true
  check_header "X-Frame-Options" true
  check_header "Content-Security-Policy" true

  echo ""
  echo "Recommended headers:"
  check_header "Referrer-Policy" false
  check_header "Permissions-Policy" false
  check_header "X-XSS-Protection" false

  echo ""
  echo "Should NOT be present:"
  if echo "$HEADERS" | grep -qi "^Server:"; then
    echo "  ⚠️  Server header is exposed (information disclosure)"
  else
    echo "  ✅ Server header not exposed"
  fi
  if echo "$HEADERS" | grep -qi "^X-Powered-By:"; then
    echo "  ❌ X-Powered-By is exposed (remove it!)"
    EXIT_CODE=1
  else
    echo "  ✅ X-Powered-By not exposed"
  fi
  echo ""
}

# Execute scans
case "$SCAN_TYPE" in
  deps)    scan_deps ;;
  secrets) scan_secrets ;;
  sast)    scan_sast ;;
  headers) scan_headers "$@" ;;
  all)
    scan_deps
    scan_secrets
    scan_sast
    ;;
  *) echo "Unknown scan type: $SCAN_TYPE"; exit 1 ;;
esac

echo "======================================"
echo "  Scan Complete"
echo "======================================"
echo "  Reports: .security-reports/"
echo "  Exit code: $EXIT_CODE"
echo "======================================"

exit "$EXIT_CODE"
