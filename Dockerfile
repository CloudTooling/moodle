# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

FROM docker.io/bitnami/minideb:bookworm

# renovate: datasource=github-tags depName=moodle/moodle
ARG MOODLE_VERSION="5.2.3"
ARG DOWNLOADS_URL="downloads.bitnami.com/files/stacksmith"
ARG EXTRA_LOCALES
ARG TARGETARCH
ARG WITH_ALL_LOCALES="no"

LABEL org.opencontainers.image.authors='Martin Reinhardt (martin@m13t.de)' \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.version=$MOODLE_VERSION \
    org.opencontainers.image.url='https://hub.docker.com/r/cloudtooling/moodle' \
    org.opencontainers.image.documentation='https://github.com/CloudTooling/moodle' \
    org.opencontainers.image.source='https://github.com/CloudTooling/moodle.git' \
    org.opencontainers.image.licenses='APACHE-2.0'

ENV OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="debian-12" \
    OS_NAME="linux"

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
# Install required system packages and dependencies
RUN install_packages acl ca-certificates cron curl libaudit1 libbrotli1 libbsd0 libbz2-1.0 libcap-ng0 libcom-err2 libcrypt1 libcurl4 libedit2 libexpat1 libffi8 libfftw3-double3 libfontconfig1 libfreetype6 libgcc-s1 libgcrypt20 libglib2.0-0 libgmp10 libgnutls30 libgomp1 libgpg-error0 libgssapi-krb5-2 libhashkit2 libhogweed6 libicu72 libidn2-0 libjpeg62-turbo libk5crypto3 libkeyutils1 libkrb5-3 libkrb5support0 liblcms2-2 libldap-2.5-0 liblqr-1-0 libltdl7 liblzma5 libmagickcore-6.q16-6 libmagickwand-6.q16-6 libmd0 libmemcached11 libncurses6 libnettle8 libnghttp2-14 libonig5 libp11-kit0 libpam0g libpcre2-8-0 libpng16-16 libpsl5 libreadline8 librtmp1 libsasl2-2 libsodium23 libsqlite3-0 libssh2-1 libssl3 libstdc++6 libsybdb5 libtasn1-6 libtidy5deb1 libtinfo6 libunistring2 libuuid1 libwebp7 libx11-6 libxau6 libxcb1 libxdmcp6 libxext6 libxml2 libxslt1.1 libzip4 libzstd1 locales openssl procps zlib1g
RUN --mount=type=secret,id=downloads_url,env=SECRET_DOWNLOADS_URL \
    DOWNLOADS_URL=${SECRET_DOWNLOADS_URL:-${DOWNLOADS_URL}} ; \
    mkdir -p /tmp/bitnami/pkg/cache/ ; cd /tmp/bitnami/pkg/cache/ || exit 1 ; \
    COMPONENTS=( \
      "render-template-1.0.9-167-linux-${OS_ARCH}-debian-12" \
      "php-8.4.22-2-linux-${OS_ARCH}-debian-12" \
      "apache-2.4.68-1-linux-${OS_ARCH}-debian-12" \
      "postgresql-client-14.23.0-0-linux-${OS_ARCH}-debian-12" \
      "mysql-client-12.3.2-1-linux-${OS_ARCH}-debian-12" \
      "libphp-8.4.22-1-linux-${OS_ARCH}-debian-12" \
      # NOTE: "moodle-${MOODLE_VERSION}-0-linux-${OS_ARCH}-debian-12" intentionally omitted here, \
      # see the TEMPORARY OVERRIDE block below. \
    ) ; \
    for COMPONENT in "${COMPONENTS[@]}"; do \
      if [ ! -f "${COMPONENT}.tar.gz" ]; then \
        curl -SsLf "https://${DOWNLOADS_URL}/${COMPONENT}.tar.gz" -O ; \
      fi ; \
      curl -SsLf "https://${DOWNLOADS_URL}/${COMPONENT}.tar.gz.sha256" -O ; \
      sha256sum -c "${COMPONENT}.tar.gz.sha256" ; \
      tar -zxf "${COMPONENT}.tar.gz" -C /opt/bitnami --strip-components=2 --no-same-owner ; \
      rm -rf "${COMPONENT}.tar.gz" "${COMPONENT}.tar.gz.sha256" ; \
    done ;
