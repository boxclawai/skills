#!/usr/bin/env bash
# pr-stats.sh - Pull request and team engineering metrics
# Usage: ./pr-stats.sh [--repo owner/repo] [--days 30] [--team user1,user2]
#
# Metrics:
#   - PR lead time (open → merge)
#   - PR size distribution
#   - Review turnaround time
#   - PR throughput per developer
#   - DORA-like deployment frequency

set -euo pipefail

REPO=""
DAYS=30
TEAM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="--repo $2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

SINCE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null)

echo "======================================"
echo "  PR & Engineering Metrics"
echo "======================================"
echo "  Period: Last $DAYS days (since $SINCE)"
echo "  Repo:   ${REPO:-'current'}"
echo "======================================"
echo ""

# Check gh CLI
if ! command -v gh &>/dev/null; then
  echo "Error: GitHub CLI (gh) required. Install: brew install gh"
  exit 1
fi

# --- Merged PRs ---
echo "=== Merged Pull Requests ==="
PR_DATA=$(gh pr list $REPO --state merged --search "merged:>=$SINCE" --limit 200 \
  --json number,title,author,createdAt,mergedAt,additions,deletions,changedFiles \
  2>/dev/null || echo "[]")

if [[ "$PR_DATA" == "[]" ]] || [[ -z "$PR_DATA" ]]; then
  echo "No merged PRs found in the last $DAYS days."
  exit 0
fi

echo "$PR_DATA" | TEAM="$TEAM" node -e "
const chunks = [];
process.stdin.on('data', d => chunks.push(d));
process.stdin.on('end', () => {
const prs = JSON.parse(Buffer.concat(chunks).toString());
const team = process.env.TEAM.split(',').filter(Boolean);

// Filter by team if specified
const filtered = team.length > 0
  ? prs.filter(pr => team.includes(pr.author.login))
  : prs;

console.log('Total merged PRs: ' + filtered.length);
console.log('');

// --- Lead Time ---
const leadTimes = filtered.map(pr => {
  const created = new Date(pr.createdAt);
  const merged = new Date(pr.mergedAt);
  return (merged - created) / (1000 * 60 * 60); // hours
}).sort((a, b) => a - b);

if (leadTimes.length > 0) {
  const median = leadTimes[Math.floor(leadTimes.length / 2)];
  const avg = leadTimes.reduce((a, b) => a + b, 0) / leadTimes.length;
  const p90 = leadTimes[Math.floor(leadTimes.length * 0.9)];

  console.log('--- Lead Time (open → merge) ---');
  console.log('  Median: ' + median.toFixed(1) + 'h');
  console.log('  Average: ' + avg.toFixed(1) + 'h');
  console.log('  P90: ' + p90.toFixed(1) + 'h');
  console.log('');
}

// --- PR Size Distribution ---
const sizes = filtered.map(pr => ({
  lines: pr.additions + pr.deletions,
  files: pr.changedFiles,
}));

const categorize = (lines) => {
  if (lines < 50) return 'XS (<50)';
  if (lines < 200) return 'S (50-200)';
  if (lines < 500) return 'M (200-500)';
  if (lines < 1000) return 'L (500-1000)';
  return 'XL (1000+)';
};

const sizeDistribution = {};
sizes.forEach(s => {
  const cat = categorize(s.lines);
  sizeDistribution[cat] = (sizeDistribution[cat] || 0) + 1;
});

console.log('--- PR Size Distribution ---');
for (const [size, count] of Object.entries(sizeDistribution).sort()) {
  const bar = '█'.repeat(Math.min(count, 40));
  console.log('  ' + size.padEnd(15) + ' ' + bar + ' ' + count);
}
console.log('');

// --- Per Developer ---
const byDev = {};
filtered.forEach(pr => {
  const dev = pr.author.login;
  if (!byDev[dev]) byDev[dev] = { count: 0, totalLines: 0, totalLeadTime: 0 };
  byDev[dev].count++;
  byDev[dev].totalLines += pr.additions + pr.deletions;
  const lt = (new Date(pr.mergedAt) - new Date(pr.createdAt)) / (1000 * 60 * 60);
  byDev[dev].totalLeadTime += lt;
});

console.log('--- Per Developer ---');
console.log('  ' + 'Developer'.padEnd(20) + 'PRs'.padStart(5) + '  Avg Lines'.padStart(12) + '  Avg Lead Time'.padStart(16));
console.log('  ' + '-'.repeat(55));
for (const [dev, stats] of Object.entries(byDev).sort((a, b) => b[1].count - a[1].count)) {
  const avgLines = Math.round(stats.totalLines / stats.count);
  const avgLT = (stats.totalLeadTime / stats.count).toFixed(1) + 'h';
  console.log('  ' + dev.padEnd(20) + String(stats.count).padStart(5) + String(avgLines).padStart(12) + avgLT.padStart(16));
}
console.log('');

// --- Deployment Frequency (merge = deploy proxy) ---
const perWeek = {};
filtered.forEach(pr => {
  const date = new Date(pr.mergedAt);
  const weekStart = new Date(date);
  weekStart.setDate(date.getDate() - date.getDay());
  const key = weekStart.toISOString().slice(0, 10);
  perWeek[key] = (perWeek[key] || 0) + 1;
});

const weeks = Object.entries(perWeek).sort();
const avgPerWeek = weeks.length > 0
  ? (weeks.reduce((s, [, c]) => s + c, 0) / weeks.length).toFixed(1)
  : '0';

console.log('--- Deployment Frequency (PRs merged/week) ---');
console.log('  Average: ' + avgPerWeek + ' PRs/week');
for (const [week, count] of weeks) {
  const bar = '█'.repeat(Math.min(count, 40));
  console.log('  ' + week + ' ' + bar + ' ' + count);
}
});
" 2>/dev/null || echo "Error: Node.js required for metrics calculation"

echo ""
echo "Report complete."
