#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Verifies every container image referenced by the chart actually exists on its registry.
#
# Bitnami split its container catalog in Aug/Sep 2025 (see CLAUDE.md): free images stopped
# receiving new versioned tags, so a chart pinned to a specific bitnami/* tag can silently
# start referencing an image that no longer exists — `helm install` then fails at pod
# scheduling time with an ImagePullBackOff, long after the chart itself passed `helm lint`/
# `ct lint`. This catches that class of break in CI instead.
#
# Checks the union of:
#   - every `image:` value in the chart's rendered manifests (with optional subcharts/sidecars
#     enabled via --set, so their default images render too)
#   - every image listed in the chart's own Chart.yaml `annotations.images` catalog metadata
#
# Usage: tests/verify-chart-images.sh <chart-dir> [helm --set key=value ...]

set -euo pipefail

CHART_DIR="${1:?Usage: $0 <chart-dir> [helm --set key=value ...]}"
shift

set_args=()
for kv in "$@"; do
  set_args+=(--set "$kv")
done

rendered_images=$(
  helm template verify-images "$CHART_DIR" --dependency-update=false "${set_args[@]}" \
    | grep -oE '^[[:space:]]*image:[[:space:]]*"?[^"[:space:]]+"?' \
    | sed -E 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?/\1/'
)

annotation_images=$(
  yq e '.annotations.images' "$CHART_DIR/Chart.yaml" | yq e '.[].image' -
)

images=$(printf '%s\n%s\n' "$rendered_images" "$annotation_images" | grep -v '^$' | sort -u)

if [ -z "$images" ]; then
  echo "No images discovered — check chart rendering / annotations.images." >&2
  exit 1
fi

echo "Discovered images:"
echo "$images"
echo

failed=0
while IFS= read -r image; do
  [ -z "$image" ] && continue
  printf 'Checking %s ... ' "$image"
  if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "MISSING"
    echo "::error::image not found: $image"
    failed=1
  fi
done <<<"$images"

exit $failed
