# renovate: datasource=github-tags depName=moodle/moodle
ARG MOODLE_VERSION=v5.1.4

# Download Moodle 5.1 source separately
FROM alpine:3 AS moodle-src

# renovate: datasource=github-tags depName=moodle/moodle
ARG MOODLE_VERSION=v5.1.4

RUN apk add --no-cache curl tar && \
    mkdir /moodle && \
    curl -fsSL https://github.com/moodle/moodle/archive/refs/tags/${MOODLE_VERSION}.tar.gz \
    | tar -xz --strip-components=1 -C /moodle

# Final image: Bitnami base + replaced Moodle code
FROM bitnamilegacy/moodle:latest
# renovate: datasource=github-tags depName=moodle/moodle
ARG MOODLE_VERSION=v5.1.4

# Update moodle
RUN rm -rf /opt/bitnami/moodle /bitnami/moodle
COPY --from=moodle-src --chown=1001:1001 /moodle /opt/bitnami/moodle
COPY --from=moodle-src --chown=1001:1001 /moodle /bitnami/moodle

ENV APP_VERSION=$MOODLE_VERSION

# update
RUN apt-get update -y &&\
  # upgrade
  apt-get upgrade -y && \
  # clean up to slim image
  apt-get clean && apt-get autoclean && apt-get autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}
