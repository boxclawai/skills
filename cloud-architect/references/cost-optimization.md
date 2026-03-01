# Cloud Cost Optimization Reference

## Table of Contents

1. [Compute Right-Sizing Methodology](#compute-right-sizing-methodology)
2. [Reserved Instances vs Savings Plans vs Spot Analysis](#reserved-instances-vs-savings-plans-vs-spot-analysis)
3. [Storage Tiering Strategies](#storage-tiering-strategies)
4. [Data Transfer Cost Reduction](#data-transfer-cost-reduction)
5. [Serverless Cost Modeling](#serverless-cost-modeling)
6. [Database Cost Optimization](#database-cost-optimization)
7. [Cost Allocation with Tags](#cost-allocation-with-tags)
8. [Budget Alerts and Anomaly Detection Setup](#budget-alerts-and-anomaly-detection-setup)
9. [FinOps Best Practices](#finops-best-practices)
10. [Cost Per Transaction / User Metrics](#cost-per-transaction--user-metrics)
11. [Tools for Cost Management](#tools-for-cost-management)
12. [Quick Wins Checklist](#quick-wins-checklist)
13. [Quick Reference: Biggest Cost Levers](#quick-reference-biggest-cost-levers)

---

## Compute Right-Sizing Methodology

### Step 1: Collect Utilization Data

Before making any sizing decisions, gather at least 14 days (ideally 30 days) of utilization data to capture weekly patterns and peak periods.

```bash
# AWS CLI: Get average CPU utilization for an EC2 instance over 14 days.
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=i-0abcdef1234567890 \
    --start-time $(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average Maximum \
    --output table

# Get memory utilization (requires CloudWatch Agent).
aws cloudwatch get-metric-statistics \
    --namespace CWAgent \
    --metric-name mem_used_percent \
    --dimensions Name=InstanceId,Value=i-0abcdef1234567890 \
    --start-time $(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average Maximum \
    --output table

# List Compute Optimizer recommendations for over-provisioned instances.
aws compute-optimizer get-ec2-instance-recommendations \
    --filters name=Finding,values=OVER_PROVISIONED \
    --output json | jq '.instanceRecommendations[] | {
      instanceId: .instanceArn,
      current: .currentInstanceType,
      recommended: .recommendationOptions[0].instanceType,
      savingsPercent: .recommendationOptions[0].savingsOpportunity.savingsOpportunityPercentage
    }'
```

### Step 2: Analyze and Categorize

| Category          | CPU Avg | CPU Max | Memory Avg | Action                              |
|-------------------|---------|---------|------------|-------------------------------------|
| Over-provisioned  | < 20%   | < 40%   | < 40%      | Downsize by 1-2 instance sizes      |
| Right-sized       | 20-60%  | 40-80%  | 40-70%     | No change needed                    |
| Under-provisioned | > 70%   | > 90%   | > 80%      | Upsize or scale horizontally        |
| Idle              | < 5%    | < 10%   | < 20%      | Terminate or schedule on/off        |

### Step 3: Instance Family Selection

```
Workload Type              Recommended Family    Why
---------------------------------------------------------------------------
General purpose web        m7g (Graviton3)       Balanced CPU/memory, 20% cheaper than x86
Memory-intensive (DB)      r7g (Graviton3)       High memory-to-CPU ratio
Compute-intensive          c7g (Graviton3)       High CPU-to-memory ratio
Burstable (dev/test)       t4g (Graviton2)       Baseline CPU + burst credits
GPU (ML inference)         g5                    NVIDIA A10G GPUs
GPU (ML training)          p4d / p5              NVIDIA A100 / H100 GPUs
Storage-optimized          i4i                   High IOPS NVMe storage
```

### Graviton (ARM) Cost Advantage

Graviton instances (suffix 'g': m7g, c7g, r7g, t4g) typically provide:
- 20% lower price than equivalent x86 instances.
- 20-40% better price-performance for most workloads.
- Requires ARM-compatible application builds (most languages and runtimes support this natively).

```
Example comparison (us-east-1, on-demand, Linux):
  m6i.xlarge  (Intel):     $0.192/hr  = $140.16/month
  m7g.xlarge  (Graviton3): $0.163/hr  = $119.00/month
  Savings: 15% on price alone, plus better performance per dollar.
```

---

## Reserved Instances vs Savings Plans vs Spot Analysis

### Comparison Matrix

| Feature               | On-Demand       | Reserved Instances (RI)      | Compute Savings Plans    | Spot Instances            |
|-----------------------|-----------------|------------------------------|--------------------------|---------------------------|
| **Commitment**        | None            | 1 or 3 years                 | 1 or 3 years             | None                      |
| **Discount**          | 0%              | Up to 72%                    | Up to 66%                | Up to 90%                 |
| **Flexibility**       | Full            | Locked to instance type/region| Any instance type/region | Full (can be interrupted) |
| **Payment options**   | Per-hour        | All upfront/Partial/No upfront| Same as RI              | Per-hour (variable price) |
| **Best for**          | Unpredictable   | Stable, known workloads      | Mixed/evolving workloads | Fault-tolerant workloads  |
| **Interruption risk** | None            | None                         | None                     | 2-minute warning          |

### Decision Framework

```
Is the workload fault-tolerant and can handle interruptions?
|
+-- YES --> Use Spot Instances (up to 90% savings)
|           Examples: Batch processing, CI/CD builds, data processing,
|                     stateless web servers behind ASG, ML training
|
+-- NO --> Is the workload stable for 1-3 years?
           |
           +-- YES --> Do you know the exact instance type?
           |           |
           |           +-- YES --> Reserved Instances (best discount for specific type)
           |           +-- NO  --> Compute Savings Plans (flexible across types)
           |
           +-- NO --> On-Demand (pay full price for flexibility)
```

### Savings Plans Calculation Example

```
Current monthly spend on EC2 compute:
  20x m7g.xlarge On-Demand: 20 * $0.163/hr * 730hrs = $2,378/month

With 1-year Compute Savings Plan (no upfront):
  Hourly commitment: $2.28/hr (calculated from expected baseline)
  Effective rate: ~$0.103/hr per m7g.xlarge
  Monthly cost: 20 * $0.103 * 730 = $1,504/month
  Savings: $874/month (37%)

With 3-year Compute Savings Plan (all upfront):
  Effective rate: ~$0.065/hr per m7g.xlarge
  Monthly cost: 20 * $0.065 * 730 = $949/month
  Savings: $1,429/month (60%)
```

### Spot Instance Best Practices

```hcl
# Terraform: EC2 Auto Scaling Group with mixed instances (Spot + On-Demand).
resource "aws_autoscaling_group" "web" {
  name                = "web-asg"
  desired_capacity    = 10
  min_size            = 4
  max_size            = 20
  vpc_zone_identifier = module.vpc.private_subnets

  mixed_instances_policy {
    instances_distribution {
      # Keep 20% as On-Demand for baseline stability.
      on_demand_base_capacity                  = 2
      on_demand_percentage_above_base_capacity = 20
      spot_allocation_strategy                 = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.web.id
        version            = "$Latest"
      }

      # Diversify across multiple instance types to reduce interruption risk.
      override {
        instance_type     = "m7g.xlarge"
        weighted_capacity = 1
      }
      override {
        instance_type     = "m6g.xlarge"
        weighted_capacity = 1
      }
      override {
        instance_type     = "m7i.xlarge"
        weighted_capacity = 1
      }
      override {
        instance_type     = "c7g.xlarge"
        weighted_capacity = 1
      }
    }
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
}
```

### Spot Interruption Handling

```python
# Lambda function triggered by EC2 Spot Interruption Warning via EventBridge.
import boto3
import json

ecs = boto3.client('ecs')
asg = boto3.client('autoscaling')

def handler(event, context):
    """Handle Spot Instance interruption (2-minute warning)."""
    instance_id = event['detail']['instance-id']
    print(f"Spot interruption warning for {instance_id}")

    # If using ECS, drain the container instance.
    # This stops new task placement and waits for existing tasks to finish.
    response = ecs.list_container_instances(
        cluster='production',
        filter=f'ec2InstanceId == {instance_id}'
    )

    if response['containerInstanceArns']:
        ecs.update_container_instances_state(
            cluster='production',
            containerInstances=response['containerInstanceArns'],
            status='DRAINING'
        )
        print(f"Set container instance to DRAINING")

    return {'statusCode': 200}
```

---

## Storage Tiering Strategies

### S3 Storage Classes Decision Tree

```
Access pattern known?
|
+-- YES
|   +-- Frequent (daily)              --> S3 Standard           ($0.023/GB)
|   +-- Infrequent (~monthly)         --> S3 Standard-IA        ($0.0125/GB)
|   |                                     Min 30-day storage, 128KB min charge
|   +-- Rare (~quarterly)             --> S3 Glacier Instant     ($0.004/GB)
|   |                                     Min 90-day storage, ms retrieval
|   +-- Archive (yearly)              --> S3 Glacier Flexible    ($0.0036/GB)
|   |                                     Min 90-day, retrieval: min-12hrs
|   +-- Deep archive (compliance)     --> S3 Glacier Deep Archive ($0.00099/GB)
|                                         Min 180-day, retrieval: 12-48hrs
|
+-- NO (unpredictable)                --> S3 Intelligent-Tiering ($0.0025/1K obj monitoring)
                                          Automatically moves objects between tiers.
                                          No retrieval fees. Best for unknown patterns.
```

### S3 Intelligent-Tiering Configuration

```hcl
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  bucket = aws_s3_bucket.data.id
  name   = "EntireDataset"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

# Lifecycle rule to move objects to Intelligent-Tiering on upload.
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "move-to-intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

### EBS Volume Optimization: gp3 vs gp2

```
gp2 (General Purpose SSD - previous generation):
  - IOPS: 3 IOPS/GB (baseline), burst to 3,000 IOPS for volumes < 1TB
  - Throughput: Up to 250 MB/s
  - Cost: $0.10/GB-month
  - Problem: You pay for storage to get IOPS. Need 1TB for 3,000 sustained IOPS.

gp3 (General Purpose SSD - current generation):
  - IOPS: 3,000 baseline (free), up to 16,000 ($0.005/IOPS above 3,000)
  - Throughput: 125 MB/s baseline (free), up to 1,000 MB/s ($0.040/MB/s above 125)
  - Cost: $0.08/GB-month (20% cheaper per GB)
  - Benefit: Decouple IOPS from storage size.

Example migration scenarios:
  gp2: 500GB volume = $50/month, gets 1,500 baseline IOPS
  gp3: 500GB volume = $40/month, gets 3,000 baseline IOPS (2x IOPS, 20% cheaper)

  gp2: 1TB volume (just to get 3,000 IOPS) = $100/month
  gp3: 200GB + 3,000 IOPS (baseline) = $16/month (84% savings)
```

```bash
# Migrate gp2 to gp3 (no downtime, online modification).
aws ec2 modify-volume \
    --volume-id vol-0abcdef1234567890 \
    --volume-type gp3 \
    --iops 3000 \
    --throughput 125

# Monitor modification progress.
aws ec2 describe-volumes-modifications \
    --volume-id vol-0abcdef1234567890 \
    --query 'VolumesModifications[0].{State:ModificationState,Progress:Progress}'

# Find all gp2 volumes (candidates for migration).
aws ec2 describe-volumes \
    --filters Name=volume-type,Values=gp2 \
    --query 'Volumes[].{ID:VolumeId,Size:Size,State:State,AZ:AvailabilityZone}' \
    --output table
```

---

## Data Transfer Cost Reduction

### Understanding Data Transfer Costs

```
FREE:
  - Data IN to AWS from the internet
  - Data transfer within the same AZ (using private IPs)
  - S3 to CloudFront
  - S3 to any service in the same region (with Gateway VPC endpoint)

CHEAP ($0.01/GB):
  - Cross-AZ within the same region (each direction)
  - VPC endpoint interface data processing

MODERATE ($0.02-0.09/GB):
  - Data OUT from AWS to internet ($0.09/GB first 10TB, tiered lower after)
  - Cross-region data transfer ($0.02/GB)

EXPENSIVE:
  - NAT Gateway data processing ($0.045/GB)
  - CloudFront to origin (but offset by cheaper edge-to-user pricing)
```

### Strategy 1: VPC Endpoints (Eliminate NAT Gateway Costs)

```hcl
# Gateway Endpoint for S3 (FREE - no per-GB charges, no hourly fee).
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.us-east-1.s3"

  route_table_ids = concat(
    module.vpc.private_route_table_ids,
    module.vpc.database_route_table_ids
  )
}

# Gateway Endpoint for DynamoDB (FREE).
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.us-east-1.dynamodb"

  route_table_ids = module.vpc.private_route_table_ids
}

# Interface Endpoint for ECR (avoids NAT for container image pulls).
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true
}

# Interface endpoints for CloudWatch Logs, Secrets Manager, STS, etc.
# Each: ~$7.20/month per AZ + $0.01/GB data processed
# vs NAT Gateway: $32/month + $0.045/GB data processed
```

### Strategy 2: CloudFront for API Responses

CloudFront-to-internet pricing is cheaper than EC2/ALB-to-internet pricing, even for uncacheable dynamic content.

```
Direct from ALB to internet:  $0.09/GB (first 10TB)
Via CloudFront to internet:   $0.085/GB (first 10TB, US/EU)

For 10TB/month of API responses:
  Direct:      10,000 GB * $0.09  = $900/month
  CloudFront:  10,000 GB * $0.085 = $850/month + ~$50 request fees
  Plus benefits: DDoS protection, TLS offloading, edge caching for cacheable responses
```

### Strategy 3: Same-AZ Placement

```hcl
# Cross-AZ costs $0.01/GB each direction = $0.02/GB round trip.
# For read-heavy workloads, place read replicas in same AZ as compute.

resource "aws_rds_cluster_instance" "reader_az_a" {
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.r7g.large"
  availability_zone  = "us-east-1a"  # Same AZ as most ECS tasks
}

# Example cost impact:
# Application does 100GB/day of DB queries cross-AZ:
# 100GB * $0.02 * 30 days = $60/month per service pair
# With same-AZ read replica: $0/month for read traffic
```

### Strategy 4: Compression Everywhere

```hcl
# Enable compression on CloudFront.
resource "aws_cloudfront_distribution" "main" {
  default_cache_behavior {
    compress = true  # Enables gzip and Brotli compression
    # Typically reduces transfer by 60-80% for text-based content.
  }
}

# Enable compression on ALB (via application).
# ALB does not compress responses; the application must.
# For Node.js:  app.use(compression())
# For Go:       middleware.Compress(5)
# For Python:   GZipMiddleware in FastAPI/Django
```

---

## Serverless Cost Modeling

### Lambda Pricing Breakdown

```
Lambda pricing has three components:
1. Requests:  $0.20 per 1 million requests
2. Duration:  $0.0000166667 per GB-second (x86)
              $0.0000133334 per GB-second (ARM/Graviton, 20% cheaper)
3. Free tier: 1M requests + 400,000 GB-seconds per month (always free)

Cost formula:
  Monthly Cost = (Requests * $0.0000002) +
                 (Avg_Duration_s * Memory_GB * Invocations * Price_per_GB_s)
```

### Lambda Cost Calculator

```python
def lambda_monthly_cost(
    invocations_per_month: int,
    avg_duration_ms: float,
    memory_mb: int,
    architecture: str = "arm64"  # "arm64" or "x86_64"
) -> dict:
    """Calculate monthly Lambda cost."""

    # Pricing (us-east-1)
    request_price = 0.20 / 1_000_000  # Per request
    gb_second_price = 0.0000133334 if architecture == "arm64" else 0.0000166667

    # Free tier
    free_requests = 1_000_000
    free_gb_seconds = 400_000

    # Calculations
    billable_requests = max(0, invocations_per_month - free_requests)
    request_cost = billable_requests * request_price

    total_gb_seconds = (avg_duration_ms / 1000) * (memory_mb / 1024) * invocations_per_month
    billable_gb_seconds = max(0, total_gb_seconds - free_gb_seconds)
    duration_cost = billable_gb_seconds * gb_second_price

    total = request_cost + duration_cost

    return {
        "invocations": f"{invocations_per_month:,}",
        "avg_duration_ms": avg_duration_ms,
        "memory_mb": memory_mb,
        "architecture": architecture,
        "total_gb_seconds": round(total_gb_seconds, 2),
        "request_cost": f"${request_cost:.2f}",
        "duration_cost": f"${duration_cost:.2f}",
        "total_monthly_cost": f"${total:.2f}",
        "cost_per_1k_invocations": f"${(total / invocations_per_month * 1000):.4f}" if invocations_per_month > 0 else "$0"
    }

# Example scenarios:
# Low traffic API (within free tier):
print(lambda_monthly_cost(100_000, 50, 256, "arm64"))
# -> total_monthly_cost: $0.00

# Medium traffic API:
print(lambda_monthly_cost(10_000_000, 100, 512, "arm64"))
# -> total_monthly_cost: $8.47

# High traffic API:
print(lambda_monthly_cost(100_000_000, 200, 1024, "arm64"))
# -> total_monthly_cost: $286.67
```

### Lambda vs Fargate Break-Even Analysis

```
Lambda wins when:
  - Traffic is spiky or unpredictable (scale-to-zero)
  - Average invocations < ~30M/month (depends on duration/memory)
  - Functions run < 500ms on average
  - You value zero-idle-cost (pay nothing when no traffic)

Fargate wins when:
  - Traffic is steady and predictable
  - Invocations > ~50M/month with >200ms duration
  - Tasks run continuously (always-on services)
  - You need persistent connections (WebSockets, gRPC streams)
  - Long-running processes (>15 min Lambda limit)

Break-even example (100M requests/month, 200ms avg, 1024MB):
  Lambda (ARM):  ~$287/month
  Fargate (2 tasks, 1vCPU, 2GB, with Savings Plan): ~$42/month
  Winner: Fargate at this scale

Break-even example (1M requests/month, 100ms avg, 512MB):
  Lambda (ARM):  ~$0 (free tier)
  Fargate (1 task, 0.25vCPU, 0.5GB): ~$9/month
  Winner: Lambda at this scale
```

### Lambda Memory Optimization

Lambda allocates CPU proportionally to memory. Sometimes increasing memory reduces duration enough to lower total cost.

```bash
# Use AWS Lambda Power Tuning (Step Functions state machine).
# https://github.com/alexcasalboni/aws-lambda-power-tuning
aws stepfunctions start-execution \
    --state-machine-arn arn:aws:states:us-east-1:123456789012:stateMachine:powerTuningStateMachine \
    --input '{
      "lambdaARN": "arn:aws:lambda:us-east-1:123456789012:function:my-function",
      "powerValues": [128, 256, 512, 1024, 1769, 3008],
      "num": 50,
      "payload": {},
      "parallelInvocation": true
    }'

# Typical finding:
#   128MB:  500ms duration = 0.064 GB-s = $0.00000107
#   512MB:  130ms duration = 0.067 GB-s = $0.00000109  (same cost, 4x faster)
#  1024MB:   70ms duration = 0.072 GB-s = $0.00000096  (cheaper AND faster!)
#  3008MB:   70ms duration = 0.210 GB-s = $0.00000280  (CPU-bound, no further gain)
# Optimal: 1024MB
```

---

## Database Cost Optimization

### Aurora Serverless v2 vs Provisioned Aurora

```
Aurora Serverless v2:
  - Scales in 0.5 ACU increments (1 ACU ~ 2GB RAM, ~1 vCPU equivalent).
  - Range: 0.5 ACU to 256 ACU.
  - Price: $0.12/ACU-hour (us-east-1).
  - Best for: Variable workloads, dev/test, overnight low-traffic periods.

Aurora Provisioned:
  - Fixed instance size (e.g., db.r7g.xlarge).
  - Price: $0.29/hr for db.r7g.xlarge (us-east-1).
  - Best for: Steady, predictable workloads.

Cost comparison:
  Workload: Varies from 2 ACU (night) to 16 ACU (peak), avg 8 ACU.

  Serverless v2:
    8 ACU avg * $0.12/ACU-hr * 730 hrs = $700.80/month

  Provisioned (must size for peak, 16 ACU ~ db.r7g.2xlarge):
    $0.58/hr * 730 hrs = $423.40/month (but paying for idle at night)

  Provisioned + 1-year RI (no upfront):
    ~$0.38/hr * 730 = $277.40/month

  Serverless v2 wins if: traffic drops to near-zero at night (scales to 0.5 ACU).
  Provisioned + RI wins if: workload is consistently above 50% of peak.
```

```hcl
# Aurora Serverless v2 configuration:
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "production-db"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "15.4"

  serverlessv2_scaling_configuration {
    min_capacity = 0.5   # Scale to near-zero during idle
    max_capacity = 16.0  # Scale up for peak traffic
  }
}

resource "aws_rds_cluster_instance" "serverless" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}
```

### Read Replicas vs ElastiCache

```
Problem: Database under read pressure. Two options:

Option A: Aurora Read Replica
  - db.r7g.xlarge: $0.29/hr = $211.70/month
  - Serves any read query (full SQL capability)
  - Replication lag: typically < 20ms
  - Best for: Complex queries, reports, analytics, diverse query patterns

Option B: ElastiCache Redis
  - cache.r7g.large: $0.166/hr = $121.18/month
  - Sub-millisecond reads for cached data
  - Requires application code changes (cache-aside or write-through)
  - Best for: Hot-key lookups, session data, leaderboards, frequently accessed objects

Decision guide:
  Repetitive key-value lookups     --> ElastiCache (faster + cheaper)
  Diverse SQL queries              --> Read Replica
  Maximum performance and savings  --> Both (ElastiCache for hot data, Replica for analytics)
```

### RDS Reserved Instance Strategy

```
Best practice: Layer your reservations over time.

Year 1: Reserve your baseline (the instances always running) for 1 year.
  - 1-year no-upfront RI: ~35% discount.
  - Observe actual usage patterns for 12 months.

Year 2: Convert proven-stable instances to 3-year reservations.
  - 3-year all-upfront RI: ~60% discount.
  - Keep variable instances on 1-year or on-demand.

Example savings:
  3x db.r7g.xlarge always running (baseline):
    On-demand:               3 * $0.29 * 730  = $635.10/month
    1-year no-upfront RI:    3 * $0.19 * 730  = $416.10/month  (35% off)
    3-year all-upfront RI:   3 * $0.115 * 730 = $251.85/month  (60% off)
    Annual savings (3yr RI): ($635.10 - $251.85) * 12 = $4,599/year
```

---

## Cost Allocation with Tags

### Tagging Strategy

```hcl
# Mandatory tags for all resources. Enforce via AWS Config or SCP.
locals {
  required_tags = {
    Environment = "production"           # production, staging, development, sandbox
    Project     = "myapp"                # Business project or product name
    Team        = "platform-engineering" # Owning team
    CostCenter  = "CC-1234"             # Finance cost center code
    ManagedBy   = "terraform"           # terraform, cloudformation, manual
  }
}

# Apply to all resources via provider default_tags.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.required_tags
  }
}
```

### Enforce Tagging with AWS Config

```hcl
resource "aws_config_config_rule" "required_tags" {
  name = "required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Environment"
    tag2Key = "Project"
    tag3Key = "Team"
    tag4Key = "CostCenter"
  })

  scope {
    compliance_resource_types = [
      "AWS::EC2::Instance",
      "AWS::RDS::DBInstance",
      "AWS::S3::Bucket",
      "AWS::Lambda::Function",
      "AWS::ECS::Service"
    ]
  }
}
```

### Cost Allocation Reports

```bash
# Enable cost allocation tags in the Billing console first.
# Then query with AWS Cost Explorer CLI:

aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-02-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=TAG,Key=Project \
    --output table

# Sample output:
# +---------------+----------------+
# |   Project     | UnblendedCost  |
# +---------------+----------------+
# | myapp         |  $4,523.45     |
# | data-pipeline |  $2,187.30     |
# | (untagged)    |  $892.10       | <-- Investigate untagged resources
# +---------------+----------------+
```

---

## Budget Alerts and Anomaly Detection Setup

### AWS Budgets

```hcl
resource "aws_budgets_budget" "monthly_total" {
  name         = "monthly-total-budget"
  budget_type  = "COST"
  limit_amount = "10000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at 80% of budget (actual).
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["cloud-ops@company.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Alert at 100% of budget (actual).
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["cloud-ops@company.com", "finance@company.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Alert when forecasted to exceed budget.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["cloud-ops@company.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}

# Per-project budget.
resource "aws_budgets_budget" "project_myapp" {
  name         = "project-myapp-budget"
  budget_type  = "COST"
  limit_amount = "5000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$myapp"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["myapp-team@company.com"]
  }
}
```

### AWS Cost Anomaly Detection

```hcl
resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "service-level-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_monitor" "project_monitor" {
  name         = "project-anomaly-monitor"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    And  = null
    Or   = null
    Not  = null
    Dimensions    = null
    Tags = {
      Key          = "Project"
      Values       = ["myapp", "data-pipeline"]
      MatchOptions = ["EQUALS"]
    }
    CostCategories = null
  })
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name = "anomaly-alerts"

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["100"]  # Alert when anomaly impact >= $100
    }
  }

  frequency = "IMMEDIATE"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn,
    aws_ce_anomaly_monitor.project_monitor.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = "cloud-ops@company.com"
  }

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_anomaly_alerts.arn
  }
}
```

---

## FinOps Best Practices

### FinOps Lifecycle

```
+-------------+     +--------------+     +--------------+
|   INFORM    |---->|   OPTIMIZE   |---->|   OPERATE    |
|             |     |              |     |              |
| - Visibility|     | - Right-size |     | - Automate   |
| - Allocation|     | - Reserved   |     | - Govern     |
| - Benchmarks|     | - Spot/Sav.  |     | - Continuous |
| - Showback  |     | - Arch. opt  |     |   improvement|
+-------------+     +--------------+     +--------------+
       ^                                        |
       +----------------------------------------+
                  Continuous cycle
