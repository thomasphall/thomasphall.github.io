---
title: "Changed Block Tracking for OpenShift VMs"
description: >-
  OpenShift 5 has two Changed Block Tracking previews, CSI and QEMU. Both
  remain Technology Preview. Incremental backup still needs its own timed
  restore.
date: 2026-11-13 07:20:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, storage, csi]
permalink: /posts/changed-block-tracking-openshift-vms/
social_title: |-
  Changed Block Tracking
  Two previews, one backup job
social_label: OpenShift Virtualization
social_subtitle: CSI snapshots · QEMU checkpoints
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

On November 11, 2026, Red Hat's
[OpenShift Virtualization 5 post](https://www.redhat.com/en/blog/unlocking-next-generation-workloads-whats-new-red-hat-openshift-virtualization-5)
described storage-agnostic incremental backups powered by QEMU Changed
Block Tracking (CBT), as a Technology Preview, with Commvault,
Cohesity, Dell, and Rubrik. The same release train documents a second
CBT feature on the Container Storage Interface (CSI) side.

A design review that says "CBT" without saying which bitmap will test
the wrong thing. One bitmap lives in QEMU and libvirt. The other lives
in a CSI driver, between two snapshots. Both are previews. Neither
result is a disaster recovery (DR) design.

[OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
is still the split between a copy you restore and a failover you have
declared. This post is the incremental layer people will put on top of
that split. It is a solutions-architect map as of November 13, 2026,
not a backup-product install guide.

## Two bitmaps, two owners

| | QEMU / KubeVirt | CSI |
| --- | --- | --- |
| What it diffs | Disk blocks changed since a libvirt checkpoint | Blocks changed between two snapshots of one volume, plus allocated ranges in a single snapshot |
| Who implements it | The backup product, against the KubeVirt backup API | The CSI driver and the backup product |
| Storage | Storage-agnostic. The array does not keep the bitmap | Only drivers that implement CSI CBT |
| What comes back | The changed blocks, copied by the backup product | Metadata. The backup product reads the snapshot data itself |
| Support statement I can cite today | The November 11 product blog calls it Technology Preview. The [OpenShift Virtualization 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes) do not list it | [KCS 7146879](https://access.redhat.com/solutions/7146879) and the [OKD 5 CSI CBT overview](https://docs.okd.io/latest/storage/container_storage_interface/persistent-storage-csi-changed-block-tracking.html): Technology Preview on OpenShift 5.0 |

> **Do not put either path in a production runbook.** Technology Preview
> features are not covered by Red Hat production service level
> agreements, may be incomplete, and are not intended for production.
> See the
> [Technology Preview Features Support Scope](https://access.redhat.com/support/offerings/techpreview).
> For the QEMU path, also wait until the OpenShift Virtualization
> release notes, or a solution you can cite, describe the build you
> will run. The product blog is not that note.
{: .prompt-warning }

## QEMU CBT is an upstream alpha API

[KubeVirt v1.8](https://kubevirt.io/2026/KubeVirt-v1-8-release.html)
added storage-agnostic incremental backup. The
[upstream proposal](https://github.com/kubevirt/enhancements/blob/main/veps/sig-storage/incremental-backup.md)
uses QEMU's changed-block tracking and a libvirt checkpoint as the
marker for each backup. The API group in that proposal is
`backup.kubevirt.io/v1alpha1`. The objects are `VirtualMachineBackup`
and `VirtualMachineBackupTracker`. Creating a tracker requires the
`IncrementalBackup` feature gate.

The tracker stores the latest successful checkpoint for one virtual
machine (VM) and one backup product. The next backup that names the
tracker copies blocks changed since that checkpoint. A backup with no
tracker, or a tracker that has no checkpoint yet, is a full backup.
`forceFullBackup` forces a full copy even when a checkpoint exists.

Two details belong in the vendor conversation:

- **One tracker per backup product.** The proposal expects each product
  to keep its own checkpoint chain. Two products sharing a tracker will
  not have independent incrementals.
- **A VM restart drops libvirt's checkpoints.** Libvirt is recreated
  when the VM starts. The proposal's answer is to redefine checkpoints
  from the tracker's stored metadata during startup. If that metadata
  is missing or stale, the next backup falls back to a full copy. A
  reboot between backups is a test, not an edge case.

Veeam has written that
[VEP-25 and VEP-26](https://www.veeam.com/blog/openshift-virtualization-backup-kubevirt-cbt.html)
are the upstream proposals, and that Kasten can read the QEMU dirty
bitmap instead of scanning the whole disk. Red Hat's November 11
sentence names Commvault, Cohesity, Dell, and Rubrik. Ask which
sentence matches the build you will install, on which OpenShift
z-stream, and whether that build is the one that creates the tracker.

I do not see
[OpenShift API for Data Protection (OADP)](/posts/oadp-vms-backup-is-not-dr/)
in that partner sentence, or in the OpenShift Virtualization 5.0
release notes. Keep the OADP design you already have — CSI snapshot, or
CSI with DataMover — until a version note says OADP consumes this
bitmap.

The practical gain, when the chain is intact, is the read. Veeam's
illustration is a 2 TB disk with 50 GB of daily change: the backup
product reads the changed blocks instead of scanning the disk. That is
backup-window math. It is not a recovery time objective (RTO), and it
is not proof the guest could recover.

## CSI CBT compares two snapshots

OpenShift 5.0 promotes CSI changed block tracking from Developer
Preview to Technology Preview. The
[OKD overview](https://docs.okd.io/latest/storage/container_storage_interface/persistent-storage-csi-changed-block-tracking.html)
describes what a backup application can ask for:

- Block ranges that changed between two snapshots of the same CSI block
  volume
- Allocated ranges inside one snapshot, so a full backup can skip
  unallocated space

The call returns metadata. The backup application reads and stores the
snapshot data on its own. The driver has to implement the API, and the
backup product has to call it. A storage class that snapshots, and a
storage class that can answer a changed-block query, are not the same
claim. Confirm the driver on the cluster you will use. The
[storage shortlist](/posts/ove-vsan-storage-alternatives/)
is where that driver was chosen; this preview does not reopen it.

CSI CBT is also the path that can get faster still once arrays
implement it. QEMU CBT exists so a backup can proceed when the array
has not. Using the QEMU bitmap against a driver that already returns
changed blocks is a product choice, not two copies of the same feature.

## Incremental backup is still backup

CBT changes how much data the backup job reads. The
[OADP post](/posts/oadp-vms-backup-is-not-dr/)
still draws the lines around that job.

| CBT can shrink | CBT leaves this alone |
| -------------- | --------------------- |
| Bytes read from the disk | Whether the guest was quiesced |
| Data moved to the backup target | A restore onto a cluster that is gone |
| The backup window, when the checkpoint chain is valid | The time you measure for that restore |
| | Replication, failover, and failback |
| | Fencing a dead node and restarting the VM |

Guest consistency is still a guest-agent problem. A crash-consistent
incremental is a crash-consistent copy that happened to be smaller.
Freeze the guest, or write the recovery point objective (RPO) as
crash-consistent. VolumeGroupSnapshot does not become generally
available because a bitmap exists.

Cluster loss is still a restore from wherever the backup product put
the blocks. Time it. A faster incremental does not change the download.

Declared DR is still the array or
[OpenShift Data Foundation](/posts/oadp-vms-backup-is-not-dr/)
Metro-DR and Regional-DR story. Fencing a gray host is still
[Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/).
Live migration is still a move. None of those is a checkpoint.

## What a pilot has to show

Run this on a non-production cluster, with a backup vendor build that
names the OpenShift version it supports. The
[storage setup](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/storage/)
in the OpenShift PoC docs is the floor: a storage class the VM can use,
before anyone talks about incrementals.

For the QEMU path, ask the vendor for five facts before you change a
disk:

1. The OpenShift and OpenShift Virtualization z-stream, and the feature
   gate their build expects.
2. Whether their product creates a `VirtualMachineBackupTracker` per
   VM, and refuses to share that tracker with another product.
3. What the next backup does after the VM restarts, when libvirt no
   longer has the checkpoint.
4. Bytes read from a disk with a known change set, next to the size of
   that disk.
5. A restore into a scratch namespace, with a stopwatch, and a statement
   of whether the guest was frozen.

For the CSI path, confirm the driver implements changed block tracking
on that OpenShift version, then ask for the same restore time. The
metadata call is not the backup. The snapshot data still has to move.

> **Keep the source until the restore has been read.** An incremental
> that reports success is not a recovered application. The same rule as
> [storage migration in OpenShift Virtualization 5.0](/posts/openshift-virtualization-5-0-features/)
> applies here: verify the copy, then delete the thing you can still
> roll back to.
{: .prompt-warning }

## The solutions architect takeaway

1. **Name the bitmap.** QEMU checkpoints and CSI snapshot diffs are
   different Technology Previews.
2. **QEMU CBT is upstream alpha.** `backup.kubevirt.io/v1alpha1`, gate
   `IncrementalBackup`, one tracker per backup product. The November 11
   blog calls the OpenShift feature Technology Preview. The
   virtualization 5.0 release notes do not list it.
3. **CSI CBT is Technology Preview on OpenShift 5.0.** It returns
   metadata for drivers that implement it. It does not return the
   backup.
4. **Restart the VM during the test.** The checkpoint chain is the
   feature. A reboot that forces a full copy is a failed incremental,
   even when the job succeeds.
5. **Time the restore.** Write the number you measured. A smaller read
   on the way out does not set the RTO.
6. **Leave DR, fencing, and live migration on their own slides.**
   Incremental backup is still backup.

> Want help deciding whether a backup vendor's CBT claim belongs in
> this design? Work with your Red Hat account team, and keep the pilot
> off production until the release notes match the build.
{: .prompt-tip }

## Related posts

- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [OpenShift Virtualization 5.0: The Updates That Matter](/posts/openshift-virtualization-5-0-features/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)

## Further reading

- [What's new in OpenShift Virtualization 5](https://www.redhat.com/en/blog/unlocking-next-generation-workloads-whats-new-red-hat-openshift-virtualization-5)
- [OpenShift Virtualization 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/release-notes)
- [How to use Changed Block Tracking (Tech Preview) in OpenShift 5.0](https://access.redhat.com/solutions/7146879)
- [CSI changed block tracking (OKD 5)](https://docs.okd.io/latest/storage/container_storage_interface/persistent-storage-csi-changed-block-tracking.html)
- [Technology Preview Features Support Scope](https://access.redhat.com/support/offerings/techpreview)
- [KubeVirt v1.8 release](https://kubevirt.io/2026/KubeVirt-v1-8-release.html)
- [KubeVirt incremental backup proposal](https://github.com/kubevirt/enhancements/blob/main/veps/sig-storage/incremental-backup.md)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/storage/)
