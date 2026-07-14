# CLAUDE.md

Guidance for working in this repo, distilled from building and debugging it.

## What this repo is and why it exists

Bitnami split its container catalog in Aug/Sep 2025: free images/charts stopped receiving
updates, moved to a frozen `bitnamilegacy` mirror that may vanish entirely, with continued
updates gated behind a paid "Bitnami Secure Images" subscription. No official MoodleHQ Helm
chart exists as a replacement (only a proposal, `moodlehq/moodle-docker#335`, unshipped as of
this writing).

This repo is a self-maintained fork covering both halves of that gap:

- **`Dockerfile` + `prebuildfs/` + `rootfs/`**: rebuilds the Bitnami Moodle image from Bitnami's
  own still-public `downloads.bitnami.com/files/stacksmith` component packages (Apache, PHP,
  the various `*-client` packages, and Moodle itself), rather than depending on any
  `bitnami/*` or `bitnamilegacy/*` image. Published to `docker.io/cloudtooling/moodle`.
- **`charts/moodle/`**: a vendored-and-modified fork of Bitnami's official `moodle` Helm chart
  (last free version pulled via `helm pull oci://registry-1.docker.io/bitnamicharts/moodle`).

**Component versions move in lockstep.** The `COMPONENTS` array in the Dockerfile (php,
apache, mysql-client, postgresql-client, libphp, render-template, moodle) are a matched set
from the same Bitnami build generation — don't bump `MOODLE_VERSION` without also checking
whether the other component versions need to move together. Likewise, `prebuildfs/`/`rootfs/`
library scripts (`libfile.sh`, `libversion.sh`, `libpersistence.sh`, etc.) are themselves
versioned per Bitnami release and may need to move in lockstep with the component set —
scripts written for a newer Apache/PHP pairing aren't guaranteed compatible with an older one.

## The `/public` layout migration

Moodle 5.1 restructured the codebase: web-accessible code moved under a new `public/`
directory (keeping `config.php` and `admin/cli/*` at the root). This image's Apache vhost
always points at `${MOODLE_BASE_DIR}/public` — so a persisted volume from a pre-5.1 install
would 403 forever the moment it's restored, since the old layout has no `public/` on disk.

`moodle_migrate_to_public_layout()` in `rootfs/opt/bitnami/scripts/libmoodle.sh` handles this
once per persisted volume (guarded by `public/` already existing; skippable via
`MOODLE_SKIP_PUBLIC_MIGRATION=yes`):

1. Backs up the old codebase to a tarball in `moodledata`.
2. Builds a merged tree: starts from a full copy of the *old* volume, overlays the *fresh*
   image's `public/` on top (so core files get updated; anything only in the old install —
   customizations, third-party plugins — survives).
3. Cleans up known-obsolete leftovers the merge would otherwise carry forward (see below).
4. Swaps the merged tree into place.

Covered by `tests/migrate_public_layout.bats` (shell-level, 16 cases) and
`tests/e2e-legacy-upgrade.sh` (full container boot against real MariaDB — some of the bugs
below only reproduce via actual PHP execution, not shell-level testing). Both run in CI
(`.github/workflows/build.yml`, jobs `Bats` and `E2E`).

## Hard-won gotchas (all found via a real production incident, July 2026)

**1. `/bitnami` itself is not writable by the runtime user — only `moodle/` and
`moodledata/` are.** The chart's `volume-permissions` initContainer only chowns those two
subPath mounts; `/bitnami` is baked into the image, root-owned. Any staging/scratch directory
the migration needs must live under `MOODLE_DATA_DIR` (moodledata), not `BITNAMI_VOLUME_DIR`
directly — and preferably not under `/tmp` either, since that counts against the container's
(often small) `ephemeral-storage` quota rather than the PVC.

**2. `cp -a` into a pre-existing directory can fail on timestamp preservation even when the
content copy itself succeeds.** `cp -a "src/." "dst/"` tries to `utime()` `dst` itself as a
final step; if `dst` is a pre-existing CSI subPath mount rather than something the current
process created, that specific call can be refused for reasons that don't block writing
*into* it. Fixed by `--no-preserve=timestamps` on that copy — file timestamps have no
functional meaning for Moodle. Confirmed via `strace`: the plain `-a` form calls
`utimensat(fd, ".", ...)` on the destination; adding the flag removes that syscall entirely.

