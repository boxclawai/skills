# Production Monitoring & Observability Templates

Comprehensive, production-grade templates for monitoring, alerting, log aggregation,
distributed tracing, and SLO management. All configurations are designed for
Kubernetes environments and follow industry best practices.

---

## Table of Contents

1. [Prometheus Configuration](#1-prometheus-configuration)
2. [Alerting Rules](#2-alerting-rules)
3. [Grafana Dashboard JSON](#3-grafana-dashboard-json)
4. [Loki + Promtail Configuration](#4-loki--promtail-configuration)
5. [OpenTelemetry Collector Configuration](#5-opentelemetry-collector-configuration)
6. [PagerDuty / Slack Integration (Alertmanager)](#6-pagerduty--slack-integration-alertmanager)
7. [SLO / SLI Definitions](#7-slo--sli-definitions)

---

## 1. Prometheus Configuration

The following `prometheus.yml` configures scrape jobs for the most common
infrastructure and application targets in a Kubernetes cluster.

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    cluster: "production"
    environment: "prod"

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "alertmanager:9093"
      scheme: http
      timeout: 10s
      api_version: v2

scrape_configs:
  # -------------------------------------------------------
  # Prometheus self-monitoring
  # -------------------------------------------------------
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # -------------------------------------------------------
  # Node Exporter - host-level metrics (CPU, memory, disk, network)
  # -------------------------------------------------------
  - job_name: "node-exporter"
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names: ["monitoring"]
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        regex: "node-exporter"
        action: keep
      - source_labels: [__meta_kubernetes_node_name]
        target_label: node

  # -------------------------------------------------------
  # cAdvisor - container resource metrics
  # -------------------------------------------------------
  - job_name: "cadvisor"
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor

  # -------------------------------------------------------
  # kube-state-metrics - Kubernetes object state
  # -------------------------------------------------------
  - job_name: "kube-state-metrics"
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names: ["monitoring"]
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        regex: "kube-state-metrics"
        action: keep

  # -------------------------------------------------------
  # Application pods with prometheus.io annotations
  # -------------------------------------------------------
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels:
          - __address__
          - __meta_kubernetes_pod_annotation_prometheus_io_port
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod

  # -------------------------------------------------------
  # Kubernetes API server
  # -------------------------------------------------------
  - job_name: "kubernetes-apiservers"
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels:
          - __meta_kubernetes_namespace
          - __meta_kubernetes_service_name
          - __meta_kubernetes_endpoint_port_name
        action: keep
        regex: default;kubernetes;https
```

---

## 2. Alerting Rules

Production-grade PrometheusRule definitions covering error rates, latency,
infrastructure health, certificate expiry, and Kubernetes-specific conditions.

```yaml
# alerting-rules.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: production-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    # =======================================================
    # Application Health
    # =======================================================
    - name: application.rules
      rules:
        # --- High Error Rate (5xx > 1% of total requests) ---
        - alert: HighErrorRate
          expr: |
            (
              sum(rate(http_requests_total{status=~"5.."}[5m])) by (namespace, service)
              /
              sum(rate(http_requests_total[5m])) by (namespace, service)
            ) > 0.01
          for: 5m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "High 5xx error rate on {{ $labels.service }}"
            description: >-
              Service {{ $labels.service }} in namespace {{ $labels.namespace }}
              has a 5xx error rate of {{ $value | humanizePercentage }} over
              the last 5 minutes (threshold: 1%).
            runbook_url: "https://runbooks.internal/high-error-rate"

        # --- High Latency (p99 > 2 seconds) ---
        - alert: HighLatencyP99
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket[5m])) by (le, namespace, service)
            ) > 2
          for: 5m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "High p99 latency on {{ $labels.service }}"
            description: >-
              Service {{ $labels.service }} in namespace {{ $labels.namespace }}
              has a p99 latency of {{ $value | humanizeDuration }}
              (threshold: 2s).
            runbook_url: "https://runbooks.internal/high-latency"

    # =======================================================
    # Kubernetes Pod Health
    # =======================================================
    - name: kubernetes.pod.rules
      rules:
        # --- Pod CrashLooping ---
        - alert: PodCrashLooping
          expr: |
            increase(kube_pod_container_status_restarts_total[1h]) > 5
          for: 10m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Pod {{ $labels.pod }} is crash-looping"
            description: >-
              Pod {{ $labels.pod }} in namespace {{ $labels.namespace }}
              has restarted {{ $value | humanize }} times in the last hour.
            runbook_url: "https://runbooks.internal/pod-crashloop"

        # --- Pod Not Ready ---
        - alert: PodNotReady
          expr: |
            kube_pod_status_ready{condition="true"} == 0
          for: 15m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Pod {{ $labels.pod }} is not ready"
            description: >-
              Pod {{ $labels.pod }} in namespace {{ $labels.namespace }}
              has been in a non-ready state for more than 15 minutes.

    # =======================================================
    # Node / Infrastructure Health
    # =======================================================
    - name: infrastructure.rules
      rules:
        # --- High CPU Usage ---
        - alert: HighCPUUsage
          expr: |
            (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.85
          for: 10m
          labels:
            severity: warning
            team: infrastructure
          annotations:
            summary: "High CPU usage on {{ $labels.instance }}"
            description: >-
              Node {{ $labels.instance }} CPU usage is at
              {{ $value | humanizePercentage }} (threshold: 85%).

        # --- High Memory Usage ---
        - alert: HighMemoryUsage
          expr: |
            (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.90
          for: 10m
          labels:
            severity: warning
            team: infrastructure
          annotations:
            summary: "High memory usage on {{ $labels.instance }}"
            description: >-
              Node {{ $labels.instance }} memory usage is at
              {{ $value | humanizePercentage }} (threshold: 90%).

        # --- Disk Space Running Low ---
        - alert: DiskSpaceLow
          expr: |
            (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
              / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.15
          for: 10m
          labels:
            severity: warning
            team: infrastructure
          annotations:
            summary: "Low disk space on {{ $labels.instance }}"
            description: >-
              Node {{ $labels.instance }} mountpoint {{ $labels.mountpoint }}
              has only {{ $value | humanizePercentage }} free disk space
              (threshold: 15%).

        - alert: DiskSpaceCritical
          expr: |
            (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
              / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.05
          for: 5m
          labels:
            severity: critical
            team: infrastructure
          annotations:
            summary: "Critical disk space on {{ $labels.instance }}"
            description: >-
              Node {{ $labels.instance }} mountpoint {{ $labels.mountpoint }}
              has only {{ $value | humanizePercentage }} free disk space
              (threshold: 5%).

        # --- Certificate Expiry ---
        - alert: CertificateExpiringSoon
          expr: |
            (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
          for: 1h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "TLS certificate expiring soon for {{ $labels.instance }}"
            description: >-
              The TLS certificate for {{ $labels.instance }} expires in
              {{ $value | humanize }} days.

        - alert: CertificateExpiryCritical
          expr: |
            (probe_ssl_earliest_cert_expiry - time()) / 86400 < 7
          for: 30m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "TLS certificate expiry critical for {{ $labels.instance }}"
            description: >-
              The TLS certificate for {{ $labels.instance }} expires in
              {{ $value | humanize }} days. Immediate action required.

        # --- Node Not Ready ---
        - alert: NodeNotReady
          expr: |
            kube_node_status_condition{condition="Ready",status="true"} == 0
          for: 5m
          labels:
            severity: critical
            team: infrastructure
          annotations:
            summary: "Node {{ $labels.node }} is not ready"
            description: >-
              Kubernetes node {{ $labels.node }} has been in a NotReady state
              for more than 5 minutes.
            runbook_url: "https://runbooks.internal/node-not-ready"
```

---

## 3. Grafana Dashboard JSON

A complete Grafana dashboard implementing the RED method (Request rate, Error rate,
Duration) and USE method (Utilization, Saturation, Errors) with templated namespace
and service selectors.

```json
{
  "dashboard": {
    "id": null,
    "uid": "prod-service-overview",
    "title": "Production Service Overview - RED & USE",
    "tags": ["production", "red", "use", "sre"],
    "timezone": "browser",
    "refresh": "30s",
    "time": { "from": "now-1h", "to": "now" },
    "templating": {
      "list": [
        {
          "name": "datasource",
          "type": "datasource",
          "query": "prometheus",
          "current": { "text": "Prometheus", "value": "Prometheus" }
        },
        {
          "name": "namespace",
          "type": "query",
          "datasource": { "uid": "${datasource}" },
          "query": "label_values(http_requests_total, namespace)",
          "refresh": 2,
          "multi": false,
          "includeAll": true,
          "allValue": ".*"
        },
        {
          "name": "service",
          "type": "query",
          "datasource": { "uid": "${datasource}" },
          "query": "label_values(http_requests_total{namespace=~\"$namespace\"}, service)",
          "refresh": 2,
          "multi": true,
          "includeAll": true,
          "allValue": ".*"
        }
      ]
    },
    "panels": [
      {
        "title": "Request Rate (req/s)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 0, "y": 0 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{namespace=~\"$namespace\",service=~\"$service\"}[5m])) by (service)",
            "legendFormat": "{{ service }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps",
            "color": { "mode": "palette-classic" }
          }
        }
      },
      {
        "title": "Error Rate (%)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 8, "y": 0 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{namespace=~\"$namespace\",service=~\"$service\",status=~\"5..\"}[5m])) by (service) / sum(rate(http_requests_total{namespace=~\"$namespace\",service=~\"$service\"}[5m])) by (service) * 100",
            "legendFormat": "{{ service }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "color": { "mode": "palette-classic" },
            "thresholds": {
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 0.5 },
                { "color": "red", "value": 1.0 }
              ]
            }
          }
        }
      },
      {
        "title": "Latency p50 / p95 / p99",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 16, "y": 0 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{namespace=~\"$namespace\",service=~\"$service\"}[5m])) by (le, service))",
            "legendFormat": "{{ service }} p50"
          },
          {
            "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace=~\"$namespace\",service=~\"$service\"}[5m])) by (le, service))",
            "legendFormat": "{{ service }} p95"
          },
          {
            "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{namespace=~\"$namespace\",service=~\"$service\"}[5m])) by (le, service))",
            "legendFormat": "{{ service }} p99"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "s" }
        }
      },
      {
        "title": "CPU Utilization by Pod",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 0, "y": 8 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=~\"$namespace\",container!=\"POD\",container!=\"\"}[5m])) by (pod)",
            "legendFormat": "{{ pod }}"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "percentunit" }
        }
      },
      {
        "title": "Memory Usage by Pod",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 8, "y": 8 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "sum(container_memory_working_set_bytes{namespace=~\"$namespace\",container!=\"POD\",container!=\"\"}) by (pod)",
            "legendFormat": "{{ pod }}"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "bytes" }
        }
      },
      {
        "title": "Disk I/O (read + write bytes/s)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 16, "y": 8 },
        "datasource": { "uid": "${datasource}" },
        "targets": [
          {
            "expr": "sum(rate(node_disk_read_bytes_total[5m])) by (instance)",
            "legendFormat": "{{ instance }} read"
          },
          {
            "expr": "sum(rate(node_disk_written_bytes_total[5m])) by (instance)",
            "legendFormat": "{{ instance }} write"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "Bps" }
        }
      }
    ]
  }
}
```

---

## 4. Loki + Promtail Configuration

### 4.1 Promtail Configuration

Promtail agent configuration with pipeline stages for parsing structured JSON logs,
extracting labels, and filtering noise.

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki-gateway.monitoring.svc.cluster.local:3100/loki/api/v1/push
    tenant_id: production
    batchwait: 1s
    batchsize: 1048576
    backoff_config:
      min_period: 500ms
      max_period: 5m
      max_retries: 10

scrape_configs:
  # -------------------------------------------------------
  # Kubernetes pod logs
  # -------------------------------------------------------
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_controller_name]
        regex: "([0-9a-z-.]+?)(-[0-9a-f]{8,10})?"
        target_label: __tmp_controller_name
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        target_label: app
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
      # Drop pods that opt out of log collection
      - source_labels: [__meta_kubernetes_pod_annotation_promtail_io_scrape]
        regex: "false"
        action: drop

    pipeline_stages:
      # ---- Detect and parse JSON logs ----
      - match:
          selector: '{container!=""}'
          stages:
            - docker: {}
            - json:
                expressions:
                  level: level
                  msg: msg
                  caller: caller
                  trace_id: trace_id
                  span_id: span_id
                  status_code: status_code
                  duration_ms: duration_ms
            - labels:
                level:
                trace_id:
            - timestamp:
                source: timestamp
                format: "2006-01-02T15:04:05.000Z07:00"
                fallback_formats:
                  - "2006-01-02T15:04:05Z"
                  - UnixMs

      # ---- Drop debug logs in production ----
      - match:
          selector: '{level="debug"}'
          action: drop
          drop_counter_reason: debug_logs_dropped

      # ---- Add static labels ----
      - static_labels:
          cluster: production

      # ---- Rate limit noisy containers ----
      - limit:
          rate: 100
          burst: 200
```

