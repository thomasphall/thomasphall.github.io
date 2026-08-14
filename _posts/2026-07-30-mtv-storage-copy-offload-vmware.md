---
title: "Storage Copy Offload for VMware Migrations to OpenShift Virtualization"
description: >-
  How Migration Toolkit for Virtualization storage copy offload moves disk data
  on the SAN instead of the IP network—and when that path fits a VMware exit.
date: 2026-07-30 15:00:00 -0500
categories: [OpenShift, Virtualization, Migration]
tags: [openshift-virtualization, mtv, vmware, storage-offload, migration]
permalink: /posts/mtv-storage-copy-offload-vmware/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Most VMware exit programs do not stall on whether a guest can boot on
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
They stall on disk copy time. Multi-terabyte volumes, parallel migration waves,
and shared datacenter networks turn “convert the VM” into a schedule problem.
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11)
(MTV) already handles inventory, mapping, and cutover. Storage copy offload—often
shortened to storage offload—changes *where* the heavy disk work happens when
your estate sits on suitable SAN storage.

This post is a solution-architect digest for platform, virtualization, and
storage teams evaluating that path on MTV 2.11. It is not a click-by-click
runbook.

## The traditional MTV path hits the network

In a typical VMware-to-OpenShift Virtualization migration, MTV still orchestrates
the plan: select VMs, map networks and storage, run cold or warm migration, and
land disks as persistent volumes for KubeVirt. The expensive part is often the
disk transfer itself.

Network-centric paths—commonly associated with VDDK-style reads from vSphere—pull
data from the source hypervisor stack, move it across the IP network, and write
it into the OpenShift storage target. That works. At small scale it is fine. At
estate scale it competes with production traffic, stretches maintenance windows,
and makes wave planning a guessing game driven by link utilization rather than
array capability.

If your bottleneck is “can the network carry another 40 TB this weekend?”,
changing the converter settings will not fix the schedule. You need a different
data path.

## Storage copy offload: keep the copy on the SAN

Storage copy offload is MTV’s answer for VMware VMs whose disks live on a storage
array network. Instead of hauling every block across the migration IP path, MTV
can accelerate the copy by using `vmkfstools` on the ESXi host. That utility can
invoke SCSI XCOPY on the array over iSCSI or Fibre Channel, so the array (and
its fabric) do more of the work in place.

Conceptually:

```text
VMware                              SAN / array                 OpenShift
┌─────────────────────┐             ┌──────────────────┐        ┌──────────────────────────────┐
│ Source VM disks     │             │                  │        │ MTV migration plan           │
│         │           │  vmkfstools │ Array-assisted   │        │   (orchestrates copy + land) │
│         v           │────────────>│ copy (XCOPY when │───────>│              │               │
│ ESXi host           │  iSCSI/FC   │ the array can)   │        │              v               │
└─────────────────────┘             └──────────────────┘        │ OpenShift Virtualization     │
                                                                │ PVCs / VM disks              │
                                                                └──────────────────────────────┘
```

MTV still owns the migration plan and the landing on OpenShift Virtualization.
What changes is the copy engine: data movement prefers the storage path over a
long IP transfer through the migration controller.

That matters for three outcomes teams care about:

1. **Faster cold migrations** for large disks, where network serialization was
   the dominant cost.
2. **Lower network load** during migration waves, so cutovers compete less with
   production east-west and backup traffic.
3. **Clearer schedules** when source and target share suitable array
   infrastructure—you plan around storage readiness, not hope that the
   uplink stays quiet.

Partner write-ups sometimes quote large acceleration factors for specific arrays
and lab conditions. Treat those as illustrative. Your result depends on array
support, fabric health, disk size mix, concurrency, and how cleanly source and
target storage map together.

## When storage copy offload helps most

Offload is not a universal default. It earns its keep when several conditions
line up:

- **Source is VMware vSphere**, which is the path MTV documents for this
  feature.
- **Disks are SAN-backed** and the offload path can actually use that storage.
- **Disks are large** (multi-TB and up), where IP copy time dominates.
- **You run wave-based migration factories**—many VMs, repeated weekends—and
  network contention is already visible in earlier pilots.
- **Target OpenShift Virtualization and provisioning are ready**, including
  StorageClasses and capacity on the destination side (for array-backed VM
  disks on OpenShift, see for example
  [Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/)).

If the topology cannot support offload, fall back to network copy. That is a
normal outcome, not a failure of the migration program. Design the factory so
both paths are acceptable; promote workloads to offload only when the storage
map proves out.

## Cold is GA; warm offload is Technology Preview

On MTV 2.11, set expectations cleanly:

| Mode | Storage copy offload status | Practical implication |
| ---- | --------------------------- | --------------------- |
| Cold migration | Generally Available | Primary production path for offload today |
| Warm migration | Technology Preview | Useful to evaluate for lower downtime; do not treat as GA |

Cold migration still means downtime for the cutover window. Offload’s job is to
shrink the data-copy portion of that window and reduce collateral network impact
while the plan runs. Warm migration remains important when business owners need
shorter outages and can accept Technology Preview for the offload path. Call that
out once in design reviews, then decide consciously—do not quietly assume warm
offload is as hardened as cold.