**3. `debug_execute()` (`prebuildfs/opt/bitnami/scripts/libos.sh`) silently swallows *both*
stdout and stderr unless `BITNAMI_DEBUG=true`.** This is the default in production. A crash
inside `admin/cli/upgrade.php` — including a bare PHP Fatal error — produces zero visible
output otherwise. **Always set `BITNAMI_DEBUG=true` first when chasing a stuck or crashing
upgrade**, in the chart values or via `kubectl set env deployment/moodle BITNAMI_DEBUG=true`.

**4. Long-removed Moodle plugins/files left on an old install can crash the upgrade in two
different ways**, both automatically handled by the migration function's cleanup step:
   - A whole removed plugin directory (e.g. `question/type/random`, i.e. `qtype_random`) can
     crash `core\component`'s classloader bootstrap with `Call to undefined function
     core\debugging()` — a real Moodle bug: a special-case check for this exact plugin calls
     the *global* `debugging()` before Moodle's own function libraries have loaded, and this
     only triggers on the very first cache rebuild after a persisted volume with that plugin
     present is restored. Handled by `MOODLE_KNOWN_REMOVED_PLUGIN_DIRS` in `libmoodle.sh`.
   - Individual leftover core files trip Moodle's own **"Mixed Moodle versions detected"**
     upgrade-abort check (`upgrade_stale_php_files_present()` in `public/lib/upgradelib.php`)
     — a hardcoded, version-by-version list of files Moodle itself has removed over the years.
     Handled by `MOODLE_KNOWN_REMOVED_CORE_FILES` in `libmoodle.sh`, copied verbatim from that
     function. **Both lists are point-in-time snapshots — refresh them from the shipped
     image's own `public/lib/upgradelib.php` whenever bumping `MOODLE_VERSION` across a major
     version**, since they need to stay ahead of the actual sequence of Moodle releases this
     fork jumps across.

**5. `livenessProbe` (a `tcpSocket` check on the HTTP port) can kill the pod mid-upgrade.**
Apache doesn't bind its port until `admin/cli/upgrade.php` finishes, and a real multi-version
jump (many plugins each running their own schema upgrade) can comfortably outrun typical
liveness budgets. Fixed properly in `charts/moodle/values.yaml` by enabling `startupProbe`
(HTTP check on `/login/index.php`, generous `failureThreshold`) instead of loosening
`livenessProbe`/`readinessProbe`: `startupProbe` only gates the pod's *first* successful boot,
then hands off to normal liveness/readiness — so steady-state responsiveness is unaffected,
and nobody needs to remember to manually disable probes for a migration again.

**6. Moodle's `upgraderunning` lock (a timestamp in `mdl_config`) is self-expiring, not a
manual-unlock situation.** If an upgrade gets killed mid-flight (e.g. by #5 before it was
fixed), later attempts fail fast with "Site is being upgraded, please retry later" until
`time()` passes the stored value. No direct DB surgery needed — just fix whatever killed the
previous attempt and let the natural retry through; the lock clears itself.

**7. There are two `config.php` files in the 5.1+ layout.** The real one, with actual
`$CFG->...` site config, lives at the root. `public/config.php` is a small auto-generated
loader stub (`require_once(__DIR__ . '/../config.php')`) — don't treat it as regular content
when reasoning about the directory tree (e.g. when manually flattening a volume back to a
pre-5.1 layout for testing, exclude it explicitly rather than letting a generic "move
everything" step overwrite the real root config with the stub).

## Testing notes

- `tests/e2e-legacy-upgrade.sh` boots the image against real MariaDB, does a fresh install,
  then manually flattens the volume back to a simulated pre-5.1 legacy layout (inverse of the
  migration function) with the exact stale content from gotcha #4 injected, restarts, and
  polls for a real healthy response.
- When polling a running container's HTTP port directly (e.g. via `/dev/tcp`), **include a
  `Host:` header** — Apache's default vhost (not the Moodle one) answers Host-less requests
  and will legitimately 404 a path that exists fine on the real vhost.
- When polling `docker logs` in a loop, use `--tail N` rather than fetching the full log each
  time — `BITNAMI_DEBUG=true` output is verbose, and re-fetching the whole growing log on
  every poll iteration compounds into real wall-clock overhead over a multi-minute wait.