### 4.2 LogQL Query Examples

Common queries for production troubleshooting and dashboarding.

```promql
# --- Error logs for a specific service in the last hour ---
{namespace="production", app="api-gateway"} |= "error" | json | level="error"

# --- HTTP 5xx responses with structured fields ---
{namespace="production", app="api-gateway"}
  | json
  | status_code >= 500
  | line_format "{{.timestamp}} [{{.level}}] {{.status_code}} {{.msg}} ({{.duration_ms}}ms)"

# --- Top 10 most frequent error messages ---
topk(10,
  sum by (msg) (
    count_over_time(
      {namespace="production"} | json | level="error" [1h]
    )
  )
)

# --- Latency percentiles from structured logs ---
quantile_over_time(0.99,
  {namespace="production", app="api-gateway"}
    | json
    | unwrap duration_ms [5m]
) by (app)

# --- Log volume rate per service ---
sum by (app) (
  rate({namespace="production"}[5m])
)

# --- Trace-correlated log lookup ---
{namespace="production"} |= "abc123-trace-id-here"

# --- Multi-line stack trace extraction ---
{namespace="production", app="worker"}
  | regexp `(?P<exception>Exception.*\n(\s+at .+\n)*)`
```

---

## 5. OpenTelemetry Collector Configuration

A production-ready OpenTelemetry Collector configuration that receives traces,
metrics, and logs, processes them, and exports to multiple backends.

