# moodle

Moodle Docker Image &amp; Helm Chart. Based on Bitnami Charts and Images

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/moodle)](https://artifacthub.io/packages/helm/moodle/moodle)
[![Docker Stars](https://img.shields.io/docker/pulls/cloudtooling/moodle)](https://hub.docker.com/r/cloudtooling/moodle/)
[![Docker Stars](https://img.shields.io/docker/stars/cloudtooling/moodle.svg)](https://hub.docker.com/r/cloudtooling/moodle/)

## Usage

### Docker image

Published to [Docker Hub](https://hub.docker.com/r/cloudtooling/moodle/tags) by
[`.github/workflows/build.yml`](.github/workflows/build.yml): `next` and a numeric
`<run-id>` tag on every push to `develop`, and `latest` plus the released version (e.g.
`5.2.1`) whenever a version tag is pushed. Pin to a released version tag in anything other
than a throwaway environment — `next`/`latest` move.

```console
docker pull cloudtooling/moodle:5.2.1
```

It's a drop-in for `bitnami/moodle`: same environment variables (`MOODLE_DATABASE_*`,
`MOODLE_USERNAME`/`MOODLE_PASSWORD`, `SMTP_*`, ...), same `/bitnami/moodle` +
`/bitnami/moodledata` volume layout. See [`docker-compose.yml`](docker-compose.yml) for a
minimal local run against real MariaDB (`docker compose up`).

### Helm chart

[`charts/moodle`](charts/moodle) is not yet published to a chart repository or OCI registry
from CI — consume it directly from a checkout of this repo until that's wired up:

```console
helm install my-release cloudtooling/moodle:0.1. \
  --set image.tag=5.2.1 \
  --set moodleUsername=admin \
  --set moodlePassword=<password> \
  --set externalDatabase.host=<mariadb-host> \
  --set externalDatabase.password=<db-password>
```

See [`charts/moodle/values.yaml`](charts/moodle/values.yaml) for the full parameter list
(it's a fork of Bitnami's chart, so upstream's
[parameter docs](charts/moodle/README.md) mostly still apply).

## Upgrading a persisted install

Bitnami-style images normally freeze a persisted install's codebase forever after its first
boot (`restore_persisted_app` just symlinks back whatever was captured then) — bumping
`MOODLE_VERSION` in the image would otherwise have zero effect on any already-running
deployment. This fork refreshes the persisted codebase on every boot where it differs from
the image, in two layers (`rootfs/opt/bitnami/scripts/libmoodle.sh`, see
[`CLAUDE.md`](CLAUDE.md) for the full story):

- `moodle_migrate_to_public_layout`: a one-time structural migration, triggered the first boot
  against a volume from before Moodle 5.1, into the new `/public` document root layout.
- `moodle_refresh_core_on_version_change`: runs on every boot after that, comparing the
  persisted codebase's `version.php` against the image's; refreshes core code on any
  mismatch — patch bumps included, not just major-version jumps. Disable with
  `MOODLE_SKIP_CORE_REFRESH=yes`.

Both back up the old codebase to a tarball in `moodledata` first, then merge it with the fresh
image's `public/` tree (core files updated, anything only in the persisted install —
customizations, third-party plugins — survives), and strip out core files and plugins Moodle
itself has since removed (the `qtype_random`-class crash and "Mixed Moodle versions detected"
upgrade-abort both come from exactly this kind of leftover, and are now handled for you). That
merge, plus the real `admin/cli/upgrade.php` run that follows it, can take noticeably longer
than a normal restart, especially on an install that's several Moodle versions behind.

The chart's `startupProbe` (enabled by default, generous `failureThreshold`) exists
specifically to give this first boot room without needing to touch `livenessProbe` —
`startupProbe` only gates the pod's *first* successful boot, then normal liveness/readiness
take over, so there's nothing to remember to revert afterward. Kubernetes may also
recursively `chown` the whole persisted volume for the pod's `fsGroup` before the container
even starts (the `VolumePermissionChangeInProgress` event) — set
`podSecurityContext.fsGroupChangePolicy: OnRootMismatch` to skip that on every rollout after
the first.

If you're jumping across a version boundary this fork hasn't crossed before, refresh
`MOODLE_KNOWN_REMOVED_CORE_FILES` and `MOODLE_KNOWN_REMOVED_PLUGIN_DIRS` in `libmoodle.sh`
from the target version's own `public/lib/upgradelib.php` first — see `CLAUDE.md`.