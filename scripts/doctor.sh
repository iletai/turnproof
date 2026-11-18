#!/usr/bin/env bash
# Preflight for the first push, and before spawning parallel agents. Read-only; prints names, never values.
# Exit 1 when something that would break CI or a build is wrong.
cd "$(dirname "$0")/.." || exit 2
fail=0
bad() { echo "FAIL $*"; fail=1; }
ok() { echo "ok   $*"; }

# 1. Files CI needs must be committed, not swallowed by .gitignore (an old repo's `.env.*` rule did this).
for f in .env.example project.yml fastlane/.env.default fastlane/.env.dev fastlane/.env.staging fastlane/.env.prod; do
  [[ -f $f ]] || { bad "missing $f"; continue; }
  if git check-ignore -q --no-index "$f"; then bad "$f is gitignored: $(git check-ignore -v --no-index "$f" | cut -f1)"; else ok "$f tracked-able"; fi
done

# 2. Secrets: every name in .env.example must be set locally (optional ones may stay empty) and on GitHub.
optional='APP_REVIEW_.*|PRIVATE_REPO_TOKEN'
names=$(grep -oE '^[A-Z][A-Z0-9_]*' .env.example)
for n in $names; do
  [[ $n =~ ^($optional)$ ]] && continue
  grep -qE "^$n=.+" .env 2>/dev/null || bad ".env: $n is empty or missing"
done
if remote=$(git remote get-url origin 2>/dev/null) && command -v gh >/dev/null; then
  repo=$(echo "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
  have=$(gh secret list -R "$repo" --json name --jq '.[].name' 2>/dev/null)
  for n in $names; do
    [[ $n =~ ^($optional)$ ]] && continue
    grep -qx "$n" <<<"$have" || bad "GitHub secret $n missing on $repo (gh secret set -f .env)"
  done
  # 3. The latest run on develop must be green before more work lands on top of it.
  last=$(gh run list -R "$repo" -b develop -L 1 --json conclusion,workflowName --jq '.[0] | "\(.workflowName) \(.conclusion)"' 2>/dev/null)
  [[ -z $last || $last == *success ]] && ok "latest develop run: ${last:-none}" || bad "latest develop run: $last"
fi

# 4. Parallel builds each need several GB; low disk makes simulators die and tests fail for no code reason.
free_gb=$(df -g / | awk 'NR==2 {print $4}')
((free_gb >= 10)) && ok "disk free ${free_gb}G" || bad "disk free ${free_gb}G (< 10G): run dev-cleanup before building"

exit $fail
