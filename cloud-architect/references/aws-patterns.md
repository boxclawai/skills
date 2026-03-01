# AWS Architecture Patterns Reference

Production-grade architecture patterns for common AWS workloads. Each pattern includes
design rationale, security considerations, and infrastructure-as-code snippets.

## Table of Contents

1. [Three-Tier Web Application](#1-three-tier-web-application)
2. [Serverless API](#2-serverless-api)
3. [Event-Driven Architecture](#3-event-driven-architecture)
4. [Data Lake](#4-data-lake)
5. [Multi-Account Strategy](#5-multi-account-strategy)
6. [Observability Stack](#6-observability-stack)
7. [Quick Reference: When to Use Each Pattern](#quick-reference-when-to-use-each-pattern)
8. [Security Checklist (All Patterns)](#security-checklist-all-patterns)

---

## 1. Three-Tier Web Application

### Architecture Overview

```
Internet → ALB (public subnets) → ECS/EKS (private subnets) → RDS (isolated subnets)
                                                              → ElastiCache (isolated subnets)
```

### VPC Design

Use a multi-AZ layout with three subnet tiers for defense in depth.

| Subnet Tier | CIDR Example     | Purpose                        | Route Table          |
|-------------|------------------|--------------------------------|----------------------|
| Public      | 10.0.1.0/24      | ALB, NAT Gateway, Bastion      | 0.0.0.0/0 → IGW     |
| Private     | 10.0.10.0/24     | ECS tasks, EKS pods            | 0.0.0.0/0 → NAT GW  |
| Isolated    | 10.0.100.0/24    | RDS, ElastiCache               | No internet route    |

### Terraform: VPC and Networking

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"

  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "production"
  one_nat_gateway_per_az = var.environment == "production"

  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  tags = local.common_tags
}
```

### Security Groups

```hcl
# ALB security group - allows inbound HTTPS from the internet
resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-alb-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS tasks - only accept traffic from the ALB
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project}-ecs-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS - only accept traffic from ECS tasks
resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}
```

### ALB with HTTPS Listener

```hcl
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "production"

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

### ECS Fargate Service

```hcl
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"  # Graviton - 20% cheaper
  }

  container_definitions = jsonencode([{
    name  = "app"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment = [{ name = "DB_HOST", value = aws_rds_cluster.main.endpoint }]
    secrets     = [{ name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db.arn }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.environment == "production" ? 3 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
}
```

### RDS Aurora with Multi-AZ

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${var.project}-db"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  database_name          = var.db_name
  master_username        = var.db_username
  master_password        = var.db_password
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted                   = true
  deletion_protection                 = var.environment == "production"
  backup_retention_period             = 14
  preferred_backup_window             = "03:00-04:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
}

resource "aws_rds_cluster_instance" "main" {
  count              = 2  # Writer + 1 Reader
  identifier         = "${var.project}-db-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.r6g.xlarge"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn
}
```

### NAT Gateway Cost Consideration

NAT Gateways cost ~$32/month per AZ plus data processing charges. For non-production
environments, use a single NAT Gateway. For production, deploy one per AZ for high
availability. Use VPC endpoints for S3, DynamoDB, and ECR to reduce NAT traffic.

---

## 2. Serverless API

### Architecture Overview

```
Client → API Gateway (REST/HTTP) → Lambda → DynamoDB
                                  → Lambda Authorizer (JWT validation)
                                  → CloudWatch Logs + X-Ray Traces
```

### API Gateway + Lambda (Terraform)

```hcl
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_stage" "live" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      method         = "$context.httpMethod"
      path           = "$context.path"
      status         = "$context.status"
      latency        = "$context.responseLatency"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}
```

### Lambda with Provisioned Concurrency

```hcl
resource "aws_lambda_function" "api" {
  function_name = "${var.project}-api-handler"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 29
  architectures = ["arm64"]  # Graviton - 20% cheaper

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.main.name
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "production" ? "warn" : "debug"
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }
}

# Provisioned concurrency to eliminate cold starts on critical paths
resource "aws_lambda_provisioned_concurrency_config" "api" {
  count                             = var.environment == "production" ? 1 : 0
  function_name                     = aws_lambda_function.api.function_name
  provisioned_concurrent_executions = var.provisioned_concurrency
  qualifier                         = aws_lambda_alias.live.name
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
}
```

### Cold Start Optimization Strategies

- **ARM64 architecture**: Use Graviton processors for faster init and lower cost.
- **Minimal bundle size**: Tree-shake dependencies; avoid large SDKs.
- **Provisioned concurrency**: Set on aliases for production critical paths.
- **SnapStart (Java)**: Enable for JVM-based functions to reduce init from seconds to <200ms.
- **Keep-alive connections**: Reuse HTTP/DB connections outside the handler.

### DynamoDB Single-Table Design

```hcl
resource "aws_dynamodb_table" "main" {
  name         = "${var.project}-table"
  billing_mode = var.environment == "production" ? "PROVISIONED" : "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = local.common_tags
}
```

### DynamoDB Access Pattern Reference

```
PK              | SK                 | Data Attributes    | GSI1PK         | GSI1SK
USER#123        | PROFILE            | name, email        | EMAIL#a@b.com  | USER#123
USER#123        | ORDER#2026-001     | total, status      | STATUS#pending | ORDER#2026-001
ORDER#2026-001  | METADATA           | userId, date       | USER#123       | ORDER#2026-001
ORDER#2026-001  | ITEM#SKU-A         | qty, price         | -              | -

Access Patterns:
  PK = "USER#123", SK = "PROFILE"             → Get user profile
  PK = "USER#123", SK begins_with("ORDER#")   → List user orders
  PK = "ORDER#2026-001"                       → Get order with all items
  GSI1: PK = "STATUS#pending"                 → List orders by status
```

---

## 3. Event-Driven Architecture

### Architecture Overview

```
Producers → EventBridge → Rules → SQS → Lambda consumers
                                → Step Functions (orchestration)
                                → SNS → Email/SMS/HTTP
                        → Archive (replay capability)
```

### EventBridge Bus and Rules

```hcl
resource "aws_cloudwatch_event_bus" "app" {
  name = "${var.project}-events"
}

resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "order-created"
  event_bus_name = aws_cloudwatch_event_bus.app.name

  event_pattern = jsonencode({
    source      = ["com.myapp.orders"]
    detail-type = ["OrderCreated"]
  })
}

resource "aws_cloudwatch_event_target" "order_processing" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.app.name
  arn            = aws_sqs_queue.order_processing.arn

  dead_letter_config {
    arn = aws_sqs_queue.events_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

# Archive for event replay during incident recovery
resource "aws_cloudwatch_event_archive" "app" {
  name             = "${var.project}-archive"
  event_source_arn = aws_cloudwatch_event_bus.app.arn
  retention_days   = 30
}
```

### SQS with Dead Letter Queue

```hcl
resource "aws_sqs_queue" "order_processing" {
  name                       = "${var.project}-order-processing"
  visibility_timeout_seconds = 300  # 6x Lambda timeout
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20  # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })

  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue" "order_dlq" {
  name                      = "${var.project}-order-processing-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, {
    AlertOnMessages = "true"
  })
}

