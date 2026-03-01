# CSS Recipes Reference

## Table of Contents

1. [Design Token System](#design-token-system)
2. [Layout Recipes](#layout-recipes)
3. [Component Recipes](#component-recipes)
4. [Animation Recipes](#animation-recipes)
5. [Dark Mode](#dark-mode)
6. [Tailwind Patterns](#tailwind-patterns)

---

## Design Token System

```css
:root {
  /* Colors - HSL for easy manipulation */
  --color-primary-50: hsl(220, 95%, 97%);
  --color-primary-100: hsl(220, 93%, 93%);
  --color-primary-500: hsl(220, 90%, 56%);
  --color-primary-600: hsl(220, 85%, 48%);
  --color-primary-700: hsl(220, 80%, 40%);

  --color-neutral-50: hsl(0, 0%, 98%);
  --color-neutral-100: hsl(0, 0%, 96%);
  --color-neutral-200: hsl(0, 0%, 90%);
  --color-neutral-500: hsl(0, 0%, 50%);
  --color-neutral-800: hsl(0, 0%, 15%);
  --color-neutral-900: hsl(0, 0%, 9%);

  --color-success: hsl(142, 71%, 45%);
  --color-warning: hsl(38, 92%, 50%);
  --color-danger: hsl(0, 84%, 60%);

  /* Spacing scale (4px base) */
  --space-0: 0;
  --space-1: 0.25rem;   /* 4px */
  --space-2: 0.5rem;    /* 8px */
  --space-3: 0.75rem;   /* 12px */
  --space-4: 1rem;      /* 16px */
  --space-5: 1.25rem;   /* 20px */
  --space-6: 1.5rem;    /* 24px */
  --space-8: 2rem;      /* 32px */
  --space-10: 2.5rem;   /* 40px */
  --space-12: 3rem;     /* 48px */
  --space-16: 4rem;     /* 64px */

  /* Typography */
  --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;

  /* Fluid type scale using clamp() */
  --text-xs: clamp(0.694rem, 0.66rem + 0.17vw, 0.8rem);
  --text-sm: clamp(0.833rem, 0.78rem + 0.27vw, 1rem);
  --text-base: clamp(1rem, 0.93rem + 0.36vw, 1.25rem);
  --text-lg: clamp(1.2rem, 1.09rem + 0.54vw, 1.563rem);
  --text-xl: clamp(1.44rem, 1.28rem + 0.8vw, 1.953rem);
  --text-2xl: clamp(1.728rem, 1.49rem + 1.17vw, 2.441rem);
  --text-3xl: clamp(2.074rem, 1.73rem + 1.7vw, 3.052rem);

  --leading-tight: 1.25;
  --leading-normal: 1.5;
  --leading-relaxed: 1.75;

  /* Shadows */
  --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
  --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
  --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
  --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);

  /* Borders */
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;
  --radius-xl: 1rem;
  --radius-full: 9999px;

  /* Transitions */
  --ease-default: cubic-bezier(0.4, 0, 0.2, 1);
  --ease-in: cubic-bezier(0.4, 0, 1, 1);
  --ease-out: cubic-bezier(0, 0, 0.2, 1);
  --ease-bounce: cubic-bezier(0.34, 1.56, 0.64, 1);
  --duration-fast: 150ms;
  --duration-normal: 250ms;
  --duration-slow: 400ms;

  /* Z-index scale */
  --z-dropdown: 100;
  --z-sticky: 200;
  --z-overlay: 300;
  --z-modal: 400;
  --z-popover: 500;
  --z-toast: 600;
  --z-tooltip: 700;
}
```

---

## Layout Recipes

### Holy Grail Layout (Header + Sidebar + Main + Footer)

```css
.app-layout {
  display: grid;
  grid-template-rows: auto 1fr auto;
  grid-template-columns: minmax(200px, 280px) 1fr;
  grid-template-areas:
    "header  header"
    "sidebar main"
    "footer  footer";
  min-height: 100dvh;
}

.header  { grid-area: header; }
.sidebar { grid-area: sidebar; }
.main    { grid-area: main; overflow-y: auto; }
.footer  { grid-area: footer; }

@media (max-width: 768px) {
  .app-layout {
    grid-template-columns: 1fr;
    grid-template-areas:
      "header"
      "main"
      "footer";
  }
  .sidebar { display: none; } /* Use mobile nav instead */
}
```

### Auto-Responsive Grid (No Media Queries)

```css
.auto-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(300px, 100%), 1fr));
  gap: var(--space-6);
}
```

### Sticky Header with Scroll Shadow

```css
.sticky-header {
  position: sticky;
  top: 0;
  z-index: var(--z-sticky);
  background: var(--color-neutral-50);
  /* Shadow appears only when scrolled */
  box-shadow: 0 0 0 0 transparent;
  transition: box-shadow var(--duration-normal) var(--ease-default);
}
.sticky-header[data-scrolled="true"] {
  box-shadow: var(--shadow-md);
}
```

### Full-Bleed Layout

```css
.full-bleed-wrapper {
  display: grid;
  grid-template-columns:
    1fr
    min(65ch, 100% - var(--space-8))
    1fr;
}
.full-bleed-wrapper > * {
  grid-column: 2;
}
.full-bleed-wrapper > .full-bleed {
  grid-column: 1 / -1;
  width: 100%;
}
```

### Aspect Ratio Card Grid

```css
.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: var(--space-4);
}
.card {
  display: flex;
  flex-direction: column;
  border-radius: var(--radius-lg);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
  transition: box-shadow var(--duration-normal) var(--ease-default);
}
.card:hover { box-shadow: var(--shadow-lg); }
.card__image {
  aspect-ratio: 16 / 9;
  object-fit: cover;
  width: 100%;
}
.card__body {
  padding: var(--space-4);
  flex: 1;
  display: flex;
  flex-direction: column;
}
.card__actions { margin-top: auto; }
```

---

## Component Recipes

### Button System

```css
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-4);
  font-size: var(--text-sm);
  font-weight: 500;
  line-height: var(--leading-tight);
  border-radius: var(--radius-md);
  border: 1px solid transparent;
  cursor: pointer;
  transition: all var(--duration-fast) var(--ease-default);
  user-select: none;
  white-space: nowrap;
}
.btn:focus-visible {
  outline: 2px solid var(--color-primary-500);
  outline-offset: 2px;
}
.btn:disabled {
  opacity: 0.5;
  pointer-events: none;
}

/* Variants */
.btn-primary {
  background: var(--color-primary-600);
  color: white;
}
.btn-primary:hover { background: var(--color-primary-700); }

.btn-secondary {
  background: transparent;
  color: var(--color-neutral-800);
  border-color: var(--color-neutral-200);
}
.btn-secondary:hover { background: var(--color-neutral-100); }

.btn-danger {
  background: var(--color-danger);
  color: white;
}

.btn-ghost {
  background: transparent;
  color: var(--color-neutral-800);
}
.btn-ghost:hover { background: var(--color-neutral-100); }

/* Sizes */
.btn-sm { padding: var(--space-1) var(--space-3); font-size: var(--text-xs); }
.btn-lg { padding: var(--space-3) var(--space-6); font-size: var(--text-base); }

/* Loading state */
.btn-loading { pointer-events: none; }
.btn-loading::after {
  content: '';
  width: 1em;
  height: 1em;
  border: 2px solid transparent;
  border-top-color: currentColor;
  border-radius: var(--radius-full);
  animation: spin 0.6s linear infinite;
}
```

### Modal / Dialog

```css
.dialog-backdrop {
  position: fixed;
  inset: 0;
  background: rgb(0 0 0 / 0.5);
  z-index: var(--z-overlay);
  display: grid;
  place-items: center;
  padding: var(--space-4);
  animation: fade-in var(--duration-normal) var(--ease-out);
}

.dialog {
  background: white;
  border-radius: var(--radius-xl);
  box-shadow: var(--shadow-xl);
  width: min(500px, 100%);
  max-height: 85dvh;
  display: flex;
  flex-direction: column;
  animation: slide-up var(--duration-normal) var(--ease-out);
}
.dialog__header {
  padding: var(--space-6) var(--space-6) var(--space-4);
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.dialog__body {
  padding: 0 var(--space-6);
  overflow-y: auto;
  flex: 1;
}
.dialog__footer {
  padding: var(--space-4) var(--space-6) var(--space-6);
  display: flex;
  justify-content: flex-end;
  gap: var(--space-3);
}

@keyframes fade-in { from { opacity: 0; } }
@keyframes slide-up { from { opacity: 0; transform: translateY(16px); } }
```

### Toast Notification

```css
.toast-container {
  position: fixed;
  bottom: var(--space-6);
  right: var(--space-6);
  z-index: var(--z-toast);
  display: flex;
  flex-direction: column-reverse;
  gap: var(--space-3);
  pointer-events: none;
}
.toast {
  pointer-events: auto;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-4);
  background: var(--color-neutral-900);
  color: white;
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-lg);
  font-size: var(--text-sm);
  animation: toast-in var(--duration-normal) var(--ease-bounce);
  max-width: 380px;
}
.toast-success { border-left: 4px solid var(--color-success); }
.toast-error   { border-left: 4px solid var(--color-danger); }
.toast-warning { border-left: 4px solid var(--color-warning); }

@keyframes toast-in {
  from { opacity: 0; transform: translateX(100%); }
}
```

---

## Animation Recipes

### Safe Animations (Respects prefers-reduced-motion)

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}

/* GPU-composited transforms only (no layout thrashing) */
.animate-enter {
  animation: enter var(--duration-normal) var(--ease-out);
}

@keyframes enter {
  from {
    opacity: 0;
    transform: translateY(8px) scale(0.97);
  }
}

/* Skeleton loading */
.skeleton {
  background: linear-gradient(
    90deg,
    var(--color-neutral-200) 0%,
    var(--color-neutral-100) 50%,
    var(--color-neutral-200) 100%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s ease-in-out infinite;
  border-radius: var(--radius-md);
}

@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

/* Scroll-driven animation (modern browsers) */
@supports (animation-timeline: view()) {
  .reveal-on-scroll {
    animation: reveal linear both;
    animation-timeline: view();
    animation-range: entry 0% entry 100%;
  }
  @keyframes reveal {
    from { opacity: 0; transform: translateY(40px); }
    to { opacity: 1; transform: translateY(0); }
  }
}
```

---

## Dark Mode

```css
/* System preference + manual toggle */
:root {
  color-scheme: light dark;

  --bg: var(--color-neutral-50);
  --bg-surface: white;
  --text: var(--color-neutral-900);
  --text-muted: var(--color-neutral-500);
  --border: var(--color-neutral-200);
}

[data-theme="dark"],
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: hsl(220, 20%, 10%);
    --bg-surface: hsl(220, 20%, 14%);
    --text: hsl(0, 0%, 95%);
    --text-muted: hsl(0, 0%, 60%);
    --border: hsl(220, 15%, 25%);
  }
}

body {
  background: var(--bg);
  color: var(--text);
}
```

---

## Tailwind Patterns

### Common Component Classes

```html
<!-- Card -->
<div class="rounded-xl border border-neutral-200 bg-white p-6 shadow-sm
            transition-shadow hover:shadow-md dark:border-neutral-800 dark:bg-neutral-900">

<!-- Badge -->
<span class="inline-flex items-center rounded-full bg-blue-50 px-2.5 py-0.5
             text-xs font-medium text-blue-700 dark:bg-blue-900/30 dark:text-blue-400">

<!-- Input -->
<input class="w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-sm
              placeholder:text-neutral-400 focus:border-blue-500 focus:outline-none
              focus:ring-2 focus:ring-blue-500/20 dark:border-neutral-700 dark:bg-neutral-900" />

<!-- Avatar group -->
<div class="flex -space-x-2">
  <img class="size-8 rounded-full border-2 border-white dark:border-neutral-900" />
</div>

<!-- Truncate multiline -->
<p class="line-clamp-3">Long text that truncates at 3 lines...</p>

<!-- Responsive hide/show -->
<div class="hidden md:block">Desktop only</div>
<div class="md:hidden">Mobile only</div>
```