```

### Monthly FinOps Review Checklist

```
INFORM:
[ ] Review Cost Explorer dashboard (month-over-month trend)
[ ] Check for untagged resources (target: < 5% of spend)
[ ] Review cost per team/project vs budget
[ ] Identify top 10 cost growth areas
[ ] Check RI/Savings Plan utilization (target: > 80%)
[ ] Review data transfer costs by service

OPTIMIZE:
[ ] Run AWS Compute Optimizer recommendations
[ ] Check for idle resources (unused EBS, unattached EIPs, idle RDS)
[ ] Review over-provisioned instances (CloudWatch metrics)
[ ] Evaluate new instance types (Graviton, latest generation)
[ ] Check S3 storage class distribution
[ ] Review NAT Gateway costs (candidates for VPC endpoints)

OPERATE:
[ ] Update Savings Plans / Reserved Instances (quarterly)
[ ] Review and update auto-scaling policies
[ ] Schedule dev/test environments (stop nights/weekends)
[ ] Clean up old snapshots, AMIs, and ECR images
[ ] Review CloudWatch log retention policies
[ ] Update budget alerts for next month's forecast
```

### Automated Cost Controls

```hcl
# Auto-stop development EC2 instances at night.
resource "aws_scheduler_schedule" "stop_dev_instances" {
  name = "stop-dev-instances-nightly"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 20 ? * MON-FRI *)"  # 8 PM weekdays
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      InstanceIds = data.aws_instances.dev.ids
    })
  }
}

