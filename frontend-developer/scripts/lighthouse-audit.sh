#!/usr/bin/env bash
# lighthouse-audit.sh - Run Lighthouse CI audit and generate report
# Usage: ./lighthouse-audit.sh <url> [--budget budget.json] [--output-dir ./reports]
#
# Requires: lighthouse (npm i -g lighthouse) or Chrome DevTools

set -euo pipefail

URL="${1:?Usage: $0 <url> [--budget budget.json] [--output-dir ./reports]}"
BUDGET_FILE=""
OUTPUT_DIR="./lighthouse-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget)
      BUDGET_FILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

echo "=== Lighthouse Audit ==="
echo "URL: $URL"
echo "Output: $OUTPUT_DIR"
echo ""

# Check for lighthouse CLI
if ! command -v lighthouse &> /dev/null; then
  echo "lighthouse not found. Installing..."
  npm install -g lighthouse
fi

# Build lighthouse command
LIGHTHOUSE_CMD=(
  lighthouse "$URL"
  --output html,json
  --output-path "$OUTPUT_DIR/report-$TIMESTAMP"
  --chrome-flags="--headless --no-sandbox --disable-gpu"
  --only-categories=performance,accessibility,best-practices,seo
  --quiet
)

# Add budget if provided
if [[ -n "$BUDGET_FILE" ]]; then
  LIGHTHOUSE_CMD+=(--budget-path "$BUDGET_FILE")
fi

echo "Running Lighthouse..."
"${LIGHTHOUSE_CMD[@]}"

# Parse JSON results and display summary
JSON_FILE="$OUTPUT_DIR/report-$TIMESTAMP.report.json"

if command -v node &> /dev/null && [[ -f "$JSON_FILE" ]]; then
  node -e "
    const report = JSON.parse(require('fs').readFileSync('$JSON_FILE', 'utf8'));
    const cats = report.categories;

    console.log('');
    console.log('╔══════════════════════════════════════╗');
    console.log('║       LIGHTHOUSE AUDIT RESULTS       ║');
    console.log('╠══════════════════════════════════════╣');

    const scores = {
      'Performance':     cats.performance?.score,
      'Accessibility':   cats.accessibility?.score,
      'Best Practices':  cats['best-practices']?.score,
      'SEO':             cats.seo?.score,
    };

    for (const [name, score] of Object.entries(scores)) {
      if (score == null) continue;
      const pct = Math.round(score * 100);
      const icon = pct >= 90 ? '🟢' : pct >= 50 ? '🟡' : '🔴';
      console.log(\`║  \${icon} \${name.padEnd(18)} \${String(pct).padStart(3)}%         ║\`);
    }

    console.log('╚══════════════════════════════════════╝');

    // Key metrics
    const audits = report.audits;
    const metrics = {
      'LCP':   audits['largest-contentful-paint']?.displayValue,
      'FID':   audits['max-potential-fid']?.displayValue,
      'CLS':   audits['cumulative-layout-shift']?.displayValue,
      'TBT':   audits['total-blocking-time']?.displayValue,
      'SI':    audits['speed-index']?.displayValue,
      'TTI':   audits['interactive']?.displayValue,
    };

    console.log('');
    console.log('Core Web Vitals:');
    for (const [name, value] of Object.entries(metrics)) {
      if (value) console.log(\`  \${name}: \${value}\`);
    }

    // Check thresholds
    const perf = Math.round((cats.performance?.score || 0) * 100);
    if (perf < 90) {
      console.log('');
      console.log('⚠️  Performance below 90%. Top opportunities:');
      const opps = Object.values(report.audits)
        .filter(a => a.details?.type === 'opportunity' && a.score !== null && a.score < 1)
        .sort((a, b) => (a.score || 0) - (b.score || 0))
        .slice(0, 5);
      for (const opp of opps) {
        console.log(\`  - \${opp.title}: \${opp.displayValue || ''}\`);
      }
    }
  "
fi

echo ""
echo "Full report: $OUTPUT_DIR/report-$TIMESTAMP.report.html"
echo "JSON data:   $OUTPUT_DIR/report-$TIMESTAMP.report.json"
