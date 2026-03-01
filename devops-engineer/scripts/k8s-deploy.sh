#!/usr/bin/env bash
# k8s-deploy.sh - Safe Kubernetes deployment with rollback
# Usage: ./k8s-deploy.sh <namespace> <deployment> <image:tag> [--timeout 300]
#
# Features:
#   - Pre-deployment health check
#   - Rolling deployment with progress monitoring
#   - Automatic rollback on failure
#   - Post-deployment verification

set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace> <deployment> <image:tag> [--timeout 300]}"
DEPLOYMENT="${2:?Usage: $0 <namespace> <deployment> <image:tag> [--timeout 300]}"
IMAGE="${3:?Usage: $0 <namespace> <deployment> <image:tag> [--timeout 300]}"
TIMEOUT=300

shift 3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "======================================"
echo "  Kubernetes Deployment"
echo "======================================"
echo "  Namespace:  $NAMESPACE"
echo "  Deployment: $DEPLOYMENT"
echo "  Image:      $IMAGE"
echo "  Timeout:    ${TIMEOUT}s"
echo "======================================"
echo ""

# Pre-checks
echo "=== Pre-deployment Checks ==="

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "ERROR: Namespace '$NAMESPACE' does not exist"
  exit 1
fi

# Verify deployment exists
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &>/dev/null; then
  echo "ERROR: Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
  exit 1
fi

# Get current state
CURRENT_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
echo "Current image:    $CURRENT_IMAGE"
echo "Current replicas: $CURRENT_REPLICAS"
echo ""

if [[ "$CURRENT_IMAGE" == "$IMAGE" ]]; then
  echo "WARNING: Image is already deployed. Restarting rollout..."
  kubectl rollout restart deployment "$DEPLOYMENT" -n "$NAMESPACE"
else
  echo "=== Deploying ==="
  kubectl set image deployment/"$DEPLOYMENT" \
    "$DEPLOYMENT=$IMAGE" \
    -n "$NAMESPACE" \
    --record
fi

echo "Waiting for rollout to complete (timeout: ${TIMEOUT}s)..."
echo ""

if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
  echo ""
  echo "=== Deployment Successful ==="

  # Post-deployment verification
  echo ""
  echo "--- Pod Status ---"
  kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$DEPLOYMENT" \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'

  echo ""
  echo "--- Ready Replicas ---"
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o custom-columns='DESIRED:.spec.replicas,READY:.status.readyReplicas,UPDATED:.status.updatedReplicas,AVAILABLE:.status.availableReplicas'

  # Check for recent restarts (might indicate issues)
  RESTARTS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$DEPLOYMENT" \
    -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | tr ' ' '\n' | awk '{s+=$1} END {print s}')

  if [[ "${RESTARTS:-0}" -gt 0 ]]; then
    echo ""
    echo "WARNING: $RESTARTS total container restarts detected. Monitor closely."
  fi

  echo ""
  echo "Deployment completed successfully."
else
  echo ""
  echo "=== Deployment FAILED - Rolling Back ==="
  echo ""

  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s

  echo ""
  echo "--- Recent Events ---"
  kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' \
    --field-selector "involvedObject.name=$DEPLOYMENT" | tail -10

  echo ""
  echo "--- Failed Pod Logs ---"
  FAILED_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$DEPLOYMENT" \
    --sort-by='.metadata.creationTimestamp' -o jsonpath='{.items[-1].metadata.name}')
  if [[ -n "$FAILED_POD" ]]; then
    kubectl logs "$FAILED_POD" -n "$NAMESPACE" --tail=50 --previous 2>/dev/null || \
    kubectl logs "$FAILED_POD" -n "$NAMESPACE" --tail=50 2>/dev/null || true
  fi

  echo ""
  echo "Rollback completed. Previous image: $CURRENT_IMAGE"
  exit 1
fi