resource "aws_scheduler_schedule" "start_dev_instances" {
  name = "start-dev-instances-morning"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 7 ? * MON-FRI *)"  # 7 AM weekdays
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      InstanceIds = data.aws_instances.dev.ids
    })
  }
}

# Savings calculation:
# Weeknight off: 11 hrs/night * 5 nights = 55 hrs
# Weekend off: 48 hrs
# Total off: 103 hrs/week out of 168 hrs = 61% savings on dev compute
```

### Showback and Chargeback Model

```
Level 1 - Showback (Visibility):
  - Publish monthly cost reports per team/project via Cost Explorer.
  - Use cost allocation tags to attribute spend.
  - Share dashboards showing spend trends and anomalies.

Level 2 - Informed Chargeback:
  - Allocate shared infrastructure costs proportionally (by request count or CPU-hours).
  - Include RI/SP amortized costs in team allocations.
  - Provide unit cost metrics (cost per transaction, cost per user).

Level 3 - Full Chargeback:
  - Teams own their AWS budgets.
  - Automated alerts when teams exceed thresholds.
  - Cost review as part of architecture decision process.
```

---

## Cost Per Transaction / User Metrics

### Defining Unit Economics

```
Metric                      Formula                          Target
---------------------------------------------------------------------------
Cost per API request        Total infra / Total API calls    < $0.0001
Cost per user per month     Total infra / MAU                < $0.50
Cost per transaction        Total infra / Transactions       < $0.01
Cost per GB stored          Storage cost / Data volume       < $0.03
Infrastructure % of revenue Infra cost / Revenue * 100       < 15%
```

### Building a Cost Dashboard

```python
import boto3
from datetime import datetime, timedelta