Storage offload also does not replace the rest of MTV. Inventory hygiene,
network mapping, guest tools and drivers, application cutover runbooks, and
rollback criteria still decide whether a wave succeeds. OpenShift Virtualization
is the destination platform; MTV is the migration tool; the array is the copy
accelerator when the topology allows it.

## What operators configure—at SA altitude

Enabling offload is a migration-plan storage concern, not a separate product.

At a conceptual level you:

1. **Install a suitable MTV version** on the OpenShift cluster that will receive
   the VMs.
2. **Configure the migration plan storage map for offload**, selecting the
   offload plugin (commonly labeled something like vSphere XCOPY in the UI).
   The plugin name is easy to over-read: it does **not** mean every array must
   support SCSI XCOPY for offload to help. Offload shifts work toward
   `vmkfstools` on ESXi; XCOPY is used when the array and VMware stack support
   that primitive.
3. **Provide the storage secret and storage product settings** required by your
   array integration.
4. **Map landing storage** so migrated disks become PVCs on OpenShift
   Virtualization through the correct StorageClass.

Certified and partner patterns exist—Hitachi VSP, Dell PowerMax, and
Portworx/FlashArray styles among them. They differ in secrets, optional hooks,
and any post-copy conversion steps. Keep vendor specifics in the storage design
doc for that account; the SA point is that offload is an MTV storage-map choice
backed by array integration, not a single identical recipe everywhere.

## Teams that must align before wave one

Treat the first offload migration as a joint pilot, not a virt-only experiment.

| Owner | What they owe the pilot |
| ----- | ----------------------- |
| Virtualization | Candidate VMs, cold vs warm decision, ESXi/vSphere readiness for the offload path |
| Storage | Array support, fabric path, credentials/secrets, confirmation source and target placements make sense |
| Platform / OpenShift | MTV installed, OpenShift Virtualization ready, StorageClasses and capacity, namespace and RBAC boundaries |
| App owners | Cutover window, validation checklist, rollback expectation |

Validate one representative VM end to end: storage map, secret, StorageClass,
boot on OpenShift Virtualization, and measured copy behavior versus a network
copy baseline. Only then size the weekend waves.

## Network copy vs storage copy offload

| Dimension | Network-centric copy | Storage copy offload |
| --------- | -------------------- | -------------------- |
| Primary data path | IP network via MTV/migration stack | SAN/array path via ESXi `vmkfstools` (XCOPY when available) |
| Speed drivers | Link speed, concurrency, VDDK-style throughput | Array and fabric capability, disk layout, offload integration quality |
| Network impact during waves | High—competes with production and backup | Lower—less disk bulk on the migration IP path |
| Best fit | Mixed storage, no shared offload-capable SAN path, smaller disks | SAN-backed VMware disks, large volumes, shared/compatible array story |
| MTV 2.11 cold | Supported | GA |
| MTV 2.11 warm | Supported | Technology Preview for offload |
| Fallback | Default for many estates | Use when topology qualifies; otherwise stay on network copy |

## Pitfalls worth calling in design review

**Plugin name equals “must have XCOPY.”**  
No. Treat “vSphere XCOPY” as the MTV offload plugin label. Confirm with your
storage partner what the array actually does underneath.

**Skipping the pilot.**  
Offload failures are usually mapping and readiness problems, not mystery
hypervisor bugs. A single measured pilot prevents a bad weekend for fifty VMs.

**Mismatched storage mapping.**  
Landing on the wrong StorageClass—or assuming source and target share a path
they do not—puts you back on a slow or broken copy with little warning.

**Treating offload as the whole migration design.**  
Faster disks do not fix bad network maps, missing guest prep, or unclear
rollback. Offload removes a bottleneck; it does not invent operational maturity.

**Promising universal speedups.**  
Quote your pilot numbers. Borrow partner marketing multipliers only as
context, not as a contractual schedule.

## SA takeaway

Use storage copy offload when the SAN path exists and large VMware disks are
dominating the migration calendar. On MTV 2.11, build production waves around
cold offload as GA; evaluate warm offload only with eyes open that it is
Technology Preview. Keep MTV as the orchestrator, OpenShift Virtualization as
the destination, and the array as the copy engine—then design the migration
factory around that storage reality, not around hope that the IP network will
absorb another wave.

If you are planning a VMware exit onto OpenShift Virtualization and want a
second set of eyes on whether offload fits your array topology, that is a useful
architecture conversation to have before the first production weekend—not after.
Keep network mapping on the same critical path as storage—see
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/)—
and use
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
for destination-platform context. If the source estate is vSAN rather than a
SAN, start with
[vSAN-like storage for OpenShift Virtualization Engine without ODF](/posts/ove-vsan-storage-alternatives/)
before you assume ODF is the only landing pool.

## Related posts

- [vSAN-like Storage for OpenShift Virtualization Engine Without ODF](/posts/ove-vsan-storage-alternatives/)
- [Configuring OpenShift Virtualization with Dell Unity Storage over iSCSI](/posts/openshift-virt-dell-unity-iscsi/)
- [OpenShift Virtualization Networking: From Pod Network to Localnet](/posts/openshift-virtualization-networking/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)

For planning detail and current prerequisites, start with Red Hat’s
[MTV documentation for migrating from VMware vSphere](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_planning-migration-vmware_mtv).
