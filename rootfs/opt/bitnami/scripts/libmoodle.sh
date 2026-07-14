#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Bitnami Moodle library

# shellcheck disable=SC1091

# Load generic libraries
. /opt/bitnami/scripts/libphp.sh
. /opt/bitnami/scripts/libfs.sh
. /opt/bitnami/scripts/libos.sh
. /opt/bitnami/scripts/libvalidations.sh
. /opt/bitnami/scripts/libpersistence.sh
. /opt/bitnami/scripts/libwebserver.sh

# Load database library
if [[ -f /opt/bitnami/scripts/libmysqlclient.sh ]]; then
    . /opt/bitnami/scripts/libmysqlclient.sh
elif [[ -f /opt/bitnami/scripts/libmysql.sh ]]; then
    . /opt/bitnami/scripts/libmysql.sh
elif [[ -f /opt/bitnami/scripts/libmariadb.sh ]]; then
    . /opt/bitnami/scripts/libmariadb.sh
fi

if [[ -f /opt/bitnami/scripts/libpostgresqlclient.sh ]]; then
    . /opt/bitnami/scripts/libpostgresqlclient.sh
elif [[ -f /opt/bitnami/scripts/libpostgresql.sh ]]; then
    . /opt/bitnami/scripts/libpostgresql.sh
fi