ce_client = boto3.client('ce')
cloudwatch = boto3.client('cloudwatch')

def get_monthly_cost():
    """Get total AWS cost for the current month."""
    today = datetime.utcnow()
    start = today.replace(day=1).strftime('%Y-%m-%d')
    end = today.strftime('%Y-%m-%d')

    response = ce_client.get_cost_and_usage(
        TimePeriod={'Start': start, 'End': end},
        Granularity='MONTHLY',
        Metrics=['UnblendedCost']
    )

    return float(response['ResultsByTime'][0]['Total']['UnblendedCost']['Amount'])

def get_monthly_api_requests():
    """Get total API Gateway requests for the current month."""
    today = datetime.utcnow()
    start = today.replace(day=1)

    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApiGateway',
        MetricName='Count',
        StartTime=start,
        EndTime=today,
        Period=2592000,  # 30 days in seconds
        Statistics=['Sum']
    )

    if response['Datapoints']:
        return int(response['Datapoints'][0]['Sum'])
    return 0

def calculate_unit_economics(active_users: int):
    total_cost = get_monthly_cost()
    api_requests = get_monthly_api_requests()

    return {
        'total_cost': f'${total_cost:,.2f}',
        'cost_per_request': f'${total_cost / max(api_requests, 1):.6f}',
        'cost_per_user': f'${total_cost / max(active_users, 1):.4f}',
        'cost_per_1m_requests': f'${(total_cost / max(api_requests, 1)) * 1_000_000:.2f}',
        'api_requests': f'{api_requests:,}',
        'active_users': f'{active_users:,}'
    }
