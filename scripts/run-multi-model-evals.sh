#!/usr/bin/env bash
# Run the CI/CD evaluation suite across Gemini, OpenAI (Codex), and Anthropic Claude models.
#
# Usage:
#   ./scripts/run-multi-model-evals.sh [--models gemini,claude,codex] [--config eval.criteria.yaml] [--eval <task-name>]

set -euo pipefail

MODELS="gemini,claude,codex"
CONFIG_FILE="eval.criteria.yaml"
EVAL_TASK=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models)
      MODELS="$2"
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

IFS=',' read -r -a MODEL_ARRAY <<< "$MODELS"

for AGENT in "${MODEL_ARRAY[@]}"; do
  AGENT_TRIMMED=$(echo "$AGENT" | xargs)
  echo "=================================================================="
  echo "Running CI/CD Evals with agent/model provider: ${AGENT_TRIMMED}"
  echo "Config: ${CONFIG_FILE}"
  echo "=================================================================="

  TMP_CONFIG=$(mktemp "/tmp/eval.${AGENT_TRIMMED}.XXXXXX.yaml")
  sed "s/^  agent: .*/  agent: ${AGENT_TRIMMED}/" "$CONFIG_FILE" > "$TMP_CONFIG"

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
