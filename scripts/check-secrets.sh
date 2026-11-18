#!/usr/bin/env bash
# Pre-commit hook: block staging of sensitive files (.env.example is the allowed template).
set -euo pipefail
BLOCKED='\.p8$|\.p12$|\.mobileprovision$|Secrets\.xcconfig$|^\.env$|^\.env\.'
staged=$(git diff --cached --name-only | grep -E "$BLOCKED" | grep -vE '^\.env\.example$' || true)
if [[ -n $staged ]]; then
  echo "error: sensitive file staged. Unstage it (git reset HEAD <file>)" >&2
  echo "$staged" >&2
  exit 1
fi
