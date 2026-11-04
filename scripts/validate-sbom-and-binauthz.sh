#!/usr/bin/env bash
# Deterministic grader for SBOM export & Cloud Run prod Binary Authorization enforcement
# Covers Rule 8 in google-cicd-deploy/SKILL.md and google-cicd-release-orchestration/SKILL.md

set -u

MODE="${1:-dev}" # dev (SBOM only, no binauthz block) or prod (SBOM + binauthz=default)
CLOUD_RUN_SERVICE="${2:-}"
ARTIFACT_REGISTRY_URI="${3:-${ARTIFACT_REGISTRY:-}}"
PROJECT_ID="${PROJECT_ID:-${PROJECT_NAME:-}}"
REGION="${REGION:-us-central1}"

CHECK_SBOM="false"
MSG_SBOM="Not checked"
CHECK_BINAUTHZ="false"
MSG_BINAUTHZ="Not checked"

if [ -n "$PROJECT_ID" ] && [ -n "$CLOUD_RUN_SERVICE" ]; then
  SVC_JSON=$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format=json \
    --quiet 2>/dev/null || true)

  IMAGE_URI=$(echo "$SVC_JSON" | jq -r '.spec.template.spec.containers[0].image // empty' 2>/dev/null || true)

  if [ -n "$IMAGE_URI" ]; then
    DIGEST_URI=$(gcloud artifacts docker images describe "$IMAGE_URI" \
      --project="$PROJECT_ID" \
      --format="value(image_summary.fully_qualified_digest)" \
      --quiet 2>/dev/null || echo "$IMAGE_URI")

    SBOM_OUT=$(gcloud artifacts sbom list \
      --resource="$DIGEST_URI" \
      --project="$PROJECT_ID" \
      --format=json \
      --quiet 2>/dev/null || true)

    if [ -n "$SBOM_OUT" ] && [ "$SBOM_OUT" != "[]" ]; then
      CHECK_SBOM="true"
      MSG_SBOM="SPDX SBOM verified for $DIGEST_URI"
    else
      MSG_SBOM="No exported SPDX SBOM found for $DIGEST_URI"
    fi
  else
    MSG_SBOM="Could not resolve deployed container image from Cloud Run service '$CLOUD_RUN_SERVICE'"
  fi

  BINAUTHZ_POLICY=$(echo "$SVC_JSON" | jq -r '.metadata.annotations["run.googleapis.com/binary-authorization"] // empty' 2>/dev/null || true)
  if [ "$MODE" = "prod" ]; then
    if [ -n "$BINAUTHZ_POLICY" ]; then
      CHECK_BINAUTHZ="true"
      MSG_BINAUTHZ="Cloud Run prod service has Binary Authorization enabled ($BINAUTHZ_POLICY)"
    else
      MSG_BINAUTHZ="Cloud Run prod service is missing --binary-authorization=default"
    fi
  else
    if [ -z "$BINAUTHZ_POLICY" ]; then
      CHECK_BINAUTHZ="true"
      MSG_BINAUTHZ="Cloud Run dev service deployed without blocking Binary Authorization gate"
    else
      MSG_BINAUTHZ="Cloud Run dev service unexpectedly set binary-authorization=$BINAUTHZ_POLICY"
    fi
  fi
fi

TOTAL_CHECKS=2
PASSED_CHECKS=0
[ "$CHECK_SBOM" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))
[ "$CHECK_BINAUTHZ" = "true" ] && PASSED_CHECKS=$((PASSED_CHECKS + 1))

SCORE=$(awk "BEGIN {printf \"%.2f\", $PASSED_CHECKS / $TOTAL_CHECKS}")

cat <<EOF
{
  "score": $SCORE,
  "details": "$PASSED_CHECKS/$TOTAL_CHECKS SBOM & Binary Authorization checks passed",
  "checks": [
    {"name": "sbom-exported", "passed": $CHECK_SBOM, "message": "$MSG_SBOM"},
    {"name": "binary-authorization-mode", "passed": $CHECK_BINAUTHZ, "message": "$MSG_BINAUTHZ"}
  ]
}
EOF
