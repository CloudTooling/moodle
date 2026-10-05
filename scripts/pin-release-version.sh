#!/usr/bin/env bash
#
# Pins the Helm chart to a release version: `image.tag` in values.yaml,
# `appVersion` and the chart's own image in the `annotations.images` catalog
# in Chart.yaml become the release version, the chart's own `version` gets a
# patch increment (or becomes the given chart version), and helm-docs
# regenerates the chart README. Run by the release workflow
# (gh-actions-templates' docker-release.yml `bump_command`), so the release
# commit points the chart at the image that release publishes.
#
#   scripts/pin-release-version.sh 5.3.0.1          # chart version: patch bump
#   scripts/pin-release-version.sh 5.3.0.1 2.0.0    # chart version: 2.0.0
#
# The release version is the Moodle version, optionally with a fourth image
# revision (5.3.0.1). An explicit chart version must be X.Y.Z and higher than
# the current one: the release pushes it to an OCI registry, where an existing
# version would be replaced.
#
# helm-docs runs from PATH if installed, otherwise from its Docker image.
# Fails without touching a file if any expected entry isn't found.
set -euo pipefail

CHART_NAME=moodle
IMAGE=docker.io/cloudtooling/moodle

VERSION="${1:-}"
CHART_VERSION="${2:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
  ! [[ -z "$CHART_VERSION" || "$CHART_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <X.Y.Z[.N]> [<chart X.Y.Z>]" >&2
  exit 1
fi
export VERSION CHART_VERSION CHART_NAME IMAGE

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/$CHART_NAME"
HELM_DOCS_IMAGE=jnorwood/helm-docs:v1.14.2

if [[ -n "$CHART_VERSION" ]]; then
  current="$(sed -n 's/^version: *//p' "$CHART/Chart.yaml")"
  highest="$(printf '%s\n%s\n' "$current" "$CHART_VERSION" | sort -V | tail -n1)"
  if [[ "$CHART_VERSION" == "$current" || "$highest" != "$CHART_VERSION" ]]; then
    echo "chart version $CHART_VERSION must be higher than the current $current" >&2
    exit 1
  fi
fi

# pin <file> <perl substitutions>: rewrite into a temp file first, so a failed
# match (die) never leaves a half-written chart file behind.
pin() {
  local file="$1" tmp
  tmp="$(mktemp)"
  if perl -0777 -pe "$2" "$file" > "$tmp"; then
    cat "$tmp" > "$file"
    rm -f "$tmp"
  else
    rm -f "$tmp"
    echo "failed to pin $file" >&2
    return 1
  fi
}

# The `tag:` must sit inside the top-level `image:` block, i.e. before the
# next unindented line.
pin "$CHART/values.yaml" '
  s/^(image:\n(?:[ \t#].*\n)*?  tag: ).*$/$1"$ENV{VERSION}"/m
    or die "image.tag not found\n";
'

pin "$CHART/Chart.yaml" '
  s/^version: (\d+)\.(\d+)\.(\d+)[ \t]*$/"version: " . ($ENV{CHART_VERSION} || "$1.$2." . ($3 + 1))/me
    or die "version (X.Y.Z) not found\n";
  s/^appVersion: .*$/appVersion: "$ENV{VERSION}"/m
    or die "appVersion not found\n";
  s/^([ \t]+image: \Q$ENV{IMAGE}\E:).*$/$1$ENV{VERSION}/m
    or die "annotations.images entry for $ENV{IMAGE} not found\n";
  s/^([ \t]+- name: \Q$ENV{CHART_NAME}\E\n[ \t]+version: ).*$/$1$ENV{VERSION}/m;
'

if command -v helm-docs >/dev/null 2>&1; then
  (cd "$ROOT" && helm-docs --chart-search-root charts)
else
  docker run --rm -v "$ROOT:/helm-docs" -w /helm-docs -u "$(id -u):$(id -g)" \
    "$HELM_DOCS_IMAGE" --chart-search-root charts
fi

echo "Pinned chart to app version $VERSION, chart version $(sed -n 's/^version: //p' "$CHART/Chart.yaml")"
