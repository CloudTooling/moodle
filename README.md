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

Root-level core content outside `public/` (`admin/cli`, `lib/` bootstrap files, `vendor/`,
`composer.json`/`composer.lock`) is replaced wholesale on refresh, and a `composer.lock` that
differs from the image's triggers a refresh too. The list of files Moodle has removed is read
from the shipped image's own `public/lib/upgradelib.php` at runtime, and those leftovers are
stripped on every boot, so crossing a new major version needs no manual list maintenance.

### Third-party plugins

Declare third-party plugins in the chart values instead of installing them through the admin UI.
The image installs or upgrades them on every boot, before `admin/cli/upgrade.php` runs, so a
plugin upgrade is a reviewed values change that ships together with the core bump that needs it:

```yaml
plugins:
  - component: mod_hvp
    # Moodle plugins directory download for one exact version (zip with bundled submodules)
    url: https://marketplace.moodle.com/api/plugins/mod_hvp/versions/2026090101/download
    sha256: 188c67fd3d3383909b93564b02ee0eb50e225169ffc2dafb551ddec01d6a5845
```

- `component` (required): the frankenstyle name. The install directory comes from the plugin
  type in `lib/components.json`, e.g. `mod_hvp` → `public/mod/hvp`.
- `url` (required): a `.zip` or `.tar.gz`, either `https://` or `file://`. A single top-level
  folder in the archive is unwrapped. GitHub source archives miss git submodules, so prefer the
  plugins directory download.
- `sha256` (optional, recommended): the archive is verified before anything on disk changes.
- `path` (optional): the install directory relative to the code root. Only needed for subplugin
  types, e.g. `public/mod/assign/feedback/example`.

A plugin is only downloaded again when its `url`/`sha256` changes (tracked in a
`.moodle-plugin-source` marker inside the plugin directory). The previous version is backed up
to `moodledata/moodle-plugin-backup-<component>-<timestamp>.tar.gz` first. A failed download,
checksum or archive check stops the boot *before* the upgrade touches the database. Removing an
entry does **not** uninstall the plugin, so uninstall it under Site administration first. The
image env var behind this is `MOODLE_PLUGINS`, a JSON array of the same objects.

Before bumping the image across a Moodle major version, check that every declared plugin's
release supports the target version, and bump it in the same change if needed.

#### Recovering from an incompatible plugin

Plugins installed through the admin UI, or copied onto the volume by hand, survive every refresh
**as-is**. Once one is incompatible with the new core, the upgrade aborts and the pod
crash-loops, e.g. on Moodle 5.3:

```text
The plugin mod_hvp is defective or outdated; sorry you cannot continue.
Error code: detectedbrokenplugin
```

By then the core DB upgrade has usually completed, so **rolling the image back is not an
option**. Fix forward instead:

1. See the actual error: set `BITNAMI_DEBUG=true` (chart `extraEnvVars`, or
   `kubectl set env deploy/moodle BITNAMI_DEBUG=true`). Without it, `admin/cli/upgrade.php`
   output is swallowed and the log just stops at `Running database upgrade`.
2. Preferred: declare the plugin under `plugins` at a compatible release and redeploy. The
   manually installed copy is backed up and replaced on the next boot.
3. If you can't redeploy: scale the deployment to 0 and start a temporary pod using the same
   image, with the PVC mounted at `/bitnami/moodle` (subPath `moodle`) and `/bitnami/moodledata`
   (subPath `moodledata`), running as the same user (`1001`, group `0`), with
   `command: ["sleep", "3600"]`. Back up `/bitnami/moodle/public/<type>/<name>` into
   moodledata, replace it with a compatible release, delete the pod and scale back to 1.

## Releasing

Run the **Create release** workflow (`.github/workflows/release.yml`, built on
[`m13tLabs/gh-actions-templates`](https://github.com/m13tLabs/gh-actions-templates)'
`docker-release.yml`) from `develop`:

- `release_version`: the Moodle version, optionally with an image revision for
  image-only fixes (e.g. `5.3.0.1`).
- `chart_version` (optional): the Helm chart version. Empty patch-bumps the current
  one; an explicit `X.Y.Z` must be higher than the current chart version.
- `draft_release`: create the GitHub release as a draft (default).

The release commit pins the chart to the image it publishes
([`scripts/pin-release-version.sh`](scripts/pin-release-version.sh)): `image.tag`,
`appVersion` and the `annotations.images` entry become the release version, and
the chart README is regenerated with helm-docs. The chart is then pushed to
`oci://ghcr.io/cloudtooling/helm-charts`. Don't bump these by hand or via Renovate;
the chart must only ever point at an image a release has already published.
