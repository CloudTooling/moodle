#!/usr/bin/env bats
#
# Tests for scripts/pin-release-version.sh, the release's bump_command. Runs
# on a copy of the repo's chart so the real files are never touched. Needs
# helm and helm-docs (or Docker for its image fallback). Lives outside
# tests/*.bats on purpose: those run inside the shell-library test image,
# which has neither.

CHART_NAME=moodle
IMAGE=docker.io/cloudtooling/moodle

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  WORK="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$WORK"
  cp -R "$ROOT/scripts" "$ROOT/charts" "$WORK/"
  CHART="$WORK/charts/$CHART_NAME"
  CHART_VERSION="$(sed -n 's/^version: //p' "$CHART/Chart.yaml")"
}

pin() {
  "$WORK/scripts/pin-release-version.sh" "$@"
}

next_patch() { # 1.0.9 -> 1.0.10
  local IFS=.
  # shellcheck disable=SC2206
  local v=($1)
  echo "${v[0]}.${v[1]}.$((v[2] + 1))"
}

chart_field() {
  sed -n "s/^$1: //p" "$CHART/Chart.yaml"
}

@test "pins image.tag, appVersion and the annotations image to the release version" {
  run pin 9.8.7.6
  [ "$status" -eq 0 ]
  [ "$(chart_field appVersion)" = '"9.8.7.6"' ]
  run helm template t "$CHART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"image: $IMAGE:9.8.7.6"* ]]
  [[ "$output" == *"app.kubernetes.io/version: 9.8.7.6"* ]]
  # The artifacthub catalog entry for our own image points at the release.
  grep -qx "      image: $IMAGE:9.8.7.6" "$CHART/Chart.yaml"
  ! grep -A1 -x "    - name: $CHART_NAME" "$CHART/Chart.yaml" | grep -q "version:" ||
    grep -A1 -x "    - name: $CHART_NAME" "$CHART/Chart.yaml" | grep -qx "      version: 9.8.7.6"
}

@test "accepts plain X.Y.Z release versions" {
  run pin 9.8.7
  [ "$status" -eq 0 ]
  [ "$(chart_field appVersion)" = '"9.8.7"' ]
}

@test "bumps the chart's own version by one patch per release" {
  pin 9.8.7
  [ "$(chart_field version)" = "$(next_patch "$CHART_VERSION")" ]
  pin 9.8.8
  [ "$(chart_field version)" = "$(next_patch "$(next_patch "$CHART_VERSION")")" ]
}

@test "uses an explicitly given chart version instead of the patch bump" {
  run pin 9.8.7 99.0.0
  [ "$status" -eq 0 ]
  [ "$(chart_field version)" = "99.0.0" ]
  grep -q "Version-99.0.0" "$CHART/README.md"
  grep -q "AppVersion-9.8.7" "$CHART/README.md"
}

@test "rejects a chart version that isn't X.Y.Z or not higher than the current one" {
  for v in v99.0.0 99.0 99.0.0.1 "$CHART_VERSION" 0.0.1; do
    run pin 9.8.7 "$v"
    [ "$status" -ne 0 ]
  done
  [[ "$output" == *"must be higher than the current $CHART_VERSION"* ]]
  git diff --no-index --quiet "$ROOT/charts" "$WORK/charts"
}

@test "rejects release versions that aren't X.Y.Z or X.Y.Z.N" {
  for v in v9.8.7 9.8 9.8.7-rc1 9.8.7.6.5 ""; do
    run pin "$v"
    [ "$status" -ne 0 ]
  done
  git diff --no-index --quiet "$ROOT/charts" "$WORK/charts"
}

@test "fails and leaves values.yaml untouched when image.tag moved" {
  perl -0pi -e 's/^(image:\n(?:[ \t#].*\n)*?)  tag: /$1  imageTag: /m' "$CHART/values.yaml"
  cp "$CHART/values.yaml" "$BATS_TEST_TMPDIR/before"

  run pin 9.8.7
  [ "$status" -ne 0 ]
  [[ "$output" == *"image.tag not found"* ]]
  cmp "$BATS_TEST_TMPDIR/before" "$CHART/values.yaml"
}