# Paths (relative to the public/ document root) of files Moodle core itself has removed over the
# years. Moodle's own admin/cli/upgrade.php refuses to run while any of these still exist ("Mixed
# Moodle versions detected"), since preserving old-install content that isn't part of the fresh
# image (see moodle_migrate_to_public_layout below) can leave exactly this kind of core leftover
# behind. Copied verbatim from $someexamplesofremovedfiles in public/lib/upgradelib.php as shipped
# in this image; refresh from that file when bumping MOODLE_VERSION across a major version.
MOODLE_KNOWN_REMOVED_CORE_FILES=(
    '/availability/renderer.php'
    '/course/tests/behat/course_controls.feature'
    '/lib/amd/src/addblockmodal.js'
    '/question/qengine.js'
    '/tag/classes/manage_table.php'
    '/badges/classes/observer.php'
    '/course/request_form.php'
    '/course/templates/activitychooser.mustache'
    '/lib/tests/xmlize_test.php'
    '/message/templates/message_drawer_view_conversation_footer_unable_to_message.mustache'
    '/admin/process_email.php'
    '/badges/preferences_form.php'
    '/lib/ajax/setuserpref.php'
    '/lib/cronlib.php'
    '/question/classes/local/bank/action_column_base.php'
    '/backup/util/ui/classes/copy/copy.php'
    '/backup/util/ui/yui/build/moodle-backup-backupselectall/moodle-backup-backupselectall.js'
    '/cache/classes/interfaces.php'
    '/cache/disabledlib.php'
    '/cache/lib.php'
    '/README.txt'
    '/lib/dataformatlib.php'
    '/lib/horde/readme_moodle.txt'
    '/lib/yui/src/formchangechecker/js/formchangechecker.js'
    '/mod/forum/pix/monologo.png'
    '/question/tests/behat/behat_question.php'
    '/badges/ajax.php'
    '/course/editdefaultcompletion.php'
    '/grade/amd/src/searchwidget/group.js'
    '/lib/behat/extension/Moodle/BehatExtension/Locator/FilesystemSkipPassedListLocator.php'
    '/lib/classes/task/legacy_plugin_cron_task.php'
    '/mod/lti/ajax.php'
    '/pix/f/archive.png'
    '/user/repository.php'
    '/admin/auth_config.php'
    '/auth/yui/passwordunmask/passwordunmask.js'
    '/lib/spout/readme_moodle.txt'
    '/lib/yui/src/tooltip/js/tooltip.js'
    '/mod/forum/classes/task/refresh_forum_post_counts.php'
    '/user/amd/build/participantsfilter.min.js'
    '/user/amd/src/participantsfilter.js'
    '/admin/classes/task_log_table.php'
    '/admin/cli/mysql_engine.php'
    '/lib/babel-polyfill/polyfill.js'
    '/lib/typo3/class.t3lib_cs.php'
    '/question/tests/category_class_test.php'
    '/customfield/edit.php'
    '/lib/phpunit/classes/autoloader.php'
    '/lib/xhprof/README'
    '/message/defaultoutputs.php'
    '/user/files_form.php'
    '/grade/grading/classes/privacy/gradingform_provider.php'
    '/lib/coursecatlib.php'
    '/lib/form/htmleditor.php'
    '/message/classes/output/messagearea/contact.php'
    '/course/classes/output/modchooser_item.php'
    '/course/yui/build/moodle-course-modchooser/moodle-course-modchooser-min.js'
    '/course/yui/src/modchooser/js/modchooser.js'
    '/h5p/classes/autoloader.php'
    '/lib/adodb/readme.txt'
    '/lib/maxmind/GeoIp2/Compat/JsonSerializable.php'
    '/lib/amd/src/modal_confirm.js'
    '/lib/fonts/font-awesome-4.7.0/css/font-awesome.css'
    '/lib/jquery/jquery-3.2.1.min.js'
    '/lib/recaptchalib.php'
    '/lib/sessionkeepalive_ajax.php'
    '/lib/yui/src/checknet/js/checknet.js'
    '/question/amd/src/qbankmanager.js'
    '/lib/form/yui/src/showadvanced/js/showadvanced.js'
    '/lib/tests/output_external_test.php'
    '/message/amd/src/message_area.js'
    '/message/templates/message_area.mustache'
    '/question/yui/src/qbankmanager/build.json'
    '/lib/classes/session/memcache.php'
    '/lib/eventslib.php'
    '/lib/form/submitlink.php'
    '/lib/medialib.php'
    '/lib/password_compat/lib/password.php'
    '/lib/dml/mssql_native_moodle_database.php'
    '/lib/dml/mssql_native_moodle_recordset.php'
    '/lib/dml/mssql_native_moodle_temptables.php'
    '/auth/README.txt'
    '/calendar/set.php'
    '/enrol/users.php'
    '/enrol/yui/rolemanager/assets/skins/sam/rolemanager.css'
    '/badges/backpackconnect.php'
    '/calendar/yui/src/info/assets/skins/sam/moodle-calendar-info.css'
    '/competency/classes/external/exporter.php'
    '/mod/forum/forum.js'
    '/user/pixgroup.php'
    '/calendar/preferences.php'
    '/lib/alfresco/'
    '/lib/jquery/jquery-1.12.1.min.js'
    '/lib/password_compat/tests/'
    '/lib/phpunit/classes/unittestcase.php'
    '/lib/classes/log/sql_internal_reader.php'
    '/lib/zend/'
    '/mod/forum/pix/icon.gif'
    '/tag/templates/tagname.mustache'
    '/tag/coursetagslib.php'
    '/lib/timezone.txt'
    '/course/delete_category_form.php'
    '/admin/tool/qeupgradehelper/version.php'
    '/admin/block.php'
    '/admin/oacleanup.php'
    '/backup/lib.php'
    '/backup/bb/README.txt'
    '/lib/excel/test.php'
    '/admin/tool/unittest/simpletestlib.php'
    '/lib/minify/builder/'
    '/lib/yui/3.4.1pr1/'
    '/search/cron_php5.php'
    '/course/report/log/indexlive.php'
    '/admin/report/backups/index.php'
    '/admin/generator.php'
    '/lib/yui/2.8.0r4/'
    '/blocks/admin/block_admin.php'
    '/blocks/admin_tree/block_admin_tree.php'
)