# CloudWatch alarm when messages land in the DLQ
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project}-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.order_dlq.name
  }
}

# Lambda consumer with batch failure reporting
resource "aws_lambda_event_source_mapping" "order_processing" {
  event_source_arn                   = aws_sqs_queue.order_processing.arn
  function_name                      = aws_lambda_function.order_processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}
```

### Step Functions Orchestration (CloudFormation)

```yaml
OrderProcessingStateMachine:
  Type: AWS::StepFunctions::StateMachine
  Properties:
    StateMachineName: !Sub "${Project}-order-processing"
    StateMachineType: STANDARD
    RoleArn: !GetAtt StepFunctionsRole.Arn
    Definition:
      StartAt: ValidateOrder
      States:
        ValidateOrder:
          Type: Task
          Resource: !GetAtt ValidateOrderFunction.Arn
          Retry:
            - ErrorEquals: ["States.TaskFailed"]
              IntervalSeconds: 2
              MaxAttempts: 3
              BackoffRate: 2
          Catch:
            - ErrorEquals: ["States.ALL"]
              Next: HandleFailure
          Next: ProcessPayment

        ProcessPayment:
          Type: Task
          Resource: !GetAtt ProcessPaymentFunction.Arn
          TimeoutSeconds: 30
          Retry:
            - ErrorEquals: ["PaymentRetryableError"]
              IntervalSeconds: 5
              MaxAttempts: 2
              BackoffRate: 2
          Catch:
            - ErrorEquals: ["States.ALL"]
              Next: HandleFailure
          Next: FulfillOrder

        FulfillOrder:
          Type: Parallel
          Branches:
            - StartAt: UpdateInventory
              States:
                UpdateInventory:
                  Type: Task
                  Resource: !GetAtt UpdateInventoryFunction.Arn
                  End: true
            - StartAt: SendConfirmation
              States:
                SendConfirmation:
                  Type: Task
                  Resource: !GetAtt SendConfirmationFunction.Arn
                  End: true
          Next: OrderComplete

        OrderComplete:
          Type: Succeed

        HandleFailure:
          Type: Task
          Resource: !GetAtt HandleFailureFunction.Arn
          End: true
