# Static Analysis Tools Reference

## Table of Contents

1. [SonarQube / SonarCloud Deep Dive](#sonarqube--sonarcloud-deep-dive)
2. [Java Tools: PMD, SpotBugs, Checkstyle, ArchUnit](#java-tools)
3. [JavaScript/TypeScript: ESLint, Biome, Prettier](#javascripttypescript-tools)
4. [Python: Ruff, mypy, Bandit, Pylint](#python-tools)
5. [Go: golangci-lint, govulncheck](#go-tools)
6. [Multi-Language: MegaLinter, Pre-commit](#multi-language-tools)
7. [Security Scanning: Snyk, Trivy, Semgrep](#security-scanning)
8. [IDE Integration](#ide-integration)
9. [Pre-commit Hooks](#pre-commit-hooks)
10. [CI/CD Pipeline Templates](#cicd-pipeline-templates)

---

## SonarQube / SonarCloud Deep Dive

### Installation (Docker)

```yaml
# docker-compose.yml
services:
  sonarqube:
    image: sonarqube:lts-community
    ports:
      - "9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar
      POSTGRES_DB: sonar
    volumes:
      - postgresql_data:/var/lib/postgresql/data

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  postgresql_data:
```

```bash
# Start SonarQube
docker compose up -d

# Access UI: http://localhost:9000
# Default credentials: admin/admin (change on first login)
# Generate token: Administration → Security → Users → Tokens
```

### SonarQube Quality Profiles

```
Built-in profiles:
  Sonar way (default)     — Balanced, good starting point
  Sonar way (extended)    — Stricter, more rules

Custom profile best practices:
  1. Start with "Sonar way" as parent
  2. Activate additional security rules
  3. Activate naming convention rules
  4. Set severity thresholds per team agreement
  5. Export and version control the profile
```

### Key SonarQube Metrics

```
Reliability:
  Bugs                    Code that is demonstrably wrong
  Reliability Rating      A=0 bugs, B=1+ minor, C=1+ major, D=1+ critical, E=1+ blocker

Security:
  Vulnerabilities         Code that can be exploited
  Security Hotspots       Security-sensitive code that needs manual review
  Security Rating         A=0 vulns, B=1+ minor, C=1+ major, D=1+ critical, E=1+ blocker

Maintainability:
  Code Smells             Maintainability issues
  Technical Debt          Estimated time to fix all code smells
  Debt Ratio              Tech debt / development cost
  Maintainability Rating  A=<5%, B=6-10%, C=11-20%, D=21-50%, E=>50%

Coverage:
  Line Coverage           Lines executed by tests / total lines
  Branch Coverage         Branches executed / total branches
  Condition Coverage      Conditions evaluated true+false / total conditions

Duplications:
  Duplicated Lines (%)    Percentage of duplicated code
  Duplicated Blocks       Number of duplicated code blocks
```

### Custom Quality Gate

```
Via API:
  # Create quality gate
  curl -u admin:$PASSWORD -X POST \
    "http://localhost:9000/api/qualitygates/create?name=Strict"

  # Add conditions
  curl -u admin:$PASSWORD -X POST \
    "http://localhost:9000/api/qualitygates/create_condition" \
    -d "gateId=2&metric=new_coverage&op=LT&error=85"

  curl -u admin:$PASSWORD -X POST \
    "http://localhost:9000/api/qualitygates/create_condition" \
    -d "gateId=2&metric=new_duplicated_lines_density&op=GT&error=2"

  curl -u admin:$PASSWORD -X POST \
    "http://localhost:9000/api/qualitygates/create_condition" \
    -d "gateId=2&metric=new_reliability_rating&op=GT&error=1"

  curl -u admin:$PASSWORD -X POST \
    "http://localhost:9000/api/qualitygates/create_condition" \
    -d "gateId=2&metric=new_security_rating&op=GT&error=1"
```

### SonarQube Configuration File

```properties
# sonar-project.properties (multi-language project)
sonar.projectKey=my-project
sonar.projectName=My Project
sonar.projectVersion=1.0

# Sources
sonar.sources=src/main/java,frontend/src
sonar.tests=src/test/java,frontend/src/__tests__
sonar.java.binaries=target/classes

# Coverage
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
sonar.javascript.lcov.reportPaths=frontend/coverage/lcov.info

# Exclusions
sonar.exclusions=\
  **/node_modules/**,\
  **/build/**,\
  **/target/**,\
  **/generated/**,\
  **/*.spec.ts,\
  **/*.test.ts

# Duplication exclusions (DTOs are naturally similar)
sonar.cpd.exclusions=\
  **/dto/**,\
  **/entity/**,\
  **/model/**

# Encoding
sonar.sourceEncoding=UTF-8
```

---

## Java Tools

### PMD Rules Configuration

```xml
<!-- pmd-ruleset.xml -->
<?xml version="1.0"?>
<ruleset name="Custom Rules"
         xmlns="http://pmd.sourceforge.net/ruleset/2.0.0">

    <description>Project-specific PMD rules</description>

    <!-- Best practices -->
    <rule ref="category/java/bestpractices.xml">
        <exclude name="JUnitTestsShouldIncludeAssert"/>
    </rule>

    <!-- Code style -->
    <rule ref="category/java/codestyle.xml">
        <exclude name="AtLeastOneConstructor"/>
        <exclude name="CommentDefaultAccessModifier"/>
        <exclude name="OnlyOneReturn"/>
    </rule>

    <!-- Common errors -->
    <rule ref="category/java/errorprone.xml">
        <exclude name="BeanMembersShouldSerialize"/>
    </rule>

    <!-- Performance -->
    <rule ref="category/java/performance.xml"/>

    <!-- Security -->
    <rule ref="category/java/security.xml"/>

    <!-- Design -->
    <rule ref="category/java/design.xml">
        <exclude name="LawOfDemeter"/>
    </rule>

    <!-- Custom thresholds -->
    <rule ref="category/java/design.xml/CyclomaticComplexity">
        <properties>
            <property name="methodReportLevel" value="15"/>
            <property name="classReportLevel" value="80"/>
        </properties>
    </rule>

    <rule ref="category/java/design.xml/NPathComplexity">
        <properties>
            <property name="reportLevel" value="200"/>
        </properties>
    </rule>

    <rule ref="category/java/design.xml/TooManyMethods">
        <properties>
            <property name="maxmethods" value="20"/>
        </properties>
    </rule>
</ruleset>
```

### SpotBugs with FindSecBugs

```xml
<!-- spotbugs-exclude.xml -->
<FindBugsFilter>
    <!-- Exclude generated code -->
    <Match>
        <Source name="~.*Generated.*"/>
    </Match>

    <!-- Exclude test classes from certain checks -->
    <Match>
        <Class name="~.*Test"/>
        <Bug pattern="RCN_REDUNDANT_NULLCHECK_OF_NONNULL_VALUE"/>
    </Match>

    <!-- Exclude Spring configuration classes -->
    <Match>
        <Class name="~.*Config"/>
        <Bug pattern="EI_EXPOSE_REP"/>
    </Match>
</FindBugsFilter>
```

### ArchUnit Rules

```java
@AnalyzeClasses(packages = "com.example", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureRules {

    // No field injection
    @ArchTest
    static final ArchRule noFieldInjection = noFields()
            .should().beAnnotatedWith(Autowired.class)
            .because("Use constructor injection instead");

    // Controllers must not access repositories
    @ArchTest
    static final ArchRule controllersDoNotAccessRepos = noClasses()
            .that().resideInAPackage("..controller..")
            .should().dependOnClassesThat().resideInAPackage("..repository..")
            .because("Controllers should use services");

    // Services must not depend on controllers
    @ArchTest
    static final ArchRule noCyclicDependencies = slices()
            .matching("com.example.(*)..")
            .should().beFreeOfCycles();

    // Entities must not use Lombok @Data
    @ArchTest
    static final ArchRule noDataOnEntities = noClasses()
            .that().areAnnotatedWith(Entity.class)
            .should().beAnnotatedWith(lombok.Data.class)
            .because("@Data generates equals/hashCode using all fields");

    // All public service methods should be logged
    @ArchTest
    static final ArchRule servicesUseSlf4j = classes()
            .that().resideInAPackage("..service..")
            .and().areNotInterfaces()
            .should().beAnnotatedWith(Slf4j.class);
}
```

---

## JavaScript/TypeScript Tools

### ESLint 9 (Flat Config)

```javascript
// eslint.config.js
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import security from 'eslint-plugin-security';
import importPlugin from 'eslint-plugin-import';

export default tseslint.config(
    eslint.configs.recommended,
    ...tseslint.configs.strictTypeChecked,
    {
        plugins: { react, 'react-hooks': reactHooks, security, import: importPlugin },
        rules: {
            // Security
            'no-eval': 'error',
            'no-implied-eval': 'error',
            'security/detect-object-injection': 'warn',
            'security/detect-non-literal-regexp': 'warn',
            'security/detect-unsafe-regex': 'error',
            'security/detect-buffer-noassert': 'error',
            'security/detect-possible-timing-attacks': 'warn',

            // Code quality
            '@typescript-eslint/no-explicit-any': 'error',
            '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
            '@typescript-eslint/no-floating-promises': 'error',
            '@typescript-eslint/no-misused-promises': 'error',
            '@typescript-eslint/prefer-nullish-coalescing': 'error',
            '@typescript-eslint/strict-boolean-expressions': 'error',

            // React
            'react-hooks/rules-of-hooks': 'error',
            'react-hooks/exhaustive-deps': 'error',

            // Import order
            'import/order': ['error', {
                groups: ['builtin', 'external', 'internal', 'parent', 'sibling', 'index'],
                'newlines-between': 'always',
                alphabetize: { order: 'asc' }
            }],

            // Complexity
            'complexity': ['warn', 15],
            'max-depth': ['warn', 4],
            'max-lines-per-function': ['warn', 50],
        }
    },
    { ignores: ['dist/', 'node_modules/', 'coverage/', '*.config.*'] }
);
```

### Biome (Faster alternative to ESLint + Prettier)

```json
// biome.json
{
  "$schema": "https://biomejs.dev/schemas/1.5.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "complexity": {
        "noBannedTypes": "error",
        "noExcessiveCognitiveComplexity": { "level": "warn", "options": { "maxAllowedComplexity": 15 } }
      },
      "security": {
        "noDangerouslySetInnerHtml": "error",
        "noGlobalEval": "error"
      },
      "suspicious": {
        "noExplicitAny": "error",
        "noConsoleLog": "warn"
      },
      "performance": {
        "noAccumulatingSpread": "warn",
        "noDelete": "warn"
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  }
}
```

---

## Python Tools

### Ruff (All-in-one Python linter)

```toml
# pyproject.toml
[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = [
    "E", "W",    # pycodestyle
    "F",         # pyflakes
    "I",         # isort
    "N",         # pep8-naming
    "S",         # flake8-bandit (security)
    "B",         # flake8-bugbear
    "A",         # flake8-builtins
    "C4",        # flake8-comprehensions
    "DTZ",       # flake8-datetimez (timezone awareness)
    "T20",       # flake8-print
    "SIM",       # flake8-simplify
    "UP",        # pyupgrade
    "ERA",       # eradicate (commented code)
    "RUF",       # ruff-specific
    "PT",        # flake8-pytest-style
    "TCH",       # type-checking imports
    "PERF",      # perflint (performance)
    "FURB",      # refurb (modern Python)
]
ignore = ["E501", "S101"]  # Line length (formatter handles), assert in tests

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "S106"]  # Allow assert and hardcoded passwords in tests

[tool.ruff.lint.isort]
known-first-party = ["myapp"]
```

### mypy Strict Configuration

```toml
[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
disallow_any_generics = true
check_untyped_defs = true
no_implicit_optional = true
warn_redundant_casts = true
warn_unused_ignores = true

[[tool.mypy.overrides]]
module = ["tests.*"]
disallow_untyped_defs = false

[[tool.mypy.overrides]]
module = ["third_party_lib.*"]
ignore_missing_imports = true
```

---

## Go Tools

### golangci-lint Configuration

```yaml
# .golangci.yml
run:
  timeout: 5m
  tests: true

linters:
  enable:
    - errcheck       # Check error returns
    - govet          # Go vet
    - staticcheck    # Advanced checks
    - gosec          # Security
    - ineffassign    # Unused assignments
    - gocritic       # Code quality
    - revive         # Linting
    - gocyclo        # Cyclomatic complexity
    - dupl           # Duplication
    - misspell       # Spelling
    - gosimple       # Simplify code
    - unconvert      # Unnecessary conversions
    - unparam        # Unused parameters
    - prealloc       # Slice preallocation

linters-settings:
  gocyclo:
    min-complexity: 15
  dupl:
    threshold: 100
  gocritic:
    enabled-tags:
      - diagnostic
      - style
      - performance
      - security
  gosec:
    excludes:
      - G104  # Unhandled errors (in tests)

issues:
  exclude-rules:
    - path: _test\.go
      linters: [gosec, dupl]
```

---

## Security Scanning

### Semgrep Rules

```yaml
# .semgrep.yml
rules:
  - id: no-exec-user-input
    patterns:
      - pattern: exec($USER_INPUT)
      - pattern-not: exec("...")
    message: "Do not pass user input to exec()"
    languages: [python, javascript]
    severity: ERROR

  - id: sql-injection
    patterns:
      - pattern: |
          $QUERY = "..." + $USER_INPUT + "..."
          $DB.execute($QUERY)
    message: "Possible SQL injection. Use parameterized queries."
    languages: [python]
    severity: ERROR

  - id: hardcoded-secret
    patterns:
      - pattern: |
          $VAR = "...$SECRET..."
      - metavariable-regex:
          metavariable: $SECRET
          regex: "(password|secret|key|token|api_key)\\s*=\\s*['\"].{8,}['\"]"
    message: "Possible hardcoded secret"
    languages: [python, javascript, java]
    severity: WARNING
```

```bash
# Run Semgrep
semgrep --config auto .
semgrep --config p/security-audit .
semgrep --config p/owasp-top-ten .

# Trivy comprehensive scan
trivy fs --security-checks vuln,secret,config .
```

---

## Pre-commit Hooks

### Husky + lint-staged (JavaScript)

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix --max-warnings 0", "prettier --write"],
    "*.{json,md,yml}": ["prettier --write"],
    "*.{css,scss}": ["stylelint --fix", "prettier --write"]
  }
}
```

```bash
npx husky init
echo "npx lint-staged" > .husky/pre-commit
echo "npx commitlint --edit \$1" > .husky/commit-msg
```

### pre-commit framework (Python/Multi-language)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: detect-private-key
      - id: no-commit-to-branch
        args: ['--branch', 'main']

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.3.0
    hooks:
      - id: ruff
        args: ['--fix']
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

---

## CI/CD Pipeline Templates

### Complete Quality Pipeline (GitHub Actions)

```yaml
name: Code Quality

on:
  pull_request:
    branches: [main, develop]

concurrency:
  group: quality-${{ github.head_ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npx eslint . --max-warnings 0
      - run: npx prettier --check .
      - run: npx tsc --noEmit

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npx vitest --coverage --reporter=junit
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          security-checks: vuln,secret
          severity: HIGH,CRITICAL
      - name: Run Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: p/security-audit

  sonarcloud:
    needs: [test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/download-artifact@v4
        with:
          name: coverage
          path: coverage/
      - uses: SonarSource/sonarcloud-github-action@master
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
