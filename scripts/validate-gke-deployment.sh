#!/usr/bin/env bash
# Deterministic grader for GKE deployment (Prompt #1 Scenario #2)
# Validates Kubernetes manifests, Artifact Registry image usage, and live GKE deployment status.

set -u

CLUSTER_NAME="${1:-}"
NAMESPACE="${2:-dev}"
WORKSPACE_DIR="${3:-.}"
PROJECT_ID="${PROJECT_ID:-${PROJECT_NAME:-}}"
REGION="${REGION:-us-central1}"

CHECK_MANIFESTS="false"
MSG_MANIFESTS="Kubernetes Deployment/Service manifests not found"
CHECK_AR_IMAGE="false"
MSG_AR_IMAGE="Artifact Registry image URI not referenced in manifests"
CHECK_CLUSTER_DEPLOY="false"
MSG_CLUSTER_DEPLOY="Workload not found in GKE cluster"

if grep -rnq "kind: Deployment" "$WORKSPACE_DIR" 2>/dev/null && \
   grep -rnq "kind: Service" "$WORKSPACE_DIR" 2>/dev/null; then
  CHECK_MANIFESTS="true"
  MSG_MANIFESTS="Kubernetes Deployment and Service manifests exist"
fi

if grep -rnqE "docker\.pkg\.dev/" "$WORKSPACE_DIR" 2>/dev/null; then
  CHECK_AR_IMAGE="true"
  MSG_AR_IMAGE="Manifests reference Artifact Registry image URI"
fi

if [ -n "$CLUSTER_NAME" ] && [ -n "$PROJECT_ID" ]; then
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1 || true

  DEPLOY_COUNT=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | awk '{print $1}')
  if [ "${DEPLOY_COUNT:-0}" -gt 0 ]; then
    CHECK_CLUSTER_DEPLOY="true"
    MSG_CLUSTER_DEPLOY="Found $DEPLOY_COUNT Deployment(s) in GKE cluster '$CLUSTER_NAME' (namespace '$NAMESPACE')"
  fi
fi

TOTAL_CHECKS=3
PASSED_CHECKS=0
[ "$CHECK_MANIFESTS" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))
[ "$CHECK_AR_IMAGE" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))
[ "$CHECK_CLUSTER_DEPLOY" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))

SCORE=$(awk "BEGIN {printf \"%.2f\", $PASSED_CHECKS / $TOTAL_CHECKS}")

cat <<EOF
{
  "score": $SCORE,
  "details": "$PASSED_CHECKS/$TOTAL_CHECKS GKE deployment checks passed",
  "checks": [
    {"name": "k8s-manifests-generated", "passed": $CHECK_MANIFESTS, "message": "$MSG_MANIFESTS"},
    {"name": "artifact-registry-image-used", "passed": $CHECK_AR_IMAGE, "message": "$MSG_AR_IMAGE"},
    {"name": "gke-cluster-deployment-active", "passed": $CHECK_CLUSTER_DEPLOY, "message": "$MSG_CLUSTER_DEPLOY"}
  ]
}
EOF
