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
- [ ] `.gitignore`/package hygiene check — make sure `.ruff_cache/`,
      `__pycache__/`, and any other dev-only cruft won't end up inside the
      distributed `.plasmoid` zip
- [ ] Packaging script that builds `knvtop.plasmoid` (a zip of
      `com.daevid.knvtop/`'s contents, metadata.json at the zip root) —
      the file format store.kde.org and Plasma's "Install from local file"
      both expect
- [ ] Test-install the built `.plasmoid` via `kpackagetool6` (or the
      equivalent local install path) to confirm the zip is structured
      correctly before it ever goes near the Store
- [ ] Draft store listing copy (title, tagline, longer description, tags/
      category) as a doc you can paste into the submission form as-is
- [ ] Screenshots for the listing (compact panel view + expanded popup) —
      can capture these via spectacle same as we've been doing all session

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
