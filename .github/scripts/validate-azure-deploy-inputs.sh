#!/usr/bin/env bash
# Exit 0 when TARGET has every required input.
# Exit 10 when AZURE_DEPLOY_ENABLED is not exactly "true" (nothing was deployed).
# Exit 1 when deploy is enabled but an input is missing or unsafe.
set -euo pipefail

target="${TARGET:-staging}"
enabled="${AZURE_DEPLOY_ENABLED:-}"

if [[ "$enabled" != "true" ]]; then
  echo "AZURE_DEPLOY_ENABLED is not true; image publish and deploy are not configured"
  exit 10
fi

fail() {
  echo "$1" >&2
  exit 1
}

require() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    fail "missing ${name}"
  fi
}

is_guid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 1
  local lower="${1,,}"
  [[ "$lower" != "00000000-0000-0000-0000-000000000000" ]]
}

require AZURE_TENANT_ID
require AZURE_SUBSCRIPTION_ID
is_guid "$AZURE_TENANT_ID" || fail "AZURE_TENANT_ID must be a non-nil GUID"
is_guid "$AZURE_SUBSCRIPTION_ID" || fail "AZURE_SUBSCRIPTION_ID must be a non-nil GUID"

require ACR_NAME
[[ "$ACR_NAME" =~ ^[a-zA-Z0-9]{5,50}$ ]] || fail "ACR_NAME is invalid"

require IMAGE_REPOSITORY
[[ "$IMAGE_REPOSITORY" != *:* && "$IMAGE_REPOSITORY" != *@* && "$IMAGE_REPOSITORY" != *latest* ]] || fail "IMAGE_REPOSITORY must not include a tag or digest"
[[ "$IMAGE_REPOSITORY" =~ ^[a-z0-9.-]+/[a-z0-9._/-]+$ ]] || fail "IMAGE_REPOSITORY is invalid"

require_https_origin() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^https://[a-zA-Z0-9.-]+$ ]] || fail "${name} must be an https origin with no path, port, or userinfo"
}

require_app_name() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "${name} is invalid"
}

require_group() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._()-]{1,90}$ ]] || fail "${name} is invalid"
}

case "$target" in
  staging)
    require AZURE_CLIENT_ID_PUBLISH
    require AZURE_CLIENT_ID_STAGING
    is_guid "$AZURE_CLIENT_ID_PUBLISH" || fail "AZURE_CLIENT_ID_PUBLISH must be a non-nil GUID"
    is_guid "$AZURE_CLIENT_ID_STAGING" || fail "AZURE_CLIENT_ID_STAGING must be a non-nil GUID"
    require STAGING_RESOURCE_GROUP
    require STAGING_CONTAINER_APP
    require STAGING_BASE_URL
    require_group STAGING_RESOURCE_GROUP "$STAGING_RESOURCE_GROUP"
    require_app_name STAGING_CONTAINER_APP "$STAGING_CONTAINER_APP"
    require_https_origin STAGING_BASE_URL "$STAGING_BASE_URL"
    ;;
  production)
    require AZURE_CLIENT_ID_PRODUCTION
    is_guid "$AZURE_CLIENT_ID_PRODUCTION" || fail "AZURE_CLIENT_ID_PRODUCTION must be a non-nil GUID"
    require PRODUCTION_RESOURCE_GROUP
    require PRODUCTION_CONTAINER_APP
    require PRODUCTION_BASE_URL
    require IMAGE_DIGEST
    require_group PRODUCTION_RESOURCE_GROUP "$PRODUCTION_RESOURCE_GROUP"
    require_app_name PRODUCTION_CONTAINER_APP "$PRODUCTION_CONTAINER_APP"
    require_https_origin PRODUCTION_BASE_URL "$PRODUCTION_BASE_URL"
    [[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "IMAGE_DIGEST must be a sha256 digest"
    ;;
  *)
    fail "TARGET must be staging or production"
    ;;
esac

echo "prerequisites valid for ${target}"
