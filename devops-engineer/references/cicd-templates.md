# CI/CD Templates Reference

## Table of Contents

1. [GitHub Actions: Full Production Pipeline](#github-actions-full-production-pipeline)
2. [GitLab CI: Comprehensive Pipeline](#gitlab-ci-comprehensive-pipeline)
3. [Reusable Workflows](#reusable-workflows)
4. [Docker Build with Layer Caching](#docker-build-with-layer-caching)
5. [Monorepo CI Strategy](#monorepo-ci-strategy)
6. [Release Automation](#release-automation)

---

## GitHub Actions: Full Production Pipeline

```yaml
name: CI/CD Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
  NODE_VERSION: '22'

jobs:
  # ==================== QUALITY GATES ====================
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm format:check
      - run: pnpm typecheck

  test-unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm test:unit -- --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/

  test-integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: testdb
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
        options: --health-cmd "redis-cli ping" --health-interval 5s
    env:
      DATABASE_URL: postgresql://test:test@localhost:5432/testdb
      REDIS_URL: redis://localhost:6379
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm db:migrate
      - run: pnpm test:integration

  test-e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: npx playwright install --with-deps chromium
      - run: pnpm test:e2e
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npx audit-ci --high
      - uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: fs
          severity: HIGH,CRITICAL
          exit-code: '1'

  # ==================== BUILD ====================
  build:
    needs: [lint, test-unit, test-integration, security]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      image-tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=semver,pattern={{version}}

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ==================== DEPLOY ====================
  deploy-staging:
    needs: build
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to staging
        run: |
          echo "Deploying ${{ needs.build.outputs.image-tag }} to staging"
          # kubectl set image deployment/app app=$REGISTRY/$IMAGE_NAME:${{ needs.build.outputs.image-tag }}
          # OR: fly deploy --image $REGISTRY/$IMAGE_NAME:${{ needs.build.outputs.image-tag }}

  deploy-production:
    needs: [build, test-e2e]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Run database migrations
        run: |
          echo "Running migrations..."
          # npx prisma migrate deploy

      - name: Deploy to production
        run: |
          echo "Deploying ${{ needs.build.outputs.image-tag }} to production"
          # kubectl set image deployment/app app=$REGISTRY/$IMAGE_NAME:${{ needs.build.outputs.image-tag }}

      - name: Health check
        run: |
          echo "Waiting for deployment..."
          sleep 30
          # curl -f https://api.myapp.com/health || exit 1

      - name: Notify
        if: always()
        run: |
          STATUS="${{ job.status }}"
          echo "Deployment $STATUS"
          # curl -X POST $SLACK_WEBHOOK -d '{"text":"Deploy '$STATUS': '${{ needs.build.outputs.image-tag }}'"}'
```

---

## GitLab CI: Comprehensive Pipeline

```yaml
# .gitlab-ci.yml — Production-grade GitLab CI pipeline
# Stages run sequentially; jobs within a stage run in parallel

stages:
  - quality
  - test
  - build
  - deploy

variables:
  DOCKER_HOST: tcp://docker:2376
  DOCKER_TLS_CERTDIR: "/certs"
  DOCKER_TLS_VERIFY: 1
  REGISTRY: registry.gitlab.com
  IMAGE_NAME: $CI_PROJECT_PATH
  NODE_VERSION: "22"
  POSTGRES_USER: test
  POSTGRES_PASSWORD: test
  POSTGRES_DB: testdb

# ==================== GLOBAL CACHE ====================
# Share node_modules across all jobs to speed up installs
default:
  cache:
    key:
      files:
        - pnpm-lock.yaml
    paths:
      - .pnpm-store/
    policy: pull

# ==================== QUALITY GATES ====================
lint:
  stage: quality
  image: node:${NODE_VERSION}-alpine
  before_script:
    - corepack enable && corepack prepare pnpm@latest --activate
    - pnpm config set store-dir .pnpm-store
    - pnpm install --frozen-lockfile
  script:
    - pnpm lint
    - pnpm format:check
    - pnpm typecheck
  cache:
    key:
      files:
        - pnpm-lock.yaml
    paths:
      - .pnpm-store/
    policy: pull-push  # First job seeds the cache

security-scan:
  stage: quality
  image: node:${NODE_VERSION}-alpine
  before_script:
    - corepack enable && corepack prepare pnpm@latest --activate
    - pnpm config set store-dir .pnpm-store
    - pnpm install --frozen-lockfile
  script:
    - npx audit-ci --high
  allow_failure: false

container-scan:
  stage: quality
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy fs --severity HIGH,CRITICAL --exit-code 1 .
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# ==================== TEST ====================
test-unit:
  stage: test
  image: node:${NODE_VERSION}-alpine
  before_script:
    - corepack enable && corepack prepare pnpm@latest --activate
    - pnpm config set store-dir .pnpm-store
    - pnpm install --frozen-lockfile
  script:
    - pnpm test:unit -- --coverage
  coverage: '/All files\s*\|\s*(\d+\.?\d*)\s*\|/'
  artifacts:
    when: always
    paths:
      - coverage/
    reports:
      junit: coverage/junit.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml
    expire_in: 7 days

test-integration:
  stage: test
  image: node:${NODE_VERSION}-alpine
  services:
    - name: postgres:17-alpine
      alias: postgres
    - name: redis:7-alpine
      alias: redis
  variables:
    DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
    REDIS_URL: redis://redis:6379
  before_script:
    - corepack enable && corepack prepare pnpm@latest --activate
    - pnpm config set store-dir .pnpm-store
    - pnpm install --frozen-lockfile
    - pnpm db:migrate
  script:
    - pnpm test:integration
  artifacts:
    when: on_failure
    paths:
      - test-results/
    expire_in: 3 days

# ==================== BUILD ====================
docker-build:
  stage: build
  image: docker:27
  services:
    - docker:27-dind
  needs:
    - lint
    - test-unit
    - test-integration
    - security-scan
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login $REGISTRY -u $CI_REGISTRY_USER --password-stdin
  script:
    - |
      docker build \
        --build-arg NODE_VERSION=${NODE_VERSION} \
        --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --build-arg VCS_REF=${CI_COMMIT_SHA} \
        --cache-from ${REGISTRY}/${IMAGE_NAME}:latest \
        --tag ${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} \
        --tag ${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_REF_SLUG} \
        .
    - docker push ${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}
    - docker push ${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_REF_SLUG}
  rules:
    - if: $CI_COMMIT_BRANCH == "main" || $CI_COMMIT_BRANCH == "develop"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      variables:
        DOCKER_PUSH: "false"

# ==================== DEPLOY ====================
deploy-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  needs:
    - docker-build
  environment:
    name: staging
    url: https://staging.myapp.com
    on_stop: stop-staging
  script:
    - kubectl config use-context ${KUBE_CONTEXT_STAGING}
    - |
      kubectl set image deployment/app \
        app=${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} \
        --namespace=staging
    - kubectl rollout status deployment/app --namespace=staging --timeout=300s
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"

stop-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: staging
    action: stop
  script:
    - kubectl config use-context ${KUBE_CONTEXT_STAGING}
    - kubectl scale deployment/app --replicas=0 --namespace=staging
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
      when: manual

deploy-production:
  stage: deploy
  image: bitnami/kubectl:latest
  needs:
    - docker-build
  environment:
    name: production
    url: https://myapp.com
  before_script:
    - echo "Running database migrations..."
    # - npx prisma migrate deploy
  script:
    - kubectl config use-context ${KUBE_CONTEXT_PRODUCTION}
    - |
      kubectl set image deployment/app \
        app=${REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} \
        --namespace=production
    - kubectl rollout status deployment/app --namespace=production --timeout=300s
  after_script:
    - |
      STATUS=$([[ $CI_JOB_STATUS == "success" ]] && echo "succeeded" || echo "failed")
      echo "Production deployment ${STATUS} for ${CI_COMMIT_SHORT_SHA}"
      # curl -X POST $SLACK_WEBHOOK -d "{\"text\":\"Deploy ${STATUS}: ${CI_COMMIT_SHORT_SHA}\"}"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual  # Require manual approval for production
  allow_failure: false
```

---

## Reusable Workflows

```yaml
# .github/workflows/reusable-ci.yml — Reusable CI workflow
# Called by other workflows via workflow_call trigger

name: Reusable CI Pipeline

on:
  workflow_call:
    inputs:
      node-version:
        description: 'Node.js version to use'
        required: false
        type: string
        default: '22'
      working-directory:
        description: 'Package directory for monorepo support'
        required: false
        type: string
        default: '.'
      run-e2e:
        description: 'Whether to run end-to-end tests'
        required: false
        type: boolean
        default: false
      docker-push:
        description: 'Whether to build and push a Docker image'
        required: false
        type: boolean
        default: false
      environment:
        description: 'Target deployment environment'
        required: false
        type: string
        default: ''
    secrets:
      NPM_TOKEN:
        description: 'NPM registry token for private packages'
        required: false
      REGISTRY_PASSWORD:
        description: 'Container registry password'
        required: false
      DEPLOY_KEY:
        description: 'SSH key or token for deployment'
        required: false
    outputs:
      image-tag:
        description: 'Docker image tag that was built'
        value: ${{ jobs.build-image.outputs.tag }}
      test-result:
        description: 'Overall test pass/fail status'
        value: ${{ jobs.test.outputs.result }}

jobs:
  # ==================== LINT & TYPECHECK ====================
  lint:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm typecheck

  # ==================== TEST ====================
  test:
    runs-on: ubuntu-latest
    outputs:
      result: ${{ steps.test-run.outcome }}
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - id: test-run
        run: pnpm test:unit -- --coverage
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-${{ inputs.working-directory }}
          path: ${{ inputs.working-directory }}/coverage/

  # ==================== E2E (CONDITIONAL) ====================
  e2e:
    if: inputs.run-e2e
    needs: [lint, test]
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: npx playwright install --with-deps chromium
      - run: pnpm test:e2e
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report-${{ inputs.working-directory }}
          path: ${{ inputs.working-directory }}/playwright-report/

  # ==================== DOCKER BUILD (CONDITIONAL) ====================
  build-image:
    if: inputs.docker-push
    needs: [lint, test]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=
            type=ref,event=branch
      - uses: docker/build-push-action@v6
        with:
          context: ${{ inputs.working-directory }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

```yaml
# .github/workflows/ci.yml — Caller workflow (monorepo example)
# Demonstrates how to invoke the reusable workflow for multiple packages

name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  # ==================== CHANGE DETECTION ====================
  changes:
    runs-on: ubuntu-latest
    outputs:
      web: ${{ steps.filter.outputs.web }}
      api: ${{ steps.filter.outputs.api }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            web:
              - 'apps/web/**'
              - 'packages/ui/**'
            api:
              - 'apps/api/**'
              - 'packages/shared/**'

  # ==================== WEB APP ====================
  ci-web:
    needs: changes
    if: needs.changes.outputs.web == 'true'
    uses: ./.github/workflows/reusable-ci.yml
    with:
      working-directory: apps/web
      run-e2e: true
      docker-push: ${{ github.ref == 'refs/heads/main' }}
    secrets:
      REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}

  # ==================== API ====================
  ci-api:
    needs: changes
    if: needs.changes.outputs.api == 'true'
    uses: ./.github/workflows/reusable-ci.yml
    with:
      working-directory: apps/api
      run-e2e: false
      docker-push: ${{ github.ref == 'refs/heads/main' }}
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}

  # ==================== DEPLOY AFTER CI ====================
  deploy-staging:
    needs: [ci-web, ci-api]
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Deploy web to staging
        run: |
          echo "Deploying web image: ${{ needs.ci-web.outputs.image-tag }}"
          echo "Deploying api image: ${{ needs.ci-api.outputs.image-tag }}"
          # kubectl set image deployment/web web=ghcr.io/${{ github.repository }}:${{ needs.ci-web.outputs.image-tag }}
          # kubectl set image deployment/api api=ghcr.io/${{ github.repository }}:${{ needs.ci-api.outputs.image-tag }}

  deploy-production:
    needs: [ci-web, ci-api]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy to production
        run: |
          echo "Production deploy — web: ${{ needs.ci-web.outputs.image-tag }}, api: ${{ needs.ci-api.outputs.image-tag }}"
          # helm upgrade myapp ./chart \
          #   --set web.image.tag=${{ needs.ci-web.outputs.image-tag }} \
          #   --set api.image.tag=${{ needs.ci-api.outputs.image-tag }}
      - name: Health check
        run: |
          sleep 30
          # curl -f https://myapp.com/health || exit 1
```

---

## Docker Build with Layer Caching

```yaml
# Optimized Docker build job with multi-platform + caching
docker-build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - uses: docker/setup-qemu-action@v3  # Multi-platform support

    - uses: docker/setup-buildx-action@v3

    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - uses: docker/build-push-action@v6
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: ${{ github.event_name != 'pull_request' }}
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        build-args: |
          NODE_VERSION=22
          BUILD_DATE=${{ github.event.head_commit.timestamp }}
          VCS_REF=${{ github.sha }}
```

---

## Monorepo CI Strategy

```yaml
# Only run jobs for changed packages
name: Monorepo CI

on:
  pull_request:
    branches: [main]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      web: ${{ steps.changes.outputs.web }}
      api: ${{ steps.changes.outputs.api }}
      shared: ${{ steps.changes.outputs.shared }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: changes
        with:
          filters: |
            web:
              - 'apps/web/**'
              - 'packages/shared/**'
              - 'packages/ui/**'
            api:
              - 'apps/api/**'
              - 'packages/shared/**'
            shared:
              - 'packages/shared/**'

  test-web:
    needs: detect-changes
    if: needs.detect-changes.outputs.web == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm --filter web test
      - run: pnpm --filter web build

  test-api:
    needs: detect-changes
    if: needs.detect-changes.outputs.api == 'true'
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env: { POSTGRES_PASSWORD: test }
        ports: ['5432:5432']
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm --filter api test
```

---

## Release Automation

```yaml
# Automated releases with Changesets
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # Full history for changelog

      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile

      - uses: changesets/action@v1
        with:
          publish: pnpm release
          version: pnpm version-packages
          commit: 'chore: release'
          title: 'chore: release'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```
