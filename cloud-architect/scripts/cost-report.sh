#!/usr/bin/env bash
# cost-report.sh - AWS cost analysis and optimization report
# Usage: ./cost-report.sh [--period 30] [--profile default] [--output reports/]
#
# Features:
#   - Monthly cost breakdown by service
#   - Daily cost trend
#   - Top cost drivers
#   - Idle/unused resource detection
#   - Savings recommendations

set -euo pipefail

PERIOD=30
PROFILE=""
OUTPUT_DIR="cost-reports"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --period) PERIOD="$2"; shift 2 ;;
    --profile) PROFILE="--profile $2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Date range
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -v-${PERIOD}d +%Y-%m-%d 2>/dev/null || date -d "${PERIOD} days ago" +%Y-%m-%d 2>/dev/null)

echo "======================================"
echo "  AWS Cost Analysis Report"
echo "======================================"
echo "  Period: $START_DATE → $END_DATE ($PERIOD days)"
echo "======================================"
echo ""

# Check AWS CLI
if ! command -v aws &>/dev/null; then
  echo "Error: AWS CLI required. Install: brew install awscli"
  exit 1
fi

# --- Monthly Cost by Service ---
echo "=== Cost by Service ==="
aws ce get-cost-and-usage $PROFILE \
  --time-period Start="$START_DATE",End="$END_DATE" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json > "$OUTPUT_DIR/cost-by-service-${TIMESTAMP}.json"

# Parse and display
node -e "
const data = JSON.parse(require('fs').readFileSync('$OUTPUT_DIR/cost-by-service-${TIMESTAMP}.json', 'utf8'));
const services = {};

for (const result of data.ResultsByTime) {
  for (const group of result.Groups) {
    const service = group.Keys[0];
    const cost = parseFloat(group.Metrics.BlendedCost.Amount);
    services[service] = (services[service] || 0) + cost;
  }
}

const sorted = Object.entries(services)
  .sort((a, b) => b[1] - a[1])
  .filter(([, cost]) => cost > 0.01);

const total = sorted.reduce((sum, [, cost]) => sum + cost, 0);

console.log('  Total: \$' + total.toFixed(2));
console.log('');
console.log('  Service'.padEnd(45) + 'Cost'.padStart(12) + '  %'.padStart(8));
console.log('  ' + '-'.repeat(65));

for (const [service, cost] of sorted.slice(0, 20)) {
  const pct = (cost / total * 100).toFixed(1);
  const bar = '█'.repeat(Math.round(cost / total * 30));
  console.log('  ' + service.substring(0, 43).padEnd(45) + ('\$' + cost.toFixed(2)).padStart(12) + (pct + '%').padStart(8) + '  ' + bar);
}
" 2>/dev/null || echo "Error parsing cost data. Check AWS credentials."

# --- Daily Cost Trend ---
echo ""
echo "=== Daily Cost Trend (last $PERIOD days) ==="
aws ce get-cost-and-usage $PROFILE \
  --time-period Start="$START_DATE",End="$END_DATE" \
  --granularity DAILY \
  --metrics BlendedCost \
  --output json > "$OUTPUT_DIR/daily-cost-${TIMESTAMP}.json"

node -e "
const data = JSON.parse(require('fs').readFileSync('$OUTPUT_DIR/daily-cost-${TIMESTAMP}.json', 'utf8'));
const daily = data.ResultsByTime.map(r => ({
  date: r.TimePeriod.Start,
  cost: parseFloat(r.Total.BlendedCost.Amount),
}));

const maxCost = Math.max(...daily.map(d => d.cost));
const avgCost = daily.reduce((s, d) => s + d.cost, 0) / daily.length;

console.log('  Average daily: \$' + avgCost.toFixed(2));
console.log('  Peak daily:    \$' + maxCost.toFixed(2));
console.log('');

// Show last 14 days as chart
const recent = daily.slice(-14);
for (const { date, cost } of recent) {
  const barLen = Math.round((cost / maxCost) * 30);
  const bar = '█'.repeat(barLen);
  const icon = cost > avgCost * 1.5 ? '⚠️ ' : '   ';
  console.log(icon + date + ' ' + bar + ' \$' + cost.toFixed(2));
}
" 2>/dev/null || true

# --- Unused Resources Detection ---
echo ""
echo "=== Potential Savings: Unused Resources ==="

echo ""
echo "--- Unattached EBS Volumes ---"
UNATTACHED=$(aws ec2 describe-volumes $PROFILE \
  --filters Name=status,Values=available \
  --query 'Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType}' \
  --output json 2>/dev/null || echo "[]")

node -e "
const vols = JSON.parse(\`$(echo "$UNATTACHED")\`);
if (vols.length === 0) {
  console.log('  None found ✅');
} else {
  console.log('  Found ' + vols.length + ' unattached volumes:');
  let totalGB = 0;
  for (const v of vols) {
    console.log('    ' + v.ID + '  ' + v.Size + 'GB  ' + v.Type);
    totalGB += v.Size;
  }
  console.log('  Total: ' + totalGB + ' GB (estimated \$' + (totalGB * 0.10).toFixed(2) + '/month for gp3)');
}
" 2>/dev/null

echo ""
echo "--- Unused Elastic IPs ---"
UNUSED_EIPS=$(aws ec2 describe-addresses $PROFILE \
  --query 'Addresses[?AssociationId==null].{IP:PublicIp,AllocationId:AllocationId}' \
  --output json 2>/dev/null || echo "[]")

node -e "
const eips = JSON.parse(\`$(echo "$UNUSED_EIPS")\`);
if (eips.length === 0) {
  console.log('  None found ✅');
} else {
  console.log('  Found ' + eips.length + ' unused EIPs (\$3.65/month each):');
  for (const e of eips) {
    console.log('    ' + e.IP + ' (' + e.AllocationId + ')');
  }
  console.log('  Potential savings: \$' + (eips.length * 3.65).toFixed(2) + '/month');
}
" 2>/dev/null

echo ""
echo "--- Old Snapshots (> 90 days) ---"
OLD_SNAPS=$(aws ec2 describe-snapshots $PROFILE \
  --owner-ids self \
  --query "length(Snapshots[?StartTime<='$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d)'])" \
  --output text 2>/dev/null || echo "0")
echo "  Old snapshots: $OLD_SNAPS"
[[ "$OLD_SNAPS" -gt 0 ]] && echo "  Review with: aws ec2 describe-snapshots --owner self --query 'Snapshots[?StartTime<=\`...\`]'"

echo ""
echo "======================================"
echo "  Reports saved: $OUTPUT_DIR/"
echo "======================================"