```

### Publishing Custom Metrics to CloudWatch

```hcl
# Alert when cost per user exceeds threshold.
resource "aws_cloudwatch_metric_alarm" "cost_per_user_high" {
  alarm_name          = "cost-per-user-exceeds-threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CostPerUser"
  namespace           = "CustomMetrics/FinOps"
  period              = 86400  # Daily
  statistic           = "Average"
  threshold           = 0.50   # $0.50 per user
  alarm_description   = "Cost per active user exceeded $0.50/month"
  alarm_actions       = [aws_sns_topic.finops_alerts.arn]
}
```

---

## Tools for Cost Management

### AWS Cost Explorer CLI

```bash
# Top 5 most expensive services this month.
aws ce get-cost-and-usage \
    --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json | \
    jq -r '.ResultsByTime[0].Groups |
      sort_by(.Metrics.UnblendedCost.Amount | tonumber) |
      reverse | .[0:5] | .[] |
      "\(.Keys[0]): $\(.Metrics.UnblendedCost.Amount)"'

# RI/Savings Plan utilization.
aws ce get-reservation-utilization \
    --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
    --granularity MONTHLY \
    --output table

# Savings Plan recommendations.
aws ce get-savings-plans-purchase-recommendation \
    --savings-plans-type COMPUTE_SP \
    --term-in-years ONE_YEAR \
    --payment-option NO_UPFRONT \
    --lookback-period-in-days SIXTY_DAYS \
    --output json

