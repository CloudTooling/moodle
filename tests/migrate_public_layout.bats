#!/usr/bin/env bats
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Covers moodle_migrate_to_public_layout() in rootfs/opt/bitnami/scripts/libmoodle.sh,
# which upgrades a persisted (pre-Moodle-5.1) codebase to the "/public" document root
# layout that this image's Apache vhost expects.

setup() {
    export BITNAMI_ROOT_DIR="${BATS_TEST_TMPDIR}/opt/bitnami"
    export BITNAMI_VOLUME_DIR="${BATS_TEST_TMPDIR}/bitnami"
    export MOODLE_BASE_DIR="${BITNAMI_ROOT_DIR}/moodle"
    export MOODLE_VOLUME_DIR="${BITNAMI_VOLUME_DIR}/moodle"
    export MOODLE_DATA_DIR="${BITNAMI_VOLUME_DIR}/moodledata"
    mkdir -p "$MOODLE_BASE_DIR" "$MOODLE_VOLUME_DIR" "$MOODLE_DATA_DIR"

    # shellcheck disable=SC1091
    . /opt/bitnami/scripts/libmoodle.sh

    # Fresh image codebase: Moodle >=5.1, already split into public/
    write_file "${MOODLE_BASE_DIR}/admin/cli/cron.php" "NEW-CLI"
    write_file "${MOODLE_BASE_DIR}/lib/setup.php" "NEW-SETUP"
    write_file "${MOODLE_BASE_DIR}/public/index.php" "NEW-CORE-INDEX"
    write_file "${MOODLE_BASE_DIR}/public/admin/index.php" "NEW-CORE-ADMIN-INDEX"
    write_file "${MOODLE_BASE_DIR}/public/lib/weblib.php" "NEW-CORE-WEBLIB"
    write_file "${MOODLE_BASE_DIR}/public/mod/forum/version.php" "NEW-CORE-FORUM"
    write_file "${MOODLE_BASE_DIR}/public/theme/boost/config.php" "NEW-CORE-BOOST"

    # Persisted volume: pre-5.1 codebase (no public/ split), some core files behind the
    # fresh image, plus a few third-party plugins the fresh image doesn't know about.
    write_file "${MOODLE_VOLUME_DIR}/config.php" "SITE-CONFIG-SECRET"
    write_file "${MOODLE_VOLUME_DIR}/.htaccess" "CUSTOM-HTACCESS"
    write_file "${MOODLE_VOLUME_DIR}/admin/cli/cron.php" "OLD-CLI"
    write_file "${MOODLE_VOLUME_DIR}/admin/index.php" "OLD-ADMIN-INDEX"
    write_file "${MOODLE_VOLUME_DIR}/admin/tool/custommonitor/version.php" "CUSTOM-ADMIN-TOOL"
    write_file "${MOODLE_VOLUME_DIR}/lib/setup.php" "OLD-SETUP"
    write_file "${MOODLE_VOLUME_DIR}/lib/weblib.php" "OLD-WEBLIB"
    write_file "${MOODLE_VOLUME_DIR}/lib/customlib/customhelper.php" "CUSTOM-LIB-HELPER"
    write_file "${MOODLE_VOLUME_DIR}/mod/forum/version.php" "OLD-FORUM"
    write_file "${MOODLE_VOLUME_DIR}/mod/customplugin/version.php" "CUSTOM-MOD-PLUGIN"
    write_file "${MOODLE_VOLUME_DIR}/theme/boost/config.php" "OLD-BOOST"
    write_file "${MOODLE_VOLUME_DIR}/theme/mytheme/config.php" "CUSTOM-THEME"
    write_file "${MOODLE_VOLUME_DIR}/index.php" "OLD-INDEX"
}

write_file() {
    mkdir -p "$(dirname "$1")"
    printf '%s' "$2" >"$1"
}

file_is() {
    [ -f "$1" ]
    [ "$(cat "$1")" = "$2" ]
}

@test "relocates config.php to the root, outside public/" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/config.php" "SITE-CONFIG-SECRET"
    [ ! -e "${MOODLE_VOLUME_DIR}/public/config.php" ]
}

@test "keeps the root CLI scripts from the shipped image, not the old volume" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/admin/cli/cron.php" "NEW-CLI"
    [ ! -e "${MOODLE_VOLUME_DIR}/public/admin/cli" ]
}

@test "updates core admin pages to the shipped image's version" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/admin/index.php" "NEW-CORE-ADMIN-INDEX"
}

@test "preserves a third-party admin tool plugin under public/admin" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/admin/tool/custommonitor/version.php" "CUSTOM-ADMIN-TOOL"
}

@test "keeps lib/setup.php at the root and does not duplicate it under public/lib" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/lib/setup.php" "NEW-SETUP"
    [ ! -e "${MOODLE_VOLUME_DIR}/public/lib/setup.php" ]
}

@test "updates core lib files and preserves a custom lib addition" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/lib/weblib.php" "NEW-CORE-WEBLIB"
    file_is "${MOODLE_VOLUME_DIR}/public/lib/customlib/customhelper.php" "CUSTOM-LIB-HELPER"
}

@test "updates a core activity module and preserves a third-party one" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/mod/forum/version.php" "NEW-CORE-FORUM"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/customplugin/version.php" "CUSTOM-MOD-PLUGIN"
}

@test "updates the core theme and preserves a custom theme" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/theme/boost/config.php" "NEW-CORE-BOOST"
    file_is "${MOODLE_VOLUME_DIR}/public/theme/mytheme/config.php" "CUSTOM-THEME"
}

@test "relocates a hidden dotfile such as a custom .htaccess" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/.htaccess" "CUSTOM-HTACCESS"
}

@test "updates the core index.php" {
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/index.php" "NEW-CORE-INDEX"
}

@test "writes a pre-migration backup archive to the data directory" {
    moodle_migrate_to_public_layout
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-public-migration-*.tar.gz"
    [ "$status" -eq 0 ]
}

@test "is a no-op when the volume already has the public/ layout" {
    mkdir -p "${MOODLE_VOLUME_DIR}/public"
    write_file "${MOODLE_VOLUME_DIR}/public/marker.php" "UNTOUCHED"
    moodle_migrate_to_public_layout
    file_is "${MOODLE_VOLUME_DIR}/public/marker.php" "UNTOUCHED"
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-public-migration-*.tar.gz 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "runs at most once: a second call is a no-op" {
    moodle_migrate_to_public_layout
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-public-migration-*.tar.gz | wc -l"
    [ "$output" -eq 1 ]
    write_file "${MOODLE_VOLUME_DIR}/public/admin/index.php" "ADMIN-CHANGED-AFTER-FIRST-MIGRATION"

    moodle_migrate_to_public_layout

    file_is "${MOODLE_VOLUME_DIR}/public/admin/index.php" "ADMIN-CHANGED-AFTER-FIRST-MIGRATION"
    run bash -c "ls '${MOODLE_DATA_DIR}'/moodle-pre-public-migration-*.tar.gz | wc -l"
    [ "$output" -eq 1 ]
}

@test "can be disabled via MOODLE_SKIP_PUBLIC_MIGRATION" {
    export MOODLE_SKIP_PUBLIC_MIGRATION="yes"
    moodle_migrate_to_public_layout
    [ ! -e "${MOODLE_VOLUME_DIR}/public" ]
}