# Directories (relative to public/) of whole plugins Moodle has removed from core. Unlike the file
# list above (individual leftover files Moodle's own upgrade check refuses to run past), these are
# plugins whose mere presence on disk can crash core bootstrap code that specifically checks for
# and warns about them (e.g. qtype_random, removed some versions back: core\component's classloader
# calls the not-yet-loaded global debugging() the first time it scans a plugin folder named this).
# Hand-curated as we encounter them; add to this list rather than special-casing them elsewhere.
MOODLE_KNOWN_REMOVED_PLUGIN_DIRS=(
    '/question/type/random'
)

########################
# Migrate a persisted Moodle codebase predating the Moodle 5.1 "/public" document root split
# Moodle 5.1 moved all web-accessible code under a new "public/" directory (keeping config.php and
# admin/cli/* at the root); the Apache vhost baked into this image already points at
# "${MOODLE_BASE_DIR}/public", so a persisted volume created by an older image (no "public/") would
# 403 forever once restore_persisted_app() symlinks it in, since Apache's document root no longer
# exists on disk. This mirrors Moodle's own documented migration (keep config.php + custom plugins,
# take fresh core code) so it also works when the running codebase itself is on the persisted volume.
# Globals:
#   MOODLE_BASE_DIR
#   MOODLE_VOLUME_DIR
#   MOODLE_DATA_DIR
#   WEB_SERVER_DAEMON_USER
#   MOODLE_KNOWN_REMOVED_CORE_FILES
#   MOODLE_KNOWN_REMOVED_PLUGIN_DIRS
# Arguments:
#   None
# Returns:
#   None
#########################
moodle_migrate_to_public_layout() {
    ! is_boolean_yes "${MOODLE_SKIP_PUBLIC_MIGRATION:-no}" || return 0
    [[ ! -e "${MOODLE_VOLUME_DIR}/public" && -d "${MOODLE_BASE_DIR}/public" ]] || return 0

    info "Persisted Moodle codebase predates the /public layout, migrating in place"

    local -r backup_file="${MOODLE_DATA_DIR}/moodle-pre-public-migration-$(date +%Y%m%d%H%M%S).tar.gz"
    info "Backing up the pre-migration codebase to ${backup_file}"
    tar -C "$(dirname "$MOODLE_VOLUME_DIR")" -czf "$backup_file" "$(basename "$MOODLE_VOLUME_DIR")"

    # Staged under MOODLE_DATA_DIR (not BITNAMI_VOLUME_DIR/"/bitnami" itself): only the
    # moodle/ and moodledata/ subPaths of the PVC are chowned to the runtime user by the
    # volume-permissions initContainer, so "/bitnami" itself is root-owned and not writable here.
    local -r staging_dir="${MOODLE_DATA_DIR}/.moodle-public-migration"
    local -r fresh_public_dir="${MOODLE_DATA_DIR}/.moodle-public-migration-fresh-public"
    rm -rf "$staging_dir" "$fresh_public_dir"
    # Start from a pristine copy of the code shipped with this image (already split correctly)
    cp -a "${MOODLE_BASE_DIR}/." "$staging_dir/"
    mv "$staging_dir/public" "$fresh_public_dir"
    mkdir -p "$staging_dir/public"

    # Relocate the site configuration, which stays at the root in the new layout too
    cp -a "${MOODLE_VOLUME_DIR}/config.php" "$staging_dir/config.php"

    # Relocate the admin area, keeping the CLI scripts at the root
    mkdir -p "$staging_dir/public/admin"
    find "${MOODLE_VOLUME_DIR}/admin" -mindepth 1 -maxdepth 1 ! -name cli -exec cp -a {} "$staging_dir/public/admin/" \;

    # Relocate the library, keeping the handful of files the root CLI bootstrap needs
    mkdir -p "$staging_dir/public/lib"
    find "${MOODLE_VOLUME_DIR}/lib" -mindepth 1 -maxdepth 1 \
        ! -name setup.php ! -name behat ! -name js ! -name components.json ! -name plugins.json ! -name thirdpartylibs.xml \
        -exec cp -a {} "$staging_dir/public/lib/" \;

    # Relocate everything else: core areas as well as any custom/third-party plugins
    find "${MOODLE_VOLUME_DIR}" -mindepth 1 -maxdepth 1 ! -name admin ! -name lib ! -name config.php \
        -exec cp -a {} "$staging_dir/public/" \;

    # Overlay the fresh core on top: core files get updated, anything found only in the old
    # install (customizations, third-party plugins) is left as migrated above.
    cp -a "${fresh_public_dir}/." "$staging_dir/public/"
    rm -rf "$fresh_public_dir"

    # The steps above preserve *any* old-install content the fresh overlay doesn't overwrite by
    # name, which includes core files/plugins Moodle itself has since removed. Clean those out
    # explicitly, matching what Moodle's own upgrade check (and this bootstrap-time plugin scan)
    # require rather than merely recommend. See the arrays' own comments above this function.
    for removed_file in "${MOODLE_KNOWN_REMOVED_CORE_FILES[@]}"; do
        [[ -e "${staging_dir}/public${removed_file}" ]] && rm -rf "${staging_dir}/public${removed_file}"
    done
    for removed_dir in "${MOODLE_KNOWN_REMOVED_PLUGIN_DIRS[@]}"; do
        [[ -e "${staging_dir}/public${removed_dir}" ]] && rm -rf "${staging_dir}/public${removed_dir}"
    done

    am_i_root && configure_permissions_ownership "$staging_dir" -d "775" -f "664" -u "$WEB_SERVER_DAEMON_USER" -g "root"

    find "${MOODLE_VOLUME_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
    # --no-preserve=timestamps: MOODLE_VOLUME_DIR is a pre-existing CSI subPath mount, not a
    # directory this process created, so "cp -a" trying to utime() the destination directory
    # itself (its final post-order step for "srcdir/.") can be refused even though writing its
    # contents just above succeeded. File timestamps carry no functional meaning for Moodle.
    cp -a --no-preserve=timestamps "${staging_dir}/." "${MOODLE_VOLUME_DIR}/"
    rm -rf "$staging_dir"

    info "Finished migrating the persisted Moodle codebase to the /public layout"
}

