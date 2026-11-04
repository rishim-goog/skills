#!/usr/bin/env bash
#
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# 1. Cross-Model Instruction & Skill Mirroring (Gemini, OpenAI Codex, and Anthropic Claude)
mkdir -p "$HOME/.gemini" "$HOME/.claude" "$HOME/.agents" "$HOME/.codex"
if [ -f "$HOME/.gemini/GEMINI.md" ]; then
    cp "$HOME/.gemini/GEMINI.md" "$HOME/.claude/CLAUDE.md"
    cp "$HOME/.gemini/GEMINI.md" "$HOME/.agents/AGENTS.md"
    cp "$HOME/.gemini/GEMINI.md" "$HOME/.codex/AGENTS.md"
fi

if [ -d "$HOME/.gemini/skills" ]; then
    mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.codex/skills"
    cp -rn "$HOME/.gemini/skills/"* "$HOME/.claude/skills/" 2>/dev/null || true
    cp -rn "$HOME/.gemini/skills/"* "$HOME/.agents/skills/" 2>/dev/null || true
    cp -rn "$HOME/.gemini/skills/"* "$HOME/.codex/skills/" 2>/dev/null || true
fi

if [ -f "/workspace/GEMINI.md" ]; then
    cp "/workspace/GEMINI.md" "/workspace/CLAUDE.md"
    cp "/workspace/GEMINI.md" "/workspace/AGENTS.md"
fi

# 2. Configure non-interactive gcloud access token
TOKEN_FILE=$(mktemp)

if gcloud auth application-default print-access-token > "$TOKEN_FILE"; then
    gcloud config set auth/access_token_file "$TOKEN_FILE"
    echo "Successfully set auth/access_token_file to $TOKEN_FILE"
else
    echo "Failed to get access token" >&2
    rm -f "$TOKEN_FILE"
    exit 1
fi

# Disable interactive prompts from eval runs
gcloud config set core/disable_prompts true
