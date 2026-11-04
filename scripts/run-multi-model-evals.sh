#!/usr/bin/env bash
# Run the CI/CD evaluation suite across Gemini, OpenAI (Codex), and Anthropic Claude models.
# Works out-of-the-box on Cloudtop (gLinux) and macOS.
#
# Usage:
#   ./scripts/run-multi-model-evals.sh [--models gemini,claude,codex] [--provider docker|local] [--config eval.criteria.yaml] [--eval <task-name>]

set -euo pipefail

MODELS="gemini,claude,codex"
PROVIDER="docker"
CONFIG_FILE="eval.criteria.yaml"
EVAL_TASK=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models)
      MODELS="$2"
      shift 2
      ;;
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --eval)
      EVAL_TASK="$2"
      shift 2
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# Pre-flight Check 1: Verify ADC credentials file exists (required for Docker bind-mount on Cloudtop)
ADC_FILE="${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/application_default_credentials.json}"
if [ ! -f "$ADC_FILE" ]; then
  echo "Error: Application Default Credentials file not found at: $ADC_FILE" >&2
  echo "On Cloudtop, run the following command first so Docker trials can authenticate to GCP:" >&2
  echo "  gcloud auth application-default login" >&2
  exit 1
fi

# Pre-flight Check 2: Auto-build cicd-evals:latest Docker image if using docker provider and image is missing
if [ "$PROVIDER" = "docker" ]; then
  if ! docker image inspect cicd-evals:latest >/dev/null 2>&1; then
    echo "Building cicd-evals:latest Docker image from Dockerfile.eval..."
    docker build -f Dockerfile.eval -t cicd-evals:latest .
  fi
fi

IFS=',' read -r -a MODEL_ARRAY <<< "$MODELS"

for AGENT in "${MODEL_ARRAY[@]}"; do
  AGENT_TRIMMED=$(echo "$AGENT" | xargs)
  echo "=================================================================="
  echo "Running CI/CD Evals | Agent: ${AGENT_TRIMMED} | Provider: ${PROVIDER}"
  echo "Config: ${CONFIG_FILE}"
  echo "=================================================================="

  TMP_CONFIG=$(mktemp "/tmp/eval.${AGENT_TRIMMED}.XXXXXX.yaml")
  sed -e "s/^  agent: .*/  agent: ${AGENT_TRIMMED}/" \
      -e "s/^  provider: .*/  provider: ${PROVIDER}/" \
      "$CONFIG_FILE" > "$TMP_CONFIG"

  CMD=(skillgrade "--config=${TMP_CONFIG}" --no-redact --save-trial-workspace)
  if [ -n "$EVAL_TASK" ]; then
    CMD+=("--eval=${EVAL_TASK}")
  fi
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    CMD+=("${EXTRA_ARGS[@]}")
  fi

  "${CMD[@]}"
  rm -f "$TMP_CONFIG"
done