########################
# Validate settings in MOODLE_* env vars
# Globals:
#   MOODLE_*
# Arguments:
#   None
# Returns:
#   0 if the validation succeeded, 1 otherwise
#########################
moodle_validate() {
    debug "Validating settings in MOODLE_* environment variables..."
    local error_code=0

    # Auxiliary functions
    print_validation_error() {
        error "$1"
        error_code=1
    }
    check_empty_value() {
        if is_empty_value "${!1}"; then
            print_validation_error "${1} must be set"
        fi
    }
    check_multi_value() {
        if [[ " ${2} " != *" ${!1} "* ]]; then
            print_validation_error "The allowed values for ${1} are: ${2}"
        fi
    }
    check_yes_no_value() {
        if ! is_yes_no_value "${!1}" && ! is_true_false_value "${!1}"; then
            print_validation_error "The allowed values for ${1} are: yes no"
        fi
    }
    check_valid_port() {
        local port_var="${1:?missing port variable}"
        local err
        if ! err="$(validate_port "${!port_var}")"; then
            print_validation_error "An invalid port was specified in the environment variable ${port_var}: ${err}."
        fi
    }

    # Validate credentials
    check_empty_value "MOODLE_PASSWORD"
    if is_boolean_yes "$ALLOW_EMPTY_PASSWORD"; then
        warn "You set the environment variable ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD}. For safety reasons, do not use this flag in a production environment."
    else
        is_empty_value "${MOODLE_DATABASE_PASSWORD}" && print_validation_error "The MOODLE_DATABASE_PASSWORD environment variable is empty or not set. Set the environment variable ALLOW_EMPTY_PASSWORD=yes to allow a blank password. This is only recommended for development environments."
    fi

    if is_empty_value "$MOODLE_HOST"; then
        warn "MOODLE_HOST is not set, wwwroot will be constructed based on HTTP_HOST header which opens up vulnerability to password-reset poisoning attacks. Do not leave this variable empty in production environments."
    fi

    # Validate SMTP credentials
    if ! is_empty_value "$MOODLE_SMTP_HOST"; then
        for empty_env_var in "MOODLE_SMTP_USER" "MOODLE_SMTP_PASSWORD"; do
            is_empty_value "${!empty_env_var}" && warn "The ${empty_env_var} environment variable is empty or not set."
        done
        check_empty_value "MOODLE_SMTP_PORT_NUMBER"
        check_valid_port "MOODLE_SMTP_PORT_NUMBER"
    fi

    # Compatibility with older images where 'moodledata' was located inside the 'htdocs' directory
    if is_mounted_dir_empty "$MOODLE_DATA_DIR" && [[ -d "${MOODLE_VOLUME_DIR}/moodledata" ]]; then
        warn "Found 'moodledata' directory inside ${MOODLE_VOLUME_DIR}. Support for this configuration is deprecated and will be removed soon. Please create a new volume mountpoint at ${MOODLE_DATA_DIR}, and copy all its files there."
    fi

    # Support for MySQL and MariaDB
    check_multi_value "MOODLE_DATABASE_TYPE" "mysqli mariadb pgsql auroramysql"

    # Check that the web server is properly set up
    web_server_validate || print_validation_error "Web server validation failed"

    # Check yes/no env. variables
    check_yes_no_value "MOODLE_REVERSEPROXY"
    check_yes_no_value "MOODLE_SSLPROXY"

    return "$error_code"
}