```yaml
# otel-collector.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
        max_recv_msg_size_mib: 16
      http:
        endpoint: "0.0.0.0:4318"
        cors:
          allowed_origins: ["*"]

  # Scrape Prometheus-format metrics from local endpoints
  prometheus:
    config:
      scrape_configs:
        - job_name: "otel-collector-self"
          scrape_interval: 10s
          static_configs:
            - targets: ["0.0.0.0:8888"]

  # Host metrics from the collector node
  hostmetrics:
    collection_interval: 30s
    scrapers:
      cpu: {}
      disk: {}
      filesystem: {}
      load: {}
      memory: {}
      network: {}

processors:
  # Batch for efficient export
  batch:
    send_batch_size: 8192
    send_batch_max_size: 16384
    timeout: 5s

  # Memory limiter to prevent OOM
  memory_limiter:
    check_interval: 5s
    limit_mib: 1024
    spike_limit_mib: 256

  # Add resource attributes
  resource:
    attributes:
      - key: environment
        value: production
        action: upsert
      - key: cluster
        value: prod-us-east-1
        action: upsert

  # Tail-based sampling for traces
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    policies:
      - name: errors-policy
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow-requests
        type: latency
        latency:
          threshold_ms: 2000
      - name: probabilistic-sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

  # Transform attributes
  attributes:
    actions:
      - key: db.statement
        action: hash
      - key: http.request.header.authorization
        action: delete

exporters:
  # Traces to Jaeger / Tempo
  otlp/traces:
    endpoint: "tempo.monitoring.svc.cluster.local:4317"
    tls:
      insecure: false
      ca_file: /etc/ssl/certs/ca-certificates.crt
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  # Metrics to Prometheus remote write
  prometheusremotewrite:
    endpoint: "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
    tls:
      insecure: true
    resource_to_telemetry_conversion:
      enabled: true

  # Logs to Loki
  loki:
    endpoint: "http://loki-gateway.monitoring.svc.cluster.local:3100/loki/api/v1/push"
    tenant_id: production
    labels:
      resource:
        service.name: "service"
        service.namespace: "namespace"

  # Debug exporter for development (disabled in production)
  # debug:
  #   verbosity: detailed

extensions:
  health_check:
    endpoint: "0.0.0.0:13133"
  pprof:
    endpoint: "0.0.0.0:1888"
  zpages:
    endpoint: "0.0.0.0:55679"

service:
  extensions: [health_check, pprof, zpages]
  telemetry:
    logs:
      level: info
    metrics:
      address: "0.0.0.0:8888"
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, attributes, batch]
      exporters: [otlp/traces]
    metrics:
      receivers: [otlp, prometheus, hostmetrics]
      processors: [memory_limiter, resource, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [loki]
```

