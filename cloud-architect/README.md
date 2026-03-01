# :cloud: Cloud Architect

> Cloud architecture expert covering AWS/GCP/Azure service selection, serverless architecture, Infrastructure as Code (Terraform/CDK/Pulumi), networking, cost optimization, multi-region deployment, disaster recovery, and the Well-Architected Framework.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies**
  - Service Selection Matrix (compute, database, storage, messaging)
  - Network Architecture (VPC design, security groups, traffic flow)
  - Serverless Architecture (event-driven patterns, best practices)
  - Cost Optimization (compute, storage, network, quick wins)
  - High Availability & Disaster Recovery (availability targets, DR strategies, multi-AZ checklist)
  - Infrastructure as Code (Terraform examples, modular structure, best practices)
  - Security / Well-Architected (identity, network, data, monitoring)
- **Quick Commands** -- AWS CLI, GCP CLI, Terraform, and cost analysis commands

### References
| File | Description | Lines |
|------|-------------|-------|
| [aws-patterns.md](references/aws-patterns.md) | Production-grade AWS architecture patterns for common workloads with design rationale, security considerations, and IaC snippets | 1322 |
| [cost-optimization.md](references/cost-optimization.md) | Cloud cost optimization reference covering compute right-sizing methodology and cost reduction strategies | 1280 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [cost-report.sh](scripts/cost-report.sh) | AWS cost analysis and optimization report generator | `./scripts/cost-report.sh [--period 30] [--profile default] [--output reports/]` |

## Tags
`aws` `gcp` `azure` `terraform` `serverless` `lambda` `vpc` `cost-optimization` `disaster-recovery` `iac`

## Quick Start

```bash
# Copy this skill to your project
cp -r cloud-architect/ /path/to/project/.skills/

# Generate an AWS cost report for the last 30 days
.skills/cloud-architect/scripts/cost-report.sh --period 30 --profile default --output reports/
```

## Part of [BoxClaw Skills](../)