# RI coverage (identify commitment opportunities).
aws ce get-reservation-coverage \
    --time-period Start=$(date -u -d '90 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
    --output json | jq '.CoveragesByTime[] | {
      period: .TimePeriod.Start,
      coverage_pct: .Total.CoverageHours.CoverageHoursPercentage
    }'

# Cost forecast for the current month.
aws ce get-cost-forecast \
    --time-period Start=$(date -u +%Y-%m-%d),End=$(date -u -d '+30 days' +%Y-%m-01) \
    --metric UNBLENDED_COST \
    --granularity MONTHLY
```

### Infracost for Terraform

Infracost provides cost estimates for Terraform changes before they are applied, integrating into CI/CD to show cost impact in pull requests.

```bash
# Install Infracost.
brew install infracost

# Generate cost breakdown for current Terraform state.
infracost breakdown --path .

# Example output:
# +----------------------------------------+-------------+
# | Project                                | Monthly Cost|
# +----------------------------------------+-------------+
# | aws_instance.web (m7g.xlarge)          |       $119  |
# | aws_rds_cluster_instance.main (x2)     |       $424  |
# | aws_nat_gateway.main (x3)             |        $97  |
# | aws_lb.main                           |        $16  |
# | Total                                 |       $656  |
# +----------------------------------------+-------------+

