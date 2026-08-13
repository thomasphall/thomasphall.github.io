# Design: Cybertruck Sentry USB → Synology NAS Blog

**Date:** 2026-08-13  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved for implementation planning

## Goal

Produce a first-person Homelab/Automation post (~1,100–1,400 words) on how a Raspberry Pi 4 running Sentry-USB-Rusty in a Cybertruck automates archiving TeslaCam/Sentry footage to a Synology NAS over SMB when home Wi‑Fi is available. Match the Blink → Synology post: architecture + practical checklist + sharp lessons—not a full upstream install clone.

## Audience & voice

- Personal site; practical, confident, no hype
- Same density and tone as `_posts/2026-08-13-blink-camera-synology-archive.md`
- Outcome: reader understands the pipeline, can reproduce with checklist + upstream docs, and knows the failure modes that matter (power, sleep, SMB identity)

## Approach

**Mirror the Blink post** (selected over narrative-first diary and comparison-led project evaluation): disclaimer → problem → constraints → stack choice → architecture → practical checklist → lessons → risks/takeaways → related posts.

## Angle

The phone app and a dumb USB stick are fine for glancebacks and terrible as a long-term archive. Put a Pi 4 in the truck as the Sentry USB gadget; let Sentry-USB-Rusty archive to Synology over SMB whenever the car reaches home Wi‑Fi.

## Front matter (draft)

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-08-13-cybertruck-sentry-synology-archive.md` |
| Title | Automating Cybertruck Sentry Footage to a Synology NAS with a Raspberry Pi |
| Description | How a Raspberry Pi 4 running Sentry-USB-Rusty in a Cybertruck archives TeslaCam/Sentry clips to a Synology share over SMB when home Wi‑Fi appears. |
| Permalink | `/posts/cybertruck-sentry-synology-archive/` |
| Categories | `[Homelab, Automation]` |
| Tags | `cybertruck, tesla, sentry-mode, sentry-usb, raspberry-pi, synology, smb, homelab` |
| Date | `2026-08-13` America/Chicago (`-0500`), after the Blink post timestamp |
| Disclaimer | Personal-site note; personal footage/hardware; third-party USB gadget software; no secrets |

## Content outline

1. **Hook** — App/USB stick works for glancebacks; bad long-term archive when the truck sleeps and the stick fills.
2. **Constraints** — Stay in-car (no nightly USB yank); use home Wi‑Fi when parked; Synology SMB; Pi 4 as USB gadget + archiver.
3. **Why this stack** — Short table: plain USB vs classic teslausb vs **Sentry-USB-Rusty** (chosen path and why).
4. **Architecture** — ASCII flow: Cybertruck → USB gadget (glovebox USB-A → Pi USB-C) → Pi 4 + Sentry-USB-Rusty → Synology share over SMB on known Wi‑Fi.
5. **Practical checklist** — Flash Pi OS Lite → install Sentry USB → wizard (known Wi‑Fi + SMB archive) → dedicated DSM user/share → glovebox cable → verify recording → confirm archive on home Wi‑Fi / manual Archive Sync. Link upstream Getting Started / Archive docs for wizard minutiae.
6. **Lessons** (only these four; numbers match scoping choices):
   1. Power + data on one USB-C cable; glovebox USB-A preferred; short data-capable cable
   2. Auto-archive when home Wi‑Fi appears; manual Archive Sync as fallback
   3. Truck sleep cuts USB power; Keep Awake / timing matters for finishing syncs
   5. Dedicated Synology DSM user + share for SMB (not admin)
7. **Risks / takeaways** — Third-party gadget software, power brownouts, incomplete sync if truck sleeps early; keep archive boring; credentials off the blog.
8. **Related posts** — Cross-link Blink Synology archive; reciprocal edit on Blink post; optional light link to storage/edge peers only if natural.

## Architecture (canonical)

```text
Cybertruck (TeslaCam / Sentry)
        │  USB gadget (glovebox USB-A → Pi USB-C)
        ▼
  Raspberry Pi 4 + Sentry-USB-Rusty
  (emulated drive + archive loop)
        │  when home Wi‑Fi + SMB
        ▼
  Synology share (e.g. teslacam/)
```

## Setup depth

Practical checklist: enough to reproduce without pasting every wizard screen. Point to [Sentry-USB-Rusty](https://github.com/Sentry-Six/Sentry-USB-Rusty) Getting Started and Archive docs for details.

## Lessons in scope

| # | Lesson |
| - | ------ |
| 1 | One-cable power+data; glovebox USB-A; short data cable |
| 2 | Auto-archive on known Wi‑Fi; manual Archive Sync fallback |
| 3 | Truck sleep cuts USB; Keep Awake / timing for sync completion |
| 5 | Dedicated Synology DSM user + share for SMB |

## Out of scope

- Full wizard screenshots / screen-by-screen install clone
- BLE charges deep-dive / drives-vs-charges troubleshooting narrative
- Old TeslaCam stick auto-import story
- NAS credentials, hostnames, IPs, or other secrets
- Publishing implementation until writing-plans + user asks for the post draft

## SEO / site wiring

- Follow `docs/seo-post-checklist.md` required front matter
- Personal-site disclaimer prompt near top
- Inline + `## Related posts` link to `/posts/blink-camera-synology-archive/`
- Reciprocal Related/inline link from Blink post to this permalink
- Update SEO checklist Homelab cluster row to include Blink + this post

## Deliverables

1. Design spec (this file) — committed
2. Implementation plan (via writing-plans skill) — after user reviews this spec
3. Post draft + Blink reciprocal link + SEO checklist update — after plan approval

## Publish path (when implementing)

1. Feature branch from `main`
2. Add Chirpy-compatible post under `_posts/`
3. Reciprocal Blink post link + SEO checklist Homelab cluster update
4. Commit, push, open PR with `gh` (only when user requests)
