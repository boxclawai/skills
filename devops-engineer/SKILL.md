---
name: devops-engineer
version: "1.0.0"
description: "DevOps engineering expert: CI/CD pipelines (GitHub Actions/GitLab CI/Jenkins), containerization (Docker/Podman), orchestration (Kubernetes/Docker Compose), infrastructure as code (Terraform/Pulumi/Ansible), monitoring (Prometheus/Grafana/Datadog), logging (ELK/Loki), and cloud platforms (AWS/GCP/Azure). Use when: (1) setting up CI/CD pipelines, (2) writing Dockerfiles or docker-compose configs, (3) configuring Kubernetes deployments, (4) writing Terraform/IaC modules, (5) setting up monitoring/alerting, (6) troubleshooting deployment issues, (7) optimizing build times. NOT for: application business logic or UI design."
tags: [cicd, docker, kubernetes, terraform, prometheus, grafana, github-actions, monitoring, infrastructure]
author: "boxclaw"
references:
  - references/cicd-templates.md
  - references/k8s-patterns.md
  - references/monitoring-templates.md
metadata:
  boxclaw:
    emoji: "🚀"
    category: "programming-role"
---

# DevOps Engineer

Expert guidance for CI/CD, containerization, orchestration, and infrastructure automation.

## Core Competencies

### 1. CI/CD Pipeline Design

#### GitHub Actions Template

```yaml
name: CI/CD
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm test
      - run: pnpm build

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - run: # deploy commands
```

#### Pipeline Best Practices

```
Speed:
  - Cache dependencies (node_modules, pip cache, go modules)
  - Parallel jobs for independent steps (lint ∥ test ∥ build)
  - Incremental builds (only rebuild changed packages)
  - Use slim base images

Safety:
  - Required status checks on main
  - Environment protection rules
  - Secret scanning + dependency audits
  - Deploy to staging before production
  - Rollback automation
```

### 2. Docker

#### Optimized Dockerfile Pattern

```dockerfile
# Multi-stage build
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

FROM node:22-slim AS build
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM node:22-slim AS runtime
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER app
EXPOSE 3000
HEALTHCHECK CMD curl -f http://localhost:3000/health || exit 1
CMD ["node", "dist/index.js"]
```

#### Docker Compose (Dev Environment)

```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    volumes: ["./src:/app/src"]
    environment:
      DATABASE_URL: postgres://dev:dev@db:5432/app
    depends_on:
      db: { condition: service_healthy }

  db:
    image: postgres:17
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: pg_isready -U dev
      interval: 5s

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

volumes:
  pgdata:
```

### 3. Kubernetes Essentials

```yaml
# Deployment with best practices
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  selector:
    matchLabels: { app: myapp }
  template:
    metadata:
      labels: { app: myapp }
    spec:
      containers:
        - name: myapp
          image: myapp:1.0.0  # Always use specific tags
          ports: [{ containerPort: 3000 }]
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 512Mi }
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 15
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: { name: db-creds, key: password }
```

### 4. Infrastructure as Code (Terraform)

```hcl
# Modular Terraform structure
terraform/
├── modules/
│   ├── vpc/
│   ├── database/
│   └── compute/
├── environments/
│   ├── dev/main.tf
│   ├── staging/main.tf
│   └── prod/main.tf
└── shared/
    └── backend.tf

# Key practices:
# - Remote state (S3 + DynamoDB lock)
# - Workspaces or directory-per-env
# - Module versioning
# - Plan → Review → Apply workflow
# - State locking to prevent concurrent changes
```

### 5. Monitoring & Observability

```
Three Pillars:
  Metrics  → Prometheus + Grafana (quantitative)
  Logs     → Loki/ELK (qualitative, searchable)
  Traces   → Jaeger/Tempo (request flow across services)

Key Metrics (RED Method):
  Rate:     Requests per second
  Errors:   Error rate (5xx / total)
  Duration: Latency (p50, p95, p99)

Key Metrics (USE Method - Infrastructure):
  Utilization: CPU/memory/disk usage %
  Saturation:  Queue depth, thread pool exhaustion
  Errors:      Hardware/driver errors

Alerting Rules:
  - Error rate > 1% for 5 minutes → Warning
  - Error rate > 5% for 2 minutes → Critical
  - p99 latency > 2s for 5 minutes → Warning
  - CPU > 85% for 10 minutes → Warning
  - Disk > 90% → Critical
```

### 6. Security Hardening

```
Container:
  - Non-root user (USER 1001)
  - Read-only filesystem where possible
  - No privileged mode
  - Scan images (Trivy, Snyk)
  - Pin base image digests

Network:
  - Network policies (deny all, allow specific)
  - TLS everywhere (cert-manager for K8s)
  - Secrets in vault, not env vars

Supply Chain:
  - Signed images (cosign)
  - SBOM generation
  - Dependency scanning in CI
```

## Quick Commands

```bash
# Docker
docker build -t myapp:latest .
docker compose up -d
docker compose logs -f app
docker system prune -af  # Clean up

# Kubernetes
kubectl apply -f k8s/
kubectl rollout status deployment/myapp
kubectl rollout undo deployment/myapp  # Rollback
kubectl top pods  # Resource usage
kubectl logs -f deployment/myapp --tail=100

# Terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
```

## References

- **CI/CD templates**: See [references/cicd-templates.md](references/cicd-templates.md)
- **Kubernetes patterns**: See [references/k8s-patterns.md](references/k8s-patterns.md)
- **Monitoring templates**: See [references/monitoring-templates.md](references/monitoring-templates.md)
