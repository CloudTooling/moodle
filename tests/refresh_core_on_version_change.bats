#!/usr/bin/env bats
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Covers moodle_refresh_core_on_version_change() in rootfs/opt/bitnami/scripts/libmoodle.sh,
# which refreshes a persisted (already on the "/public" layout) codebase whenever the image
# ships a different Moodle version - restore_persisted_app() would otherwise keep serving
# whatever codebase was captured at the volume's first boot forever, no matter how many
# MOODLE_VERSION bumps the image goes through.

setup() {
    export BITNAMI_ROOT_DIR="${BATS_TEST_TMPDIR}/opt/bitnami"
    export BITNAMI_VOLUME_DIR="${BATS_TEST_TMPDIR}/bitnami"
    export MOODLE_BASE_DIR="${BITNAMI_ROOT_DIR}/moodle"
    export MOODLE_VOLUME_DIR="${BITNAMI_VOLUME_DIR}/moodle"
    export MOODLE_DATA_DIR="${BITNAMI_VOLUME_DIR}/moodledata"
    mkdir -p "$MOODLE_BASE_DIR" "$MOODLE_VOLUME_DIR" "$MOODLE_DATA_DIR"

    # shellcheck disable=SC1091
    . /opt/bitnami/scripts/libmoodle.sh

    # Fresh image codebase: newer Moodle version, already split into public/
    write_file "${MOODLE_BASE_DIR}/admin/cli/cron.php" "NEW-CLI"
    write_file "${MOODLE_BASE_DIR}/lib/setup.php" "NEW-SETUP"
    write_file "${MOODLE_BASE_DIR}/public/version.php" '$version = 2026091300.00;'
    write_file "${MOODLE_BASE_DIR}/public/index.php" "NEW-CORE-INDEX"
    write_file "${MOODLE_BASE_DIR}/public/lib/weblib.php" "NEW-CORE-WEBLIB"
    write_file "${MOODLE_BASE_DIR}/public/mod/forum/version.php" "NEW-CORE-FORUM"
    write_file "${MOODLE_BASE_DIR}/public/theme/boost/config.php" "NEW-CORE-BOOST"

    # Persisted volume: older Moodle version, already on the /public layout, plus a
    # third-party plugin/theme the fresh image doesn't know about.
    write_file "${MOODLE_VOLUME_DIR}/config.php" "SITE-CONFIG-SECRET"
    write_file "${MOODLE_VOLUME_DIR}/admin/cli/cron.php" "OLD-CLI"
    write_file "${MOODLE_VOLUME_DIR}/lib/setup.php" "OLD-SETUP"
    write_file "${MOODLE_VOLUME_DIR}/public/version.php" '$version = 2026060800.00;'
    write_file "${MOODLE_VOLUME_DIR}/public/index.php" "OLD-CORE-INDEX"
    write_file "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "OLD-CORE-WEBLIB"
    write_file "${MOODLE_VOLUME_DIR}/public/mod/forum/version.php" "OLD-CORE-FORUM"
    write_file "${MOODLE_VOLUME_DIR}/public/mod/customplugin/version.php" "CUSTOM-MOD-PLUGIN"
    write_file "${MOODLE_VOLUME_DIR}/public/theme/boost/config.php" "OLD-CORE-BOOST"
    write_file "${MOODLE_VOLUME_DIR}/public/theme/mytheme/config.php" "CUSTOM-THEME"

    # A core file/plugin Moodle itself has since removed - left on the old install, this is
    # exactly what trips Moodle's own "Mixed Moodle versions detected" upgrade check.
    write_file "${MOODLE_VOLUME_DIR}/public/lib/cronlib.php" "STALE-CRONLIB"
    write_file "${MOODLE_VOLUME_DIR}/public/question/type/random/version.php" "STALE-QTYPE-RANDOM"

    # Mirror the real chart's permission model - see the equivalent comment in
    # migrate_public_layout.bats for why this matters.
    chmod 555 "$BITNAMI_VOLUME_DIR"
}

teardown() {
    chmod 755 "$BITNAMI_VOLUME_DIR" 2>/dev/null || true
}

write_file() {
    mkdir -p "$(dirname "$1")"
    printf '%s' "$2" >"$1"
}

file_is() {
    [ -f "$1" ]
    [ "$(cat "$1")" = "$2" ]
}

@test "updates a core file to the shipped image's version" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "NEW-CORE-WEBLIB"
}

@test "updates the core index.php" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/index.php" "NEW-CORE-INDEX"
}

@test "leaves config.php untouched" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/config.php" "SITE-CONFIG-SECRET"
}

@test "preserves a third-party plugin and theme the fresh image doesn't know about" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/mod/customplugin/version.php" "CUSTOM-MOD-PLUGIN"
    file_is "${MOODLE_VOLUME_DIR}/public/theme/mytheme/config.php" "CUSTOM-THEME"
}

@test "updates a core activity module and a core theme" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/mod/forum/version.php" "NEW-CORE-FORUM"
    file_is "${MOODLE_VOLUME_DIR}/public/theme/boost/config.php" "NEW-CORE-BOOST"
}

@test "refreshes root-level admin/cli scripts from the image" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/admin/cli/cron.php" "NEW-CLI"
}

@test "refreshes root-level lib bootstrap files from the image" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/lib/setup.php" "NEW-SETUP"
}

@test "updates the persisted version.php to the shipped image's version" {
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/version.php" '$version = 2026091300.00;'
}

@test "removes a core file Moodle itself has since removed, instead of carrying it forward" {
    moodle_refresh_core_on_version_change
    [ ! -e "${MOODLE_VOLUME_DIR}/public/lib/cronlib.php" ]
}

@test "removes a whole plugin Moodle itself has since removed (qtype_random)" {
    moodle_refresh_core_on_version_change
    [ ! -e "${MOODLE_VOLUME_DIR}/public/question/type/random" ]
}

@test "writes a pre-refresh backup archive to the data directory" {
    moodle_refresh_core_on_version_change
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-core-refresh-*.tar.gz"
    [ "$status" -eq 0 ]
}

@test "is a no-op when the persisted and shipped versions already match" {
    write_file "${MOODLE_VOLUME_DIR}/public/version.php" '$version = 2026091300.00;'
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "OLD-CORE-WEBLIB"
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-core-refresh-*.tar.gz 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "runs at most once: a second call with no further version change is a no-op" {
    moodle_refresh_core_on_version_change
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-core-refresh-*.tar.gz | wc -l"
    [ "$output" -eq 1 ]
    write_file "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "WEBLIB-CHANGED-AFTER-FIRST-REFRESH"

    moodle_refresh_core_on_version_change

    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "WEBLIB-CHANGED-AFTER-FIRST-REFRESH"
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-core-refresh-*.tar.gz | wc -l"
    [ "$output" -eq 1 ]
}

@test "can be disabled via MOODLE_SKIP_CORE_REFRESH" {
    export MOODLE_SKIP_CORE_REFRESH="yes"
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "OLD-CORE-WEBLIB"
}

@test "is a no-op when the persisted volume has no version.php yet" {
    rm -f "${MOODLE_VOLUME_DIR}/public/version.php"
    moodle_refresh_core_on_version_change
    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "OLD-CORE-WEBLIB"
}
