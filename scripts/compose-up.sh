#!/usr/bin/env bash
# Dựng stack dev nhưng vẫn gắn đúng SHA hiện tại vào tag và OCI label.
set -euo pipefail
cd "$(dirname "$0")/.."

GIT_SHA="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "error: working tree không sạch — hãy commit trước khi build image ${GIT_SHA}" >&2
  exit 1
fi

export GIT_SHA
exec docker compose up --build "$@"
