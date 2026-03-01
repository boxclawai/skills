---
name: cloud-architect
version: "1.0.0"
description: "Cloud architecture expert: AWS/GCP/Azure service selection, serverless architecture (Lambda/Cloud Functions/Azure Functions), Infrastructure as Code (Terraform/CDK/Pulumi), networking (VPC/subnets/security groups), cost optimization, multi-region deployment, disaster recovery, and Well-Architected Framework. Use when: (1) designing cloud infrastructure for applications, (2) selecting cloud services for specific requirements, (3) optimizing cloud costs, (4) designing multi-region or disaster recovery architecture, (5) writing IaC for cloud resources, (6) reviewing cloud security configurations. NOT for: application business logic, frontend UI, or on-premises infrastructure."
tags: [aws, gcp, azure, terraform, serverless, lambda, vpc, cost-optimization, disaster-recovery, iac]
author: "boxclaw"
references:
  - references/aws-patterns.md
  - references/cost-optimization.md
metadata:
  boxclaw:
    emoji: "☁️"
    category: "programming-role"
---

# Cloud Architect

Expert guidance for designing, deploying, and optimizing cloud infrastructure.

## Core Competencies

### 1. Service Selection Matrix

```
Compute:
  Container (ECS/GKE/ACA):  Long-running services, full control
  Serverless (Lambda/CF):    Event-driven, variable traffic, <15min
  VM (EC2/GCE):              Legacy apps, custom OS, GPU
  Edge (CloudFront Fn):      Low-latency, simple transforms

Database:
  Relational (RDS/Cloud SQL):     ACID, complex queries, joins
  Document (DynamoDB/Firestore):  Key-value, flexible schema, massive scale
  Graph (Neptune/Neo4j):          Relationship-heavy data
  Time-series (Timestream):       IoT, metrics, logs
  Cache (ElastiCache/Memorystore):Read-heavy, session store

Storage:
  Object (S3/GCS):          Files, backups, data lake
  Block (EBS/PD):           VM disks, databases
  File (EFS/Filestore):     Shared across instances
  Archive (Glacier/Nearline):Cold storage, compliance

Messaging:
  Queue (SQS/Cloud Tasks):       Point-to-point, guaranteed delivery
  Pub/Sub (SNS+SQS/Pub/Sub):     Fan-out, event distribution
  Stream (Kinesis/Pub/Sub):       Ordered, real-time processing
  Event Bus (EventBridge):        Cross-service event routing
```

### 2. Network Architecture

```
VPC Design (AWS example):
  CIDR: 10.0.0.0/16 (65,536 IPs)

  Public subnets (per AZ):
    10.0.1.0/24, 10.0.2.0/24    → ALB, NAT Gateway, bastion
  Private subnets (per AZ):
    10.0.10.0/24, 10.0.11.0/24  → App servers, containers
  Data subnets (per AZ):
    10.0.20.0/24, 10.0.21.0/24  → RDS, ElastiCache (no internet)

Security Groups (least privilege):
  ALB:     Inbound 443 from 0.0.0.0/0
  App:     Inbound 3000 from ALB SG only
  DB:      Inbound 5432 from App SG only
  Redis:   Inbound 6379 from App SG only

Traffic Flow:
  Internet → CloudFront → ALB (public) → App (private) → DB (data)
  App → NAT Gateway → Internet (outbound only)
```

### 3. Serverless Architecture

```
Event-Driven Pattern:
  API Gateway → Lambda → DynamoDB
  S3 upload → Lambda → Process → SQS → Lambda → Notify

Best Practices:
  Cold starts:   Keep functions warm (provisioned concurrency)
  Timeout:       Set realistic limits (not max)
  Memory:        More memory = more CPU = faster (cost optimize)
  Layers:        Share common dependencies across functions
  VPC:           Avoid unless necessary (adds cold start latency)

Patterns:
  API:           API Gateway + Lambda + DynamoDB
  Async:         SQS → Lambda (batch processing)
  Schedule:      EventBridge rule → Lambda (cron jobs)
  Stream:        DynamoDB Streams / Kinesis → Lambda
  Orchestration: Step Functions (complex workflows)
```

### 4. Cost Optimization

