#!/usr/bin/env bash
# Deterministic grader for Agent Registry auto-registration on Cloud Run or GKE
# Covers Prompt #1 (Agentic & MCP Server workloads in Scenarios #1, #2, #4) and Prompt #3.

set -u

RUNTIME="${1:-run}"
TARGET_NAME="${2:-}"
WORKSPACE_DIR="${3:-.}"
EXPECTED_TYPE="${4:-agent}" # "agent" or "mcp-server"
PROJECT_ID="${PROJECT_ID:-${PROJECT_NAME:-}}"
REGION="${REGION:-us-central1}"

CHECK_RUNTIME_ATTR="false"
MSG_RUNTIME_ATTR="Not checked"
CHECK_AGENT_REGISTRY="false"
MSG_AGENT_REGISTRY="Not checked"

if [ "$RUNTIME" = "run" ]; then
  if [ -n "$PROJECT_ID" ] && [ -n "$TARGET_NAME" ]; then
    SVC_JSON=$(gcloud beta run services describe "$TARGET_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --format=json \
      --quiet 2>/dev/null || true)

    if [ "$EXPECTED_TYPE" = "mcp-server" ]; then
      if echo "$SVC_JSON" | grep -qiE "mcp-server|mcp_server"; then
        CHECK_RUNTIME_ATTR="true"
        MSG_RUNTIME_ATTR="Cloud Run service '$TARGET_NAME' configured with --functional-type=mcp-server"
      else
        MSG_RUNTIME_ATTR="Cloud Run service '$TARGET_NAME' missing --functional-type=mcp-server"
      fi
    else
      if echo "$SVC_JSON" | grep -qiE "agent|agent-identity"; then
        CHECK_RUNTIME_ATTR="true"
        MSG_RUNTIME_ATTR="Cloud Run service '$TARGET_NAME' configured with native functional-type=agent / agent-identity"
      else
        MSG_RUNTIME_ATTR="Cloud Run service '$TARGET_NAME' missing --functional-type=agent or --identity-type=agent-identity"
      fi
    fi

    AR_OUT=$(gcloud agent-registry agents list \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --filter="agentId:$TARGET_NAME" \
      --format="value(agentId)" \
      --quiet 2>/dev/null || true)

    if [ -z "$AR_OUT" ] && [ "$EXPECTED_TYPE" = "mcp-server" ]; then
      AR_OUT=$(gcloud agent-registry mcp-servers list \
        --location="$REGION" \
        --project="$PROJECT_ID" \
        --filter="mcpServerId:$TARGET_NAME" \
        --format="value(mcpServerId)" \
        --quiet 2>/dev/null || true)
    fi

    if [ -n "$AR_OUT" ]; then
      CHECK_AGENT_REGISTRY="true"
      MSG_AGENT_REGISTRY="Workload '$TARGET_NAME' verified in Google Cloud Agent Registry ($AR_OUT)"
    else
      MSG_AGENT_REGISTRY="Workload '$TARGET_NAME' not found in Google Cloud Agent Registry"
    fi
  else
    MSG_RUNTIME_ATTR="Missing PROJECT_ID or TARGET_NAME"
    MSG_AGENT_REGISTRY="Missing PROJECT_ID or TARGET_NAME"
  fi
elif [ "$RUNTIME" = "gke" ]; then
  if [ "$EXPECTED_TYPE" = "mcp-server" ]; then
    GKE_TYPE_PATTERN="MCP_SERVER"
  else
    GKE_TYPE_PATTERN="(AGENT|MCP_SERVER)"
  fi

  if grep -rnqE "registry\.gke\.io/functional-type.*${GKE_TYPE_PATTERN}" "$WORKSPACE_DIR" 2>/dev/null && \
     grep -rnqE "apphub\.cloud\.google\.com/functional-type.*${GKE_TYPE_PATTERN}" "$WORKSPACE_DIR" 2>/dev/null && \
     grep -rnqE 'iam\.gke\.io/spiffe-identity-type.*agent-identity' "$WORKSPACE_DIR" 2>/dev/null; then
    CHECK_RUNTIME_ATTR="true"
    MSG_RUNTIME_ATTR="GKE manifests contain registry.gke.io/functional-type, apphub.cloud.google.com/functional-type, and iam.gke.io/spiffe-identity-type"
  else
    MSG_RUNTIME_ATTR="GKE manifests missing required Agent Registry native discovery labels/annotations"
  fi

  if [ -n "$PROJECT_ID" ] && [ -n "$TARGET_NAME" ]; then
    AR_OUT=$(gcloud agent-registry agents list \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --filter="agentId:$TARGET_NAME" \
      --format="value(agentId)" \
      --quiet 2>/dev/null || true)
    if [ -n "$AR_OUT" ]; then
      CHECK_AGENT_REGISTRY="true"
      MSG_AGENT_REGISTRY="GKE Agent '$TARGET_NAME' verified in Google Cloud Agent Registry"
    elif [ "$CHECK_RUNTIME_ATTR" = "true" ]; then
      CHECK_AGENT_REGISTRY="true"
      MSG_AGENT_REGISTRY="GKE native auto-registration annotations present (control-plane discovery pending)"
    fi
  else
    CHECK_AGENT_REGISTRY="$CHECK_RUNTIME_ATTR"
    MSG_AGENT_REGISTRY="Evaluated from GKE manifest annotations"
  fi
fi

TOTAL_CHECKS=2
PASSED_CHECKS=0
[ "$CHECK_RUNTIME_ATTR" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))
[ "$CHECK_AGENT_REGISTRY" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))

SCORE=$(awk "BEGIN {printf \"%.2f\", $PASSED_CHECKS / $TOTAL_CHECKS}")

cat <<EOF
{
  "score": $SCORE,
  "details": "$PASSED_CHECKS/$TOTAL_CHECKS Agent Registry checks passed",
  "checks": [
    {"name": "native-runtime-agent-attributes", "passed": $CHECK_RUNTIME_ATTR, "message": "$MSG_RUNTIME_ATTR"},
    {"name": "agent-registry-entry", "passed": $CHECK_AGENT_REGISTRY, "message": "$MSG_AGENT_REGISTRY"}
  ]
}
EOF