# TEMPORARY OVERRIDE: Bitnami has not published a "moodle-${MOODLE_VERSION}" stacksmith
# package yet (only up to 5.2.2 as of 2026-09-13), so build the Moodle payload ourselves
# from the official upstream release + composer, mirroring what Bitnami's package normally
# provides (upstream release tree extracted to /opt/bitnami/moodle, with vendor/ installed
# via composer). Once Bitnami publishes a real "moodle-${MOODLE_VERSION}-0-..." package,
# delete this RUN step and restore the COMPONENTS entry commented out above.
# download.moodle.org sits behind Cloudflare bot protection that consistently 403s requests
# from GitHub Actions' (and other datacenter) IP ranges, so pull the source straight from the
# moodle/moodle GitHub tag instead (verified byte-for-byte equivalent to the moodle.org release
# tarball, save for a git-only .gitignore and an informational, unused githash.php).
# curl retries + a browser User-Agent below guard against getcomposer.org's occasional hiccups.
RUN MOODLE_BUILD_CURL_OPTS=(--fail --silent --show-error --location --retry 5 --retry-all-errors --retry-delay 5 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36") ; \
    mkdir -p /tmp/moodle-build /opt/bitnami/moodle ; cd /tmp/moodle-build ; \
    curl "${MOODLE_BUILD_CURL_OPTS[@]}" "https://github.com/moodle/moodle/archive/refs/tags/v${MOODLE_VERSION}.tar.gz" -o moodle.tar.gz ; \
    tar -zxf moodle.tar.gz -C /opt/bitnami/moodle --strip-components=1 ; \
    curl "${MOODLE_BUILD_CURL_OPTS[@]}" https://getcomposer.org/installer -o composer-setup.php ; \
    /opt/bitnami/php/bin/php composer-setup.php --quiet ; \
    /opt/bitnami/php/bin/php composer.phar install --no-dev --optimize-autoloader --no-interaction --working-dir=/opt/bitnami/moodle ; \
    cd / ; rm -rf /tmp/moodle-build ;
RUN apt-get update && apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists /var/cache/apt/archives
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true
RUN sed -i -e '/pam_loginuid.so/ s/^#*/#/' /etc/pam.d/cron
RUN update-locale LANG=C.UTF-8 LC_MESSAGES=POSIX && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales && \
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
RUN echo 'en_AU.UTF-8 UTF-8' >> /etc/locale.gen
RUN /opt/bitnami/scripts/locales/generate-locales.sh
RUN uninstall_packages curl

COPY rootfs /
RUN /opt/bitnami/scripts/apache/postunpack.sh
RUN /opt/bitnami/scripts/php/postunpack.sh
RUN /opt/bitnami/scripts/apache-modphp/postunpack.sh
RUN /opt/bitnami/scripts/moodle/postunpack.sh
RUN /opt/bitnami/scripts/mysql-client/postunpack.sh
ENV APACHE_HTTPS_PORT_NUMBER="" \
    APACHE_HTTP_PORT_NUMBER="" \
    APP_VERSION="${MOODLE_VERSION}" \
    BITNAMI_APP_NAME="moodle" \
    IMAGE_REVISION="5" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    PATH="/opt/bitnami/common/bin:/opt/bitnami/php/bin:/opt/bitnami/php/sbin:/opt/bitnami/apache/bin:/opt/bitnami/postgresql/bin:/opt/bitnami/mysql/bin:$PATH"

EXPOSE 8080 8443

ENTRYPOINT [ "/opt/bitnami/scripts/moodle/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/moodle/run.sh" ]
