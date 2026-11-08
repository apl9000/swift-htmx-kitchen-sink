#!/usr/bin/env bash
# Exit 0 when the running commit is still the branch tip.
# Exit 2 when a newer commit has landed. Exit 1 when the arguments are not SHAs.
set -euo pipefail

run="${1:-}"
latest="${2:-}"
sha_re='^[0-9a-f]{40}$'

if [[ ! "$run" =~ $sha_re || ! "$latest" =~ $sha_re ]]; then
  echo "both arguments must be 40-character commit SHAs" >&2
  exit 1
fi

if [[ "$run" != "$latest" ]]; then
  echo "stale run ${run}; latest is ${latest}" >&2
  exit 2
fi

echo "run is current"