```

### SNS Fan-Out Pattern

```hcl
resource "aws_sns_topic" "order_events" {
  name = "${var.project}-order-events"
}

# Multiple SQS queues subscribe to the same topic for parallel processing
resource "aws_sns_topic_subscription" "inventory" {
  topic_arn            = aws_sns_topic.order_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.inventory_update.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    eventType = ["OrderCreated", "OrderCancelled"]
  })
}

resource "aws_sns_topic_subscription" "analytics" {
  topic_arn            = aws_sns_topic.order_events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.analytics_ingest.arn
  raw_message_delivery = true
  # No filter - receives all events
}

resource "aws_sns_topic_subscription" "notifications" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notifications.arn

  filter_policy = jsonencode({
    eventType  = ["OrderCreated"]
    orderTotal = [{ numeric = [">=", 100] }]  # Only high-value orders
  })
}
```

### DLQ Handling Best Practices

- Set SQS `visibility_timeout` to at least 6x the consumer Lambda timeout.
- Use `maxReceiveCount` of 3-5 before sending to DLQ.
- Alarm on DLQ depth and set up an operational runbook for reprocessing.
- Tag DLQ messages with the original event source and failure reason.
- Use EventBridge archive and replay for recovering from upstream failures.
- Use `ReportBatchItemFailures` so only failed messages in a batch are retried.

---

## 4. Data Lake

### Architecture Overview

```
Sources → Kinesis/S3 → Raw Zone → Glue ETL → Processed Zone → Athena/Redshift
                        (landing)              (parquet)        (curated views)
                                                              → QuickSight
```

### S3 Bucket Structure (Medallion Architecture)

```
s3://datalake-{account}-{region}/
  ├── raw/              # Bronze: Immutable source data, original format
  │   ├── orders/
  │   │   └── year=2026/month=03/day=01/
  │   │       └── orders_20260301.json.gz
  │   └── clickstream/
  │       └── year=2026/month=03/day=01/hour=14/
  ├── processed/        # Silver: Cleaned, validated, partitioned Parquet
  │   ├── orders/
  │   │   └── year=2026/month=03/
  │   │       └── part-00000.snappy.parquet
  │   └── sessions/
  └── curated/          # Gold: Business-ready aggregations
      ├── daily_revenue/
      └── user_cohorts/