---

## 6. PagerDuty / Slack Integration (Alertmanager)

Complete Alertmanager configuration with smart routing, receiver definitions for
PagerDuty and Slack, and inhibition rules to reduce alert noise.

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: "smtp.internal:587"
  smtp_from: "alertmanager@company.com"
  smtp_auth_username: "alertmanager"
  smtp_auth_password_file: "/etc/alertmanager/secrets/smtp-password"
  pagerduty_url: "https://events.pagerduty.com/v2/enqueue"
  slack_api_url_file: "/etc/alertmanager/secrets/slack-webhook-url"

# -------------------------------------------------------
# Routing tree
# -------------------------------------------------------
route:
  receiver: "default-slack"
  group_by: ["alertname", "namespace", "service"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    # Critical alerts -> PagerDuty (immediate page)
    - receiver: "pagerduty-critical"
      match:
        severity: critical
      group_wait: 10s
      repeat_interval: 1h
      continue: true

    # Critical alerts also go to Slack #incidents
    - receiver: "slack-incidents"
      match:
        severity: critical
      group_wait: 10s

    # Warning alerts -> Slack #alerts
    - receiver: "slack-warnings"
      match:
        severity: warning
      group_wait: 1m
      repeat_interval: 8h

    # Infrastructure team alerts
    - receiver: "slack-infrastructure"
      match:
        team: infrastructure
      group_by: ["alertname", "instance"]

    # Platform team alerts
    - receiver: "slack-platform"
      match:
        team: platform
      group_by: ["alertname", "namespace", "service"]

# -------------------------------------------------------
# Receivers
# -------------------------------------------------------
receivers:
  - name: "default-slack"
    slack_configs:
      - channel: "#monitoring"
        send_resolved: true
        title: '{{ .GroupLabels.alertname }} [{{ .Status | toUpper }}]'
        text: >-
          *Alert:* {{ .GroupLabels.alertname }}
          *Severity:* {{ .CommonLabels.severity }}
          *Namespace:* {{ .CommonLabels.namespace }}
          {{ range .Alerts }}
          - {{ .Annotations.summary }}
          {{ end }}

  - name: "pagerduty-critical"
    pagerduty_configs:
      - service_key_file: "/etc/alertmanager/secrets/pagerduty-service-key"
        severity: '{{ .CommonLabels.severity }}'
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        details:
          firing: '{{ .Alerts.Firing | len }}'
          resolved: '{{ .Alerts.Resolved | len }}'
          namespace: '{{ .CommonLabels.namespace }}'
          service: '{{ .CommonLabels.service }}'
          runbook: '{{ .CommonAnnotations.runbook_url }}'

  - name: "slack-incidents"
    slack_configs:
      - channel: "#incidents"
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        title: ':rotating_light: {{ .GroupLabels.alertname }} [{{ .Status | toUpper }}]'
        text: >-
          *Severity:* `{{ .CommonLabels.severity }}`
          *Namespace:* `{{ .CommonLabels.namespace }}`
          *Service:* `{{ .CommonLabels.service }}`
          *Runbook:* {{ .CommonAnnotations.runbook_url }}
          {{ range .Alerts }}
          ---
          {{ .Annotations.description }}
          {{ end }}
        actions:
          - type: button
            text: "Runbook"
            url: '{{ .CommonAnnotations.runbook_url }}'
          - type: button
            text: "Dashboard"
            url: "https://grafana.internal/d/prod-service-overview"

  - name: "slack-warnings"
    slack_configs:
      - channel: "#alerts"
        send_resolved: true
        title: '{{ .GroupLabels.alertname }} [{{ .Status | toUpper }}]'
        text: >-
          {{ range .Alerts }}
          - {{ .Annotations.summary }}
          {{ end }}

  - name: "slack-infrastructure"
    slack_configs:
      - channel: "#infra-alerts"
        send_resolved: true
        title: '{{ .GroupLabels.alertname }} on {{ .GroupLabels.instance }}'
        text: >-
          {{ range .Alerts }}
          - {{ .Annotations.description }}
          {{ end }}

  - name: "slack-platform"
    slack_configs:
      - channel: "#platform-alerts"
        send_resolved: true
        title: '{{ .GroupLabels.alertname }} [{{ .CommonLabels.namespace }}]'
        text: >-
          {{ range .Alerts }}
          - {{ .Annotations.description }}
          {{ end }}

# -------------------------------------------------------
# Inhibition rules - suppress noise during known incidents
# -------------------------------------------------------
inhibit_rules:
  # If a critical alert fires, suppress warnings for the same alert + namespace
  - source_matchers:
      - severity = critical
    target_matchers:
      - severity = warning
    equal: ["alertname", "namespace"]

  # If a node is not ready, suppress pod-level alerts on that node
  - source_matchers:
      - alertname = NodeNotReady
    target_matchers:
      - severity =~ "warning|critical"
    equal: ["node"]

  # If the cluster is down, suppress all service alerts
  - source_matchers:
      - alertname = ClusterDown
    target_matchers:
      - severity =~ "warning|critical"
```

---

## 7. SLO / SLI Definitions

Templates for defining Service Level Objectives, Indicators, and error budget
tracking. These can be implemented with tools like Sloth, Pyrra, or custom
Prometheus recording rules.

### 7.1 SLO Specification Template

| Field               | Example Value                               | Description                          |
|---------------------|---------------------------------------------|--------------------------------------|
| Service             | api-gateway                                 | Name of the service                  |
| SLO Name            | availability                                | Identifier for this SLO              |
| SLI Type            | availability                                | availability, latency, throughput    |
| Target              | 99.9%                                       | SLO target percentage                |
| Window              | 30 days (rolling)                           | Evaluation window                    |
| Error Budget        | 0.1% = 43.2 min/month                      | Allowed downtime                     |
| Owner               | platform-team                               | Responsible team                     |
| Alert Burn Rate 1x  | Page if 1h burn > 14.4x budget rate         | Fast-burn alert threshold            |
| Alert Burn Rate 5x  | Ticket if 6h burn > 6x budget rate          | Slow-burn alert threshold            |

### 7.2 SLO Recording Rules (Prometheus)

```yaml
# slo-recording-rules.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-api-gateway
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: slo.api-gateway.availability
      rules:
        # ---- Total requests (good + bad) ----
        - record: slo:http_requests:total_rate5m
          expr: |
            sum(rate(http_requests_total{service="api-gateway"}[5m]))

        # ---- Good requests (non-5xx) ----
        - record: slo:http_requests:good_rate5m
          expr: |
            sum(rate(http_requests_total{service="api-gateway",status!~"5.."}[5m]))

        # ---- Error ratio (1 - availability) ----
        - record: slo:http_requests:error_ratio5m
          expr: |
            1 - (slo:http_requests:good_rate5m / slo:http_requests:total_rate5m)

        # ---- Error budget remaining (30-day rolling window) ----
        - record: slo:http_requests:error_budget_remaining
          expr: |
            1 - (
              sum_over_time(slo:http_requests:error_ratio5m[30d])
              / (30 * 24 * 12)
            ) / 0.001

    - name: slo.api-gateway.latency
      rules:
        # ---- Requests within latency threshold (< 500ms) ----
        - record: slo:http_latency:good_rate5m
          expr: |
            sum(rate(http_request_duration_seconds_bucket{
              service="api-gateway",
              le="0.5"
            }[5m]))

        # ---- Latency SLI ratio ----
        - record: slo:http_latency:ratio5m
          expr: |
            slo:http_latency:good_rate5m / slo:http_requests:total_rate5m
```

### 7.3 Multi-Window Burn Rate Alerts

These alerts implement Google's multi-window, multi-burn-rate approach for
SLO-based alerting. They detect both fast burns (recent spike) and slow burns
(sustained degradation).

```yaml
# slo-burn-rate-alerts.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-burn-rate-alerts
  namespace: monitoring
spec:
  groups:
    - name: slo.burn-rate.api-gateway
      rules:
        # ---- Fast burn: 1h window, 14.4x budget consumption ----
        # Pages on-call within minutes of a serious incident
        - alert: SLOHighBurnRate_ApiGateway
          expr: |
            (
              sum(rate(http_requests_total{service="api-gateway",status=~"5.."}[1h]))
              / sum(rate(http_requests_total{service="api-gateway"}[1h]))
            ) > (14.4 * 0.001)
            and
            (
              sum(rate(http_requests_total{service="api-gateway",status=~"5.."}[5m]))
              / sum(rate(http_requests_total{service="api-gateway"}[5m]))
            ) > (14.4 * 0.001)
          for: 2m
          labels:
            severity: critical
            slo: "api-gateway-availability"
            window: "1h"
          annotations:
            summary: "API Gateway SLO fast burn rate exceeded"
            description: >-
              API Gateway is burning through its error budget at 14.4x the
              acceptable rate. At this rate the entire monthly budget will be
              consumed in approximately 2 hours.

        # ---- Slow burn: 6h window, 6x budget consumption ----
        # Creates a ticket for investigation
        - alert: SLOSlowBurnRate_ApiGateway
          expr: |
            (
              sum(rate(http_requests_total{service="api-gateway",status=~"5.."}[6h]))
              / sum(rate(http_requests_total{service="api-gateway"}[6h]))
            ) > (6 * 0.001)
            and
            (
              sum(rate(http_requests_total{service="api-gateway",status=~"5.."}[30m]))
              / sum(rate(http_requests_total{service="api-gateway"}[30m]))
            ) > (6 * 0.001)
          for: 15m
          labels:
            severity: warning
            slo: "api-gateway-availability"
            window: "6h"
          annotations:
            summary: "API Gateway SLO slow burn rate exceeded"
            description: >-
              API Gateway is burning through its error budget at 6x the
              acceptable rate over a 6-hour window. Investigation recommended.
```

### 7.4 Error Budget Policy

Define what actions to take at different error budget consumption levels.

| Budget Remaining | Status   | Action                                              |
|------------------|----------|-----------------------------------------------------|
| > 50%            | Healthy  | Normal development velocity, deploy as usual        |
| 25% - 50%        | Caution  | Reduce risky deployments, increase review scrutiny  |
| 10% - 25%        | At Risk  | Freeze feature deployments, focus on reliability    |
| 0% - 10%         | Depleted | Full deployment freeze, all hands on reliability    |
| < 0%             | Violated | Post-incident review required, exec escalation      |

---

## Quick Reference: Metric Naming Conventions

Follow Prometheus naming best practices for consistency across teams.

| Pattern                                      | Example                                | Usage                  |
|----------------------------------------------|----------------------------------------|------------------------|
| `<namespace>_<name>_total`                   | `http_requests_total`                  | Counter                |
| `<namespace>_<name>_seconds`                 | `http_request_duration_seconds`        | Histogram / Summary    |
| `<namespace>_<name>_bytes`                   | `node_memory_MemAvailable_bytes`       | Gauge (bytes)          |
| `<namespace>_<name>_info`                    | `node_uname_info`                      | Info metric (labels)   |
| `<namespace>_<name>_ratio`                   | `slo:http_requests:error_ratio5m`      | Computed ratio (0-1)   |

---

## Quick Reference: Common Labels

Standardize labels across all services for consistent querying and dashboarding.

| Label        | Description                        | Example Values                    |
|--------------|------------------------------------|-----------------------------------|
| `namespace`  | Kubernetes namespace               | production, staging               |
| `service`    | Service / application name         | api-gateway, user-service         |
| `pod`        | Pod name                           | api-gateway-7f8b9c-x2k4l         |
| `node`       | Kubernetes node                    | ip-10-0-1-42                      |
| `instance`   | Scrape target (host:port)          | 10.0.1.42:9100                    |
| `cluster`    | Cluster identifier                 | prod-us-east-1                    |
| `team`       | Owning team                        | platform, infrastructure          |
| `severity`   | Alert severity                     | critical, warning, info           |
