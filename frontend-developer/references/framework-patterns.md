# Framework Patterns Reference

## Table of Contents

1. [React Patterns](#react-patterns)
2. [Vue 3 Patterns](#vue-3-patterns)
3. [Svelte Patterns](#svelte-patterns)
4. [Angular Patterns](#angular-patterns)
5. [Cross-Framework State Patterns](#cross-framework-state-patterns)

---

## React Patterns

### Custom Hook Pattern

```tsx
// useAsync - Production-grade async operation hook
function useAsync<T>(asyncFn: () => Promise<T>, deps: DependencyList = []) {
  const [state, setState] = useState<{
    data: T | null;
    error: Error | null;
    status: 'idle' | 'pending' | 'success' | 'error';
  }>({ data: null, error: null, status: 'idle' });

  const execute = useCallback(async () => {
    setState({ data: null, error: null, status: 'pending' });
    try {
      const data = await asyncFn();
      setState({ data, error: null, status: 'success' });
      return data;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      setState({ data: null, error: err, status: 'error' });
      throw err;
    }
  }, deps);

  return { ...state, execute };
}
```

### Compound Component Pattern

```tsx
// Production compound component with context
interface TabsContextType {
  activeTab: string;
  setActiveTab: (id: string) => void;
}

const TabsContext = createContext<TabsContextType | null>(null);

function useTabsContext() {
  const ctx = useContext(TabsContext);
  if (!ctx) throw new Error('Tab components must be used within <Tabs>');
  return ctx;
}

function Tabs({ defaultTab, children, onChange }: TabsProps) {
  const [activeTab, setActiveTab] = useState(defaultTab);

  const handleChange = useCallback((id: string) => {
    setActiveTab(id);
    onChange?.(id);
  }, [onChange]);

  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab: handleChange }}>
      <div role="tablist">{children}</div>
    </TabsContext.Provider>
  );
}

Tabs.Tab = function Tab({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab, setActiveTab } = useTabsContext();
  return (
    <button
      role="tab"
      aria-selected={activeTab === id}
      aria-controls={`panel-${id}`}
      onClick={() => setActiveTab(id)}
      className={activeTab === id ? 'tab-active' : 'tab'}
    >
      {children}
    </button>
  );
};

Tabs.Panel = function Panel({ id, children }: { id: string; children: ReactNode }) {
  const { activeTab } = useTabsContext();
  if (activeTab !== id) return null;
  return (
    <div role="tabpanel" id={`panel-${id}`} aria-labelledby={`tab-${id}`}>
      {children}
    </div>
  );
};
```

### Render Props / Headless Component

```tsx
// Headless toggle component - logic without UI
interface UseToggleReturn {
  isOpen: boolean;
  open: () => void;
  close: () => void;
  toggle: () => void;
  buttonProps: {
    onClick: () => void;
    'aria-expanded': boolean;
    'aria-controls': string;
  };
  contentProps: {
    id: string;
    role: string;
    hidden: boolean;
  };
}

function useToggle(id: string, defaultOpen = false): UseToggleReturn {
  const [isOpen, setIsOpen] = useState(defaultOpen);
  return {
    isOpen,
    open: () => setIsOpen(true),
    close: () => setIsOpen(false),
    toggle: () => setIsOpen(prev => !prev),
    buttonProps: {
      onClick: () => setIsOpen(prev => !prev),
      'aria-expanded': isOpen,
      'aria-controls': id,
    },
    contentProps: {
      id,
      role: 'region',
      hidden: !isOpen,
    },
  };
}
```

### Error Boundary Pattern

```tsx
interface ErrorBoundaryProps {
  fallback: ReactNode | ((error: Error, reset: () => void) => ReactNode);
  onError?: (error: Error, info: ErrorInfo) => void;
  children: ReactNode;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    this.props.onError?.(error, info);
    // Report to Sentry/Datadog
    reportError(error, { componentStack: info.componentStack });
  }

  reset = () => this.setState({ error: null });

  render() {
    if (this.state.error) {
      const { fallback } = this.props;
      return typeof fallback === 'function'
        ? fallback(this.state.error, this.reset)
        : fallback;
    }
    return this.props.children;
  }
}

// Usage with Suspense
function App() {
  return (
    <ErrorBoundary fallback={(err, reset) => (
      <div role="alert">
        <p>Something went wrong: {err.message}</p>
        <button onClick={reset}>Try again</button>
      </div>
    )}>
      <Suspense fallback={<Skeleton />}>
        <Dashboard />
      </Suspense>
    </ErrorBoundary>
  );
}
```

### React Server Components Pattern

```tsx
// Server component (default in Next.js App Router)
// Runs ONLY on server, zero client JS
async function ProductPage({ params }: { params: { id: string } }) {
  const product = await db.product.findUnique({ where: { id: params.id } });
  if (!product) notFound();

  return (
    <article>
      <h1>{product.name}</h1>
      <p>{product.description}</p>
      <PriceDisplay price={product.price} />
      {/* Client component for interactivity */}
      <AddToCartButton productId={product.id} />
    </article>
  );
}

// Client component (opt-in with 'use client')
'use client';
function AddToCartButton({ productId }: { productId: string }) {
  const [isPending, startTransition] = useTransition();
  const addToCart = useCartStore(state => state.add);

  return (
    <button
      disabled={isPending}
      onClick={() => startTransition(() => addToCart(productId))}
    >
      {isPending ? 'Adding...' : 'Add to Cart'}
    </button>
  );
}
```

---

## Vue 3 Patterns

### Composable Pattern

```typescript
// useAsync composable
import { ref, watchEffect, type Ref } from 'vue';

interface UseAsyncReturn<T> {
  data: Ref<T | null>;
  error: Ref<Error | null>;
  isLoading: Ref<boolean>;
  execute: () => Promise<T>;
}

export function useAsync<T>(fn: () => Promise<T>): UseAsyncReturn<T> {
  const data = ref<T | null>(null) as Ref<T | null>;
  const error = ref<Error | null>(null);
  const isLoading = ref(false);

  const execute = async () => {
    isLoading.value = true;
    error.value = null;
    try {
      const result = await fn();
      data.value = result;
      return result;
    } catch (e) {
      error.value = e instanceof Error ? e : new Error(String(e));
      throw error.value;
    } finally {
      isLoading.value = false;
    }
  };

  return { data, error, isLoading, execute };
}

// useLocalStorage composable
export function useLocalStorage<T>(key: string, defaultValue: T) {
  const stored = localStorage.getItem(key);
  const data = ref<T>(stored ? JSON.parse(stored) : defaultValue) as Ref<T>;

  watchEffect(() => {
    localStorage.setItem(key, JSON.stringify(data.value));
  });

  return data;
}
```

### Provide/Inject Pattern (Dependency Injection)

```typescript
// Theme provider
import { provide, inject, reactive, type InjectionKey } from 'vue';

interface Theme {
  mode: 'light' | 'dark';
  primary: string;
  toggle: () => void;
}

const ThemeKey: InjectionKey<Theme> = Symbol('theme');

export function provideTheme() {
  const theme = reactive<Theme>({
    mode: 'light',
    primary: '#3b82f6',
    toggle() {
      this.mode = this.mode === 'light' ? 'dark' : 'light';
    },
  });
  provide(ThemeKey, theme);
  return theme;
}

export function useTheme(): Theme {
  const theme = inject(ThemeKey);
  if (!theme) throw new Error('useTheme() requires provideTheme() in ancestor');
  return theme;
}
```

---

## Svelte Patterns

### Store Pattern

```typescript
// Writable store with persistence
import { writable, derived } from 'svelte/store';

function createPersistentStore<T>(key: string, initial: T) {
  const stored = typeof localStorage !== 'undefined'
    ? localStorage.getItem(key)
    : null;

  const store = writable<T>(stored ? JSON.parse(stored) : initial);

  store.subscribe(value => {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(key, JSON.stringify(value));
    }
  });

  return store;
}

// Cart store with derived values
export const cartItems = createPersistentStore<CartItem[]>('cart', []);

export const cartTotal = derived(cartItems, $items =>
  $items.reduce((sum, item) => sum + item.price * item.qty, 0)
);

export const cartCount = derived(cartItems, $items =>
  $items.reduce((sum, item) => sum + item.qty, 0)
);
```

---

## Angular Patterns

### Signal-Based State Management

```typescript
// Angular 17+ signals pattern
import { signal, computed, effect } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class CartService {
  private items = signal<CartItem[]>([]);

  readonly total = computed(() =>
    this.items().reduce((sum, i) => sum + i.price * i.qty, 0)
  );

  readonly count = computed(() =>
    this.items().reduce((sum, i) => sum + i.qty, 0)
  );

  constructor() {
    // Auto-persist to localStorage
    effect(() => {
      localStorage.setItem('cart', JSON.stringify(this.items()));
    });
  }

  add(product: Product) {
    this.items.update(items => {
      const existing = items.find(i => i.id === product.id);
      if (existing) {
        return items.map(i =>
          i.id === product.id ? { ...i, qty: i.qty + 1 } : i
        );
      }
      return [...items, { ...product, qty: 1 }];
    });
  }

  remove(productId: string) {
    this.items.update(items => items.filter(i => i.id !== productId));
  }
}
```

---

## Cross-Framework State Patterns

### Optimistic Updates

```typescript
// Works with any framework's state management
async function optimisticUpdate<T>({
  currentState,
  optimisticState,
  setState,
  serverAction,
  rollback,
}: {
  currentState: T;
  optimisticState: T;
  setState: (state: T) => void;
  serverAction: () => Promise<T>;
  rollback?: (error: Error) => void;
}): Promise<T> {
  // 1. Apply optimistic state immediately
  setState(optimisticState);

  try {
    // 2. Perform server action
    const serverState = await serverAction();
    // 3. Replace with server-confirmed state
    setState(serverState);
    return serverState;
  } catch (error) {
    // 4. Rollback on failure
    setState(currentState);
    rollback?.(error instanceof Error ? error : new Error(String(error)));
    throw error;
  }
}

// Usage: Like button
async function toggleLike(postId: string) {
  const current = getPost(postId);
  await optimisticUpdate({
    currentState: current,
    optimisticState: { ...current, liked: !current.liked, likes: current.likes + (current.liked ? -1 : 1) },
    setState: (post) => updatePost(postId, post),
    serverAction: () => api.toggleLike(postId),
    rollback: (err) => toast.error(`Failed: ${err.message}`),
  });
}
```

### Finite State Machine for UI

```typescript
// State machine for complex UI flows (form wizard, modals, etc.)
type FormState = 'idle' | 'editing' | 'validating' | 'submitting' | 'success' | 'error';
type FormEvent = 'EDIT' | 'VALIDATE' | 'SUBMIT' | 'SUCCESS' | 'ERROR' | 'RESET';

const transitions: Record<FormState, Partial<Record<FormEvent, FormState>>> = {
  idle:       { EDIT: 'editing' },
  editing:    { VALIDATE: 'validating' },
  validating: { SUBMIT: 'submitting', ERROR: 'editing' },
  submitting: { SUCCESS: 'success', ERROR: 'error' },
  success:    { RESET: 'idle' },
  error:      { EDIT: 'editing', RESET: 'idle' },
};

function transition(state: FormState, event: FormEvent): FormState {
  return transitions[state]?.[event] ?? state;
}
```
