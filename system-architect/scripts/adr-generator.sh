#!/usr/bin/env bash
# adr-generator.sh - Architecture Decision Record generator
# Usage: ./adr-generator.sh <title> [--dir docs/adr]
#
# Creates a new ADR file with sequential numbering and standard template

set -euo pipefail

# Cross-platform sed in-place
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

TITLE="${1:?Usage: $0 <title> [--dir docs/adr]}"
ADR_DIR="docs/adr"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) ADR_DIR="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

mkdir -p "$ADR_DIR"

# Find next ADR number
# Portable: sort numerically by ADR number, extract digits
LAST_NUM=$(ls "$ADR_DIR"/ADR-*.md 2>/dev/null | sed 's/.*ADR-\([0-9]*\).*/\1/' | sort -n | tail -1 || echo "0")
LAST_NUM="${LAST_NUM:-0}"
NEXT_NUM=$(printf "%03d" $((10#$LAST_NUM + 1)))

# Slug from title
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
FILENAME="$ADR_DIR/ADR-${NEXT_NUM}-${SLUG}.md"
DATE=$(date +%Y-%m-%d)

cat > "$FILENAME" << EOF
# ADR-${NEXT_NUM}: ${TITLE}

| Field        | Value                                    |
|-------------|------------------------------------------|
| **Status**  | Proposed                                 |
| **Date**    | ${DATE}                                  |
| **Authors** | [Author Name]                            |
| **Reviewers** | [Reviewer Names]                       |
| **Supersedes** | -                                     |

## Context

<!--
What is the issue we're seeing that motivates this decision?
What are the forces at play (technical, organizational, product)?
Include relevant constraints, requirements, and context.
-->

[Describe the context and problem statement here]

## Decision Drivers

- [Driver 1: e.g., Performance requirements]
- [Driver 2: e.g., Team expertise]
- [Driver 3: e.g., Time constraints]
- [Driver 4: e.g., Cost considerations]

## Considered Options

### Option 1: [Name]

**Description:** [Brief description]

| Pros | Cons |
|------|------|
| [Pro 1] | [Con 1] |
| [Pro 2] | [Con 2] |

### Option 2: [Name]

**Description:** [Brief description]

| Pros | Cons |
|------|------|
| [Pro 1] | [Con 1] |
| [Pro 2] | [Con 2] |

### Option 3: [Name]

**Description:** [Brief description]

| Pros | Cons |
|------|------|
| [Pro 1] | [Con 1] |
| [Pro 2] | [Con 2] |

## Decision

<!--
What is the chosen option and why?
How does it address the decision drivers?
-->

We will use **[Chosen Option]** because:

1. [Reason 1]
2. [Reason 2]
3. [Reason 3]

## Consequences

### Positive

- [Positive consequence 1]
- [Positive consequence 2]

### Negative

- [Negative consequence 1]
- [Negative consequence 2]

### Risks

- [Risk 1] — Mitigation: [How to mitigate]
- [Risk 2] — Mitigation: [How to mitigate]

## Implementation Notes

<!--
High-level implementation approach, key files to change,
migration steps, or any other technical notes.
-->

- [ ] [Implementation step 1]
- [ ] [Implementation step 2]
- [ ] [Implementation step 3]

## Follow-up

- [ ] Review after [timeframe] to validate decision
- [ ] Monitor [metric] for success criteria
- [ ] Update team documentation

## References

- [Link to relevant docs, RFCs, or prior ADRs]
EOF

echo "Created: $FILENAME"
echo ""
echo "Next steps:"
echo "  1. Edit the ADR: $FILENAME"
echo "  2. Fill in context, options, and decision"
echo "  3. Set status to 'Accepted' after team review"
echo "  4. Commit: git add $FILENAME && git commit -m 'adr: ${TITLE}'"

# Create index if it doesn't exist
INDEX="$ADR_DIR/README.md"
if [[ ! -f "$INDEX" ]]; then
  cat > "$INDEX" << 'EOF'
# Architecture Decision Records

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|

## About ADRs

Architecture Decision Records capture important architectural decisions along with their context and consequences.

### Statuses

- **Proposed**: Under discussion
- **Accepted**: Decision made and approved
- **Deprecated**: No longer valid (superseded)
- **Superseded**: Replaced by a newer ADR
EOF
  echo "Created index: $INDEX"
fi

# Append to index
sedi "/^| ADR | Title/a\\
| [ADR-${NEXT_NUM}](ADR-${NEXT_NUM}-${SLUG}.md) | ${TITLE} | Proposed | ${DATE} |" "$INDEX" 2>/dev/null || true
