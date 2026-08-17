---
title: "Archiving Blink Camera Clips to a Synology NAS"
description: >-
  How I automate Blink cloud clip downloads to a Synology NAS with Docker,
  saved OAuth tokens, and DSM Task Scheduler—no Sync Module 2 hardware required.
date: 2026-08-13 14:00:00 -0500
categories: [Homelab, Automation]
tags: [homelab, automation, synology, blink]
permalink: /posts/blink-camera-synology-archive/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. This describes a personal
> archival setup for cameras and footage I own. Blink has no public third-party
> API; anything built on reverse-engineered clients can break when Amazon
> changes authentication.
{: .prompt-info }

I run a handful of older Blink cameras on a grandfathered free cloud plan. The
app is fine for glancing at events. It is a terrible long-term archive.

What I wanted was boring and reliable: pull motion clips on a schedule, drop
them on the Synology with a predictable folder layout, skip duplicates, and
re-authenticate only when Blink’s tokens actually die—not every hour. (Same
“capture elsewhere, archive on the NAS” idea as my
[Tesla Sentry → Synology](/posts/tesla-sentry-synology-archive/)
setup—different source, same destination discipline.)

I keep the implementation in a **private** GitHub repo. This post covers the
architecture and ops notes, not a public install guide for that code.

## Constraints that shaped the design

- **No Sync Module 2 USB path.** Projects like BlinkPi are excellent if you can
  present a fake USB drive to an SM2. I do not have that hardware, so cloud
  download was the only viable path.
- **No UI automation.** Scraping the mobile app with device farms is fragile and
  overkill for personal archival.
- **No Blink subscription purchased “for API access.”** A subscription does not
  give you an official developer API. It changes cloud retention and some local
  USB behaviors; it is not a stable integration contract.
- **Synology-first.** Container Manager / Docker Compose, DSM Task Scheduler,
  clips on a dedicated share.

## What exists in the ecosystem

| Approach | Verdict for my setup |
| --- | --- |
| Official Blink public API | Does not exist for third-party clip download |
| [`blinkpy`](https://github.com/fronzbot/blinkpy) (Home Assistant’s library) | Best-maintained unofficial client; supports video metadata + download |
| USB gadget archivers (BlinkPi, Watchman, …) | Great if you have Sync Module 2; not applicable here |
| Stale Docker images / old PowerShell downloaders | Easy to find; often broken after 2025 OAuth changes |

So the shape of the solution is small: a Python job on top of current
`blinkpy`, packaged as a one-shot container, scheduled by DSM Task Scheduler.

## Architecture

```text
Blink cloud (clips + OAuth)
        │
        ▼
  blink-archiver container   ← docker compose run --rm
  (list metadata → download new IDs)
        │
        ▼
  /volume1/blink/archive/<Camera>/YYYY/MM/DD/*.mp4
  /volume1/blink/.state/   (credentials, seen IDs, watermark, logs)
```

Important separation on the NAS: **project files**, **clip archive**, and
**state** are not the same directory tree. Mounting the whole share as the
archive root mixes `Dockerfile` with `Driveway/2026/08/13/…`. Clips go under
`archive/`; tokens and run state go under `.state/`.

### Naming

Blink reports camera names with spaces (`East Backyard`). On disk I strip
spaces so paths stay shell- and rsync-friendly (`EastBackyard/`). Matching for
filters still uses whatever Blink returns; default is “all cameras.”

Example object path:

```text
/volume1/blink/archive/EastBackyard/2026/08/13/20260813T143022Z_eastbackyard_<id>.mp4
```

### Idempotency

Each media item gets a stable clip ID (Blink’s ID when present, otherwise a
hash of the media path). Before download:

1. Skip if the ID is already in `seen.json`
2. Skip if the destination file already exists
3. Write to `*.partial`, then rename
4. Only then record the ID

A lookback watermark (for example 48 hours) means a failed mid-run still
re-lists recent clips; `seen.json` prevents double copies.

## Auth and MFA (the part that actually hurts)

Amazon pushed Blink’s login flow through several OAuth changes in late 2025.
Password-grant flows died; libraries had to catch up. Unattended archival only
works if you:

1. Bootstrap **once** interactively (email/password + 2FA)
2. Persist the full credential JSON (access + refresh material + device IDs)
3. Save credentials again after every successful run so rotated refresh tokens
   are not lost
4. Fail loudly when MFA is required again—do not spin on bad logins

In practice I re-auth when a scheduled run exits with an auth failure, after a
password change, or after another Blink OAuth change breaks login. Hourly jobs
should not prompt for 2FA.

One subtlety: share a single `aiohttp` `ClientSession` between `Blink` and
`Auth`. If `Auth` opens its own session and you only close yours, you get
noisy “Unclosed client session” errors even when login succeeded.

## Synology ops

### Permissions

DSM often denies non-admin access to `/var/run/docker.sock`. If `docker compose
build` returns permission denied, use an administrator account or `sudo`, and
run Task Scheduler as a user that can talk to Docker.

### Env files and File Station

Copies to the NAS frequently **drop dotfiles**. If `.env.example` never
arrived, ship a non-hidden `env.example` too, then run `cp env.example .env`
on the box.

### Schedule

Prefer DSM Task Scheduler over a forever-running sidecar:

```bash
#!/bin/sh
cd /volume1/blink || exit 1
/usr/local/bin/docker compose run --rm archiver >> /volume1/blink/.state/cron.log 2>&1
```

Every **30–60 minutes** is enough for free-plan retention without hammering
Blink. Do not poll every minute.

### Observability when containers are `--rm`

`docker compose logs` will not help after the task finishes. Use:

- Task Scheduler’s result / history UI
- `.state/cron.log` (stdout/stderr redirect)
- `.state/last_success.txt` as a freshness signal
- A tiny health command that fails if last success is too old

Optional: webhook on non-zero exit (ntfy, Slack incoming webhook, etc.).

## Validation checklist I actually used

1. Interactive bootstrap → credentials file written; camera list printed
2. `DRY_RUN=true` → clips listed, zero files written
3. One real run → files appear under `archive/<Camera>/…`
4. Immediate second run → downloads stay at zero (dedupe works)
5. Task Scheduler “Run” once → `cron.log` and `last_success.txt` update
6. Compare one clip timestamp in the Blink app to the NAS path

## Risks I am accepting

- **Unofficial API / ToS gray area**, even for personal footage I own
- **Auth breakage** whenever Blink changes OAuth again—mitigate by pinning
  `blinkpy`, watching HA/blinkpy releases, and keeping a one-shot re-bootstrap
  path ready
- **Rate limits / lockouts** if you schedule too aggressively
- **Cloud retention** on a free plan: if a clip expires before your interval,
  it is gone; schedule inside the retention window

## Takeaways

If you have Sync Module 2, USB-local archival is often cleaner than fighting
cloud OAuth. If you do not—as I do not—the maintainable path today is still
`blinkpy` plus a thin, idempotent downloader on the NAS.

Keep the scheduler dumb, the state directory sacred, and the archive tree
boring. Most of the failure modes are auth and permissions, not video codecs.
{: .prompt-tip }

## Related posts

- [Tesla Sentry Footage to Synology NAS with a Raspberry Pi](/posts/tesla-sentry-synology-archive/)