########################
# Ensure Moodle is initialized
# Globals:
#   MOODLE_*
# Arguments:
#   None
# Returns:
#   None
#########################
moodle_initialize() {
    # Check if Moodle has already been initialized and persisted in a previous run
    local db_type db_host db_port db_name db_user db_pass
    local -r app_name="moodle"
    if ! is_app_initialized "$app_name"; then
        # Ensure Moodle persisted directories exist (i.e. when a volume has been mounted to /bitnami)
        info "Ensuring Moodle directories exist"
        for dir in "$MOODLE_VOLUME_DIR" "$MOODLE_DATA_DIR"; do
            ensure_dir_exists "$dir"
            # Use daemon:root ownership for compatibility when running as a non-root user
            am_i_root && configure_permissions_ownership "$dir" -d "775" -f "664" -u "$WEB_SERVER_DAEMON_USER" -g "root" -n
        done

        info "Trying to connect to the database server"
        db_type="$MOODLE_DATABASE_TYPE"
        db_host="$MOODLE_DATABASE_HOST"
        db_port="$MOODLE_DATABASE_PORT_NUMBER"
        db_name="$MOODLE_DATABASE_NAME"
        db_user="$MOODLE_DATABASE_USER"
        db_pass="$MOODLE_DATABASE_PASSWORD"
        [[ "$db_type" = "mariadb" || "$db_type" = "mysqli" || "$db_type" = "auroramysql" ]] && moodle_wait_for_mysql_connection "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"
        [[ "$db_type" = "pgsql" ]] && moodle_wait_for_postgresql_connection "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"

        # Create Moodle install argument list, allowing to pass custom options via 'MOODLE_INSTALL_EXTRA_ARGS'
        local -a moodle_install_args=("--dbtype=${db_type}" "--dbhost=${db_host}" "--dbport=${db_port}" "--dbname=${db_name}" "--dbuser=${db_user}" "--dbpass=${db_pass}")
        local -a extra_args
        read -r -a extra_args <<<"$MOODLE_INSTALL_EXTRA_ARGS"
        [[ "${#extra_args[@]}" -gt 0 ]] && moodle_install_args+=("${extra_args[@]}")

        # Handle --prefix (table prefix) being overridden via MOODLE_INSTALL_EXTRA_ARGS
        mdl_prefix="mdl_"
        for extra_arg in "${extra_args[@]}"; do
            if [[ $extra_arg == --prefix=* ]]; then
                mdl_prefix=${extra_arg#--prefix=}
                break
            fi
        done
        # Setup Moodle
        if ! is_boolean_yes "$MOODLE_SKIP_BOOTSTRAP"; then
            info "Running Moodle install script"
            # Create the configuration file and populate the database
            moodle_install "${moodle_install_args[@]}"
            # Configure additional settings in the database according to user inputs
            local db_remote_execute="mysql_remote_execute"
            [[ "$db_type" = "pgsql" ]] && db_remote_execute="postgresql_remote_execute"
            local -a db_execute_args=("$db_host" "$db_port" "$db_name" "$db_user" "$db_pass")
            # Configure no-reply e-mail address for SMTP
            echo "INSERT INTO ${mdl_prefix}config (name, value) VALUES ('noreplyaddress', '${MOODLE_EMAIL}')" | "$db_remote_execute" "${db_execute_args[@]}"
            # Additional Bitnami customizations
            echo "UPDATE ${mdl_prefix}course SET summary='Moodle powered by Bitnami' WHERE id='1'" | "$db_remote_execute" "${db_execute_args[@]}"
            # SMTP configuration
            if ! is_empty_value "$MOODLE_SMTP_HOST"; then
                info "Configuring SMTP credentials"
                "$db_remote_execute" "${db_execute_args[@]}" <<EOF
UPDATE ${mdl_prefix}config SET value='${MOODLE_SMTP_HOST}:${MOODLE_SMTP_PORT_NUMBER}' WHERE name='smtphosts';
UPDATE ${mdl_prefix}config SET value='${MOODLE_SMTP_USER}' WHERE name='smtpuser';
UPDATE ${mdl_prefix}config SET value='${MOODLE_SMTP_PASSWORD}' WHERE name='smtppass';
UPDATE ${mdl_prefix}config SET value='${MOODLE_SMTP_PROTOCOL}' WHERE name='smtpsecure';
EOF
            fi
        else
            info "An already initialized Moodle database was provided, it will not be re-initialized"
            # Create the configuration file
            info "Creating Moodle configuration file"
            moodle_install "${moodle_install_args[@]}" --skip-database
            # Perform Moodle database schema upgrade
            info "Running database upgrade"
            moodle_upgrade
        fi
        # Change wwwroot configuration
        moodle_configure_wwwroot
        # Turn on Moodle's reverseproxy (also sslproxy if using ssl) so we can use the reverse proxy
        if is_boolean_yes "$MOODLE_REVERSEPROXY" || is_boolean_yes "$MOODLE_SSLPROXY"; then
            moodle_configure_reverseproxy
        fi

        info "Persisting Moodle installation"
        persist_app "$app_name" "$MOODLE_DATA_TO_PERSIST"
    else
        moodle_migrate_to_public_layout

        info "Restoring persisted Moodle installation"
        restore_persisted_app "$app_name" "$MOODLE_DATA_TO_PERSIST"

        info "Trying to connect to the database server"
        db_type="$(moodle_conf_get "\$CFG->dbtype")"
        db_host="$(moodle_conf_get "\$CFG->dbhost")"
        db_port="$(moodle_conf_get "'dbport'")"
        db_name="$(moodle_conf_get "\$CFG->dbname")"
        db_user="$(moodle_conf_get "\$CFG->dbuser")"
        db_pass="$(moodle_conf_get "\$CFG->dbpass")"
        [[ "$db_type" = "mariadb" || "$db_type" = "mysqli" || "$db_type" = "auroramysql" ]] && moodle_wait_for_mysql_connection "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"
        [[ "$db_type" = "pgsql" ]] && moodle_wait_for_postgresql_connection "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"

        # Perform Moodle database schema upgrade
        info "Running database upgrade"
        moodle_upgrade

        # Skip the following check for legacy installs where moodledata is in /bitnami/moodle/moodledata and not /bitnami/moodledata (#142)
        if ! is_dir_empty "${MOODLE_DATA_DIR}/sessions"; then
            # This fixes an issue when restoring Moodle, due to cookies/sessions from a previous run being considered closed.
            # Therefore, users are unable to connect to Moodle with their cookies since the server considers them invalid.
            # The problem disappears when removing the old (invalid) session files.
            find "${MOODLE_DATA_DIR}/sessions/" -name "sess_*" -delete
        fi
    fi

    # Ensure Moodle cron jobs are created when running setup with a root user
    local -a cron_cmd=("${PHP_BIN_DIR}/php" "${MOODLE_BASE_DIR}/admin/cli/cron.php")
    if am_i_root; then
        generate_cron_conf "moodle" "${cron_cmd[*]} > /dev/null 2>> ${MOODLE_DATA_DIR}/moodle-cron.log" --run-as "$WEB_SERVER_DAEMON_USER" --schedule "*/${MOODLE_CRON_MINUTES} * * * *"
    else
        warn "Skipping cron configuration for Moodle because of running as a non-root user"
    fi

    # Avoid exit code of previous commands to affect the result of this function
    true
}

########################
# Get an entry from the Moodle configuration file (config.php)
# Globals:
#   MOODLE_*
# Arguments:
#   $1 - PHP variable name
# Returns:
#   None
#########################
moodle_conf_get() {
    local -r key="${1:?key missing}"
    debug "Getting ${key} from Moodle configuration"
    # Sanitize key (sed does not support fixed string substitutions)
    local sanitized_pattern
    sanitized_pattern="^\s*(//\s*)?$(sed 's/[]\[^$.*/]/\\&/g' <<<"$key")\s*=>?([^;,]+)[;,]"
    grep -E "$sanitized_pattern" "$MOODLE_CONF_FILE" | sed -E "s|${sanitized_pattern}|\2|" | tr -d "\"' "
}

########################
# Wait until a MySQL or MariaDB database is accessible with the currently-known credentials
# Globals:
#   *
# Arguments:
#   $1 - database host
#   $2 - database port
#   $3 - database name
#   $4 - database username
#   $5 - database user password (optional)
# Returns:
#   true if the database connection succeeded, false otherwise
#########################
moodle_wait_for_mysql_connection() {
    local -r db_host="${1:?missing database host}"
    local -r db_port="${2:?missing database port}"
    local -r db_name="${3:?missing database name}"
    local -r db_user="${4:?missing database user}"
    local -r db_pass="${5:-}"
    check_mysql_connection() {
        echo "SELECT 1" | mysql_remote_execute "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"
    }
    if ! retry_while "check_mysql_connection"; then
        error "Could not connect to the database"
        return 1
    fi
}

########################
# Wait until a PostgreSQL database is accessible with the currently-known credentials
# Globals:
#   *
# Arguments:
#   $1 - database host
#   $2 - database port
#   $3 - database name
#   $4 - database username
#   $5 - database user password (optional)
# Returns:
#   true if the database connection succeeded, false otherwise
#########################
moodle_wait_for_postgresql_connection() {
    local -r db_host="${1:?missing database host}"
    local -r db_port="${2:?missing database port}"
    local -r db_name="${3:?missing database name}"
    local -r db_user="${4:?missing database user}"
    local -r db_pass="${5:-}"
    check_postgresql_connection() {
        echo "SELECT 1" | postgresql_remote_execute "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass"
    }
    if ! retry_while "check_postgresql_connection"; then
        error "Could not connect to the database"
        return 1
    fi
}

########################
# Run Moodle install script
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   true if the script succeeded, false otherwise
#########################
moodle_install() {
    local -r http_port="${WEB_SERVER_HTTP_PORT_NUMBER:-"$WEB_SERVER_DEFAULT_HTTP_PORT_NUMBER"}"
    local -a moodle_install_args=(
        "${PHP_BIN_DIR}/php"
        "admin/cli/install.php"
        "--lang=${MOODLE_LANG}"
        "--chmod=2775"
        "--wwwroot=http://localhost:${http_port}"
        "--dataroot=${MOODLE_DATA_DIR}"
        "--adminuser=${MOODLE_USERNAME}"
        "--adminpass=${MOODLE_PASSWORD}"
        "--adminemail=${MOODLE_EMAIL}"
        "--fullname=${MOODLE_SITE_NAME}"
        "--shortname=${MOODLE_SITE_NAME}"
        "--non-interactive"
        "--allow-unstable"
        "--agree-license"
        "$@"
    )
    pushd "$MOODLE_BASE_DIR" >/dev/null || exit
    # Run as web server user to avoid having to change permissions/ownership afterwards
    if am_i_root; then
        debug_execute run_as_user "$WEB_SERVER_DAEMON_USER" "${moodle_install_args[@]}"
        # Remove write permissions for the web server to the config.php file
        configure_permissions_ownership "$MOODLE_CONF_FILE" -f "640" -u "root" -g "$WEB_SERVER_DAEMON_GROUP"
    else
        debug_execute "${moodle_install_args[@]}"
    fi
    popd >/dev/null || exit
}

########################
# Run Moodle database schema upgrade script
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   true if the script succeeded, false otherwise
#########################
moodle_upgrade() {
    pushd "$MOODLE_BASE_DIR" >/dev/null || exit
    local -a moodle_upgrade_args=(
        "${PHP_BIN_DIR}/php"
        "admin/cli/upgrade.php"
        "--non-interactive"
        "--allow-unstable"
    )
    am_i_root && moodle_upgrade_args=("run_as_user" "$WEB_SERVER_DAEMON_USER" "${moodle_upgrade_args[@]}")
    debug_execute "${moodle_upgrade_args[@]}"
    popd >/dev/null || exit
}

########################
# Configure Moodle www root
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
moodle_configure_wwwroot() {
    local -r http_port="${WEB_SERVER_HTTP_PORT_NUMBER:-"$WEB_SERVER_DEFAULT_HTTP_PORT_NUMBER"}"
    # Sanitize the hostname including quotes
    local host="${MOODLE_HOST:+"'${MOODLE_HOST}'"}"
    # Default value if the hostname isn't provided
    host="${host:-"\$_SERVER['HTTP_HOST']"}"
    # sed replacement notes:
    # - The ampersand ('&') is escaped due to sed replacing any non-escaped ampersand characters with the matched string
    # - For the replacement text to be multi-line, an \ needs to be specified to escape the newline character
    local conf_to_replace="if (empty(\$_SERVER['HTTP_HOST'])) {\\
  \$_SERVER['HTTP_HOST'] = '127.0.0.1:${http_port}';\\
}"
    if is_boolean_yes "$MOODLE_SSLPROXY"; then
        conf_to_replace="$conf_to_replace\\
\$CFG->wwwroot   = 'https://' . ${host};"
    else
        conf_to_replace="$conf_to_replace\\
if (isset(\$_SERVER['HTTPS']) \&\& \$_SERVER['HTTPS'] == 'on') {\\
  \$CFG->wwwroot   = 'https://' . ${host};\\
} else {\\
  \$CFG->wwwroot   = 'http://' . ${host};\\
}"
    fi
    replace_in_file "$MOODLE_CONF_FILE" "\\\$CFG->wwwroot\s*=.*" "$conf_to_replace"
}

########################
# Configure Moodle reverse proxy
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
moodle_configure_reverseproxy() {
    # Checking the reverseproxy setting values
    if is_boolean_yes "$MOODLE_REVERSEPROXY"; then
        content="$(sed "/^require/i \$CFG->reverseproxy = true;" "$MOODLE_CONF_FILE")"
        echo "$content" > "$MOODLE_CONF_FILE"
    fi
    # Checking the sslproxy setting values
    if is_boolean_yes "$MOODLE_SSLPROXY"; then
        content="$(sed "/^require/i \$CFG->sslproxy = true;" "$MOODLE_CONF_FILE")"
        echo "$content" > "$MOODLE_CONF_FILE"
    fi

    true
}