```

### Terraform: Data Lake S3 and Glue

```hcl
resource "aws_s3_bucket" "datalake" {
  bucket = "${var.project}-datalake-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  rule {
    id     = "raw-tiering"
    status = "Enabled"
    filter { prefix = "raw/" }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "processed-tiering"
    status = "Enabled"
    filter { prefix = "processed/" }
    transition {
      days          = 180
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_glue_catalog_database" "datalake" {
  name = "${var.project}_datalake"
}

resource "aws_glue_crawler" "raw_orders" {
  name          = "${var.project}-raw-orders"
  database_name = aws_glue_catalog_database.datalake.name
  role          = aws_iam_role.glue_crawler.arn
  schedule      = "cron(0 */6 * * ? *)"

  s3_target {
    path = "s3://${aws_s3_bucket.datalake.id}/raw/orders/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })
}

resource "aws_glue_job" "orders_etl" {
  name     = "${var.project}-orders-etl"
  role_arn = aws_iam_role.glue_etl.arn

  command {
    script_location = "s3://${aws_s3_bucket.scripts.id}/glue/orders_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"               = "python"
    "--enable-metrics"             = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"            = "true"
    "--spark-event-logs-path"      = "s3://${aws_s3_bucket.scripts.id}/spark-logs/"
    "--TempDir"                    = "s3://${aws_s3_bucket.scripts.id}/temp/"
    "--source_path"                = "s3://${aws_s3_bucket.datalake.id}/raw/orders/"
    "--target_path"                = "s3://${aws_s3_bucket.datalake.id}/processed/orders/"
  }

  glue_version      = "4.0"
  number_of_workers = 10
  worker_type       = "G.1X"
  timeout           = 120
}
```

### Lake Formation Permissions

```hcl
resource "aws_lakeformation_permissions" "analysts_read" {
  principal   = aws_iam_role.data_analysts.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.datalake.name
    wildcard      = true
  }
}

resource "aws_lakeformation_permissions" "engineers_write" {
  principal   = aws_iam_role.data_engineers.arn
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.datalake.name
    wildcard      = true
  }
}
```

### Athena Query Examples

```sql
-- Cost-optimized query: partition pruning + columnar scan
SELECT date_trunc('day', order_date) AS day,
       COUNT(*) AS order_count,
       SUM(total_amount) AS revenue
FROM datalake.processed_orders
WHERE year = '2026' AND month = '03'
GROUP BY 1
ORDER BY 1;

-- CTAS: Create a curated table from processed data
CREATE TABLE datalake.daily_revenue
WITH (
  format = 'PARQUET',
  partitioned_by = ARRAY['year', 'month'],
  external_location = 's3://datalake-bucket/curated/daily_revenue/'
) AS
SELECT date_trunc('day', order_date) AS day,
       product_category,
       COUNT(DISTINCT customer_id) AS unique_customers,
       SUM(total_amount) AS revenue,
       year, month
FROM datalake.processed_orders
GROUP BY 1, 2, year, month;

-- Athena charges $5/TB scanned. Parquet + partitioning can reduce scans
-- from hundreds of GB to a few MB for targeted queries.
```

---

## 5. Multi-Account Strategy

### Account Structure

```
Management Account (root)
├── Security OU
│   ├── Log Archive Account       # Centralized CloudTrail, Config, VPC Flow Logs
│   └── Security Tooling Account  # GuardDuty delegated admin, Security Hub
├── Infrastructure OU
│   ├── Network Hub Account       # Transit Gateway, DNS, shared VPCs
│   └── Shared Services Account   # CI/CD, artifact repos, container registries
├── Workloads OU
│   ├── Dev Account
│   ├── Staging Account
│   └── Production Account
└── Sandbox OU
    └── Developer Sandbox Accounts
```

### Control Tower and Organizations (Terraform)

```hcl
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "controltower.amazonaws.com",
    "sso.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "config.amazonaws.com",
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  feature_set = "ALL"
}

