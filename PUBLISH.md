# Publishing knvtop to store.kde.org — checklist

Split into two groups: things that can be done in this repo/session, and
things that need your own KDE Identity login (store submission is a web
form under your account — not something an agent session can do for you,
account creation and credential entry are off-limits regardless of
permission mode).

## Local prep (this session can do these)

- [x] Add `LICENSE` file with the full LGPL-2.1-or-later text (metadata.json
      already declares this license; there's no LICENSE file in the repo yet)
- [x] "Service not running" detection in the popup — if the shared
      `knvtop-service` D-Bus daemon isn't reachable, show its install
      instructions instead of a blank/broken-looking popup. Installing the
      plasmoid alone does not install the shared daemon.
- [x] `.gitignore`/package hygiene check — `git archive` only includes
      tracked files, so `.ruff_cache/`/`__pycache__/`/etc. can't end up in
      the package without also needing to be committed first
- [x] Packaging script (`scripts/build-plasmoid.sh`) that builds
      `knvtop-<version>.plasmoid` (a zip of `com.daevid.knvtop/`'s
      contents, metadata.json at the zip root) — verified clean, 14 files,
      no dev cruft
- [x] Test-install the built `.plasmoid` via `kpackagetool6` (or the
      equivalent local install path) to confirm the zip is structured
      correctly before it ever goes near the Store — `kpackagetool6
      --type Plasma/Applet --upgrade knvtop-<version>.plasmoid` installed
      cleanly, files match the repo exactly, plasmashell reloaded with no
      errors
- [x] Draft store listing copy (title, tagline, longer description, tags/
      category) — see `STORE_LISTING.md`
- [x] Public source link — created https://github.com/DAE51D/knvtop and
      set up a Gitea push mirror (same pattern as `strix-halo-power`, just
      the other direction: Gitea stays authoritative, auto-pushes to
      GitHub on every commit + an 8h fallback interval). Verified: both
      remotes' HEAD commits match exactly.
- [x] Move the shared D-Bus sampler into
      https://github.com/DAE51D/knvtop-service. Both the widget and onvtop
      use the stable bus API; installing the widget is no longer required
      to use the daemon.
- [x] Screenshots for the listing — `compact-panel.png` captured directly;
      `tooltip.png`/`popup-expanded.png`/`config-page.png` supplied by the
      owner (needed the widget clicked open, safer for them to grab than
      another synthetic-click attempt). All four embedded in README.md.

## Needs your KDE Identity login (can't be done from here)

- [ ] Create/log into a KDE Identity account at id.kde.org (shared login
      across store.kde.org, invent.kde.org, bugs.kde.org)
- [ ] Go to store.kde.org → Plasma 6 add-ons / widgets category → "Add new
      item" (or whatever the current upload flow is labeled)
- [ ] Fill in the submission form using the drafted copy above, attach
      screenshots, upload `knvtop.plasmoid`
- [ ] Publish / submit for review

If anything in the "local prep" half unexpectedly trips a guardrail too,
skip it here and do it yourself — no need to fight it, just note which
item and move to the next one.