# Compare cost of a Terraform change (for CI/CD integration).
infracost diff --path . --compare-to infracost-base.json
```

### Infracost CI/CD Integration (GitHub Actions)

```yaml
name: Infracost
on:
  pull_request:
    paths:
      - '**.tf'
      - '**.tfvars'

jobs:
  infracost:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Infracost
        uses: infracost/actions/setup@v3
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}

      - name: Generate Infracost diff
        run: |
          infracost diff \
            --path=. \
            --format=json \
            --out-file=/tmp/infracost.json

      - name: Post Infracost comment
        run: |
          infracost comment github \
            --path=/tmp/infracost.json \
            --repo=$GITHUB_REPOSITORY \
            --pull-request=${{ github.event.pull_request.number }} \
            --github-token=${{ secrets.GITHUB_TOKEN }}
```

### Recommended Tools Summary

| Tool                      | Purpose                                    | Cost        |
|---------------------------|--------------------------------------------|-------------|
| AWS Cost Explorer         | Native AWS cost analysis                   | Free        |
| AWS Compute Optimizer     | Right-sizing recommendations               | Free        |
| AWS Trusted Advisor       | Cost optimization checks                   | Free (basic)|
| Infracost                 | Terraform cost estimation in CI/CD         | Free (OSS)  |
| Kubecost                  | Kubernetes cost allocation                 | Free (OSS)  |
| Vantage                   | Multi-cloud cost management                | Paid        |
| CloudHealth (VMware)      | Enterprise FinOps platform                 | Paid        |
| Spot.io (NetApp)          | Automated Spot/RI management               | Paid        |

---

## Quick Wins Checklist

These are common optimizations that typically yield immediate savings with minimal risk.

```
[ ] Migrate all gp2 EBS volumes to gp3 (20% cheaper, higher baseline IOPS)
[ ] Delete unattached EBS volumes and unused Elastic IPs ($3.60/month per EIP)
[ ] Add S3 lifecycle rules (Intelligent-Tiering, expire old versions, abort multipart uploads)
[ ] Add VPC Gateway Endpoints for S3 and DynamoDB (free, reduces NAT costs)
[ ] Enable gzip/brotli compression on CloudFront and ALB
[ ] Stop dev/test instances on nights and weekends (up to 67% savings)
[ ] Delete unused NAT Gateways in dev environments ($32/month each)
[ ] Right-size over-provisioned RDS instances
[ ] Clean up old ECR images, CloudWatch log groups, and EBS snapshots
[ ] Switch Lambda functions to ARM/Graviton (20% cheaper, same or better perf)
[ ] Review and reduce CloudWatch log retention periods (default is never expire)
[ ] Consolidate underutilized accounts
[ ] Set up Cost Anomaly Detection (free, catches unexpected spend spikes)
```

---

## Quick Reference: Biggest Cost Levers

| Lever                        | Typical Savings | Effort | Risk   |
|------------------------------|-----------------|--------|--------|
| Reserved Instances / SP      | 30-60%          | Low    | Low    |
| Right-sizing EC2/RDS         | 10-30%          | Medium | Low    |
| Graviton migration           | 20-40%          | Medium | Low    |
| S3 lifecycle policies        | 40-70%          | Low    | Low    |
| VPC endpoints (replace NAT)  | 50-80%          | Low    | Low    |
| Spot instances (batch)       | 60-90%          | Medium | Medium |
| Auto-scaling + scheduling    | 20-60%          | Medium | Low    |
| gp2 to gp3 EBS migration    | 20%             | Low    | Low    |
| Lambda memory optimization   | 10-50%          | Medium | Low    |
| CloudFront caching           | 20-50%          | Low    | Low    |