```
Compute:
  Right-size:     Monitor usage, downsize over-provisioned
  Reserved/Savings: 1-3 year commitments for steady workloads (30-60% off)
  Spot/Preemptible: Fault-tolerant workloads (60-90% off)
  Auto-scaling:   Scale to zero when idle

Storage:
  Lifecycle policies:  Hot → Warm → Cold → Archive
  Intelligent tiering: Auto-move based on access patterns
  Compress:            Gzip/Zstd before storage
  Clean up:            Delete old snapshots, unused volumes

Network:
  CDN:               Cache at edge, reduce origin traffic
  VPC Endpoints:     Avoid NAT Gateway costs for AWS services
  Data transfer:     Keep traffic within same region/AZ

General:
  Tags:              Cost allocation by team/project/environment
  Budgets + Alerts:  Set thresholds, alert at 80%/100%
  Regular reviews:   Monthly cost review, kill zombie resources
  FinOps dashboard:  Track cost per unit (per user, per request)

Quick Wins:
  - Delete unattached EBS volumes
  - Stop non-production instances nights/weekends
  - Use S3 Intelligent-Tiering
  - Right-size RDS instances
  - Review unused Elastic IPs, load balancers
```

### 5. High Availability & Disaster Recovery

```
Availability Targets:
  99.9%   → 8.7h downtime/year   (single region, multi-AZ)
  99.95%  → 4.4h downtime/year   (multi-AZ, automated failover)
  99.99%  → 52min downtime/year  (multi-region active-passive)
  99.999% → 5min downtime/year   (multi-region active-active)

DR Strategies:
  Backup & Restore (RPO: hours, RTO: hours):
    S3 cross-region replication + automated restore scripts

  Pilot Light (RPO: minutes, RTO: minutes):
    Core infra running in DR region, scale up on failover

  Warm Standby (RPO: seconds, RTO: minutes):
    Scaled-down clone in DR region, route traffic on failover

  Active-Active (RPO: ~0, RTO: ~0):
    Full deployment in multiple regions, global load balancer
    Most expensive, most resilient

Multi-AZ Checklist:
  [ ] Compute: instances in >= 2 AZs behind ALB
  [ ] Database: Multi-AZ RDS or Aurora (automatic failover)
  [ ] Cache: Redis cluster mode with replicas across AZs
  [ ] Storage: S3 (automatically multi-AZ)
  [ ] DNS: Route 53 health checks + failover routing
```

### 6. Infrastructure as Code (Terraform)

```hcl
# Modular, environment-aware Terraform
# terraform/modules/api/main.tf

resource "aws_ecs_service" "api" {
  name            = "${var.project}-api-${var.environment}"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.api.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 3000
  }
}

# terraform/environments/prod/main.tf
module "api" {
  source          = "../../modules/api"
  project         = "boxclaw"
  environment     = "prod"
  desired_count   = 3
  ecs_cluster_id  = module.cluster.id
  private_subnet_ids = module.vpc.private_subnet_ids
}
```

#### IaC Best Practices

```
Structure:
  terraform/
  ├── modules/          # Reusable components
  │   ├── vpc/
  │   ├── database/
  │   └── api/
  ├── environments/     # Per-environment configs
  │   ├── dev/
  │   ├── staging/
  │   └── prod/
  └── shared/           # Backend, providers

Practices:
  - Remote state (S3 + DynamoDB lock / GCS + lock)
  - Separate state per environment
  - Pin provider versions
  - terraform plan in CI, apply with approval
  - Use data sources to reference existing resources
  - Never store secrets in state (use secret manager)
```

### 7. Security (Well-Architected)

```
Identity:
  - IAM roles > access keys (no long-lived credentials)
  - Least privilege (use IAM Access Analyzer)
  - MFA on root and admin accounts
  - Service-linked roles for AWS services

Network:
  - Private subnets for compute/data
  - Security groups: deny by default
  - VPC Flow Logs enabled
  - WAF on public endpoints

Data:
  - Encryption at rest (KMS managed keys)
  - Encryption in transit (TLS 1.2+)
  - S3: block public access, versioning, MFA delete
  - Database: encrypted, no public access

Monitoring:
  - CloudTrail: all API calls logged
  - GuardDuty: threat detection
  - Config: compliance rules
  - Security Hub: centralized findings
```

## Quick Commands

```bash
# AWS
aws sts get-caller-identity
aws ec2 describe-instances --filters "Name=tag:Env,Values=prod"
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws s3 ls --summarize --human-readable

# GCP
gcloud compute instances list
gcloud sql instances list
gcloud storage ls

# Terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
terraform import aws_instance.myapp i-1234567890

# Cost
aws ce get-cost-and-usage --time-period Start=2025-02-01,End=2025-03-01 \
  --granularity MONTHLY --metrics BlendedCost
```

## References

- **AWS patterns**: See [references/aws-patterns.md](references/aws-patterns.md)
- **Cost optimization**: See [references/cost-optimization.md](references/cost-optimization.md)
