#!/usr/bin/env bash
# component-generator.sh - Generate React/Vue component scaffolding
# Usage: ./component-generator.sh <ComponentName> [--framework react|vue] [--dir src/components]
#
# Generates:
#   - Component file with proper typing
#   - CSS Module / styles
#   - Test file
#   - Barrel export (index.ts)

set -euo pipefail

# Cross-platform sed in-place
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

COMPONENT_NAME="${1:?Usage: $0 <ComponentName> [--framework react|vue] [--dir src/components]}"
FRAMEWORK="react"
BASE_DIR="src/components"

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework) FRAMEWORK="$2"; shift 2 ;;
    --dir) BASE_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Convert PascalCase to kebab-case for file/dir names
# Portable PascalCase to kebab-case (no GNU \L needed)
KEBAB_NAME=$(echo "$COMPONENT_NAME" | sed 's/\([A-Z]\)/-\1/g' | sed 's/^-//' | tr '[:upper:]' '[:lower:]')
COMPONENT_DIR="$BASE_DIR/$COMPONENT_NAME"

mkdir -p "$COMPONENT_DIR"

echo "Generating $FRAMEWORK component: $COMPONENT_NAME"
echo "Directory: $COMPONENT_DIR"

if [[ "$FRAMEWORK" == "react" ]]; then
  # React component
  cat > "$COMPONENT_DIR/$COMPONENT_NAME.tsx" << 'COMPONENT'
import { type ComponentPropsWithoutRef, forwardRef } from 'react';
import styles from './__COMPONENT_NAME__.module.css';

export interface __COMPONENT_NAME__Props extends ComponentPropsWithoutRef<'div'> {
  /** Variant style of the component */
  variant?: 'default' | 'primary' | 'secondary';
}

export const __COMPONENT_NAME__ = forwardRef<HTMLDivElement, __COMPONENT_NAME__Props>(
  function __COMPONENT_NAME__({ variant = 'default', className, children, ...props }, ref) {
    return (
      <div
        ref={ref}
        className={`${styles.root} ${styles[variant]} ${className ?? ''}`}
        {...props}
      >
        {children}
      </div>
    );
  }
);
COMPONENT
  sedi "s/__COMPONENT_NAME__/$COMPONENT_NAME/g" "$COMPONENT_DIR/$COMPONENT_NAME.tsx"

  # CSS Module
  cat > "$COMPONENT_DIR/$COMPONENT_NAME.module.css" << CSS
.root {
  /* Base styles */
}

.default {
  /* Default variant */
}

.primary {
  /* Primary variant */
}

.secondary {
  /* Secondary variant */
}
CSS

  # Test file
  cat > "$COMPONENT_DIR/$COMPONENT_NAME.test.tsx" << 'TEST'
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { __COMPONENT_NAME__ } from './__COMPONENT_NAME__';

describe('__COMPONENT_NAME__', () => {
  it('renders children', () => {
    render(<__COMPONENT_NAME__>Hello</__COMPONENT_NAME__>);
    expect(screen.getByText('Hello')).toBeInTheDocument();
  });

  it('applies variant class', () => {
    const { container } = render(
      <__COMPONENT_NAME__ variant="primary">Content</__COMPONENT_NAME__>
    );
    expect(container.firstChild).toHaveClass('primary');
  });

  it('forwards ref', () => {
    const ref = { current: null };
    render(<__COMPONENT_NAME__ ref={ref}>Test</__COMPONENT_NAME__>);
    expect(ref.current).toBeInstanceOf(HTMLDivElement);
  });

  it('passes through additional props', () => {
    render(<__COMPONENT_NAME__ data-testid="custom">Test</__COMPONENT_NAME__>);
    expect(screen.getByTestId('custom')).toBeInTheDocument();
  });
});
TEST
  sedi "s/__COMPONENT_NAME__/$COMPONENT_NAME/g" "$COMPONENT_DIR/$COMPONENT_NAME.test.tsx"

  # Barrel export
  cat > "$COMPONENT_DIR/index.ts" << INDEX
export { $COMPONENT_NAME } from './$COMPONENT_NAME';
export type { ${COMPONENT_NAME}Props } from './$COMPONENT_NAME';
INDEX

elif [[ "$FRAMEWORK" == "vue" ]]; then
  # Vue component
  cat > "$COMPONENT_DIR/$COMPONENT_NAME.vue" << 'VUE'
<script setup lang="ts">
interface Props {
  /** Variant style of the component */
  variant?: 'default' | 'primary' | 'secondary';
}

withDefaults(defineProps<Props>(), {
  variant: 'default',
});
</script>

<template>
  <div :class="[$style.root, $style[variant]]">
    <slot />
  </div>
</template>

<style module>
.root {
  /* Base styles */
}

.default {
  /* Default variant */
}

.primary {
  /* Primary variant */
}

.secondary {
  /* Secondary variant */
}
</style>
VUE

  # Test file
  cat > "$COMPONENT_DIR/$COMPONENT_NAME.test.ts" << 'TEST'
import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import __COMPONENT_NAME__ from './__COMPONENT_NAME__.vue';

describe('__COMPONENT_NAME__', () => {
  it('renders slot content', () => {
    const wrapper = mount(__COMPONENT_NAME__, {
      slots: { default: 'Hello' },
    });
    expect(wrapper.text()).toContain('Hello');
  });

  it('applies variant prop', () => {
    const wrapper = mount(__COMPONENT_NAME__, {
      props: { variant: 'primary' },
      slots: { default: 'Content' },
    });
    expect(wrapper.classes()).toContain('primary');
  });
});
TEST
  sedi "s/__COMPONENT_NAME__/$COMPONENT_NAME/g" "$COMPONENT_DIR/$COMPONENT_NAME.test.ts"

  # Barrel export
  cat > "$COMPONENT_DIR/index.ts" << INDEX
export { default as $COMPONENT_NAME } from './$COMPONENT_NAME.vue';
INDEX
fi

echo ""
echo "Generated files:"
find "$COMPONENT_DIR" -type f | sort | while read -r f; do
  echo "  $f"
done
echo ""
echo "Done! Import with: import { $COMPONENT_NAME } from './$COMPONENT_DIR'"