# SCP: deny actions outside approved regions
resource "aws_organizations_policy" "region_restriction" {
  name    = "RestrictRegions"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnapprovedRegions"
        Effect    = "Deny"
        NotAction = [
          "iam:*", "sts:*", "organizations:*",
          "support:*", "budgets:*", "cloudfront:*",
          "route53:*", "waf:*", "wafv2:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "region_restriction" {
  policy_id = aws_organizations_policy.region_restriction.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# SCP: prevent root user actions in member accounts
resource "aws_organizations_policy" "deny_root" {
  name    = "DenyRootUser"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyRootUserActions"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      },
      {
        Sid       = "DenyLeaveOrganization"
        Effect    = "Deny"
        Action    = "organizations:LeaveOrganization"
        Resource  = "*"
      }
    ]
  })
}
```

### Cross-Account IAM Role

```hcl
# In the target account: role that CI/CD in the shared services account can assume
resource "aws_iam_role" "deploy" {
  name = "cicd-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.cicd_account_id}:role/cicd-runner"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })
}

# In the CI/CD account: policy allowing assumption of deploy roles
resource "aws_iam_policy" "assume_deploy" {
  name = "assume-deploy-roles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${var.dev_account_id}:role/cicd-deploy-role",
          "arn:aws:iam::${var.staging_account_id}:role/cicd-deploy-role",
          "arn:aws:iam::${var.prod_account_id}:role/cicd-deploy-role",
        ]
      }
    ]
  })
}
```

### SSO Permission Sets

```hcl
resource "aws_ssoadmin_permission_set" "admin" {
  name             = "AdministratorAccess"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
}

resource "aws_ssoadmin_permission_set" "readonly" {
  name             = "ReadOnlyAccess"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
}
```

### Key Principles

- **Least privilege by default**: SCPs deny dangerous actions at the OU level.
- **Centralized logging**: All accounts send CloudTrail and Config to Log Archive.
- **Network isolation**: Each workload account has its own VPC; interconnect via Transit Gateway.
- **SSO for human access**: Never create long-lived IAM users; use Identity Center with MFA.
- **Tagging enforcement**: Tag policies ensure cost allocation and ownership tracking.

---

## 6. Observability Stack

### Architecture Overview

```
Application → CloudWatch Agent → Metrics/Logs → Alarms → SNS → PagerDuty/Slack
            → X-Ray SDK → Traces → Service Map
            → CloudWatch Embedded Metric Format (EMF)
