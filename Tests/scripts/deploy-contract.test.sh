#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >/tmp/deploy-contract.out 2>/tmp/deploy-contract.err
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    echo "command: $*" >&2
    echo "expected exit ${expected}, got ${actual}" >&2
    cat /tmp/deploy-contract.out >&2 || true
    cat /tmp/deploy-contract.err >&2 || true
    fail "exit status"
  fi
}

"$root/.github/scripts/stale-guard.sh" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >/dev/null
assert_exit 2 "$root/.github/scripts/stale-guard.sh" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
assert_exit 1 "$root/.github/scripts/stale-guard.sh" "not-a-sha" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

"$root/.github/scripts/auth-gate-check.sh" --health-get 200 --health-head 200 --gate 302 >/dev/null
"$root/.github/scripts/auth-gate-check.sh" --health-get 200 --health-head 200 --gate 401 >/dev/null
assert_exit 1 "$root/.github/scripts/auth-gate-check.sh" --health-get 200 --health-head 200 --gate 200
assert_exit 1 "$root/.github/scripts/auth-gate-check.sh" --health-get 401 --health-head 200 --gate 401
assert_exit 1 "$root/.github/scripts/auth-gate-check.sh" --health-get 200 --health-head 404 --gate 302

assert_exit 10 env AZURE_DEPLOY_ENABLED=false TARGET=staging "$root/.github/scripts/validate-azure-deploy-inputs.sh"

staging_ok=(
  env
  AZURE_DEPLOY_ENABLED=true
  TARGET=staging
  AZURE_TENANT_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  AZURE_SUBSCRIPTION_ID=11111111-2222-3333-4444-555555555555
  AZURE_CLIENT_ID_PUBLISH=99999999-8888-7777-6666-555555555555
  AZURE_CLIENT_ID_STAGING=12121212-3434-5656-7878-909090909090
  ACR_NAME=exampleacr
  IMAGE_REPOSITORY=exampleacr.azurecr.io/kitchen-sink
  STAGING_RESOURCE_GROUP=rg-example
  STAGING_CONTAINER_APP=app-staging
  STAGING_BASE_URL=https://staging.example.com
)
"${staging_ok[@]}" "$root/.github/scripts/validate-azure-deploy-inputs.sh" >/dev/null

assert_exit 1 env AZURE_DEPLOY_ENABLED=true TARGET=staging \
  AZURE_TENANT_ID=00000000-0000-0000-0000-000000000000 \
  AZURE_SUBSCRIPTION_ID=11111111-2222-3333-4444-555555555555 \
  AZURE_CLIENT_ID_PUBLISH=99999999-8888-7777-6666-555555555555 \
  AZURE_CLIENT_ID_STAGING=12121212-3434-5656-7878-909090909090 \
  ACR_NAME=exampleacr \
  IMAGE_REPOSITORY=exampleacr.azurecr.io/kitchen-sink \
  STAGING_RESOURCE_GROUP=rg-example \
  STAGING_CONTAINER_APP=app-staging \
  STAGING_BASE_URL=https://staging.example.com \
  "$root/.github/scripts/validate-azure-deploy-inputs.sh"

assert_exit 1 env AZURE_DEPLOY_ENABLED=true TARGET=production \
  AZURE_TENANT_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
  AZURE_SUBSCRIPTION_ID=11111111-2222-3333-4444-555555555555 \
  AZURE_CLIENT_ID_PRODUCTION=99999999-8888-7777-6666-555555555555 \
  ACR_NAME=exampleacr \
  IMAGE_REPOSITORY=exampleacr.azurecr.io/kitchen-sink:latest \
  PRODUCTION_RESOURCE_GROUP=rg-example \
  PRODUCTION_CONTAINER_APP=app-prod \
  PRODUCTION_BASE_URL=https://app.example.com \
  IMAGE_DIGEST=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  "$root/.github/scripts/validate-azure-deploy-inputs.sh"

digest="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
dry="$(
  AZURE_DEPLOY_ENABLED=true \
  TARGET=staging \
  IMAGE_REPOSITORY=exampleacr.azurecr.io/kitchen-sink \
  IMAGE_DIGEST="$digest" \
  RESOURCE_GROUP=rg-example \
  CONTAINER_APP_NAME=app-staging \
  BASE_URL=https://staging.example.com \
  "$root/.github/scripts/deploy-containerapp-image.sh" --dry-run
)"
[[ "$dry" == *"az containerapp update"* ]] || fail "dry-run missing image update"
[[ "$dry" == *"@${digest}"* ]] || fail "dry-run did not pin the digest"
[[ "$dry" == *"ROLLBACK_ON_FAILURE az containerapp ingress traffic set"* ]] || fail "dry-run missing rollback"
[[ "$dry" == *"GATE https://staging.example.com/health"* ]] || fail "dry-run missing auth gate"
[[ "$dry" != *"containerapp create"* ]] || fail "dry-run creates an app"
[[ "$dry" != *"identity create"* && "$dry" != *"secret set"* && "$dry" != *"ingress enable"* ]] || fail "dry-run mutates identity, secrets, or ingress"

assert_exit 1 env AZURE_DEPLOY_ENABLED=false TARGET=staging \
  IMAGE_REPOSITORY=exampleacr.azurecr.io/kitchen-sink \
  IMAGE_DIGEST="$digest" \
  RESOURCE_GROUP=rg-example \
  CONTAINER_APP_NAME=app-staging \
  BASE_URL=https://staging.example.com \
  "$root/.github/scripts/deploy-containerapp-image.sh" --dry-run

if grep -n 'id-token' .github/workflows/ci.yml; then
  fail "pull request workflow must not request an OIDC token"
fi
if grep -n 'pull_request_target' .github/workflows/*.yml; then
  fail "pull_request_target is not used"
fi
if grep -En 'containerapp create|identity create|ad sp create|secret set|ingress enable' .github/workflows/*.yml .github/scripts/*.sh; then
  fail "workflows or scripts create ingress, identities, or secrets"
fi
if grep -En 'docker|build-push|workflow_call:' .github/workflows/deploy-production.yml; then
  fail "production caller must stay a thin dispatch wrapper"
fi
if ! grep -q 'workflow_dispatch' .github/workflows/deploy-production.yml; then
  fail "production deploy must be an explicit dispatch"
fi
if grep -q 'workflow_dispatch' .github/workflows/release-staging.yml; then
  fail "staging release is push-to-main only"
fi
if grep -RIn --exclude-dir=.git 'apl9000/.github/workflows\|reusable-swift-azure-app.yml@' .github deploy README.md; then
  fail "do not point at an unpublished central workflow ref"
fi

python3 - <<'PY'
import pathlib, sys
try:
    import yaml
except ImportError:
    sys.exit(0)
root = pathlib.Path(".")
for path in root.glob(".github/workflows/*.yml"):
    with path.open() as handle:
        yaml.safe_load(handle)
print("workflow yaml parsed")
PY

echo "deploy contract tests passed"
