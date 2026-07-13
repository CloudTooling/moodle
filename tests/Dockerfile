# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Minimal environment for unit-testing the rootfs/prebuildfs shell libraries with BATS.
# Deliberately skips the PHP/Apache/Moodle component download the production Dockerfile
# needs, since the libraries under test are plain bash sourced at their real /opt/bitnami
# paths, not the compiled components.

FROM docker.io/bitnami/minideb:bookworm

COPY prebuildfs /
RUN install_packages ca-certificates findutils git tar
RUN git clone --depth 1 --branch v1.11.1 https://github.com/bats-core/bats-core.git /tmp/bats-core \
    && /tmp/bats-core/install.sh /usr/local \
    && rm -rf /tmp/bats-core

COPY rootfs /

ENV HOME="/tmp"
USER 1001

WORKDIR /tests
COPY tests/*.bats /tests/

ENTRYPOINT ["bats"]
CMD ["/tests"]
