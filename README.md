# moodle

Moodle Docker Image &amp; Helm Chart. Based on Bitnami Charts and Images

[![Docker Stars](https://img.shields.io/docker/pulls/cloudtooling/moodle)](https://hub.docker.com/r/cloudtooling/moodle/)
[![Docker Stars](https://img.shields.io/docker/stars/cloudtooling/moodle.svg)](https://hub.docker.com/r/cloudtooling/moodle/)

## Usage

oci://ghcr.io/cloudtooling/helm-charts/moodle


cloudtooling/moodle

## Upgrading

The first boot after upgrading a persisted volume past Moodle 5.1 triggers an in-place
migration to the new `/public` document root layout (`moodle_migrate_to_public_layout` in
`rootfs/opt/bitnami/scripts/libmoodle.sh`): it writes a full backup tarball of the old
codebase to `moodledata`, then copies the codebase twice (once into staging, once back).
On top of that, Kubernetes may recursively `chown` the whole persisted volume for the pod's
`fsGroup` before the container even starts (the `VolumePermissionChangeInProgress` event).
Both are one-off, disk-size-dependent, and can comfortably run past this chart's default
`startupProbe`/`livenessProbe`/`readinessProbe` thresholds, causing the kubelet to kill and
restart the pod mid-migration.

Before rolling out a version that crosses the 5.1 boundary, temporarily raise
`startupProbe.failureThreshold` (and/or `initialDelaySeconds`) generously for that one
rollout, then revert once the migration has completed. Setting
`podSecurityContext.fsGroupChangePolicy: OnRootMismatch` avoids re-chowning the whole volume
on every subsequent rollout, but does not by itself speed up this first migration.