```

### CloudWatch Alarms (Terraform)

```hcl
# P99 latency alarm
resource "aws_cloudwatch_metric_alarm" "api_high_latency" {
  alarm_name          = "${var.project}-api-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2.0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# 5xx error rate alarm using metric math
resource "aws_cloudwatch_metric_alarm" "api_error_rate" {
  alarm_name          = "${var.project}-api-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5

  metric_query {
    id          = "error_rate"
    expression  = "(errors / requests) * 100"
    label       = "5xx Error Rate %"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Composite alarm: fire only when BOTH latency AND errors are elevated
resource "aws_cloudwatch_composite_alarm" "service_health" {
  alarm_name = "${var.project}-service-unhealthy"

  alarm_rule = join(" AND ", [
    "ALARM(${aws_cloudwatch_metric_alarm.api_high_latency.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.api_error_rate.alarm_name})"
  ])

  alarm_actions = [aws_sns_topic.critical_alerts.arn]
}
```

### CloudWatch Log Insights Queries

```
# Lambda cold start analysis
fields @timestamp, @initDuration, @duration, @memorySize, @maxMemoryUsed
| filter ispresent(@initDuration)
| stats avg(@initDuration) as avgColdStart,
        max(@initDuration) as maxColdStart,
        count(*) as coldStartCount
  by bin(1h)

# Find the slowest API requests in the last hour
fields @timestamp, @message, @duration
| filter @type = "REPORT"
| stats avg(@duration), max(@duration), p99(@duration) by bin(5m)
| sort max(@duration) desc

# Trace errors across Lambda invocations
fields @timestamp, @requestId, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50

# API Gateway latency breakdown
fields @timestamp, responseLatency, integrationLatency, path
| stats avg(responseLatency) as avg_total,
        avg(integrationLatency) as avg_integration,
        avg(responseLatency - integrationLatency) as avg_overhead
  by path
| sort avg_total desc

# DynamoDB throttle detection
filter @message like /ProvisionedThroughputExceededException/
| stats count(*) as throttle_count by bin(5m)
| sort throttle_count desc
```

### X-Ray Tracing Configuration

```hcl
resource "aws_xray_sampling_rule" "api" {
  rule_name      = "${var.project}-api"
  priority       = 1000
  reservoir_size = 10    # 10 traces per second guaranteed
  fixed_rate     = 0.05  # then 5% sampling
  version        = 1
  host           = "*"
  http_method    = "*"
  service_name   = "${var.project}-api"
  service_type   = "*"
  url_path       = "*"
  resource_arn   = "*"
}

# X-Ray group for filtering traces with errors
resource "aws_xray_group" "errors" {
  group_name        = "${var.project}-errors"
  filter_expression = "fault = true OR error = true"
}
```

### Custom Metrics with Embedded Metric Format (EMF)

```javascript
// Emit structured metrics from Lambda without CloudWatch SDK overhead.
// EMF logs are automatically parsed by CloudWatch into custom metrics.
const emitMetric = (metricName, value, unit, dimensions) => {
  console.log(JSON.stringify({
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [{
        Namespace: "MyApp/BusinessMetrics",
        Dimensions: [Object.keys(dimensions)],
        Metrics: [{ Name: metricName, Unit: unit }]
      }]
    },
    ...dimensions,
    [metricName]: value
  }));
};

// Usage in a Lambda handler
exports.handler = async (event) => {
  const startTime = Date.now();
  // ... process request ...

  emitMetric("OrderValue", order.total, "None", {
    Environment: process.env.ENVIRONMENT,
    Region: process.env.AWS_REGION
  });

  emitMetric("ProcessingDuration", Date.now() - startTime, "Milliseconds", {
    Environment: process.env.ENVIRONMENT,
    Operation: "CreateOrder"
  });
};
```

### Dashboard as Code (CloudFormation)

```yaml
MonitoringDashboard:
  Type: AWS::CloudWatch::Dashboard
  Properties:
    DashboardName: !Sub "${Project}-operations"
    DashboardBody: !Sub |
      {
        "widgets": [
          {
            "type": "metric",
            "properties": {
              "title": "API Latency (p50/p99)",
              "metrics": [
                ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${ALB.FullName}", {"stat": "p50", "label": "p50"}],
                ["...", {"stat": "p99", "label": "p99"}]
              ],
              "period": 60,
              "view": "timeSeries"
            }
          },
          {
            "type": "metric",
            "properties": {
              "title": "Request Count & Errors",
              "metrics": [
                ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${ALB.FullName}", {"stat": "Sum"}],
                ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "${ALB.FullName}", {"stat": "Sum", "color": "#d62728"}]
              ],
              "period": 60,
              "view": "timeSeries"
            }
          },
          {
            "type": "log",
            "properties": {
              "title": "Recent Errors",
              "query": "fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20",
              "region": "${AWS::Region}",
              "view": "table"
            }
          }
        ]
      }
```

---

## Quick Reference: When to Use Each Pattern

| Workload Characteristic         | Recommended Pattern           |
|---------------------------------|-------------------------------|
| Consistent traffic, low latency | Three-Tier (ECS/EKS + RDS)   |
| Bursty traffic, pay-per-use     | Serverless API                |
| Loosely coupled microservices   | Event-Driven                  |
| Analytics and reporting         | Data Lake                     |
| Enterprise governance           | Multi-Account Strategy        |
| All production workloads        | Observability Stack           |

## Security Checklist (All Patterns)

```
[ ] Encryption at rest enabled for all data stores (RDS, S3, DynamoDB, SQS)
[ ] Encryption in transit (TLS 1.2+ on all endpoints)
[ ] Least-privilege IAM roles (no wildcard actions on production resources)
[ ] VPC security groups reference other groups, not CIDR blocks where possible
[ ] Secrets in Secrets Manager or SSM Parameter Store, not environment variables
[ ] CloudTrail enabled in all accounts with log file validation
[ ] GuardDuty enabled in all accounts
[ ] Automated compliance checks via AWS Config rules
[ ] WAF on all public-facing ALBs and API Gateways
[ ] Regular access key rotation and unused credential cleanup
```
