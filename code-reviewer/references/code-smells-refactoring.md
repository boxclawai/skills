# Code Smells & Refactoring Patterns Reference

## Table of Contents

1. [Code Smell Catalog](#code-smell-catalog)
2. [Refactoring Techniques](#refactoring-techniques)
3. [Clean Code Principles](#clean-code-principles)
4. [Complexity Metrics](#complexity-metrics)
5. [Common Anti-Patterns](#common-anti-patterns)
6. [Refactoring Recipes](#refactoring-recipes)
7. [Technical Debt Classification](#technical-debt-classification)
8. [When NOT to Refactor](#when-not-to-refactor)

---

## Code Smell Catalog

### Bloaters (Code that grows too large)

```
God Class / God Object
  Symptom:   Class has 500+ lines, 20+ methods, 15+ fields
  Impact:    Hard to understand, test, and modify
  Refactor:  Extract classes by responsibility

Long Method
  Symptom:   Method has 30+ lines, multiple levels of abstraction
  Impact:    Hard to read, test individual paths
  Refactor:  Extract method, replace temp with query

Long Parameter List
  Symptom:   Method takes 4+ parameters
  Impact:    Hard to call correctly, easy to mix up order
  Refactor:  Introduce parameter object, use builder pattern

Data Clumps
  Symptom:   Same group of fields/params appear together repeatedly
             (startDate, endDate, timezone) or (street, city, zip)
  Impact:    Duplication, missing abstraction
  Refactor:  Extract class (DateRange, Address)

Primitive Obsession
  Symptom:   Using strings for email, phone, currency, status
  Impact:    No validation, no behavior, easy to mix up
  Refactor:  Introduce value objects (Email, Money, OrderStatus)
```

### Object-Orientation Abusers

```
Switch Statements / Long if-else chains
  Symptom:   switch/if-else on type field scattered across codebase
  Impact:    Adding new type requires modifying many files
  Refactor:  Replace with polymorphism, strategy pattern

Refused Bequest
  Symptom:   Subclass doesn't use most inherited methods
  Impact:    Violates Liskov substitution
  Refactor:  Replace inheritance with delegation/composition

Feature Envy
  Symptom:   Method uses data from another class more than its own
  Impact:    Logic in wrong place, tight coupling
  Refactor:  Move method to the class it envies

Inappropriate Intimacy
  Symptom:   Classes access each other's private fields/methods
  Impact:    Tight coupling, changes cascade
  Refactor:  Move methods, extract class, hide delegate
```

### Change Preventers

```
Divergent Change
  Symptom:   One class changed for many different reasons
  Impact:    Violates single responsibility
  Refactor:  Extract class per responsibility

Shotgun Surgery
  Symptom:   One logical change requires editing 10+ files
  Impact:    Easy to miss a file, incomplete changes
  Refactor:  Move related code together, consolidate

Parallel Inheritance Hierarchies
  Symptom:   Creating subclass in one hierarchy requires
             creating subclass in another
  Impact:    Duplication of hierarchy structure
  Refactor:  Merge hierarchies, use composition
```

### Dispensables (Unnecessary code)

```
Dead Code
  Symptom:   Unreachable code, unused variables, commented-out code
  Impact:    Noise, misleading, maintenance burden
  Refactor:  Delete it (version control has the history)

Speculative Generality
  Symptom:   Abstract class with one implementation,
             methods "for future use", unused parameters
  Impact:    Over-engineering, unnecessary complexity
  Refactor:  Remove until actually needed (YAGNI)

Duplicate Code
  Symptom:   Same logic in 2+ places (copy-paste)
  Impact:    Bug fixes must be applied in all copies
  Refactor:  Extract method/class, pull up to parent
```

### Couplers

```
Message Chains (Train Wreck)
  Symptom:   order.getCustomer().getAddress().getCity().getName()
  Impact:    Tight coupling to object structure
  Refactor:  Hide delegate, introduce query method

Middle Man
  Symptom:   Class only delegates to another class
  Impact:    Unnecessary indirection
  Refactor:  Remove middle man, use direct calls

Incomplete Library Class
  Symptom:   Need to extend library behavior
  Impact:    Can't modify library code
  Refactor:  Introduce wrapper/adapter, extension method
```

---

## Refactoring Techniques

### Extract Method

```java
// Before: Long method with mixed concerns
public void processOrder(Order order) {
    // Validate
    if (order.getItems().isEmpty()) throw new ValidationException("No items");
    if (order.getTotal().compareTo(BigDecimal.ZERO) <= 0) throw new ValidationException("Invalid total");

    // Calculate discount
    BigDecimal discount = BigDecimal.ZERO;
    if (order.getCustomer().isVip()) {
        discount = order.getTotal().multiply(new BigDecimal("0.10"));
    }
    if (order.getItems().size() > 10) {
        discount = discount.add(order.getTotal().multiply(new BigDecimal("0.05")));
    }
    order.setDiscount(discount);
    order.setFinalTotal(order.getTotal().subtract(discount));

    // Save and notify
    orderRepository.save(order);
    emailService.sendConfirmation(order.getCustomer().getEmail(), order);
    metricsService.recordOrder(order);
}

// After: Clear, testable methods
public void processOrder(Order order) {
    validate(order);
    applyDiscounts(order);
    save(order);
    notifyCustomer(order);
    recordMetrics(order);
}

private void validate(Order order) {
    if (order.getItems().isEmpty()) throw new ValidationException("No items");
    if (order.getTotal().compareTo(BigDecimal.ZERO) <= 0)
        throw new ValidationException("Invalid total");
}

private void applyDiscounts(Order order) {
    BigDecimal discount = discountCalculator.calculate(order);
    order.setDiscount(discount);
    order.setFinalTotal(order.getTotal().subtract(discount));
}
```

### Replace Conditional with Polymorphism

```java
// Before: Switch on type
public BigDecimal calculateShipping(Order order) {
    return switch (order.getShippingType()) {
        case "standard" -> new BigDecimal("5.00");
        case "express" -> new BigDecimal("15.00").add(
                order.getWeight().multiply(new BigDecimal("0.50")));
        case "overnight" -> new BigDecimal("25.00").add(
                order.getWeight().multiply(new BigDecimal("1.00")));
        case "free" -> BigDecimal.ZERO;
        default -> throw new IllegalArgumentException("Unknown shipping: " +
                order.getShippingType());
    };
}

// After: Strategy pattern
public sealed interface ShippingStrategy {
    BigDecimal calculate(Order order);

    record Standard() implements ShippingStrategy {
        public BigDecimal calculate(Order order) { return new BigDecimal("5.00"); }
    }
    record Express() implements ShippingStrategy {
        public BigDecimal calculate(Order order) {
            return new BigDecimal("15.00")
                    .add(order.getWeight().multiply(new BigDecimal("0.50")));
        }
    }
    record Overnight() implements ShippingStrategy {
        public BigDecimal calculate(Order order) {
            return new BigDecimal("25.00")
                    .add(order.getWeight().multiply(new BigDecimal("1.00")));
        }
    }
    record Free() implements ShippingStrategy {
        public BigDecimal calculate(Order order) { return BigDecimal.ZERO; }
    }
}
```

### Introduce Value Object

```java
// Before: Primitive obsession
public class User {
    private String email;        // Could be any string
    private String phone;        // No format validation
    private int amount;          // Cents? Dollars? What currency?
    private String status;       // Magic strings everywhere
}

// After: Type-safe value objects
public class User {
    private Email email;
    private PhoneNumber phone;
    private Money balance;
    private UserStatus status;
}

public record Email(String value) {
    public Email {
        if (value == null || !value.matches("^[\\w.-]+@[\\w.-]+\\.\\w{2,}$")) {
            throw new IllegalArgumentException("Invalid email: " + value);
        }
        value = value.toLowerCase().trim();
    }
}

public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "Amount required");
        Objects.requireNonNull(currency, "Currency required");
        if (amount.scale() > 2) {
            throw new IllegalArgumentException("Max 2 decimal places");
        }
    }

    public Money add(Money other) {
        if (!currency.equals(other.currency))
            throw new CurrencyMismatchException(currency, other.currency);
        return new Money(amount.add(other.amount), currency);
    }

    public static Money usd(String amount) {
        return new Money(new BigDecimal(amount), Currency.getInstance("USD"));
    }
}
```

### Replace Inheritance with Composition

```java
// Before: Fragile base class problem
public class ArrayList<E> extends AbstractList<E> { }
public class LoggingList<E> extends ArrayList<E> {
    @Override
    public boolean add(E e) {
        log.info("Adding: {}", e);
        return super.add(e);  // Tight coupling to parent
    }
    @Override
    public boolean addAll(Collection<? extends E> c) {
        log.info("Adding {} items", c.size());
        return super.addAll(c);  // May call add() internally = double logging!
    }
}

// After: Composition + delegation
public class LoggingList<E> implements List<E> {
    private final List<E> delegate;
    private final Logger log;

    public LoggingList(List<E> delegate) {
        this.delegate = delegate;
        this.log = LoggerFactory.getLogger(LoggingList.class);
    }

    @Override
    public boolean add(E e) {
        log.info("Adding: {}", e);
        return delegate.add(e);
    }

    @Override
    public boolean addAll(Collection<? extends E> c) {
        log.info("Adding {} items", c.size());
        return delegate.addAll(c);  // No double logging risk
    }
    // ... delegate all other methods
}
```

---

## Clean Code Principles

### Naming

```
Functions:  verb + noun          → calculateTotal(), validateEmail(), sendNotification()
Booleans:  is/has/can/should    → isActive, hasPermission, canDelete, shouldRetry
Classes:   noun                  → OrderProcessor, EmailValidator, PaymentGateway
Interfaces: adjective/-able      → Serializable, Cacheable, Retryable
Constants: SCREAMING_SNAKE      → MAX_RETRY_COUNT, DEFAULT_TIMEOUT_MS

Anti-patterns:
  ✗ data, info, temp, result   — too vague
  ✗ manager, handler, processor — overloaded terms
  ✗ Utils, Helper, Common       — dumping ground classes
  ✗ doStuff(), handle(), process() — meaningless verbs
  ✗ Single-letter variables      — except i,j in short loops
  ✗ Abbreviations               — use 'customer' not 'cust'
```

### Functions

```
Rules:
  1. Do one thing (single responsibility)
  2. One level of abstraction per function
  3. Max 3 parameters (use object for more)
  4. No side effects (or name them explicitly)
  5. Command-Query Separation:
     - Commands change state, return void
     - Queries return data, don't change state
  6. Max 20 lines (aim for 5-10)

Error handling:
  - Throw specific exceptions, not generic ones
  - Don't return null (use Optional or empty collection)
  - Don't pass null as parameter
  - Fail fast at boundaries
```

### Comments

```
Good comments:
  ✓ Legal (copyright, license)
  ✓ Explanation of intent (WHY, not WHAT)
  ✓ Warning of consequences
  ✓ TODO with ticket reference
  ✓ Javadoc on public APIs
  ✓ Clarification of obscure library behavior

Bad comments (should be refactored away):
  ✗ Paraphrasing code: // increment i by 1
  ✗ Commented-out code (use version control)
  ✗ Journal comments (use git log)
  ✗ Noise: // default constructor
  ✗ Closing brace comments: } // end if
  ✗ Misleading comments (outdated/wrong)
```

---

## Complexity Metrics

### Cyclomatic Complexity

```
Definition: Number of independent paths through code
Formula:    CC = E - N + 2P (edges - nodes + 2 * connected components)
Shortcut:   Count decision points + 1

Rating:
  1-5    Simple, low risk
  6-10   Moderate complexity
  11-20  High complexity, hard to test
  21+    Very high risk, refactor immediately

Each of these adds 1 to complexity:
  if, else if, case, for, while, do-while,
  catch, &&, ||, ?, throw (in some tools)
```

### Cognitive Complexity (SonarQube metric)

```
Better than cyclomatic for readability assessment.
Penalizes:
  - Nesting (each level adds more)
  - Breaks in linear flow (if, for, while, catch)
  - Boolean operator sequences (&&, ||)

Example:
  if (a) {                          // +1 (if)
      for (int i = 0; i < n; i++) { // +2 (for, nested)
          if (b && c) {             // +4 (if nested*2, &&)
              doSomething();
          }
      }
  }
  // Cognitive complexity: 7

Rating:
  0-5    Simple
  6-15   Needs attention
  15+    Refactor required
```

### Method/Class Size Guidelines

```
                    Warning     Refactor
  Method lines:     30          50+
  Method params:    3           5+
  Class lines:      200         400+
  Class methods:    15          25+
  Class fields:     8           15+
  File lines:       300         500+
  Nesting depth:    3           5+
  Import count:     15          25+
```

---

## Common Anti-Patterns

### The God Object

```java
// Anti-pattern: one class does everything
public class ApplicationManager {
    public User authenticateUser() { ... }
    public void sendEmail() { ... }
    public Order processOrder() { ... }
    public void generateReport() { ... }
    public void backupDatabase() { ... }
    public void renderDashboard() { ... }
    // 2000 more lines...
}

// Fix: split by responsibility
public class AuthenticationService { ... }
public class EmailService { ... }
public class OrderService { ... }
public class ReportService { ... }
```

### Premature Optimization

```java
// Anti-pattern: optimizing before measuring
// Using byte arrays and bitwise ops for "performance"
public boolean isEven(int n) {
    return (n & 1) == 0;  // "faster than n % 2"
}

// Reality: JIT compiler handles this. Write clear code first.
public boolean isEven(int n) {
    return n % 2 == 0;  // Clear intent
}

// Rule: Make it work → Make it right → Make it fast (only if needed)
// Profile first, then optimize the actual bottleneck
```

### Exception Anti-Patterns

```java
// Anti-pattern 1: Pokemon exception handling
try {
    doEverything();
} catch (Exception e) {
    // Gotta catch 'em all... and ignore them
}

// Anti-pattern 2: Exception for control flow
try {
    user = userRepository.findById(id);
} catch (NoSuchElementException e) {
    user = createDefaultUser();
}

// Better:
Optional<User> user = userRepository.findById(id);
User result = user.orElseGet(this::createDefaultUser);

// Anti-pattern 3: Logging and rethrowing
catch (IOException e) {
    log.error("Failed", e);
    throw e;  // Logged twice when caught again upstream
}

// Better: log OR rethrow, not both
catch (IOException e) {
    throw new OrderProcessingException("Failed to process order " + id, e);
}
```

---

## Technical Debt Classification

### Debt Quadrant (Martin Fowler)

```
              Deliberate              Inadvertent
         ┌─────────────────────┬─────────────────────┐
Reckless │ "We don't have time │ "What's a design    │
         │  for design"        │  pattern?"          │
         ├─────────────────────┼─────────────────────┤
Prudent  │ "Ship now, refactor │ "Now we know how we │
         │  before next sprint"│  should have done it"│
         └─────────────────────┴─────────────────────┘

Priority for repayment:
  1. Security debt      → Fix immediately
  2. Reliability debt   → Fix this sprint
  3. Performance debt   → Schedule for next sprint
  4. Maintainability    → Refactor opportunistically
  5. Style/convention   → Automate with linters
```

### Tracking Technical Debt

```markdown
## Tech Debt Register (maintain in wiki/notion)

| ID | Description | Impact | Effort | Priority | Owner | Ticket |
|----|-------------|--------|--------|----------|-------|--------|
| TD-001 | OrderService is 800 lines | Hard to modify, test | 3 days | High | @alice | PROJ-456 |
| TD-002 | No index on orders.created_at | Slow queries >10K rows | 1 hour | Critical | @bob | PROJ-457 |
| TD-003 | Inline SQL strings | SQL injection risk | 2 days | Critical | @carol | PROJ-458 |
| TD-004 | No retry on payment gateway | Intermittent failures | 4 hours | High | @dave | PROJ-459 |

Rule of thumb: Spend 15-20% of sprint capacity on tech debt
```

---

## When NOT to Refactor

```
Don't refactor when:
  1. Code is working and rarely changed ("if it ain't broke...")
  2. You're about to rewrite/replace the module
  3. No tests exist (write tests first, then refactor)
  4. Under tight deadline with no buffer for risk
  5. Refactoring for aesthetics, not actual pain
  6. The "improvement" adds complexity without benefit

Always refactor when:
  1. You need to add a feature and the code resists it
  2. You're fixing a bug caused by poor structure
  3. Code review reveals security issues
  4. Performance problems traced to specific code
  5. New team member can't understand the code
  6. Duplicated logic is causing sync bugs

Boy Scout Rule: "Leave the code better than you found it"
  — But don't refactor unrelated code in a feature PR
  — Make a separate refactoring PR for clarity
```
