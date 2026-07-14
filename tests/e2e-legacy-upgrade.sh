#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# End-to-end regression test for the class of bugs found migrating a real, years-old production
# Moodle install to this image's Moodle 5.2.x build:
#
#   1. A stale, long-removed plugin (qtype_random) crashing core\component's classloader with
#      "Call to undefined function core\debugging()" during the very first cache rebuild.
#   2. Moodle's own "Mixed Moodle versions detected" upgrade check refusing to proceed because
#      other core files Moodle itself has since removed were still present.
#
# Unlike tests/migrate_public_layout.bats (which tests the shell relocation logic in isolation),
# this boots the actual image against real MariaDB and drives it through actual PHP execution,
# since both bugs above only reproduce when Moodle's own code actually runs.
#
# Usage: tests/e2e-legacy-upgrade.sh <image-ref>

set -euo pipefail

IMAGE="${1:?Usage: $0 <image-ref>}"
NET="moodle-e2e-net-$$"
DB="moodle-e2e-db-$$"
APP="moodle-e2e-app-$$"
VOL="moodle-e2e-vol-$$"

cleanup() {
    docker rm -f "$APP" "$DB" >/dev/null 2>&1 || true
    docker volume rm "$VOL" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Setting up network/volume"
docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null

echo "==> Starting MariaDB"
docker run -d --name "$DB" --network "$NET" \
    -e ALLOW_EMPTY_PASSWORD=yes \
    -e MARIADB_USER=bn_moodle \
    -e MARIADB_DATABASE=bitnami_moodle \
    -e MARIADB_CHARACTER_SET=utf8mb4 \
    -e MARIADB_COLLATE=utf8mb4_unicode_ci \
    docker.io/bitnami/mariadb:latest >/dev/null

echo "==> Fresh install: booting $IMAGE against empty volumes"
docker run -d --name "$APP" --network "$NET" \
    -v "${VOL}:/bitnami/moodle" \
    -e MOODLE_DATABASE_HOST="$DB" \
    -e MOODLE_DATABASE_PORT_NUMBER=3306 \
    -e MOODLE_DATABASE_USER=bn_moodle \
    -e MOODLE_DATABASE_NAME=bitnami_moodle \
    -e ALLOW_EMPTY_PASSWORD=yes \
    -e MOODLE_USERNAME=admin \
    -e MOODLE_PASSWORD='Sup3rSecret!' \
    -e MOODLE_EMAIL=admin@example.com \
    -e BITNAMI_DEBUG=true \
    "$IMAGE" >/dev/null

echo "==> Waiting for fresh install to finish"
# --tail (not full "docker logs") keeps each poll cheap regardless of how much verbose
# BITNAMI_DEBUG output has accumulated; bounded by wall-clock deadline, not iteration count,
# since a loaded Docker host can make each poll itself take much longer than "sleep 5" implies.
deadline=$(( $(date +%s) + 900 ))
found=false
while [ "$(date +%s)" -lt "$deadline" ]; do
    if docker logs --tail 200 "$APP" 2>&1 | grep -q "Moodle setup finished"; then
        found=true
        break
    fi
    sleep 5
done
if [ "$found" != "true" ]; then
    echo "FAIL: fresh install never finished"
    docker logs "$APP" 2>&1 | tail -60
    exit 1
fi
echo "==> Fresh install OK"

echo "==> Simulating an old, years-old pre-/public install with known-legacy leftovers"
docker rm -f "$APP" >/dev/null
docker run --rm -v "${VOL}:/bitnami/moodle" "$IMAGE" bash -c '
    set -euo pipefail
    cd /bitnami/moodle
    # Flatten back to the pre-Moodle-5.1 layout (the inverse of moodle_migrate_to_public_layout):
    # merge public/admin and public/lib back into their root counterparts, move everything else
    # in public/ up to root, then drop the now-empty public/ directory entirely. public/config.php
    # is a small loader stub (require_once __DIR__."/../config.php") introduced alongside the
    # /public split - excluded here since the real root config.php (with actual $CFG->... site
    # config) already exists and pre-5.1 installs never had this indirection at all.
    cp -a public/admin/. admin/
    cp -a public/lib/. lib/
    find public -mindepth 1 -maxdepth 1 ! -name admin ! -name lib ! -name config.php -exec mv {} . \;
    rm -rf public

    # A whole plugin Moodle has since removed from core (crashes classloader bootstrap if left
    # on disk - see MOODLE_KNOWN_REMOVED_PLUGIN_DIRS in libmoodle.sh).
    mkdir -p question/type/random
    cat > question/type/random/version.php <<PHP
<?php
defined("MOODLE_INTERNAL") || die();
\$plugin->version = 2024100700;
\$plugin->requires = 2024100100;
\$plugin->component = "qtype_random";
PHP

    # A core file Moodle has since removed (see MOODLE_KNOWN_REMOVED_CORE_FILES in libmoodle.sh).
    echo "<?php // stale legacy cronlib" > lib/cronlib.php
'
echo "==> Legacy state staged"

echo "==> Restarting against the simulated legacy volume (this must run the real migration + upgrade)"
docker run -d --name "$APP" --network "$NET" \
    -v "${VOL}:/bitnami/moodle" \
    -e MOODLE_DATABASE_HOST="$DB" \
    -e MOODLE_DATABASE_PORT_NUMBER=3306 \
    -e MOODLE_DATABASE_USER=bn_moodle \
    -e MOODLE_DATABASE_NAME=bitnami_moodle \
    -e ALLOW_EMPTY_PASSWORD=yes \
    -e MOODLE_USERNAME=admin \
    -e MOODLE_PASSWORD='Sup3rSecret!' \
    -e MOODLE_EMAIL=admin@example.com \
    -e BITNAMI_DEBUG=true \
    "$IMAGE" >/dev/null

echo "==> Waiting for Apache to come up and serve a real 200"
ok=false
deadline=$(( $(date +%s) + 900 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    if docker exec "$APP" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && printf "GET /login/index.php HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 && head -1 <&3' 2>/dev/null | grep -q "200"; then
        ok=true
        break
    fi
    if ! docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null | grep -q true; then
        echo "FAIL: container exited unexpectedly"
        docker logs "$APP" 2>&1 | tail -80
        exit 1
    fi
    sleep 5
done

if [ "$ok" != "true" ]; then
    echo "FAIL: never got a healthy 200 from /login/index.php"
    docker logs "$APP" 2>&1 | tail -80
    exit 1
fi

echo "==> PASS: legacy install with stale qtype_random + removed core files migrated and upgraded cleanly"
