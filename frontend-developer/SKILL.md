---
name: frontend-developer
version: "1.0.0"
description: "Frontend development expert: React, Vue, Angular, Svelte, CSS/Tailwind, responsive design, accessibility (a11y), performance optimization, state management, component architecture, and browser APIs. Use when: (1) building UI components or pages, (2) implementing responsive layouts, (3) optimizing Core Web Vitals or bundle size, (4) fixing CSS/layout issues, (5) adding client-side interactivity or animations, (6) reviewing frontend code for accessibility or performance. NOT for: backend API logic, database operations, or infrastructure."
tags: [react, vue, angular, svelte, css, tailwind, accessibility, performance, components, responsive]
author: "boxclaw"
references:
  - references/framework-patterns.md
  - references/css-recipes.md
metadata:
  boxclaw:
    emoji: "🎨"
    category: "programming-role"
---

# Frontend Developer

Expert guidance for building modern, accessible, performant user interfaces.

## Core Competencies

### 1. Component Architecture

Design reusable, composable components following these principles:

```
Single Responsibility: One component = one purpose
Composition over Inheritance: Compose small components into larger ones
Props Down, Events Up: Unidirectional data flow
Controlled vs Uncontrolled: Know when to use each pattern
```

#### React Pattern

```jsx
// Compound component pattern for flexible APIs
function Select({ children, value, onChange }) {
  return (
    <SelectContext.Provider value={{ value, onChange }}>
      <div role="listbox">{children}</div>
    </SelectContext.Provider>
  );
}
Select.Option = function Option({ value, children }) {
  const ctx = useContext(SelectContext);
  return (
    <div role="option" aria-selected={ctx.value === value}
      onClick={() => ctx.onChange(value)}>
      {children}
    </div>
  );
};
```

#### Vue Pattern

```vue
<!-- Composable + slot pattern -->
<template>
  <div class="data-table">
    <slot name="header" :columns="columns" />
    <slot name="row" v-for="row in data" :row="row" :key="row.id" />
    <slot name="empty" v-if="!data.length">No data</slot>
  </div>
</template>
```

### 2. State Management Decision Tree

```
Local UI state (toggle, form input) → useState / ref
Shared between siblings → lift state to parent
App-wide (auth, theme, locale) → Context / Pinia / Redux
Server data (API responses) → TanStack Query / SWR
URL state (filters, pagination) → URL search params
Complex async flows → Zustand / Redux + middleware
```

### 3. CSS & Layout Strategy

```
Layout system: CSS Grid (2D) + Flexbox (1D)
Spacing: Use design tokens (--space-1, --space-2, ...)
Typography: Fluid type scale with clamp()
Colors: CSS custom properties + prefers-color-scheme
Responsive: Mobile-first, breakpoint tokens
Animation: prefer-reduced-motion, GPU-composited transforms
```

#### Responsive Breakpoints

```css
/* Mobile-first approach */
:root {
  --bp-sm: 640px;
  --bp-md: 768px;
  --bp-lg: 1024px;
  --bp-xl: 1280px;
}

.container {
  width: 100%;
  padding-inline: var(--space-4);
}
@media (min-width: 768px) {
  .container { max-width: 720px; margin-inline: auto; }
}
@media (min-width: 1024px) {
  .container { max-width: 960px; }
}
```

### 4. Performance Checklist

| Metric | Target | How to Achieve |
|--------|--------|----------------|
| LCP | < 2.5s | Optimize critical rendering path, preload hero image |
| FID/INP | < 200ms | Code-split, defer non-critical JS, use `startTransition` |
| CLS | < 0.1 | Set explicit dimensions on images/embeds, font-display: swap |
| Bundle Size | < 200KB gzip | Tree-shaking, dynamic imports, analyze with bundler plugin |
| TTI | < 3.5s | Lazy load below-fold, prefetch routes |

#### Code Splitting Pattern

```jsx
// Route-level splitting
const Dashboard = lazy(() => import('./pages/Dashboard'));
const Settings = lazy(() => import('./pages/Settings'));

// Component-level splitting
const HeavyChart = lazy(() => import('./components/HeavyChart'));
```

### 5. Accessibility (a11y) Standards

```
WCAG 2.1 AA minimum:
- Semantic HTML first (button, nav, main, article)
- ARIA only when native semantics insufficient
- Keyboard navigation: all interactive elements focusable
- Color contrast: 4.5:1 text, 3:1 large text/UI
- Focus indicators: visible, high contrast
- Screen reader: meaningful alt text, aria-labels
- Forms: label + input association, error announcements
```

#### Testing a11y

```bash
# Automated
npx axe-core/cli http://localhost:3000
npx pa11y http://localhost:3000

# In code
import { axe } from 'jest-axe';
expect(await axe(container)).toHaveNoViolations();
```

### 6. Build & Tooling

| Tool | Use Case |
|------|----------|
| Vite | Dev server + build (fast HMR, ESM-native) |
| Turbopack/webpack | Large monorepo builds |
| ESLint + Prettier | Code quality + formatting |
| Storybook | Component development + visual testing |
| Playwright | E2E browser testing |
| Lighthouse CI | Performance regression in CI |

## Quick Commands

```bash
# Dev server
npm run dev                          # Start Vite dev server
npx storybook dev                    # Start Storybook

# Build & analyze
npm run build                        # Production build
npx vite-bundle-visualizer           # Bundle size analysis

# Testing
npx vitest                           # Unit tests (watch mode)
npx playwright test                  # E2E tests
npx lighthouse http://localhost:3000 --view  # Performance audit

# Code quality
npx eslint . --fix                   # Lint + autofix
npx tsc --noEmit                     # Type check only
```

## Workflow

```
1. Design review → understand specs, breakpoints, interactions
2. Component tree → map UI into component hierarchy
3. Build atoms → small reusable primitives first
4. Compose pages → assemble atoms into features
5. Accessibility pass → keyboard, screen reader, contrast
6. Performance audit → Lighthouse, bundle analysis
7. Cross-browser test → Chrome, Firefox, Safari, mobile
```

## References

- **Framework patterns**: See [references/framework-patterns.md](references/framework-patterns.md)
- **CSS recipes**: See [references/css-recipes.md](references/css-recipes.md)
