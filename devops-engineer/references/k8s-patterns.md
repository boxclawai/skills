# Kubernetes Patterns Reference

## Table of Contents

1. [Production Deployment Template](#production-deployment-template)
2. [Horizontal Pod Autoscaler](#horizontal-pod-autoscaler)
3. [ConfigMap and Secrets Management](#configmap-and-secrets-management)
4. [Ingress with TLS](#ingress-with-tls)
5. [Network Policies](#network-policies)
6. [CronJob Pattern](#cronjob-pattern)
7. [Helm Chart Structure](#helm-chart-structure)
8. [Troubleshooting Runbook](#troubleshooting-runbook)

---

## Production Deployment Template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: myapp
    app.kubernetes.io/version: "1.5.0"
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime
  selector:
    matchLabels:
      app.kubernetes.io/name: api
  template:
    metadata:
      labels:
        app.kubernetes.io/name: api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "3000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: api
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      # Anti-affinity: spread across nodes
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: api
                topologyKey: kubernetes.io/hostname

      # Topology spread: balance across zones
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: api

      containers:
        - name: api
          image: ghcr.io/myorg/api:1.5.0  # Always pin versions
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3000
              protocol: TCP

          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 512Mi

          env:
            - name: NODE_ENV
              value: production
            - name: PORT
              value: "3000"
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: host
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name

          # Readiness: traffic routing control
          readinessProbe:
            httpGet:
              path: /health/ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3

          # Liveness: restart on deadlock
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            failureThreshold: 3

          # Startup: slow boot tolerance
          startupProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30  # 5s * 30 = 150s max startup

          # Graceful shutdown
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 10"]

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]

          volumeMounts:
            - name: tmp
              mountPath: /tmp

      volumes:
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: production
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
  selector:
    app.kubernetes.io/name: api
```

---

## Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 20
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60     # Wait 60s before scaling up again
      policies:
        - type: Pods
          value: 4                        # Add max 4 pods per 60s
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300    # Wait 5min before scaling down
      policies:
        - type: Percent
          value: 25                      # Remove max 25% per 5min
          periodSeconds: 300
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    # Custom metric: requests per second
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"
```

---

## ConfigMap and Secrets Management

```yaml
# ConfigMap: application configuration (non-sensitive data)
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: production
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/component: config
data:
  # Simple key-value pairs
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  CACHE_TTL: "300"
  CORS_ORIGINS: "https://app.example.com,https://admin.example.com"

  # Embedded config file
  nginx.conf: |
    worker_processes auto;
    events {
      worker_connections 1024;
    }
    http {
      server {
        listen 80;
        location /health {
          return 200 'ok';
        }
      }
    }
---
# Secret: sensitive data (base64-encoded at rest, use sealed-secrets or
# external-secrets-operator in production)
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: production
  labels:
    app.kubernetes.io/name: api
type: Opaque
stringData:                          # stringData avoids manual base64 encoding
  host: "db.internal.example.com"
  port: "5432"
  username: "api_service"
  password: "REPLACE_VIA_CI_PIPELINE"  # Never commit real secrets to Git
  connection-string: "postgresql://api_service:REPLACE@db.internal.example.com:5432/appdb?sslmode=require"
---
# ExternalSecret: pull secrets from AWS Secrets Manager / Vault / GCP SM
# Requires external-secrets-operator installed in cluster
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials-external
  namespace: production
spec:
  refreshInterval: 1h               # Poll interval for secret rotation
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials             # K8s Secret to create/update
    creationPolicy: Owner
  data:
    - secretKey: host
      remoteRef:
        key: production/api/database
        property: host
    - secretKey: password
      remoteRef:
        key: production/api/database
        property: password
```

**Best Practices:**
- Never commit plaintext secrets to version control; use SealedSecrets, SOPS, or ExternalSecrets.
- Set `immutable: true` on ConfigMaps/Secrets that do not change to improve cluster performance.
- Use `stringData` instead of `data` in Secret manifests to avoid manual base64 encoding errors.
- Mount secrets as volumes (not env vars) when the application supports file-based config, enabling live rotation without pod restart.
- Enable encryption at rest for etcd (`EncryptionConfiguration`) to protect Secret data on disk.
- Restrict Secret access with RBAC: grant `get` only on specific Secret names, never wildcard.
- Use `envFrom` with a `configMapRef` to inject all ConfigMap keys as env vars without listing each individually.
- Rotate secrets on a schedule; pair ExternalSecrets `refreshInterval` with your secret manager's rotation policy.

---

## Ingress with TLS

```yaml
# cert-manager ClusterIssuer for automated Let's Encrypt TLS certificates
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: platform-team@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
---
# Ingress resource with TLS termination, rate limiting, and security headers
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: production
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/component: ingress
  annotations:
    # TLS via cert-manager
    cert-manager.io/cluster-issuer: letsencrypt-prod

    # NGINX-specific settings
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"

    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "50"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"

    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
      more_set_headers "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload";

    # CORS (if API serves browser clients directly)
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://app.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - api.example.com
        - admin.example.com
      secretName: api-example-com-tls    # cert-manager creates this automatically
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
    - host: admin.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-dashboard
                port:
                  number: 80
```

**Best Practices:**
- Always enforce HTTPS redirection; never serve production traffic over plain HTTP.
- Use cert-manager with Let's Encrypt for automated certificate issuance and renewal (certificates renew 30 days before expiry).
- Set `proxy-body-size` to match your application's maximum expected request payload; avoid unlimited.
- Apply rate limiting at the Ingress layer as the first line of defense against abuse.
- Add HSTS headers with a long `max-age` and `preload` for browsers to enforce HTTPS.
- Use separate Ingress resources per team or domain to limit blast radius of misconfigurations.
- Monitor certificate expiry with Prometheus alerts (`certmanager_certificate_expiration_timestamp_seconds`).
- For multi-cluster setups, consider using DNS-based GSLB instead of a single Ingress endpoint.

---

## Network Policies

```yaml
# Default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
---
# Allow API to receive traffic from ingress controller only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: 3000
          protocol: TCP
---
# Allow API to connect to database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-to-database
  namespace: production
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: api
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: postgres
      ports:
        - port: 5432
          protocol: TCP
    # Allow DNS resolution
    - to: []
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

---

## CronJob Pattern

```yaml
# CronJob: scheduled database backup with retry and concurrency control
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: production
  labels:
    app.kubernetes.io/name: db-backup
    app.kubernetes.io/component: maintenance
spec:
  schedule: "0 2 * * *"                    # Daily at 02:00 UTC
  timeZone: "Etc/UTC"                      # Explicit timezone (K8s 1.27+)
  concurrencyPolicy: Forbid               # Never run overlapping jobs
  successfulJobsHistoryLimit: 7            # Keep last 7 successful runs
  failedJobsHistoryLimit: 5               # Keep last 5 failed runs
  startingDeadlineSeconds: 300             # Skip if not started within 5min of schedule
  suspend: false                           # Set true to pause without deleting
  jobTemplate:
    spec:
      backoffLimit: 3                      # Retry failed pods up to 3 times
      activeDeadlineSeconds: 3600          # Kill job after 1 hour max
      ttlSecondsAfterFinished: 86400       # Clean up completed Job after 24h
      template:
        metadata:
          labels:
            app.kubernetes.io/name: db-backup
          annotations:
            sidecar.istio.io/inject: "false"   # Disable service mesh for batch jobs
        spec:
          restartPolicy: OnFailure             # Required for CronJob (Never or OnFailure)
          serviceAccountName: db-backup
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: backup
              image: ghcr.io/myorg/db-backup:2.1.0
              imagePullPolicy: IfNotPresent
              command:
                - /bin/sh
                - -c
                - |
                  set -euo pipefail
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  FILENAME="backup-${TIMESTAMP}.sql.gz"
                  echo "Starting backup: ${FILENAME}"
                  pg_dump -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
                    --no-owner --no-acl | gzip > "/tmp/${FILENAME}"
                  aws s3 cp "/tmp/${FILENAME}" \
                    "s3://${BACKUP_BUCKET}/postgres/${FILENAME}" \
                    --storage-class STANDARD_IA
                  echo "Backup uploaded successfully: ${FILENAME}"
              env:
                - name: DB_HOST
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: host
                - name: DB_USER
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: username
                - name: DB_NAME
                  value: "appdb"
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: password
                - name: BACKUP_BUCKET
                  value: "myorg-prod-backups"
              resources:
                requests:
                  cpu: 500m
                  memory: 512Mi
                limits:
                  cpu: "1"
                  memory: 1Gi
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: [ALL]
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: tmp
              emptyDir:
                sizeLimit: 5Gi
```

**Best Practices:**
- Always set `concurrencyPolicy: Forbid` for data-sensitive jobs (backups, migrations) to prevent data corruption from parallel runs.
- Use `activeDeadlineSeconds` as a hard timeout to prevent runaway jobs from consuming resources indefinitely.
- Set `startingDeadlineSeconds` so missed schedules (e.g., during cluster maintenance) are skipped rather than queued and fired in bulk.
- Use `ttlSecondsAfterFinished` to automatically clean up completed Job objects and avoid etcd bloat.
- Disable service mesh sidecars (`sidecar.istio.io/inject: "false"`) for batch jobs; sidecars prevent pod completion.
- Always use `set -euo pipefail` in shell scripts to fail fast on errors instead of silently continuing.
- Monitor CronJob failures with alerts on `kube_job_status_failed` Prometheus metric.
- Use `restartPolicy: OnFailure` for transient error recovery; use `Never` if your script handles retries internally.

---

## Helm Chart Structure

```
mychart/
├── Chart.yaml              # Chart metadata and dependencies
├── Chart.lock              # Locked dependency versions
├── values.yaml             # Default configuration values
├── values-production.yaml  # Production overrides (do not commit secrets)
├── templates/
│   ├── _helpers.tpl        # Reusable named templates
│   ├── deployment.yaml     # Deployment manifest
│   ├── service.yaml        # Service manifest
│   ├── ingress.yaml        # Ingress manifest
│   ├── hpa.yaml            # HorizontalPodAutoscaler
│   ├── configmap.yaml      # ConfigMap manifest
│   ├── secret.yaml         # Secret manifest (use external-secrets in prod)
│   ├── networkpolicy.yaml  # Network policy
│   ├── serviceaccount.yaml # ServiceAccount with IRSA/Workload Identity
│   ├── pdb.yaml            # PodDisruptionBudget
│   └── NOTES.txt           # Post-install usage instructions
└── tests/
    └── test-connection.yaml  # Helm test for connectivity validation
```

```yaml
# Chart.yaml
apiVersion: v2
name: api
description: Production API service Helm chart
type: application
version: 1.2.0           # Chart version (bump on chart changes)
appVersion: "1.5.0"      # Application version (matches container tag)
maintainers:
  - name: Platform Team
    email: platform-team@example.com
dependencies:
  - name: redis
    version: "18.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

```yaml
# values.yaml (defaults -- overridden per environment)
replicaCount: 2

image:
  repository: ghcr.io/myorg/api
  tag: ""                           # Overridden by --set image.tag=<version>
  pullPolicy: IfNotPresent

serviceAccount:
  create: true
  annotations: {}                   # Add IRSA/Workload Identity annotations here

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  targetCPUUtilization: 70

ingress:
  enabled: true
  className: nginx
  host: api.example.com
  tls: true
  clusterIssuer: letsencrypt-prod

redis:
  enabled: false                    # Toggle subchart dependency
```

```yaml
# templates/_helpers.tpl
{{- define "api.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "api.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

**Best Practices:**
- Always separate `Chart.version` (chart packaging) from `appVersion` (application release); bump independently.
- Use `--set image.tag` in CI/CD pipelines rather than hardcoding tags in `values.yaml`.
- Lint and validate charts before merge: `helm lint`, `helm template | kubeval`, `helm test`.
- Use `values-<env>.yaml` files for environment-specific overrides; never store secrets in values files.
- Define a `PodDisruptionBudget` in every chart to protect availability during node drains and cluster upgrades.
- Use named templates in `_helpers.tpl` for labels, names, and selectors to ensure consistency across all resources.
- Pin dependency versions with `Chart.lock` and run `helm dependency update` in CI to catch upstream breaking changes.
- Include `NOTES.txt` with post-install instructions so operators know how to verify and access the deployed service.

---

## Troubleshooting Runbook

```bash
# === Pod not starting ===
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container logs
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Common causes:
# - ImagePullBackOff: wrong image name/tag, registry auth
# - CrashLoopBackOff: app crashes on startup, check logs
# - Pending: insufficient resources, check node capacity
# - OOMKilled: increase memory limits

# === High latency ===
kubectl top pods -n <namespace>                    # Resource usage
kubectl get hpa -n <namespace>                     # Check if scaling
kubectl describe hpa <name> -n <namespace>         # Scaling events

# === Network issues ===
kubectl exec -it <pod> -- nslookup <service-name>  # DNS check
kubectl exec -it <pod> -- curl -v <service-url>    # Connectivity
kubectl get networkpolicy -n <namespace>           # Network policies

# === Rolling back ===
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout undo deployment/<name> -n <namespace>
kubectl rollout history deployment/<name> -n <namespace>

# === Resource pressure ===
kubectl top nodes
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```
