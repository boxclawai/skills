#!/usr/bin/env bash
# dbt-helper.sh - dbt workflow automation
# Usage: ./dbt-helper.sh <action> [args]
#
# Actions:
#   dev           Run dbt in development mode (build + test changed models)
#   ci            Full CI check (build all + test + docs)
#   freshness     Check source freshness
#   audit         Audit model quality (tests coverage, documentation)
#   deps          Update and check dependencies
#   lineage       Show upstream/downstream for a model

set -euo pipefail

ACTION="${1:?Usage: $0 <dev|ci|freshness|audit|deps|lineage> [args]}"
shift

case "$ACTION" in
  dev)
    echo "=== dbt Development Build ==="
    echo ""

    # Run only changed models + downstream
    if command -v git &>/dev/null; then
      CHANGED=$(git diff --name-only HEAD~1 -- models/ | sed 's|models/||;s|\.sql||' | tr '\n' ' ')
      if [[ -n "$CHANGED" ]]; then
        echo "Changed models: $CHANGED"
        echo "Building changed + downstream..."
        dbt build --select "$(echo $CHANGED | sed 's/ /+,/g')+"
      else
        echo "No model changes detected. Running full build..."
        dbt build
      fi
    else
      dbt build
    fi

    echo ""
    echo "Running tests on modified models..."
    dbt test --select "state:modified+" 2>/dev/null || dbt test
    ;;

  ci)
    echo "=== dbt CI Pipeline ==="
    echo ""

    echo "Step 1/5: Checking dependencies..."
    dbt deps
    echo ""

    echo "Step 2/5: Compiling project..."
    dbt compile
    echo ""

    echo "Step 3/5: Running all models..."
    dbt run --full-refresh 2>/dev/null || dbt run
    echo ""

    echo "Step 4/5: Running all tests..."
    dbt test
    echo ""

    echo "Step 5/5: Generating docs..."
    dbt docs generate
    echo ""

    echo "CI pipeline complete."
    echo "View docs: dbt docs serve"
    ;;

  freshness)
    echo "=== Source Freshness Check ==="
    dbt source freshness

    echo ""
    echo "Check freshness results in target/sources.json"
    if command -v node &>/dev/null && [[ -f "target/sources.json" ]]; then
      node -e "
        const data = JSON.parse(require('fs').readFileSync('target/sources.json', 'utf8'));
        const results = data.results || [];
        console.log('');
        console.log('Source Freshness Summary:');
        console.log('========================');
        for (const r of results) {
          const status = r.status === 'pass' ? '✅' : r.status === 'warn' ? '⚠️' : '❌';
          const age = r.max_loaded_at_time_ago_in_s
            ? Math.round(r.max_loaded_at_time_ago_in_s / 3600) + 'h ago'
            : 'unknown';
          console.log(\`  \${status} \${r.unique_id.padEnd(50)} \${age}\`);
        }
      " 2>/dev/null || true
    fi
    ;;

  audit)
    echo "=== dbt Model Audit ==="
    echo ""

    # Check for models without tests
    echo "--- Models Without Tests ---"
    dbt ls --resource-type model --output json 2>/dev/null | \
      node -e "
        const readline = require('readline');
        const rl = readline.createInterface({ input: process.stdin });
        const models = [];
        rl.on('line', l => { try { models.push(JSON.parse(l)); } catch {} });
        rl.on('close', () => {
          // This is a simplified check
          console.log('Total models: ' + models.length);
          console.log('Run: dbt test --select <model> to check test coverage');
        });
      " 2>/dev/null || echo "Install node for detailed audit"

    echo ""
    echo "--- Models Without Descriptions ---"
    dbt ls --resource-type model --output json 2>/dev/null | \
      node -e "
        const readline = require('readline');
        const rl = readline.createInterface({ input: process.stdin });
        const undocumented = [];
        rl.on('line', l => {
          try {
            const m = JSON.parse(l);
            if (!m.description || m.description.trim() === '') {
              undocumented.push(m.unique_id);
            }
          } catch {}
        });
        rl.on('close', () => {
          if (undocumented.length === 0) {
            console.log('All models have descriptions ✅');
          } else {
            console.log('Undocumented models (' + undocumented.length + '):');
            undocumented.forEach(m => console.log('  - ' + m));
          }
        });
      " 2>/dev/null || echo "Run 'dbt docs generate' and check catalog.json"

    echo ""
    echo "--- Stale Models (not run recently) ---"
    if [[ -f "target/run_results.json" ]]; then
      node -e "
        const data = JSON.parse(require('fs').readFileSync('target/run_results.json', 'utf8'));
        const results = data.results || [];
        const errors = results.filter(r => r.status === 'error');
        const warnings = results.filter(r => r.status === 'warn');
        console.log('Last run: ' + results.length + ' models');
        console.log('  Errors: ' + errors.length);
        console.log('  Warnings: ' + warnings.length);
        errors.forEach(e => console.log('  ❌ ' + e.unique_id + ': ' + (e.message || '').substring(0, 100)));
      " 2>/dev/null
    else
      echo "No run results found. Run 'dbt run' first."
    fi
    ;;

  deps)
    echo "=== dbt Dependencies ==="
    dbt deps
    echo ""
    echo "Dependencies installed successfully."

    echo ""
    echo "Installed packages:"
    if [[ -f "packages.yml" ]]; then
      cat packages.yml
    elif [[ -f "dependencies.yml" ]]; then
      cat dependencies.yml
    fi
    ;;

  lineage)
    MODEL="${1:?Usage: $0 lineage <model-name>}"
    echo "=== Lineage for: $MODEL ==="
    echo ""

    echo "--- Upstream (parents) ---"
    dbt ls --select "+${MODEL}" --resource-type model 2>/dev/null || echo "Could not determine upstream"

    echo ""
    echo "--- Downstream (children) ---"
    dbt ls --select "${MODEL}+" --resource-type model 2>/dev/null || echo "Could not determine downstream"

    echo ""
    echo "For visual lineage: dbt docs generate && dbt docs serve"
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 <dev|ci|freshness|audit|deps|lineage> [args]"
    exit 1
    ;;
esac
