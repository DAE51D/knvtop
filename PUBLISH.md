# Publishing knvtop to store.kde.org — checklist

Split into two groups: things that can be done in this repo/session, and
things that need your own KDE Identity login (store submission is a web
form under your account — not something an agent session can do for you,
account creation and credential entry are off-limits regardless of
permission mode).

## Local prep (this session can do these)

- [x] Add `LICENSE` file with the full LGPL-2.1-or-later text (metadata.json
      already declares this license; there's no LICENSE file in the repo yet)
- [x] "Service not running" detection in the popup — if the D-Bus backend
      isn't reachable, show setup instructions (the systemd steps from
      README.md) instead of a blank/broken-looking popup. This matters for
      a store listing since installing the plasmoid alone doesn't install
      the backend service.
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
      --type Plasma/Applet --upgrade knvtop-1.0.0.plasmoid` installed
      cleanly, files match the repo exactly, plasmashell reloaded with no
      errors
- [x] Draft store listing copy (title, tagline, longer description, tags/
      category) — see `STORE_LISTING.md`. Also flags a real blocker: the
      repo lives on a private LAN-only Gitea, and a public listing needs a
      publicly-reachable source link (see that file's note)
- [~] Screenshots for the listing — `screenshots/compact-panel.png`
      captured (safe, no interaction needed). The two popup screenshots
      (LLM cards view + full process view) need the widget clicked open;
      given tonight's earlier close call with synthetic clicks, easier and
      safer for you to grab those two yourself — you've already sent great
      examples of both in this conversation

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
