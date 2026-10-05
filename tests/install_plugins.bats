#!/usr/bin/env bats
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Covers moodle_install_plugins() in rootfs/opt/bitnami/scripts/libmoodle.sh, which installs the
# third-party plugins pinned in MOODLE_PLUGINS into the codebase before admin/cli/upgrade.php
# runs - so a plugin upgrade is a reviewed config change, not manual surgery on the volume.

setup() {
    export BITNAMI_ROOT_DIR="${BATS_TEST_TMPDIR}/opt/bitnami"
    export BITNAMI_VOLUME_DIR="${BATS_TEST_TMPDIR}/bitnami"
    export MOODLE_BASE_DIR="${BITNAMI_ROOT_DIR}/moodle"
    export MOODLE_VOLUME_DIR="${BITNAMI_VOLUME_DIR}/moodle"
    export MOODLE_DATA_DIR="${BITNAMI_VOLUME_DIR}/moodledata"
    mkdir -p "$MOODLE_BASE_DIR" "$MOODLE_VOLUME_DIR" "$MOODLE_DATA_DIR"

    # shellcheck disable=SC1091
    . /opt/bitnami/scripts/libmoodle.sh
    export PHP_BIN_DIR=/usr/bin

    write_file "${MOODLE_VOLUME_DIR}/lib/components.json" '{"plugintypes": {"mod": "public/mod", "local": "public/local"}}'
    write_file "${MOODLE_VOLUME_DIR}/public/mod/forum/version.php" "CORE-FORUM"

    ARCHIVES="${BATS_TEST_TMPDIR}/archives"
    mkdir -p "$ARCHIVES"
}

write_file() {
    mkdir -p "$(dirname "$1")"
    printf '%s' "$2" >"$1"
}

file_is() {
    [ -f "$1" ]
    [ "$(cat "$1")" = "$2" ]
}

# make_plugin <dir-name-inside-archive> <component> <release> - stages a plugin source tree
make_plugin() {
    local -r src="${BATS_TEST_TMPDIR}/src/$1"
    rm -rf "${BATS_TEST_TMPDIR}/src"
    write_file "${src}/version.php" "<?php \$plugin->component = '$2'; \$plugin->release = '$3';"
    write_file "${src}/lib.php" "LIB-$3"
}

make_tgz() {
    tar -czf "${ARCHIVES}/$1" -C "${BATS_TEST_TMPDIR}/src" .
    echo "${ARCHIVES}/$1"
}

make_zip() {
    php -r '
        $zip = new ZipArchive(); $zip->open($argv[1], ZipArchive::CREATE);
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($argv[2], FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) { $zip->addFile($f->getPathname(), substr($f->getPathname(), strlen($argv[2]) + 1)); }
        $zip->close();' "${ARCHIVES}/$1" "${BATS_TEST_TMPDIR}/src"
    echo "${ARCHIVES}/$1"
}

@test "is a no-op when MOODLE_PLUGINS is unset" {
    unset MOODLE_PLUGINS
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ ! -e "${MOODLE_VOLUME_DIR}/public/mod/hvp" ]
}

@test "installs a plugin from a zip wrapped in a single top-level folder" {
    make_plugin hvp mod_hvp 1.28.4
    archive="$(make_zip hvp.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.28.4"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/forum/version.php" "CORE-FORUM"
}

@test "installs a plugin from a GitHub-style tar.gz" {
    make_plugin moodle-local_probe-abc123 local_probe 2.0
    archive="$(make_tgz probe.tar.gz)"
    export MOODLE_PLUGINS="[{\"component\": \"local_probe\", \"url\": \"file://${archive}\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/local/probe/lib.php" "LIB-2.0"
}

@test "upgrades an existing plugin, dropping its old files and backing it up first" {
    write_file "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.27.2"
    write_file "${MOODLE_VOLUME_DIR}/public/mod/hvp/removed_in_new_release.php" "OLD"
    make_plugin hvp mod_hvp 1.28.4
    archive="$(make_zip hvp.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.28.4"
    [ ! -e "${MOODLE_VOLUME_DIR}/public/mod/hvp/removed_in_new_release.php" ]
    run bash -c "tar -tzf '${MOODLE_DATA_DIR}'/moodle-plugin-backup-mod_hvp-*.tar.gz"
    [[ "$output" == *"hvp/removed_in_new_release.php"* ]]
}

@test "does not reinstall when the pinned url/sha256 are unchanged" {
    make_plugin hvp mod_hvp 1.28.4
    archive="$(make_zip hvp.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    write_file "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "TOUCHED-AFTER-INSTALL"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "TOUCHED-AFTER-INSTALL"
}

@test "verifies the sha256 and leaves the installed plugin untouched on mismatch" {
    write_file "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.27.2"
    make_plugin hvp mod_hvp 1.28.4
    archive="$(make_zip hvp.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\", \"sha256\": \"$(printf '0%.0s' {1..64})\"}]"
    run moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum mismatch"* ]]
    file_is "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.27.2"
}

@test "accepts a matching sha256" {
    make_plugin hvp mod_hvp 1.28.4
    archive="$(make_zip hvp.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\", \"sha256\": \"$(sha256sum "$archive" | cut -d' ' -f1)\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/hvp/lib.php" "LIB-1.28.4"
}

@test "rejects an archive whose version.php declares a different component" {
    make_plugin hvp mod_other 1.0
    archive="$(make_zip other.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"mod_hvp\", \"url\": \"file://${archive}\"}]"
    run moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ "$status" -ne 0 ]
    [ ! -e "${MOODLE_VOLUME_DIR}/public/mod/hvp" ]
}

@test "uses an explicit path for plugin types not in components.json (subplugins)" {
    make_plugin myfeedback assignfeedback_myfeedback 1.0
    archive="$(make_zip myfeedback.zip)"
    export MOODLE_PLUGINS="[{\"component\": \"assignfeedback_myfeedback\", \"url\": \"file://${archive}\", \"path\": \"public/mod/assign/feedback/myfeedback\"}]"
    moodle_install_plugins "$MOODLE_VOLUME_DIR"
    file_is "${MOODLE_VOLUME_DIR}/public/mod/assign/feedback/myfeedback/lib.php" "LIB-1.0"
}

@test "fails on an unknown plugin type without an explicit path" {
    export MOODLE_PLUGINS='[{"component": "assignfeedback_x", "url": "file:///nonexistent.zip"}]'
    run moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"set \"path\" explicitly"* ]]
}

@test "fails on invalid JSON" {
    export MOODLE_PLUGINS='not json'
    run moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ "$status" -ne 0 ]
}

@test "fails when the archive cannot be downloaded" {
    export MOODLE_PLUGINS='[{"component": "mod_hvp", "url": "file:///nonexistent.zip"}]'
    run moodle_install_plugins "$MOODLE_VOLUME_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not download"* ]]
}
