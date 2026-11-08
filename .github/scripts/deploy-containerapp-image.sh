#!/usr/bin/env bash
# Update an existing Container App to one immutable digest, then require
# /health and an authentication challenge on /. On failure, shift traffic
# back to the previous ready revision.
#
# This script does not create the app, identity, secrets, or ingress.
# --dry-run prints the intended actions and does not call Azure or curl.
set -euo pipefail

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
fi

: "${TARGET:?}"
: "${IMAGE_REPOSITORY:?}"
: "${IMAGE_DIGEST:?}"
: "${RESOURCE_GROUP:?}"
: "${CONTAINER_APP_NAME:?}"
: "${BASE_URL:?}"
: "${AZURE_DEPLOY_ENABLED:?}"

if [[ "$AZURE_DEPLOY_ENABLED" != "true" ]]; then
  echo "refusing to deploy because AZURE_DEPLOY_ENABLED is not true" >&2
  exit 1
fi

if [[ "$TARGET" != "staging" && "$TARGET" != "production" ]]; then
  echo "TARGET must be staging or production" >&2
  exit 1
fi

if [[ ! "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "IMAGE_DIGEST must be a sha256 digest" >&2
  exit 1
fi

if [[ "$IMAGE_REPOSITORY" == *:* || "$IMAGE_REPOSITORY" == *@* || "$IMAGE_REPOSITORY" == *latest* ]]; then
  echo "IMAGE_REPOSITORY must not include a tag or digest" >&2
  exit 1
fi

if [[ ! "$BASE_URL" =~ ^https://[a-zA-Z0-9.-]+$ ]]; then
  echo "BASE_URL must be an https origin" >&2
  exit 1
fi

image="${IMAGE_REPOSITORY}@${IMAGE_DIGEST}"
root="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "$dry_run" == true ]]; then
  echo "VERIFY_MANIFEST ${image}"
  echo "READ_PREVIOUS_REVISION az containerapp show --name ${CONTAINER_APP_NAME} --resource-group ${RESOURCE_GROUP}"
  echo "UPDATE az containerapp update --name ${CONTAINER_APP_NAME} --resource-group ${RESOURCE_GROUP} --image ${image}"
  echo "POLL_READY az containerapp revision list --name ${CONTAINER_APP_NAME} --resource-group ${RESOURCE_GROUP}"
  echo "GATE ${BASE_URL}/health GET/HEAD and ${BASE_URL}/ auth challenge"
  echo "ROLLBACK_ON_FAILURE az containerapp ingress traffic set --name ${CONTAINER_APP_NAME} --resource-group ${RESOURCE_GROUP}"
  exit 0
fi

echo "checking that ${image} already exists; this deploy does not build an image"
az acr manifest show \
  --registry "${ACR_NAME:?}" \
  --name "${IMAGE_REPOSITORY#*/}@${IMAGE_DIGEST}" \
  --only-show-errors >/dev/null

previous="$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.latestReadyRevisionName" \
  --output tsv)"

az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$image" \
  --output none

ready=""
for _ in $(seq 1 30); do
  state="$(az containerapp revision list \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "reverse(sort_by([].{name:name, created:properties.createdTime, state:properties.runningState, health:properties.healthState}, &created))[0].state" \
    --output tsv)"
  health="$(az containerapp revision list \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "reverse(sort_by([].{name:name, created:properties.createdTime, health:properties.healthState}, &created))[0].health" \
    --output tsv)"
  if [[ "$state" == "Running" && "$health" == "Healthy" ]]; then
    ready="yes"
    break
  fi
  if [[ "$state" == "Failed" || "$state" == "ActivationFailed" ]]; then
    break
  fi
  sleep 10
done

rollback() {
  if [[ -n "$previous" ]]; then
    az containerapp ingress traffic set \
      --name "$CONTAINER_APP_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --revision-weight "${previous}=100" \
      --output none || true
  fi
  echo "deploy failed readiness or auth gate; rollback to ${previous:-<none>} was requested" >&2
  exit 1
}

if [[ "$ready" != "yes" ]]; then
  rollback
fi

probe() {
  curl -sS -o /dev/null -w '%{http_code}' --max-redirs 0 --max-time 20 "$@" || true
}

health_get="$(probe "${BASE_URL}/health")"
health_head="$(probe -I "${BASE_URL}/health")"
gate="$(probe "${BASE_URL}/")"

if ! "$root/.github/scripts/auth-gate-check.sh" \
  --health-get "$health_get" \
  --health-head "$health_head" \
  --gate "$gate"
then
  rollback
fi

echo "deployed ${image} to ${TARGET} ${CONTAINER_APP_NAME}"
