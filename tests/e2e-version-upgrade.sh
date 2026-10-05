#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# End-to-end regression test for upgrading a real deployment from the previously *released*
# image to the image under test - the exact path every production volume takes on a version bump.
#
# Found via the 5.2.4 -> 5.3.0 production incident (October 2026): the core refresh carried
# 5.2-only files (lib/amd/src/url.js & co.) forward onto the persisted volume because the
# hardcoded removed-files list hadn't been updated for 5.3, so every boot crashed in
# admin/cli/upgrade.php on "Mixed Moodle versions detected". Neither tests/*.bats (synthetic
# trees) nor tests/e2e-legacy-upgrade.sh (fresh install of the *same* image, flattened back)
# could see that, since neither ever puts a real older Moodle codebase on the volume. This test
# does, so a Renovate MOODLE_VERSION bump fails in CI instead of in production.
#
# Usage: tests/e2e-version-upgrade.sh <image-ref> [previous-image-ref]
#   previous-image-ref defaults to docker.io/cloudtooling/moodle:<newest git tag whose version
#   differs from the Dockerfile's MOODLE_VERSION>, i.e. the release production is running now.

set -euo pipefail

IMAGE="${1:?Usage: $0 <image-ref> [previous-image-ref]}"
PREVIOUS_IMAGE="${2:-}"
if [[ -z "$PREVIOUS_IMAGE" ]]; then
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    current_version="$(sed -n -E 's/^ARG MOODLE_VERSION="([^"]+)"/\1/p' "${repo_root}/Dockerfile")"
    previous_tag="$(git -C "$repo_root" tag --list 'v*' --sort=-v:refname | grep -vx "v${current_version}" | head -n1)"
    [[ -n "$previous_tag" ]] || { echo "FAIL: no previous release tag found (fetch tags?)"; exit 1; }
    PREVIOUS_IMAGE="docker.io/cloudtooling/moodle:${previous_tag#v}"
fi

NET="moodle-e2e-upg-net-$$"
DB="moodle-e2e-upg-db-$$"
APP="moodle-e2e-upg-app-$$"
VOL="moodle-e2e-upg-vol-$$"
DATA_VOL="moodle-e2e-upg-data-$$"

cleanup() {
    docker rm -f "$APP" "$DB" >/dev/null 2>&1 || true
    docker volume rm "$VOL" "$DATA_VOL" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_app() {
    # Both volumes persisted, mirroring the chart's moodle/ + moodledata/ subPath mounts
    docker run -d --name "$APP" --network "$NET" \
        -v "${VOL}:/bitnami/moodle" \
        -v "${DATA_VOL}:/bitnami/moodledata" \
        -e MOODLE_DATABASE_HOST="$DB" \
        -e MOODLE_DATABASE_PORT_NUMBER=3306 \
        -e MOODLE_DATABASE_USER=bn_moodle \
        -e MOODLE_DATABASE_NAME=bitnami_moodle \
        -e ALLOW_EMPTY_PASSWORD=yes \
        -e MOODLE_USERNAME=admin \
        -e MOODLE_PASSWORD='Sup3rSecret!' \
        -e MOODLE_EMAIL=admin@example.com \
        -e BITNAMI_DEBUG=true \
        "$1" >/dev/null
}

# Polls for a real 200 from the Moodle vhost; bounded by wall-clock deadline (see the equivalent
# comment in tests/e2e-legacy-upgrade.sh for why not by iteration count).
wait_for_healthy() {
    local -r what="$1"
    local deadline=$(( $(date +%s) + 900 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if docker exec "$APP" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && printf "GET /login/index.php HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 && head -1 <&3' 2>/dev/null | grep -q "200"; then
            return 0
        fi
        if ! docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null | grep -q true; then
            echo "FAIL: ${what}: container exited unexpectedly"
            docker logs "$APP" 2>&1 | tail -80
            exit 1
        fi
        sleep 5
    done
    echo "FAIL: ${what}: never got a healthy 200 from /login/index.php"
    docker logs "$APP" 2>&1 | tail -80
    exit 1
}

moodle_release() {
    docker exec "$APP" cat /bitnami/moodle/public/version.php | sed -n -E "s/^\\\$release *= *'([^']+)'.*/\\1/p"
}

echo "==> Upgrade path under test: ${PREVIOUS_IMAGE} -> ${IMAGE}"

echo "==> Setting up network/volumes"
docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null
docker volume create "$DATA_VOL" >/dev/null

echo "==> Starting MariaDB"
docker run -d --name "$DB" --network "$NET" \
    -e ALLOW_EMPTY_PASSWORD=yes \
    -e MARIADB_USER=bn_moodle \
    -e MARIADB_DATABASE=bitnami_moodle \
    -e MARIADB_CHARACTER_SET=utf8mb4 \
    -e MARIADB_COLLATE=utf8mb4_unicode_ci \
    docker.io/bitnami/mariadb:latest >/dev/null

echo "==> Fresh install with the previous release"
run_app "$PREVIOUS_IMAGE"
wait_for_healthy "fresh install of ${PREVIOUS_IMAGE}"
previous_release="$(moodle_release)"
[[ -n "$previous_release" ]] || { echo "FAIL: could not read \$release from the persisted version.php"; exit 1; }
echo "==> Previous release up: ${previous_release}"

echo "==> Upgrading the same volumes to the image under test"
docker rm -f "$APP" >/dev/null
run_app "$IMAGE"
wait_for_healthy "upgrade to ${IMAGE}"
new_release="$(moodle_release)"

if [[ "$new_release" == "$previous_release" ]]; then
    echo "FAIL: persisted codebase still reports ${previous_release} - core refresh never happened"
    docker logs "$APP" 2>&1 | tail -80
    exit 1
fi

echo "==> PASS: ${previous_release} -> ${new_release} upgraded cleanly on a persisted volume"
