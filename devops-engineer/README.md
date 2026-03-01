# :rocket: DevOps Engineer

> DevOps engineering expert covering CI/CD pipelines, containerization (Docker), orchestration (Kubernetes), infrastructure as code (Terraform), monitoring (Prometheus/Grafana), logging, and cloud platforms (AWS/GCP/Azure).

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies** -- CI/CD Pipeline Design, Docker, Kubernetes Essentials, Infrastructure as Code (Terraform), Monitoring & Observability, Security Hardening
- **Quick Commands** -- Essential commands for Docker, Kubernetes, and Terraform workflows
- **References** -- Links to included reference documents

### References
| File | Description | Lines |
|------|-------------|-------|
| [cicd-templates.md](references/cicd-templates.md) | CI/CD templates reference including GitHub Actions full production pipeline | 809 |
| [k8s-patterns.md](references/k8s-patterns.md) | Kubernetes patterns reference including production deployment templates | 738 |
| [monitoring-templates.md](references/monitoring-templates.md) | Production monitoring and observability templates for Prometheus, Grafana, logging, and tracing | 1170 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [docker-cleanup.sh](scripts/docker-cleanup.sh) | Clean up Docker resources safely with dry-run support | `./scripts/docker-cleanup.sh [--dry-run] [--aggressive]` |
| [k8s-deploy.sh](scripts/k8s-deploy.sh) | Safe Kubernetes deployment with rollback capability | `./scripts/k8s-deploy.sh <namespace> <deployment> <image:tag> [--timeout 300]` |

## Tags
`cicd` `docker` `kubernetes` `terraform` `prometheus` `grafana` `github-actions` `monitoring` `infrastructure`

## Quick Start

```bash
# Copy this skill to your project
cp -r devops-engineer/ /path/to/project/.skills/

# Clean up Docker resources (preview what would be deleted)
.skills/devops-engineer/scripts/docker-cleanup.sh --dry-run

# Deploy to Kubernetes with automatic rollback
.skills/devops-engineer/scripts/k8s-deploy.sh production myapp myapp:v1.2.0
```

## Part of [BoxClaw Skills](../)
