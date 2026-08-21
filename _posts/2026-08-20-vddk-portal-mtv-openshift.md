---
title: "VDDK Off Broadcom's Public Portal: MTV Migrations"
description: >-
  Broadcom has gated VMware VDDK downloads behind TAP and entitlements.
  How that change hits MTV migrations to OpenShift Virtualization—and
  what to do instead.
date: 2026-08-20 12:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, migration, vmware, storage]
og_image: /assets/img/og/vddk-portal-mtv-openshift.png
permalink: /posts/vddk-portal-mtv-openshift/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Access rules for Broadcom
> downloads change. Confirm current entitlement on the Broadcom developer
> portal and in Red Hat MTV docs before you treat any path as blocked or
> available.
{: .prompt-info }

VMware-exit programs used to stall on disk copy time. Some now stall
*before* the first byte moves: they cannot obtain the
[VMware Virtual Disk Development Kit](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/latest)
(VDDK). [Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) still orchestrates the move onto
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
It does not ship VMware’s SDK. The factory that assumed “download VDDK on
Friday, migrate on Saturday” is the thing that broke.

This post is a solution-architect digest for MTV 2.12 and OpenShift 4.22. It
is not a click-by-click image build, and it is not legal advice on Broadcom
license terms. For operator install and a vSphere provider in a PoC, use the
[Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/mtv/)
guide—then treat VDDK as a procurement item, not a browser errand.

## What VDDK actually does in MTV

VDDK is VMware’s C library set for reading virtual disks through vStorage
APIs for Data Protection (VADP). Backup products use it. So do migrators.
MTV does not embed those libraries. You download the Linux tarball, wrap
it in a container, push that image to a registry the cluster can pull, and
point the vSphere `Provider` at it (`vddkInitImage`). MTV runs the image
as an init container so `virt-v2v` / `nbdkit` can talk to ESXi the way
VMware designed.

Red Hat’s wording on MTV 2.12 is consistent:

- Creating a VDDK image is **optional** and **strongly recommended**.
- Skipping it is an explicit provider choice labeled **not recommended**.
- Without VDDK, network copy is **significantly slower**.
- For VMs whose disks live on **VMware vSAN**, VDDK is mandatory. MTV
  fails those plans with `Migration failed: VDDK image required for vSAN
  storage`.

The UI can even upload a VDDK archive and build the init image for you. That
only helps if you already have the archive.

Red Hat cannot host the tarball. Product docs also warn that putting the
image in a **public** registry can violate VMware license terms. Keep it in
a private registry the landing cluster can pull.

## What changed on the portal

The kit is not gone as a product. Broadcom still publishes VDDK (9.1 is
current as of this writing) and still has a
[developer landing page](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/latest).
What disappeared for a lot of VMware-exit teams is the **public,
self-service download** that MTV documentation still tells you to use.

In practice, customers and partners report some mix of:

- Download buttons that return JSON errors or a permanent login loop.
- Entitlement walls that a vSphere support contract does not clear.
- Broadcom support directing people to the
  [VMware Technology Alliance Program](https://tap.broadcom.com/)
  (TAP).

TAP is an **ISV and hardware-vendor** program: build, certify, and sell
against VMware. It is not a customer off-ramp. Community reports from
migration products (Nutanix Move is a public example) describe the same
dead end: you need TAP, TAP asks whether you build software for Broadcom,
and “we are leaving vSphere” is the wrong answer.

Read that as a procurement and timeline problem, not as a conspiracy
slide. The incentive is obvious. VDDK is how third-party tools read VMDKs
efficiently. Gating it slows every exit that assumed the old VMware
developer portal.

MTV docs still say “navigate to the VMware VDDK download page.” That
sentence is now the riskiest line in the runbook.

## How migrations actually break

Not every OpenShift Virtualization landing zone dies. The copy path
matters.

```text
vSphere disks
     │
     ├── VDDK network copy ──► CDI volumes ──► OpenShift Virtualization
     │     (fast, required for vSAN; needs the tarball)
     │
     ├── No VDDK ────────────► slower virt-v2v path ──► OpenShift Virtualization
     │     (allowed except vSAN; weekends get longer)
     │
     └── Storage copy offload ──► Volume Populators / XCOPY ──► OpenShift Virtualization
           (array path; does not consume VDDK for the copy)
```

| Source storage | VDDK available | Practical MTV path |
| -------------- | -------------- | ------------------ |
| SAN / NFS / VMFS, you have a legal VDDK archive | Yes | Network copy with `vddkInitImage` — still the default factory |
| SAN that MTV documents for offload | Optional | [Storage copy offload](/posts/mtv-storage-copy-offload-vmware/) — VDDK is not the copy engine |
| SAN / NFS / VMFS, no VDDK | No | Cold network copy without the SDK; plan for much slower waves |
| **vSAN** | **Required** | No VDDK → plan fails. Offload does not replace VDDK here |

Three consequences show up in design reviews.

**1. vSAN estates are a hard stop without the kit.**  
That is not folklore. MTV 2.12 troubleshooting documents the error and
the fix: configure a VDDK init image. If the source is vSAN and you
cannot obtain VDDK, the factory does not “degrade.” It does not start.
Storage vMotion onto NFS or a SAN *before* MTV runs, followed by a normal
migration, is an architecture conversation—not a hidden checkbox.

**2. Warm migration and Deep Inspection get worse.**  
Warm copy leans on Changed Block Tracking (CBT) and efficient disk
reads. Deep Inspection on MTV 2.12 mounts guest filesystems through
VDDK. Skip the SDK and you lose the incremental path that makes
low-downtime waves honest, plus the guest-inside evidence that
[AI-assisted MTV planning](/posts/ai-agents-mtv-vsphere/)
wants. Cold still works on non-vSAN disks. The outage window grows.

**3. Offload is the VDDK-independent accelerator—when the array qualifies.**  
On MTV 2.12, storage copy offload uses `vmkfstools` on ESXi and SCSI
XCOPY on a supported array. The bits stay on the fabric. You still need
array credentials, a clean snapshot story, and a `StorageMap` that is
*all* offload or *all* VDDK. Mixing those mappings in one `Plan` fails
because the controller copies through CDI (VDDK) or Volume Populators
(offload), not both. Offload is not a vSAN workaround.

If the source is vSAN and the destination is supposed to *feel* like
vSAN, that is a landing-storage problem as well as a copy problem. See
[vSAN-like storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/).

## What to do this week

Treat VDDK like a pull secret: find it before the PoC weekend, store it
somewhere boring, and do not rediscover it during cutover.

1. **Inventory what you already have.**  
   Old `VMware-vix-disklib-*.tar.gz` files from an entitled download are
   the fastest legal path. Match major version to the vSphere line MTV
   documents for your OpenShift version. Build the init image once, push
   to a private registry, reference it on the `Provider`. MTV 2.12 can
   build from an uploaded archive in the UI.

2. **Open the Broadcom path in parallel, with the right persona.**  
   A named support contact with a current vSphere entitlement should try
   [developer.broadcom.com](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/latest)
   and, if that fails, a Broadcom case. TAP is for partners building on
   VMware. Do not put the migration PM through an ISV questionnaire and
   call it a plan.

3. **Classify every datastore: vSAN, offload-capable SAN, or neither.**  
   vSAN VMs are VDDK-gated. SAN VMs may be offload-gated instead. Mixed
   estates need **two plan shapes**, not one heroic `StorageMap`.

4. **Prove one VM on the path you can actually run.**  
   Measure cold-with-VDDK, cold-without-VDDK, and cold-offload if the
   array is in MTV’s offload list. Quote *your* numbers in the wave
   calendar. Partner speed-up claims are not a schedule.

5. **Do not pirate the SDK.**  
   Random tarballs from a Slack DM are a license and supply-chain
   incident. Red Hat will not ship VDDK for you. If the customer cannot
   obtain it, redesign the copy path; do not smuggle libraries.

6. **Keep GitOps as the record.**  
   The `Provider` setting, the image pull secret, and the offload
   `Secret` belong in the same factory repo as the `Plan`. Chat history
   that says “we skipped VDDK” is not an audit trail.

For a first cluster, start from
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and land Virtualization before you argue about copy engines.

## Pitfalls worth calling in the design review

**“Optional means we can ignore it.”**  
Optional for MTV means the operator installs. For a vSAN source, it
means the plan fails. For everyone else it means the weekend does not
fit.

**“Offload replaces VDDK everywhere.”**  
It replaces the *network* copy on qualifying SANs. It does not read
vSAN objects. It does not mix with VDDK mappings in the same plan.

**“We will download it during the migration workshop.”**  
Assume you cannot. Put “VDDK archive in private registry” on the
readiness checklist next to vCenter credentials and the transfer
network.

**“Any VDDK version is fine.”**  
MTV documents which VDDK major lines go with which OpenShift
Virtualization versions. Wrong libraries fail in conversion pods, not
in a friendly form validation.

**“Public Quay is convenient.”**  
Convenient, and a license problem. Private registry, pull secret,
namespace that the provider can actually use. MTV 2.12 also documents
cross-namespace pull failures when the image lives in `openshift-mtv`
and the provider does not.

## The SA takeaway

Broadcom did not have to delete VDDK to slow VMware exits. Gating the
public download is enough. MTV 2.12 still wants that SDK for fast
network copy, for warm incremental work, for Deep Inspection, and
**absolutely** for vSAN. OpenShift Virtualization is not blocked as a
destination. The blocked thing is the *assumption* that VDDK is a free
file on a portal.

Lead with three decisions:

1. **Do we have a legal VDDK archive or a realistic Broadcom path?**  
   If yes, build `vddkInitImage` once and stop talking about it.
2. **Is the source vSAN?**  
   If yes and there is no VDDK, change the storage layout or stop
   promising MTV dates.
3. **Can the SAN take offload?**  
   If yes, make that the factory default for those datastores and keep
   VDDK plans separate.

If you are scoping a VMware exit onto OpenShift Virtualization, the
useful conversation this month is not “does MTV still work?” It does.
The useful conversation is which copy engine you can actually license
before the first wave.

## Related posts

- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)
- [AI Agents for MTV: vSphere to OpenShift Virtualization](/posts/ai-agents-mtv-vsphere/)
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)

> Want help mapping VDDK versus offload versus a vSAN holdout onto an
> MTV factory? Reach out to your Red Hat account team—or prove one VM
> on the copy path you can actually obtain before you schedule a wave.
{: .prompt-tip }

## Further reading

- [Planning a migration from VMware vSphere (MTV 2.12)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_planning-migration-vmware_mtv)
- [MTV 2.12 troubleshooting: VDDK required for vSAN](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_troubleshooting-migration_mtv)
- [Migrating from VMware vSphere (MTV 2.12)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-vmware_mtv)
- [VMware Virtual Disk Development Kit (Broadcom developer portal)](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/latest)
- [VMware Technology Alliance Program](https://tap.broadcom.com/)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/mtv/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)
