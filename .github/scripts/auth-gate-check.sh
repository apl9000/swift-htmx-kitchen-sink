#!/usr/bin/env bash
# Health must be open. Every other probed URL must be an authentication challenge.
# A 200 on the application URL fails the deploy even when health is healthy.
set -euo pipefail

health_get=""
health_head=""
gate=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --health-get)
      health_get="${2:-}"
      shift 2
      ;;
    --health-head)
      health_head="${2:-}"
      shift 2
      ;;
    --gate)
      gate="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$health_get" != "200" || "$health_head" != "200" ]]; then
  echo "health probe must return 200 for GET and HEAD (got GET ${health_get:-missing} HEAD ${health_head:-missing})" >&2
  exit 1
fi

case "$gate" in
  301|302|303|307|308|401|403)
    echo "auth gate challenged anonymous access with ${gate}"
    ;;
  *)
    echo "auth gate returned ${gate:-missing}; expected 301, 302, 303, 307, 308, 401, or 403" >&2
    exit 1
    ;;
esac
