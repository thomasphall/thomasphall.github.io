---
title: "Tesla Sentry to Synology NAS with a Raspberry Pi"
description: >-
  How a Raspberry Pi 4 running Sentry-USB-Rusty in a Tesla archives TeslaCam
  and Sentry Mode clips to a Synology share over SMB when home Wi‑Fi appears.
date: 2026-08-13 14:30:00 -0500
categories: [Homelab, Automation]
tags: [homelab, automation, synology, tesla]
og_image: /assets/img/og/tesla-sentry-synology-archive.png
permalink: /posts/tesla-sentry-synology-archive/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. This describes a personal
> archival setup for vehicle footage I own. Sentry USB is third-party software;
> Tesla software and USB behavior change—verify against current vehicle settings
> and upstream docs before you rely on it.
{: .prompt-info }

The Tesla app is fine for glancing at a Sentry event. A USB stick in the
glovebox is fine until it fills, the car sleeps, or you actually want a
searchable archive on the NAS next to everything else you already keep.

What I wanted was boring and automatic: the Tesla keeps writing TeslaCam/Sentry
clips in the car, and when I park at home the footage lands on the Synology
without me yanking a drive every night.

I ended up with a Raspberry Pi 4 in the car running
[Sentry-USB-Rusty](https://github.com/Sentry-Six/Sentry-USB-Rusty)—the modern
“Sentry USB” stack—archiving over SMB to a dedicated Synology share. This post
is the architecture and ops notes, not a clone of the upstream install wizard.

## Constraints that shaped the design

- **Stay in the car.** No nightly USB swap ritual.
- **Use home Wi‑Fi when parked.** Archive should start when the Pi joins a known
  network, not while I am on cellular or a random hotspot.
- **Synology-first.** SMB share, dedicated DSM user, clips on disk I already
  back up.
- **Pi 4 as the USB gadget.** The Tesla sees a drive; the Pi also runs the
  archive loop.

## What exists in the ecosystem

| Approach | Verdict for my setup |
| --- | --- |
| Plain USB stick | Works until it fills; zero automation |
| Classic [teslausb](https://github.com/marcone/teslausb) | Mature baseline; more DIY config surface |
| [Sentry-USB-Rusty](https://github.com/Sentry-Six/Sentry-USB-Rusty) | Browser setup, SMB/NFS/rsync/rclone archives, active project—what I run |
| Cloud-only Tesla APIs | Not a substitute for local TeslaCam/Sentry files |

I wanted something maintained with a wizard for Wi‑Fi + NAS, not a weekend of
shell glue. Sentry USB fit.

## Architecture

```text
Tesla (TeslaCam / Sentry)
        │  USB gadget (glovebox USB-A → Pi USB-C)
        ▼
  Raspberry Pi 4 + Sentry-USB-Rusty
  (emulated drive + archive loop)
        │  when home Wi‑Fi + SMB
        ▼
  Synology share (e.g. teslacam/)
```

The important split: the car only ever talks to the **emulated drive**. The
NAS only ever receives what the **archive loop** copies when the Pi is on a
known network. Manual “Archive Sync” in the web UI is the escape hatch when
automatic did not fire.

Same idea as my
[Blink → Synology archival](/posts/blink-camera-synology-archive/) setup:
keep capture and long-term storage as separate concerns, then automate the
boring copy.

## Practical checklist

Upstream remains authoritative:
[Getting Started](https://github.com/Sentry-Six/Sentry-USB-Rusty/wiki/Getting-Started)
and
[Archive Methods](https://github.com/Sentry-Six/Sentry-USB-Rusty/wiki/Archive-Methods).
What I actually did, compressed:

1. Flash **Raspberry Pi OS Lite (64-bit)** with Imager (user, Wi‑Fi, SSH on).
2. Boot on a bench PSU, `apt update && apt upgrade`, install Sentry USB per the
   Getting Started curl installer; hostname becomes `sentryusb`.
3. Finish the **Setup Wizard**: mark home Wi‑Fi as known, choose **CIFS/SMB**,
   point at the Synology share.
4. On DSM: create a share (for example `teslacam`) and a **non-admin** user with
   read/write on that share only; use those credentials in the wizard.
5. Power off the Pi, then run a short, **data-capable USB-A to USB-C cable**
   from the vehicle’s glovebox USB-A port to the Pi’s USB-C port (power +
   gadget on one cable).
6. Confirm the dashcam icon records. If the vehicle offers **Encrypt Dashcam
   Recordings** (newer software), leave it off—encrypted clips are not useful
   to the archiver today.
7. Park on home Wi‑Fi and confirm files appear on the share; if needed, open
   `http://sentryusb.local` → **Settings → Archive Sync** and watch
   **Logs → Archive Loop**.

## Lessons that mattered

### One cable, glovebox port, short data cable

On a Pi 4, USB-C is both power and the OTG/gadget port. In the Tesla I use the
**glovebox USB-A** (the storage port), not a rear charge-only port. Buy a short
**data + charging** cable; charge-only or long thin cables brown out the Pi
under load.

### Auto-archive on known Wi‑Fi; manual sync as fallback

The happy path is: arrive home → Pi joins known Wi‑Fi → archive loop runs →
clips land on the Synology. When that does not happen (Wi‑Fi flaky, share
offline, I am debugging), **Archive Sync** in Settings is the explicit kick.
Do not treat “the car recorded” as “the NAS has a copy.”

### Vehicle sleep cuts USB power

When the vehicle sleeps, USB power usually drops and the Pi dies with it. That
is expected. If a large sync is still running, you can lose the window.
**Keep Awake** (and related hold settings in Sentry USB) exists so the car
stays powered long enough for the archive to finish. Time the first real sync
while you can still watch the Archive Loop log.

### Dedicated Synology user and share

Do not archive as admin into a kitchen-sink share. Create a DSM user for the
Pi, grant **Read/Write** only on that dedicated share, and enable SMB. If the
wizard cannot mount, check SMB is on and—on older DSM quirks—whether an
explicit CIFS version is required (upstream Archive docs cover that field).

## Validation checklist I actually used

1. Bench install completes; `http://sentryusb.local` loads the UI
2. Wizard saves known home Wi‑Fi and SMB settings without mount errors
3. In the car, dashcam icon appears and new clips land on the emulated drive
4. Park at home → Archive Loop shows a successful run; files appear on the share
5. Force a second **Archive Sync** → no duplicate storm (already-archived clips
   stay put)
6. Spot-check one Sentry event timestamp in the car against the NAS folder

## Risks I am accepting

- **Third-party USB gadget software** in a vehicle I care about; I update when
  upstream does and I keep a plain stick as a fallback.
- **Power brownouts** on a Pi 4 drawing from car USB—cable quality matters more
  than people admit.
- **Incomplete sync** if sleep wins the race against archive.
- **Software churn** on both Tesla and Sentry USB (encryption toggles, USB
  behavior, installer paths).

## Takeaways

A dumb stick records. A Pi that *looks* like a stick can also empty itself onto
the NAS when you get home. For me the durable choices were Sentry-USB-Rusty,
SMB to Synology, a dedicated DSM identity, and treating vehicle sleep as a
first-class scheduling constraint—not an afterthought.

Keep the share boring, the credentials off the blog, and the first validation
run where you can still see the Archive Loop.
{: .prompt-tip }

## Related posts

- [Archiving Blink Camera Clips to a Synology NAS](/posts/blink-camera-synology-archive/)
